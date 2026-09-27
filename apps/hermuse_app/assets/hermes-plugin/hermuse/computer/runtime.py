"""Backend seam of the agent's computer, and its Docker implementation.

The browser provider, the hooks, ``setup``, the CLI and the dashboard routes
only use :class:`ComputerRuntime` obtained from :func:`get_runtime` — never
Docker directly. ``rt`` arguments are the ``runtime.json`` dict; whatever the
backend, it carries loopback ``cdp_port``, ``screen_port`` and ``token``.

``timeout`` arguments are one global deadline for the whole call (lock wait
included), not a per-step limit.

``prepare`` never blocks on slow work: it starts ``bootstrap.py`` as one
detached process that installs Docker when it is missing and installable
(Linux, passwordless sudo), then pulls the published image (building it
locally when the pull fails). ``status`` reports it as ``building``.
"""

from __future__ import annotations

import http.client
import json
import os
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Optional, Protocol, Sequence

from . import state

IMAGE = "hermuse-computer:0.2.0"
# Published by .github/workflows/computer-image.yml (linux/amd64 + linux/arm64).
REGISTRY_IMAGE = f"ghcr.io/yellow-stick/{IMAGE}"
IMAGE_DIR = Path(__file__).resolve().parent / "image"
BOOTSTRAP = Path(__file__).resolve().parent / "bootstrap.py"
CDP_PORT = 9223
SCREEN_PORT = 8765
MODES = ("browser", "desktop")

DOCKER_SOCKET = "/var/run/docker.sock"
GET_DOCKER_URL = "https://docs.docker.com/get-started/get-docker/"
# build.json "step" of the running bootstrap -> status detail.
STEP_DOCKER, STEP_PULL, STEP_BUILD = "docker", "pull", "build"
STEP_DETAILS = {
    STEP_DOCKER: "Installing Docker…",
    STEP_PULL: "Downloading the computer image…",
    STEP_BUILD: "Building the computer image…",
}

_DAEMON_PROBE_S = 5.0
_SUDO_PROBE_S = 5.0
_STEP_MIN_S = 0.5
_STEP_MAX_S = 10.0
_CDP_POLL_S = 0.5
_HTTP_TIMEOUT_S = 3.0
_PREPARE_TIMEOUT_S = 10.0
_STOP_TIMEOUT_S = 30.0
_BUILD_MAX_AGE_S = 2 * 3600.0  # an older build.json is a dead (or reused) pid

# Loopback only: never route 127.0.0.1 through HTTP(S)_PROXY.
_LOOPBACK = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class ComputerRuntime(Protocol):
    def status(self, home: Any, timeout: float = 10.0) -> dict: ...

    def prepare(self, home: Any) -> None: ...

    def ensure_running(self, home: Any, timeout: float = 30.0) -> dict: ...

    def stop(self, home: Any) -> None: ...

    def cdp_ws_url(self, rt: dict) -> str: ...

    def tabs(self, rt: dict) -> list[dict]: ...

    def activate(self, rt: dict, tab_id: str) -> None: ...

    def close_tab(self, rt: dict, tab_id: str) -> None: ...

    def thumbnail(self, rt: dict) -> bytes: ...

    def set_mode(self, rt: dict, mode: str) -> None: ...


def get_runtime() -> ComputerRuntime:
    """The only construction site of a computer backend."""
    return DockerComputerRuntime()


def profile_name(home: Any) -> str:
    """Last path segment of *home* reduced to ``[a-z0-9-]`` (``default`` when empty)."""
    return re.sub(r"[^a-z0-9]+", "-", Path(home).name.lower()).strip("-") or "default"


def container_name(home: Any) -> str:
    return f"hermuse-computer-{profile_name(home)}"


def volume_name(home: Any) -> str:
    return f"{container_name(home)}-home"


