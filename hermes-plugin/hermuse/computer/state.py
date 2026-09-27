"""Computer state files under ``HERMES_HOME/hermuse/computer/`` (stdlib only).

* ``runtime.json`` ``{backend, container, cdp_port, screen_port, token, image, mode}``
  — written by :meth:`runtime.ComputerRuntime.ensure_running`.
* ``control.json`` ``{holder: "agent"|"human", lease_id, since}`` — the Take
  control lease. Every writer lives in the dashboard process (the WebSocket
  bridge) and goes through :func:`take_control` / :func:`release_control` /
  :func:`reset_control`; the agent's ``pre_tool_call`` hook only reads it.
* ``build.json`` ``{pid, started, step}`` + ``build.log`` — the background
  bootstrap (Docker install, image pull or build); ``step`` is its current stage.
* ``snapshots/<tool_call_id>.jpg`` — screen right after each browser tool call.
* ``runtime.lock/`` — inter-process lifecycle lock (:func:`lifecycle_lock`).
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import shutil
import tempfile
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Iterator, Optional

try:  # agent process: package hermes_plugins.hermuse
    from .. import store
except ImportError:  # dashboard backend / tests: plugin root on sys.path
    import store  # type: ignore[no-redef]

AGENT = "agent"
HUMAN = "human"

RUNTIME_FILE = "runtime.json"
CONTROL_FILE = "control.json"
BUILD_FILE = "build.json"
BUILD_LOG = "build.log"
SNAPSHOTS_DIR = "snapshots"
LOCK_DIR = "runtime.lock"
LOCK_OWNER = "owner.json"

SNAPSHOT_KEEP = 200
TOOL_CALL_ID_RE = re.compile(r"^[A-Za-z0-9_\-:.]{1,128}$")

_LOCK_POLL_S = 0.2
_LOCK_OWNERLESS_STALE_S = 10.0
_LOCK_MAX_AGE_S = 600.0
LOCK_BUSY_MESSAGE = "hermuse computer: error — another Hermuse process is starting the computer"

# Serializes control writes inside the (single) writer process.
_control_lock = threading.Lock()


def computer_root(home: os.PathLike[str] | str) -> Path:
    return store.hermuse_root(home) / "computer"


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _write_json(path: Path, data: dict[str, Any]) -> None:
    store.atomic_write_text(path, json.dumps(data, indent=2) + "\n")


def write_bytes_atomic(path: Path, data: bytes) -> None:
    """Binary twin of ``store.atomic_write_text`` (temp file + fsync + rename)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp_", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


# --- runtime.json -------------------------------------------------------------


def read_runtime(home: os.PathLike[str] | str) -> Optional[dict[str, Any]]:
    """The last ``runtime.json``, or None when missing/corrupt."""
    data = _read_json(computer_root(home) / RUNTIME_FILE)
    if not isinstance(data, dict):
        return None
    try:
        int(data["cdp_port"]), int(data["screen_port"]), str(data["token"])
    except (KeyError, TypeError, ValueError):
        return None
    return data


def write_runtime(home: os.PathLike[str] | str, rt: dict[str, Any]) -> None:
    _write_json(computer_root(home) / RUNTIME_FILE, rt)


# --- control.json -------------------------------------------------------------


def _agent_control() -> dict[str, Any]:
    return {"holder": AGENT, "lease_id": None}


def read_control(home: os.PathLike[str] | str) -> dict[str, Any]:
    """``{holder, lease_id, since?}``; the agent holds control when the file is missing/corrupt."""
    data = _read_json(computer_root(home) / CONTROL_FILE)
    if not isinstance(data, dict):
        return _agent_control()
    lease_id = data.get("lease_id")
    if data.get("holder") == HUMAN and isinstance(lease_id, str) and lease_id:
        return {"holder": HUMAN, "lease_id": lease_id, "since": data.get("since")}
    return _agent_control()


def _write_control(home: os.PathLike[str] | str, holder: str, lease_id: Optional[str]) -> None:
    _write_json(computer_root(home) / CONTROL_FILE,
                {"holder": holder, "lease_id": lease_id, "since": store.utcnow_iso()})


def take_control(home: os.PathLike[str] | str) -> str:
    """Give control to a new human lease (latest human wins); returns its ``lease_id``."""
    lease_id = uuid.uuid4().hex
    with _control_lock:
        _write_control(home, HUMAN, lease_id)
    return lease_id


def release_control(home: os.PathLike[str] | str, lease_id: Optional[str]) -> bool:
    """Hand control back to the agent only if *lease_id* still holds it."""
    if not lease_id:
        return False
    with _control_lock:
        if read_control(home)["lease_id"] != lease_id:
            return False
        _write_control(home, AGENT, None)
    return True


