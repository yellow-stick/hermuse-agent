"""Subscription bridge of a Hermes server: a pinned CLIProxyAPI next to Hermes.

A Hermes on a server cannot use the CLIProxyAPI sidecar of the Hermuse desktop
app: a custom endpoint pointing there would call the server's own loopback.
So subscriptions sign in here, on this CLIProxyAPI, and Hermes points at it
(``http://127.0.0.1:<port>/v1``, same host as Hermes) as a custom endpoint.
The browser of a sign-in runs on the user's machine and its OAuth redirect
(``http://localhost:<port>/…``) cannot reach this server: the user pastes
the address the browser landed on and :func:`submit_callback` hands it to
CLIProxyAPI, which reads the code from it. No callback port is ever opened
here. Device-code sign-ins need nothing pasted.

Everything lives under ``HERMES_HOME/hermuse/bridge/`` (0700); no root needed:

* ``bin/cliproxy-<version>`` — the pinned release binary (Linux x86-64 and
  ARM64), downloaded from GitHub and checked against the archive and binary
  sha256 of ``packages/hermuse_host/cliproxy.lock``.
* ``keys.json`` (0600) — ``{port, api_key, management_key}``, generated once;
  the loopback port is kept so the endpoint registered in Hermes stays valid.
* ``config.yaml`` (0600) — rewritten before every start (CLIProxyAPI replaces
  the plaintext management key by its bcrypt hash), with the schema of the
  desktop sidecar (``buildCliproxyConfig``).
* ``auth/`` (0700) — account files (the CLIProxyAPI ``auth-dir``), written and
  removed through its management API on loopback, which applies them at once.
* ``cliproxy.json`` ``{pid, binary, port, started}`` + ``cliproxy.log`` (0600)
  — the detached process and its output.
* ``bridge.lock`` — ``flock`` serializing install, start and stop across
  processes.

:func:`ensure` installs and starts the bridge on demand;
:func:`start_if_configured` restarts one set up earlier (reboot, crash) when
the plugin loads. Stdlib only.
"""

from __future__ import annotations

import contextlib
import hashlib
import http.client
import json
import logging
import os
import platform
import re
import secrets
import signal
import socket
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, BinaryIO, Callable, Iterator, Optional

try:  # agent process: package hermes_plugins.hermuse
    from . import store
except ImportError:  # dashboard backend / tests: plugin root on sys.path
    import store  # type: ignore[no-redef]

logger = logging.getLogger(__name__)

VERSION = "v7.3.18"
RELEASE_URL = "https://github.com/router-for-me/CLIProxyAPI/releases/download/{version}/{asset}"
# Name of the server binary inside the release archive.
ARCHIVE_BINARY = "cli-proxy-api"


@dataclass(frozen=True)
class Asset:
    """One release archive and the checksum of the binary inside it."""

    name: str
    archive_sha256: str
    binary_sha256: str


# The linux entries of packages/hermuse_host/cliproxy.lock (tests compare them).
ASSETS = {
    "linux-amd64": Asset(
        "CLIProxyAPI_7.3.18_linux_amd64.tar.gz",
        "f9441024eaa953fd19ad1ff191dbe29dcfbc6a70a53f712062d96f531803b766",
        "b6e3431e3ba296745327a9a9f3f4bbb5385035c3f1c4df2118c786c12f01ceff",
    ),
    "linux-arm64": Asset(
        "CLIProxyAPI_7.3.18_linux_aarch64.tar.gz",
        "eeae7e16fa8f86bd06be2993c637e70240903e52dd72fcc2a5c9fa2e6b327cee",
        "9d4661491969ee16ec8b6c641d3f691480cfb2fc381a0155bf7e082cedd11d1d",
    ),
}
_MACHINES = {"x86_64": "amd64", "amd64": "amd64", "aarch64": "arm64", "arm64": "arm64"}

DIR_NAME = "bridge"
BIN_DIR = "bin"
AUTH_DIR = "auth"
KEYS_FILE = "keys.json"
CONFIG_FILE = "config.yaml"
PROCESS_FILE = "cliproxy.json"
LOG_FILE = "cliproxy.log"
LOCK_FILE = "bridge.lock"