def current_user() -> str:
    """Login name of this process ("" when unknown)."""
    try:
        import pwd

        return pwd.getpwuid(os.getuid()).pw_name
    except (ImportError, KeyError):
        return os.environ.get("USER") or os.environ.get("USERNAME") or ""


def docker_install_hint() -> str:
    """``docker_missing`` detail: what the user runs when Hermuse cannot install Docker itself."""
    if sys.platform.startswith("linux"):
        user = current_user() or "$USER"
        return (f"curl -fsSL https://get.docker.com | sudo sh && "
                f"sudo usermod -aG docker {shlex.quote(user)}")
    return f"Install Docker Desktop: {GET_DOCKER_URL}"


def needs_docker_group() -> bool:
    """True when this process lacks a ``docker`` group membership granted after it started.

    ``usermod -aG docker`` only reaches new logins: a Hermes started before it
    cannot open the Docker socket until restarted, but ``sg docker`` can.
    """
    if os.name != "posix" or not os.path.exists(DOCKER_SOCKET):
        return False
    if os.access(DOCKER_SOCKET, os.R_OK | os.W_OK):
        return False
    try:
        import grp

        members = grp.getgrnam("docker").gr_mem
    except (ImportError, KeyError):
        return False
    user = current_user()
    return bool(user) and user in members


def docker_command(docker: str, args: Sequence[str]) -> list[str]:
    """argv running ``docker <args>``, through ``sg docker`` when :func:`needs_docker_group`."""
    command = [docker, *args]
    if needs_docker_group():
        sg = shutil.which("sg")
        if sg is not None:
            return [sg, "docker", "-c", shlex.join(command)]
    return command


def docker_installer(timeout: float = _SUDO_PROBE_S) -> Optional[str]:
    """How the bootstrap can install Docker here: ``"apt"``, ``"script"`` (get.docker.com), or None.

    Only on Linux with passwordless sudo (``sudo -n true``); anything else needs the user.
    """
    if not sys.platform.startswith("linux"):
        return None
    sudo = shutil.which("sudo")
    if sudo is None:
        return None
    try:
        probe = subprocess.run([sudo, "-n", "true"], stdin=subprocess.DEVNULL,
                               capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if probe.returncode != 0:
        return None
    if shutil.which("apt-get") is not None:
        return "apt"
    if shutil.which("curl") is not None:
        return "script"
    return None


def loopback_request(url: str, timeout: float, *, method: str = "GET",
                     body: Optional[dict] = None) -> bytes:
    """HTTP to 127.0.0.1 without proxies; raises ``OSError`` (``HTTPError`` for >= 400)."""
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"Content-Type": "application/json"} if body is not None else {}
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    with _LOOPBACK.open(request, timeout=timeout) as response:
        return response.read()


class DockerTimeout(RuntimeError):
    def __init__(self, command: str) -> None:
        super().__init__(f"hermuse computer: error — docker {command} timed out")
        self.command = command


def _status(state_name: str, detail: str = "") -> dict:
    return {"state": state_name, "detail": detail}


def _first_line(text: str) -> str:
    return next((line.strip() for line in (text or "").splitlines() if line.strip()), "")


def _no_such(stderr: str) -> bool:
    return "no such" in (stderr or "").lower()


def _step_timeout(deadline: float, command: str) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise DockerTimeout(command)
    return max(_STEP_MIN_S, min(_STEP_MAX_S, remaining))


def _failed(result: subprocess.CompletedProcess, what: str) -> RuntimeError:
    return RuntimeError(f"hermuse computer: error — {_first_line(result.stderr) or what + ' failed'}")