def reset_control(home: os.PathLike[str] | str) -> None:
    """Back to the agent unconditionally (leases die with the process holding their sockets)."""
    with _control_lock:
        _write_control(home, AGENT, None)


# --- build.json / build.log ---------------------------------------------------


def read_build(home: os.PathLike[str] | str) -> Optional[dict[str, Any]]:
    data = _read_json(computer_root(home) / BUILD_FILE)
    return data if isinstance(data, dict) else None


def write_build(home: os.PathLike[str] | str, pid: int, started: float, step: str) -> None:
    _write_json(computer_root(home) / BUILD_FILE, {"pid": pid, "started": started, "step": step})


def set_build_step(home: os.PathLike[str] | str, step: str) -> None:
    """Record the bootstrap's current stage, keeping its pid and start time."""
    build = read_build(home) or {"pid": os.getpid(), "started": time.time()}
    _write_json(computer_root(home) / BUILD_FILE, {**build, "step": step})


def clear_build(home: os.PathLike[str] | str) -> None:
    with contextlib.suppress(FileNotFoundError):
        (computer_root(home) / BUILD_FILE).unlink()


def build_log_path(home: os.PathLike[str] | str) -> Path:
    return computer_root(home) / BUILD_LOG


def build_log_tail(home: os.PathLike[str] | str) -> str:
    """Last non-empty line of ``build.log`` ("" when missing/empty)."""
    try:
        with open(build_log_path(home), "rb") as fh:
            fh.seek(0, os.SEEK_END)
            fh.seek(max(0, fh.tell() - 65536))
            text = fh.read().decode("utf-8", "replace")
    except OSError:
        return ""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return lines[-1] if lines else ""


# --- snapshots ----------------------------------------------------------------


def snapshot_path(home: os.PathLike[str] | str, tool_call_id: str) -> Optional[Path]:
    """``snapshots/<id>.jpg``, or None for an id outside ``TOOL_CALL_ID_RE``."""
    if not TOOL_CALL_ID_RE.match(tool_call_id or ""):
        return None
    return computer_root(home) / SNAPSHOTS_DIR / f"{tool_call_id}.jpg"


def save_snapshot(home: os.PathLike[str] | str, tool_call_id: str, jpeg: bytes) -> None:
    path = snapshot_path(home, tool_call_id)
    if path is None:
        return
    write_bytes_atomic(path, jpeg)
    snapshots = sorted(path.parent.glob("*.jpg"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in snapshots[SNAPSHOT_KEEP:]:
        with contextlib.suppress(OSError):
            old.unlink()


# --- processes and the lifecycle lock -------------------------------------------


def pid_alive(pid: Any) -> bool:
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if os.name == "nt":
        # Never os.kill() on Windows: it terminates the process.
        import ctypes
        from ctypes import wintypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.restype = wintypes.HANDLE
        kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return ctypes.get_last_error() == 5  # ERROR_ACCESS_DENIED: exists, not ours
        try:
            code = wintypes.DWORD()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
                return False
            return code.value == 259  # STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def _lock_is_stale(lock: Path) -> bool:
    owner = _read_json(lock / LOCK_OWNER)
    if not isinstance(owner, dict):
        try:
            age = time.time() - lock.stat().st_mtime
        except FileNotFoundError:
            return False  # released meanwhile: just retry mkdir
        return age > _LOCK_OWNERLESS_STALE_S
    try:
        since = float(owner.get("since"))
    except (TypeError, ValueError):
        return True
    return not pid_alive(owner.get("pid")) or time.time() - since > _LOCK_MAX_AGE_S


@contextlib.contextmanager
def lifecycle_lock(home: os.PathLike[str] | str, deadline: float) -> Iterator[None]:
    """Exclusive ``prepare``/``ensure_running``/``stop`` across processes.

    ``os.mkdir`` is atomic on Linux, macOS and Windows. *deadline* is a
    ``time.monotonic()`` value; waiting past it raises ``RuntimeError``.
    """
    lock = computer_root(home) / LOCK_DIR
    lock.parent.mkdir(parents=True, exist_ok=True)
    while True:
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            if _lock_is_stale(lock):
                shutil.rmtree(lock, ignore_errors=True)
                continue
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError(LOCK_BUSY_MESSAGE) from None
            time.sleep(min(_LOCK_POLL_S, remaining))
    try:
        _write_json(lock / LOCK_OWNER, {"pid": os.getpid(), "since": time.time()})
        yield
    finally:
        shutil.rmtree(lock, ignore_errors=True)