# Account files as CLIProxyAPI names them (``claude-<email>.json``,
# ``codex-<hash>-<email>-<plan>.json``, …): one path segment, never hidden.
ACCOUNT_NAME_RE = re.compile(r"[A-Za-z0-9@_+=-][A-Za-z0-9@._+=-]{0,194}\.json")
MAX_ARCHIVE_BYTES = 256 * 1024 * 1024
MAX_BINARY_BYTES = 256 * 1024 * 1024
MAX_REDIRECT_URL_CHARS = 8192

# ``GET /v0/management/<provider>-auth-url`` routes of CLIProxyAPI v7.3.18 for
# the subscriptions Hermuse offers (``CliproxyProvider`` in Dart).
LOGIN_PROVIDERS = ("anthropic", "codex", "meta", "antigravity", "xai", "kimi", "kimi-ai",
                   "devin")

UNSUPPORTED_DETAIL = "The subscription bridge runs on Linux servers (x86-64 or ARM64)."
NOT_SET_UP_DETAIL = "The subscription bridge is not set up on this server yet."
BUSY_DETAIL = "Another Hermuse request is preparing the subscription bridge; try again."
STARTING_DETAIL = "The subscription bridge is starting."

ENSURE_TIMEOUT_S = 180.0
_READY_TIMEOUT_S = 30.0
_DOWNLOAD_TIMEOUT_S = 60.0
_HTTP_TIMEOUT_S = 10.0
_PROBE_TIMEOUT_S = 2.0
_POLL_S = 0.25
_STOP_WAIT_S = 5.0
_LOG_TAIL_CHARS = 500

# Loopback only: never route 127.0.0.1 through HTTP(S)_PROXY.
_LOOPBACK = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class BridgeUnavailable(RuntimeError):
    """The bridge cannot serve this request now: unsupported host, not set up, busy."""


class BridgeError(RuntimeError):
    """Download, checksum, start or CLIProxyAPI failure; the message says which."""


# --- paths ----------------------------------------------------------------------


def bridge_root(home: os.PathLike[str] | str) -> Path:
    return store.hermuse_root(home) / DIR_NAME


def binary_path(home: os.PathLike[str] | str) -> Path:
    return bridge_root(home) / BIN_DIR / f"cliproxy-{VERSION}"


def auth_dir(home: os.PathLike[str] | str) -> Path:
    return bridge_root(home) / AUTH_DIR


def platform_key() -> Optional[str]:
    """``linux-amd64`` / ``linux-arm64`` on a host the pinned release covers, else None."""
    if not sys.platform.startswith("linux"):
        return None
    arch = _MACHINES.get(platform.machine().lower())
    return f"linux-{arch}" if arch else None


def _asset() -> Asset:
    asset = ASSETS.get(platform_key() or "")
    if asset is None:
        raise BridgeUnavailable(UNSUPPORTED_DETAIL)
    return asset


# --- private files --------------------------------------------------------------


def _private_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, 0o700)
    return path