class DockerComputerRuntime:
    """One long-lived container per Hermes profile, built from :data:`IMAGE`."""

    # --- docker ------------------------------------------------------------------

    def _docker(self, args: list[str], timeout: float) -> subprocess.CompletedProcess:
        docker = shutil.which("docker")
        if docker is None:
            raise RuntimeError("hermuse computer: docker_missing — docker was not found on PATH")
        try:
            return subprocess.run(docker_command(docker, args), capture_output=True,
                                  encoding="utf-8", errors="replace", timeout=timeout)
        except subprocess.TimeoutExpired:
            raise DockerTimeout(args[0]) from None
        except OSError as exc:
            raise RuntimeError(f"hermuse computer: error — cannot run docker: {exc}") from exc

    def _run(self, args: list[str], deadline: float) -> subprocess.CompletedProcess:
        return self._docker(args, _step_timeout(deadline, args[0]))

    def _daemon_probe(self, deadline: float) -> subprocess.CompletedProcess:
        """``docker version`` capped at 5 s; ``DockerTimeout`` when the daemon hangs."""
        timeout = min(_DAEMON_PROBE_S, _step_timeout(deadline, "version"))
        return self._docker(["version", "--format", "{{.Server.Version}}"], timeout)

    def _image_present(self, deadline: float) -> bool:
        return self._run(["image", "inspect", "--format", "{{.Id}}", IMAGE], deadline).returncode == 0

    @staticmethod
    def _running_bootstrap(home: Any) -> Optional[dict]:
        """``build.json`` of a live bootstrap, else None (dead, finished, or too old to trust the pid)."""
        build = state.read_build(home)
        if not build:
            return None
        try:
            started = float(build.get("started"))
        except (TypeError, ValueError):
            return None
        if time.time() - started < _BUILD_MAX_AGE_S and state.pid_alive(build.get("pid")):
            return build
        return None

    # --- status -------------------------------------------------------------------

    def status(self, home: Any, timeout: float = 10.0) -> dict:
        """``{"state", "detail"}``; never raises."""
        try:
            return self._status(home, time.monotonic() + timeout)
        except DockerTimeout as exc:
            return _status("error", f"docker {exc.command} timed out")
        except RuntimeError as exc:
            return _status("error", str(exc).split(" — ", 1)[-1])

    def _status(self, home: Any, deadline: float) -> dict:
        # First: while it installs Docker there is no docker binary yet.
        bootstrap = self._running_bootstrap(home)
        if bootstrap is not None:
            return _status("building", STEP_DETAILS.get(
                bootstrap.get("step"), "Preparing the agent's computer…"))
        if shutil.which("docker") is None:
            return _status("docker_missing", docker_install_hint())
        _step_timeout(deadline, "version")  # an exhausted budget is not a daemon failure
        try:
            probe = self._daemon_probe(deadline)
        except DockerTimeout:
            return _status("daemon_down", "docker version timed out")
        if probe.returncode != 0:
            return _status("daemon_down", _first_line(probe.stderr) or "the Docker daemon did not answer")
        if not self._image_present(deadline):
            build = state.read_build(home)
            # A bootstrap that died installing Docker never tried the image.
            if build is not None and build.get("step") != STEP_DOCKER:
                tail = state.build_log_tail(home) or "no build output"
                return _status("error", f"Computer image build failed: {tail}")
            return _status("image_missing", f"{IMAGE} is not on this host yet")
        name = container_name(home)
        inspect = self._run(
            ["inspect", "--type", "container", "--format", "{{.State.Running}}", name], deadline)
        if inspect.returncode != 0:
            if _no_such(inspect.stderr):
                return _status("stopped", f"{name} is not created yet")
            return _status("error", _first_line(inspect.stderr) or "docker inspect failed")
        return _status("running" if inspect.stdout.strip() == "true" else "stopped", name)

    # --- lifecycle ----------------------------------------------------------------

    def prepare(self, home: Any) -> None:
        """Start the background bootstrap when Docker (installable) or the image is missing.

        Never blocks on it; a no-op while it runs or once the image exists.
        Calling it again after a failed bootstrap is the retry.
        """
        deadline = time.monotonic() + _PREPARE_TIMEOUT_S
        with state.lifecycle_lock(home, deadline):
            if self._running_bootstrap(home) is not None:
                return
            if shutil.which("docker") is None:
                installer = docker_installer(
                    min(_SUDO_PROBE_S, _step_timeout(deadline, "sudo")))
                if installer is not None:
                    self._start_bootstrap(home, installer)
                return  # otherwise status() tells the user how to install Docker
            if self._daemon_probe(deadline).returncode != 0:
                return  # nothing can pull or build now; status() reports daemon_down
            if self._image_present(deadline):
                return
            self._start_bootstrap(home, None)

    @staticmethod
    def _start_bootstrap(home: Any, installer: Optional[str]) -> None:
        state.clear_build(home)
        log_path = state.build_log_path(home)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        command = [sys.executable, str(BOOTSTRAP), str(home)]
        if installer is not None:
            command.append(installer)
        with open(log_path, "wb") as log:  # truncates the previous attempt
            bootstrap = subprocess.Popen(
                command, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                start_new_session=True)
        state.write_build(home, bootstrap.pid, time.time(),
                          STEP_DOCKER if installer is not None else STEP_PULL)
        # Reap it when done: a zombie child would still look alive to pid_alive().
        threading.Thread(target=bootstrap.wait, name="hermuse-computer-bootstrap",
                         daemon=True).start()

    def ensure_running(self, home: Any, timeout: float = 30.0) -> dict:
        deadline = time.monotonic() + timeout
        with state.lifecycle_lock(home, deadline):
            current = self._status(home, deadline)
            if current["state"] not in ("stopped", "running"):
                raise RuntimeError(f"hermuse computer: {current['state']} — {current['detail']}")
            name = container_name(home)
            image = self._run(
                ["inspect", "--type", "container", "--format", "{{.Config.Image}}", name], deadline)
            exists = image.returncode == 0
            if exists and image.stdout.strip() != IMAGE:
                # Plugin upgraded: recreate from the new image; the named volume keeps logins.
                removed = self._run(["rm", "-f", name], deadline)
                if removed.returncode != 0:
                    raise _failed(removed, "docker rm")
                exists = False
            started = True
            if not exists:
                created = self._run([
                    "run", "-d", "--name", name, "--shm-size", "2g", "--memory", "3g",
                    "--pids-limit", "1024", "--security-opt", "no-new-privileges",
                    "--cap-drop", "ALL", "-e", f"SCREEND_TOKEN={secrets.token_urlsafe(32)}",
                    "-v", f"{volume_name(home)}:/home/hermuse",
                    "-p", f"127.0.0.1::{CDP_PORT}", "-p", f"127.0.0.1::{SCREEN_PORT}", IMAGE,
                ], deadline)
                if created.returncode != 0:
                    raise _failed(created, "docker run")
            elif current["state"] != "running":
                restarted = self._run(["start", name], deadline)
                if restarted.returncode != 0:
                    raise _failed(restarted, "docker start")
            else:
                started = False
            cdp_port = self._port(name, CDP_PORT, deadline)
            screen_port = self._port(name, SCREEN_PORT, deadline)
            token = self._token(name, deadline)
            self._wait_for_cdp(cdp_port, deadline, timeout)
            previous = state.read_runtime(home) or {}
            keep_mode = not started and previous.get("container") == name
            rt = {
                "backend": "docker", "container": name, "cdp_port": cdp_port,
                "screen_port": screen_port, "token": token, "image": IMAGE,
                # A fresh screend starts in browser mode.
                "mode": previous.get("mode") if keep_mode and previous.get("mode") in MODES else "browser",
            }
            state.write_runtime(home, rt)
            return rt

    def _port(self, name: str, port: int, deadline: float) -> int:
        result = self._run(["port", name, f"{port}/tcp"], deadline)
        if result.returncode != 0:
            raise _failed(result, "docker port")
        for line in result.stdout.splitlines():
            host_port = line.strip().rpartition(":")[2]
            if host_port.isdigit():
                return int(host_port)
        raise RuntimeError(f"hermuse computer: error — {name} does not publish {port}/tcp")

    def _token(self, name: str, deadline: float) -> str:
        result = self._run(["inspect", "--type", "container", "--format",
                            "{{range .Config.Env}}{{println .}}{{end}}", name], deadline)
        if result.returncode != 0:
            raise _failed(result, "docker inspect")
        for line in result.stdout.splitlines():
            if line.startswith("SCREEND_TOKEN="):
                return line.split("=", 1)[1].strip()
        raise RuntimeError(f"hermuse computer: error — {name} has no SCREEND_TOKEN")

    @staticmethod
    def _wait_for_cdp(cdp_port: int, deadline: float, timeout: float) -> None:
        url = f"http://127.0.0.1:{cdp_port}/json/version"
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError(
                    f"hermuse computer: error — Chromium did not answer on CDP within {timeout:g} s")
            try:
                loopback_request(url, min(1.0, remaining))
                return
            except (OSError, http.client.HTTPException):
                pass
            time.sleep(max(0.0, min(_CDP_POLL_S, deadline - time.monotonic())))

    def stop(self, home: Any) -> None:
        deadline = time.monotonic() + _STOP_TIMEOUT_S
        with state.lifecycle_lock(home, deadline):
            if shutil.which("docker") is None:
                return
            result = self._run(["stop", container_name(home)], deadline)
            if result.returncode != 0 and not _no_such(result.stderr):
                raise _failed(result, "docker stop")

    # --- Chromium (CDP) and screend -------------------------------------------------

    @staticmethod
    def _cdp(rt: dict, path: str) -> bytes:
        return loopback_request(f"http://127.0.0.1:{int(rt['cdp_port'])}{path}", _HTTP_TIMEOUT_S)

    def cdp_ws_url(self, rt: dict) -> str:
        version = json.loads(self._cdp(rt, "/json/version"))
        path = urllib.parse.urlsplit(str(version.get("webSocketDebuggerUrl") or "")).path
        if not path.startswith("/devtools/browser/"):
            raise RuntimeError("hermuse computer: error — Chromium reported no browser WebSocket URL")
        # Never trust the host Chromium reports: it sits behind Docker's port mapping.
        return f"ws://127.0.0.1:{int(rt['cdp_port'])}{path}"

    def tabs(self, rt: dict) -> list[dict]:
        targets = json.loads(self._cdp(rt, "/json/list"))
        return [
            {"id": str(t.get("id") or ""), "url": str(t.get("url") or ""),
             "title": str(t.get("title") or "")}
            for t in targets if isinstance(t, dict) and t.get("type") == "page"
        ]

    def activate(self, rt: dict, tab_id: str) -> None:
        self._cdp(rt, f"/json/activate/{urllib.parse.quote(tab_id, safe='')}")

    def close_tab(self, rt: dict, tab_id: str) -> None:
        self._cdp(rt, f"/json/close/{urllib.parse.quote(tab_id, safe='')}")

    @staticmethod
    def _screen_url(rt: dict, path: str) -> str:
        token = urllib.parse.quote(str(rt["token"]), safe="")
        return f"http://127.0.0.1:{int(rt['screen_port'])}{path}?token={token}"

    def thumbnail(self, rt: dict) -> bytes:
        return loopback_request(self._screen_url(rt, "/thumbnail"), _HTTP_TIMEOUT_S)

    def set_mode(self, rt: dict, mode: str) -> None:
        if mode not in MODES:
            raise ValueError(f"mode must be one of {MODES}")
        loopback_request(self._screen_url(rt, "/mode"), _HTTP_TIMEOUT_S, method="POST",
                         body={"mode": mode})
        rt["mode"] = mode
        from hermes_constants import get_hermes_home

        home = get_hermes_home()
        current = state.read_runtime(home)
        if current is not None and current.get("container") == rt.get("container"):
            state.write_runtime(home, {**current, "mode": mode})