def _write_private(path: Path, data: bytes, mode: int = 0o600) -> None:
    """Atomic write (temp file + fsync + rename) of a file only this user can read."""
    fd, tmp = tempfile.mkstemp(prefix=".tmp_", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def load_keys(home: os.PathLike[str] | str) -> Optional[dict[str, Any]]:
    """``keys.json`` when complete, else None."""
    data = _read_json(bridge_root(home) / KEYS_FILE)
    if not isinstance(data, dict):
        return None
    port, api, management = data.get("port"), data.get("api_key"), data.get("management_key")
    if not isinstance(port, int) or not 0 < port < 65536:
        return None
    if not isinstance(api, str) or not api or not isinstance(management, str) or not management:
        return None
    return {"port": port, "api_key": api, "management_key": management}


def _save_keys(home: os.PathLike[str] | str, keys: dict[str, Any]) -> None:
    _write_private(bridge_root(home) / KEYS_FILE, (json.dumps(keys, indent=2) + "\n").encode())


def _ensure_keys(home: os.PathLike[str] | str) -> dict[str, Any]:
    keys = load_keys(home)
    if keys is None:
        keys = {"port": _free_port(), "api_key": secrets.token_urlsafe(32),
                "management_key": secrets.token_urlsafe(32)}
        _save_keys(home, keys)
    return keys


def config_text(port: int, auth: Path, api_key: str, management_key: str) -> str:
    """CLIProxyAPI v7.3.18 config with the schema of the desktop sidecar.

    Loopback ``host``, explicit ``port``, ``auth-dir``, ``api-keys``, and
    ``remote-management`` with ``allow-remote: false`` plus the plaintext
    ``secret-key`` the server hashes on startup. Values are JSON-quoted,
    which YAML accepts.
    """
    q = json.dumps
    return (
        "# Generated by Hermuse. Do not edit: overwritten on every bridge start.\n"
        'host: "127.0.0.1"\n'
        f"port: {port}\n"
        f"auth-dir: {q(str(auth))}\n"
        "api-keys:\n"
        f"  - {q(api_key)}\n"
        "remote-management:\n"
        "  allow-remote: false\n"
        f"  secret-key: {q(management_key)}\n"
        "  disable-control-panel: true\n"
        "discovery:\n"
        "  enabled: false\n"
    )


@contextlib.contextmanager
def _locked(home: os.PathLike[str] | str, deadline: float) -> Iterator[None]:
    """Exclusive install/start/stop across processes and threads (``flock``).

    *deadline* is a ``time.monotonic()`` value; waiting past it raises
    :class:`BridgeUnavailable`. Linux only, like the bridge.
    """
    import fcntl

    root = _private_dir(bridge_root(home))
    fd = os.open(root / LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise BridgeUnavailable(BUSY_DETAIL) from None
                time.sleep(_POLL_S)
        yield
    finally:
        os.close(fd)  # releases the lock


# --- install --------------------------------------------------------------------


def _sha256_file(path: os.PathLike[str] | str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verified(path: Path, sha256: str) -> bool:
    try:
        return _sha256_file(path) == sha256
    except OSError:
        return False


def _download(url: str, out: BinaryIO) -> None:
    """Stream *url* into *out*; refuses more than :data:`MAX_ARCHIVE_BYTES`."""
    request = urllib.request.Request(url, headers={"User-Agent": "hermuse-plugin"})
    with urllib.request.urlopen(request, timeout=_DOWNLOAD_TIMEOUT_S) as response:
        total = 0
        while True:
            chunk = response.read(1 << 16)
            if not chunk:
                return
            total += len(chunk)
            if total > MAX_ARCHIVE_BYTES:
                raise BridgeError(f"{url} is larger than expected")
            out.write(chunk)


def _extract_binary(archive: Path) -> bytes:
    """Bytes of :data:`ARCHIVE_BINARY` in the release tarball (never extracted to disk by name)."""
    try:
        with tarfile.open(archive, "r:gz") as tar:
            for member in tar:
                if member.name not in (ARCHIVE_BINARY, f"./{ARCHIVE_BINARY}") or not member.isreg():
                    continue
                if member.size > MAX_BINARY_BYTES:
                    break
                source = tar.extractfile(member)
                if source is None:
                    break
                return source.read()
    except (tarfile.TarError, OSError, EOFError) as exc:
        raise BridgeError(f"cannot read the CLIProxyAPI archive: {exc}") from exc
    raise BridgeError(f"the CLIProxyAPI archive holds no usable {ARCHIVE_BINARY}")


def _install(home: os.PathLike[str] | str, asset: Asset,
             fetch: Callable[[str, BinaryIO], None]) -> Path:
    """The verified pinned binary; downloaded first when missing or altered."""
    binary = binary_path(home)
    if _verified(binary, asset.binary_sha256):
        return binary
    bin_dir = _private_dir(binary.parent)
    url = RELEASE_URL.format(version=VERSION, asset=asset.name)
    fd, tmp = tempfile.mkstemp(prefix=".download_", dir=str(bin_dir))
    try:
        with os.fdopen(fd, "wb") as fh:
            try:
                fetch(url, fh)
            except (OSError, ValueError, http.client.HTTPException) as exc:  # URLError, timeouts
                raise BridgeError(f"cannot download {asset.name}: {exc}") from exc
        if _sha256_file(tmp) != asset.archive_sha256:
            raise BridgeError(f"{asset.name} does not match its pinned checksum")
        data = _extract_binary(Path(tmp))
        if hashlib.sha256(data).hexdigest() != asset.binary_sha256:
            raise BridgeError(f"the binary in {asset.name} does not match its pinned checksum")
        _write_private(binary, data, mode=0o700)
    finally:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
    for old in bin_dir.glob("cliproxy-*"):  # binaries of earlier pinned versions
        if old != binary:
            with contextlib.suppress(OSError):
                old.unlink()
    return binary


# --- process --------------------------------------------------------------------


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        # Like Go's listeners: a port in TIME_WAIT after a restart is free.
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True


def _cmdline(pid: int) -> list[bytes]:
    """Arguments of *pid*; empty for a zombie or a vanished process."""
    try:
        return [arg for arg in Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0") if arg]
    except OSError:
        return []


def _bridge_process(home: os.PathLike[str] | str) -> Optional[dict[str, Any]]:
    """``cliproxy.json`` while its pid runs this home's config, else None.

    The command line must name this home's ``config.yaml``: a recycled pid or
    a zombie never passes.
    """
    data = _read_json(bridge_root(home) / PROCESS_FILE)
    if not isinstance(data, dict):
        return None
    pid, port = data.get("pid"), data.get("port")
    if not isinstance(pid, int) or pid <= 0 or not isinstance(port, int):
        return None
    if str(bridge_root(home) / CONFIG_FILE).encode() not in _cmdline(pid):
        return None
    return data


def _exited(pid: int) -> bool:
    """True once *pid* closed its files (zombie or reaped): its port is free again.

    An empty command line is not enough: the kernel drops it before closing
    the process's sockets.
    """
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[-1].split()
    except OSError:
        return True
    return not fields or fields[0] in ("Z", "X")


def _stop_pid(pid: int) -> None:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            return
        deadline = time.monotonic() + _STOP_WAIT_S
        while time.monotonic() < deadline:
            if _exited(pid):
                return
            time.sleep(0.05)


def _start(home: os.PathLike[str] | str, binary: Path,
           keys: dict[str, Any]) -> tuple[dict[str, Any], subprocess.Popen]:
    """Spawn CLIProxyAPI detached on the persisted port (a new one when that is taken)."""
    root = bridge_root(home)
    if not _port_free(keys["port"]):
        logger.warning("hermuse bridge: port %s is taken, moving", keys["port"])
        keys = {**keys, "port": _free_port()}
        _save_keys(home, keys)
    auth = _private_dir(auth_dir(home))
    config = root / CONFIG_FILE
    _write_private(config, config_text(
        keys["port"], auth, keys["api_key"], keys["management_key"]).encode())
    log_fd = os.open(root / LOG_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(log_fd, 0o600)
    with os.fdopen(log_fd, "wb") as log:
        process = subprocess.Popen(
            [str(binary), "-config", str(config)], cwd=str(root), stdin=subprocess.DEVNULL,
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    record = {"pid": process.pid, "binary": str(binary), "port": keys["port"],
              "started": time.time()}
    _write_private(root / PROCESS_FILE, (json.dumps(record) + "\n").encode())
    # Reap it when it exits: a zombie child would keep its pid.
    threading.Thread(target=process.wait, name="hermuse-bridge-reaper", daemon=True).start()
    return record, process


def _log_tail(home: os.PathLike[str] | str) -> str:
    try:
        text = (bridge_root(home) / LOG_FILE).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    return " | ".join(line.strip() for line in text.splitlines() if line.strip())[-_LOG_TAIL_CHARS:]


def _request(port: int, method: str, path: str, *, key: str,
             query: Optional[dict[str, str]] = None, body: Optional[bytes] = None,
             timeout: float = _HTTP_TIMEOUT_S) -> tuple[int, bytes]:
    """HTTP to the bridge on 127.0.0.1 without proxies: ``(status, body)``.

    Raises ``OSError`` when it does not answer at all.
    """
    url = f"http://127.0.0.1:{port}{path}"
    if query:
        url += "?" + urllib.parse.urlencode(query)
    headers = {"Authorization": f"Bearer {key}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with _LOOPBACK.open(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, exc.read()
        finally:
            exc.close()


def _call(port: int, method: str, path: str, *, key: str,
          query: Optional[dict[str, str]] = None, body: Optional[bytes] = None) -> tuple[int, bytes]:
    try:
        return _request(port, method, path, key=key, query=query, body=body)
    except OSError as exc:
        raise BridgeError(f"CLIProxyAPI does not answer: {exc}") from exc


def _probe(port: int, management_key: str) -> bool:
    try:
        status, _ = _request(port, "GET", "/v0/management/config", key=management_key,
                             timeout=_PROBE_TIMEOUT_S)
    except OSError:
        return False
    return status == 200


def _wait_ready(port: int, management_key: str, deadline: float,
                process: Optional[subprocess.Popen] = None) -> bool:
    while True:
        if _probe(port, management_key):
            return True
        if process is not None and process.poll() is not None:
            return False
        if time.monotonic() >= deadline:
            return False
        time.sleep(_POLL_S)


def _serve(home: os.PathLike[str] | str, binary: Path, keys: dict[str, Any],
           deadline: float) -> dict[str, Any]:
    """Record of a CLIProxyAPI of *binary* answering on loopback; (re)started as needed.

    Called with the lock held. A process of another binary (an earlier pinned
    version) or one that never answers is replaced.
    """
    ready_by = min(deadline, time.monotonic() + _READY_TIMEOUT_S)
    record = _bridge_process(home)
    if record is not None:
        if record.get("binary") == str(binary) and _wait_ready(
                record["port"], keys["management_key"], ready_by):
            return record
        _stop_pid(record["pid"])
    record, process = _start(home, binary, keys)
    if not _wait_ready(record["port"], keys["management_key"],
                       min(deadline, time.monotonic() + _READY_TIMEOUT_S), process):
        _stop_pid(process.pid)
        raise BridgeError(f"CLIProxyAPI did not start: {_log_tail(home) or 'no output'}")
    return record


def ensure(home: os.PathLike[str] | str, timeout: float = ENSURE_TIMEOUT_S) -> dict[str, Any]:
    """Install the pinned binary when missing, start the bridge, and say how Hermes reaches it.

    ``{base_url, api_key, version}``: the custom endpoint of Hermes is
    ``<base_url>/v1`` with ``api_key`` as its bearer key (the management key
    never leaves this host). Raises :class:`BridgeUnavailable` or
    :class:`BridgeError`.
    """
    asset = _asset()
    deadline = time.monotonic() + timeout
    with _locked(home, deadline):
        binary = _install(home, asset, _download)
        keys = _ensure_keys(home)
        record = _serve(home, binary, keys, deadline)
    return {"base_url": f"http://127.0.0.1:{record['port']}", "api_key": keys["api_key"],
            "version": VERSION}


def _running(home: os.PathLike[str] | str) -> tuple[int, dict[str, Any]]:
    """``(port, keys)`` of the answering bridge; a stopped one that was set up starts first."""
    asset = _asset()
    keys = load_keys(home)
    if keys is None or not binary_path(home).is_file():
        raise BridgeUnavailable(NOT_SET_UP_DETAIL)
    record = _bridge_process(home)
    if record is not None and _probe(record["port"], keys["management_key"]):
        return record["port"], keys
    deadline = time.monotonic() + _READY_TIMEOUT_S * 2
    with _locked(home, deadline):
        binary = _install(home, asset, _download)
        record = _serve(home, binary, keys, deadline)
    return record["port"], keys


def start_if_configured(home: os.PathLike[str] | str) -> None:
    """Plugin-load check: start a bridge set up earlier that does not run.

    One ``/proc`` read when it runs; never downloads, never waits for it to
    answer, never raises (a failure shows in :func:`status`).
    """
    try:
        asset = ASSETS.get(platform_key() or "")
        keys = load_keys(home)
        binary = binary_path(home)
        if asset is None or keys is None or not binary.is_file() or _bridge_process(home):
            return
        with _locked(home, time.monotonic()):
            if _bridge_process(home) is None and _verified(binary, asset.binary_sha256):
                _start(home, binary, keys)
    except BridgeUnavailable:
        return  # busy: whoever holds the lock is starting it
    except Exception as exc:  # noqa: BLE001 — plugin loading must never fail on the bridge
        logger.warning("hermuse bridge: not started: %s", exc)


def stop(home: os.PathLike[str] | str, timeout: float = 30.0) -> None:
    """Stop the bridge process of *home*; a no-op when none runs."""
    if platform_key() is None:
        return
    with _locked(home, time.monotonic() + timeout):
        record = _bridge_process(home)
        if record is not None:
            _stop_pid(record["pid"])
        with contextlib.suppress(FileNotFoundError):
            (bridge_root(home) / PROCESS_FILE).unlink()


# --- accounts and models --------------------------------------------------------


def _error_of(body: bytes) -> str:
    with contextlib.suppress(ValueError):
        data = json.loads(body)
        if isinstance(data, dict):
            for key in ("error", "message", "detail"):
                if isinstance(data.get(key), str) and data[key]:
                    return data[key]
    return body.decode("utf-8", errors="replace").strip()[:200] or "no details"


def _account(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": str(entry.get("name") or entry.get("id") or ""),
        "provider": str(entry.get("provider") or entry.get("type") or ""),
        "email": str(entry.get("email") or ""),
        "usable": not entry.get("disabled") and not entry.get("unavailable"),
        "status": str(entry.get("status") or ""),
        "status_message": str(entry.get("status_message") or ""),
    }


def _api_accounts(port: int, management_key: str) -> list[dict[str, Any]]:
    status, body = _call(port, "GET", "/v0/management/auth-files", key=management_key)
    if status != 200:
        raise BridgeError(f"CLIProxyAPI did not list its accounts: {_error_of(body)}")
    with contextlib.suppress(ValueError, AttributeError):
        files = json.loads(body).get("files")
        if isinstance(files, list):
            return [_account(entry) for entry in files if isinstance(entry, dict)]
    raise BridgeError("CLIProxyAPI did not list its accounts")


def _disk_accounts(home: os.PathLike[str] | str) -> list[dict[str, Any]]:
    """Account files of a stopped bridge: known, but nothing serves them."""
    try:
        paths = sorted(auth_dir(home).iterdir())
    except OSError:
        return []
    accounts = []
    for path in paths:
        if not ACCOUNT_NAME_RE.fullmatch(path.name) or not path.is_file():
            continue
        data = _read_json(path)
        if isinstance(data, dict):
            accounts.append({**_account({**data, "name": path.name, "provider": data.get("type")}),
                             "usable": False, "status": "stopped"})
    return accounts


def status(home: os.PathLike[str] | str) -> dict[str, Any]:
    """``{supported, platform, version, installed, running, base_url, accounts, detail, sign_in}``.

    Never raises. ``accounts`` are ``{name, provider, email, usable, status,
    status_message}``; ``base_url`` is null until the bridge was set up;
    ``sign_in`` says subscriptions sign in here (:func:`start_login`). A
    bridge that was set up but does not run is started in the background.
    """
    key = platform_key()
    result: dict[str, Any] = {
        "supported": key in ASSETS, "platform": key or f"{sys.platform}-{platform.machine().lower()}",
        "version": VERSION, "installed": False, "running": False, "base_url": None,
        "accounts": [], "detail": "", "sign_in": True,
    }
    if key not in ASSETS:
        result["detail"] = UNSUPPORTED_DETAIL
        return result
    keys = load_keys(home)
    result["installed"] = binary_path(home).is_file()
    record = _bridge_process(home)
    if record is not None:
        result["base_url"] = f"http://127.0.0.1:{record['port']}"
    elif keys is not None:
        result["base_url"] = f"http://127.0.0.1:{keys['port']}"
    if record is not None and keys is not None:
        try:
            result["accounts"] = _api_accounts(record["port"], keys["management_key"])
            result["running"] = True
            return result
        except BridgeError as exc:
            result["detail"] = str(exc)
    elif result["installed"] and keys is not None:
        start_if_configured(home)
        result["detail"] = STARTING_DETAIL
    result["accounts"] = _disk_accounts(home)
    return result


def check_account_name(name: Any) -> str:
    """*name* when it is a plain account file name (one segment, ``.json``), else ``ValueError``."""
    if not isinstance(name, str) or not ACCOUNT_NAME_RE.fullmatch(name):
        raise ValueError("invalid account file name")
    return name


def _json_object(body: bytes) -> Optional[dict[str, Any]]:
    with contextlib.suppress(ValueError):
        data = json.loads(body)
        if isinstance(data, dict):
            return data
    return None


def _management_json(home: os.PathLike[str] | str, method: str, path: str, what: str, *,
                     query: Optional[dict[str, str]] = None,
                     payload: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    """A management call of the running bridge: its JSON object on 200.

    A 4xx answer (unknown or expired sign-in, bad address) is a ``ValueError``
    with CLIProxyAPI's message; anything else a :class:`BridgeError`.
    """
    port, keys = _running(home)
    body = None if payload is None else json.dumps(payload).encode()
    status_code, raw = _call(port, method, path, key=keys["management_key"], query=query,
                             body=body)
    if 400 <= status_code < 500:
        raise ValueError(_error_of(raw))
    data = _json_object(raw)
    if status_code != 200 or data is None:
        raise BridgeError(f"CLIProxyAPI could not {what}: {_error_of(raw)}")
    return data


def _check_state(state: Any) -> str:
    if not isinstance(state, str) or not state.strip() or len(state) > 200:
        raise ValueError("invalid sign-in state")
    return state.strip()


def start_login(home: os.PathLike[str] | str, provider: str) -> dict[str, Any]:
    """Start a subscription sign-in on this bridge.

    → CLIProxyAPI's ``{status, url, state}``, plus ``flow: "device"``,
    ``user_code`` and ``expires_in`` for device-code sign-ins. A browser
    sign-in ends with :func:`submit_callback`; poll :func:`login_status`.
    """
    if provider not in LOGIN_PROVIDERS:
        raise ValueError("unknown subscription")
    data = _management_json(home, "GET", f"/v0/management/{provider}-auth-url",
                            "start the sign-in")
    if not isinstance(data.get("url"), str) or not isinstance(data.get("state"), str):
        raise BridgeError("CLIProxyAPI started a sign-in without a link")
    return data


def login_status(home: os.PathLike[str] | str, state: str) -> dict[str, Any]:
    """``{status: "wait" | "ok" | "error", error?}`` of sign-in *state*."""
    data = _management_json(home, "GET", "/v0/management/get-auth-status",
                            "read the sign-in", query={"state": _check_state(state)})
    result = {"status": str(data.get("status") or "")}
    if isinstance(data.get("error"), str):
        result["error"] = data["error"]
    return result


def submit_callback(home: os.PathLike[str] | str, redirect_url: str) -> dict[str, Any]:
    """Hand CLIProxyAPI the address the browser was sent to after the sign-in.

    CLIProxyAPI reads ``state`` and ``code`` (or ``error``) from it and
    finishes the pending sign-in of that state; ``ValueError`` when no sign-in
    waits for it.
    """
    if not isinstance(redirect_url, str) or not redirect_url.strip() \
            or len(redirect_url) > MAX_REDIRECT_URL_CHARS:
        raise ValueError("paste the address the browser showed after the sign-in")
    _management_json(home, "POST", "/v0/management/oauth-callback", "take the address",
                     payload={"redirect_url": redirect_url.strip()})
    return {"ok": True}


def cancel_login(home: os.PathLike[str] | str, state: str) -> dict[str, Any]:
    """Cancel sign-in *state* → ``{cancelled}``."""
    data = _management_json(home, "DELETE", "/v0/management/oauth-session",
                            "cancel the sign-in", query={"state": _check_state(state)})
    return {"cancelled": bool(data.get("cancelled", True))}


def delete_account(home: os.PathLike[str] | str, name: str) -> bool:
    """Remove account file *name*; False when there is none."""
    check_account_name(name)
    port, keys = _running(home)
    status_code, body = _call(port, "DELETE", "/v0/management/auth-files",
                              key=keys["management_key"], query={"name": name})
    if status_code == 404:
        return False
    if status_code != 200:
        raise BridgeError(f"CLIProxyAPI could not remove the account: {_error_of(body)}")
    return True


def models(home: os.PathLike[str] | str) -> dict[str, Any]:
    """``GET /v1/models`` of the bridge: ``{object: "list", data: [{id, object, owned_by}]}``.

    Only models with a usable account are listed.
    """
    port, keys = _running(home)
    status_code, body = _call(port, "GET", "/v1/models", key=keys["api_key"])
    if status_code != 200:
        raise BridgeError(f"CLIProxyAPI did not list its models: {_error_of(body)}")
    entries = None
    with contextlib.suppress(ValueError, AttributeError):
        entries = json.loads(body).get("data")
    if not isinstance(entries, list):
        raise BridgeError("CLIProxyAPI did not list its models")
    return {"object": "list", "data": [
        {"id": entry["id"], "object": "model", "owned_by": entry.get("owned_by")}
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("id"), str) and entry["id"]
    ]}
