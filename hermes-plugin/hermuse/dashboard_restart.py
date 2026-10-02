"""In-place restart of the Hermes dashboard this plugin runs in.

A dashboard serves the plugin routes it imported when it started until its
process restarts, and Hermes 0.21 has no API to restart it. :func:`schedule`
re-executes the command line that started this process once the HTTP answer
is out: ``sys.orig_argv`` (the interpreter with its flags, then the ``hermes``
launcher, the console script or ``-m hermes_cli.main``, ``dashboard`` and its
options) in the same environment and working directory. ``os.execv`` keeps
the PID, so whatever runs the dashboard keeps it: a systemd unit (it sees no
exit, so ``Restart=on-failure`` has nothing to do), a user unit, a dashboard
started by hand in a terminal.

Before the process is replaced, Hermes' own exit teardown of its chat sessions
runs (it persists open transcripts; ``atexit`` does not run on exec), and
every socket is closed on exec so the restarted dashboard binds its port
again. Stdlib only: Hermes is reached through ``sys.modules``.
"""

from __future__ import annotations

import logging
import os
import secrets
import signal
import stat
import sys
import threading
from typing import Mapping, Optional, Sequence

#: This start of the dashboard: another value answers once it restarted.
BOOT = secrets.token_hex(8)

#: Between the answer and the restart: time for the answer to reach the client.
DELAY_S = 1.0

#: How long Hermes' session teardown may take before the process is replaced.
TEARDOWN_TIMEOUT_S = 15.0

_SUBCOMMANDS = ("dashboard", "serve")

log = logging.getLogger(__name__)
_lock = threading.Lock()
_scheduled = False


class RestartUnavailable(Exception):
    """This process cannot restart itself in place; the message says why."""


def command_line(argv: Optional[Sequence[str]] = None,
                 environ: Optional[Mapping[str, str]] = None) -> list[str]:
    """The command line that started this ``hermes dashboard`` (or ``serve``).

    Raises :class:`RestartUnavailable` when the process cannot be restarted in
    place: on Windows (``exec`` starts another process there), for a backend a
    desktop app spawned (it restarts it itself; Hermes' own test for it), and
    for anything but ``hermes dashboard`` or ``hermes serve``.
    """
    argv = list(sys.orig_argv if argv is None else argv)
    environ = os.environ if environ is None else environ
    if os.name != "posix":
        raise RestartUnavailable("A dashboard restarts itself on Linux and macOS only.")
    if "--ssh-session-token-file" in argv or (
            environ.get("HERMES_DESKTOP") == "1" and environ.get("HERMES_DASHBOARD_SESSION_TOKEN")):
        raise RestartUnavailable("The desktop app that started this Hermes restarts it.")
    if _subcommand(argv) is None:
        raise RestartUnavailable("This process is not `hermes dashboard`.")
    if not sys.executable or not os.access(sys.executable, os.X_OK):
        raise RestartUnavailable("The Python running this dashboard cannot be started again.")
    return argv


def _subcommand(argv: Sequence[str]) -> Optional[str]:
    """``dashboard`` or ``serve`` when *argv* runs Hermes with it: through the
    ``hermes`` launcher or console script, or ``python -m hermes_cli.main``."""
    for index in range(1, len(argv)):
        arg = argv[index]
        if os.path.basename(arg) == "hermes" or (arg == "hermes_cli.main" and argv[index - 1] == "-m"):
            return next((word for word in argv[index + 1:] if word in _SUBCOMMANDS), None)
    return None


def schedule(argv: Sequence[str]) -> bool:
    """Replaces this process with *argv* in :data:`DELAY_S` seconds.

    False when a restart is already on its way: one at a time.
    """
    global _scheduled
    with _lock:
        if _scheduled:
            return False
        _scheduled = True
    timer = threading.Timer(DELAY_S, _restart, args=(list(argv),))
    timer.daemon = True
    timer.start()
    return True


def _restart(argv: list[str]) -> None:
    log.info("hermuse: restarting the Hermes dashboard in place (pid %d)", os.getpid())
    teardown = threading.Thread(target=_finish_sessions, name="hermuse-restart-teardown", daemon=True)
    teardown.start()
    teardown.join(TEARDOWN_TIMEOUT_S)
    _flush_output()
    _close_sockets_on_exec()
    # A blocked signal would stay blocked in the new program (SIGTERM included).
    signal.pthread_sigmask(signal.SIG_SETMASK, set())
    try:
        os.execv(sys.executable, argv)
    except OSError as exc:
        # The sessions are closed already: exit so a supervisor starts it again
        # rather than leave a half torn-down dashboard serving.
        print(f"hermuse: the dashboard could not restart: {exc}", file=sys.stderr, flush=True)
        os._exit(1)


def _finish_sessions() -> None:
    """Hermes' exit teardown of its chat sessions (persists open transcripts)."""
    gateway = sys.modules.get("tui_gateway.server")
    finish = getattr(gateway, "_shutdown_sessions", None)
    if callable(finish):
        try:
            finish()
        except Exception:  # noqa: BLE001 — the restart goes on
            log.warning("hermuse: session teardown before the restart failed", exc_info=True)


def _flush_output() -> None:
    for logger in (logging.getLogger(), *logging.Logger.manager.loggerDict.values()):
        for handler in getattr(logger, "handlers", ()):
            try:
                handler.flush()
            except Exception:  # noqa: BLE001 — best effort, the restart goes on
                pass
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.flush()
        except (AttributeError, OSError, ValueError):
            pass


def _close_sockets_on_exec() -> None:
    """Marks every socket close-on-exec: one kept open (a listening socket made
    inheritable, as uvicorn's ``bind_socket`` does) would hold the port."""
    directory = "/proc/self/fd" if os.path.isdir("/proc/self/fd") else "/dev/fd"
    try:
        fds = [int(name) for name in os.listdir(directory)]
    except OSError:
        return
    for fd in fds:
        try:
            if fd > 2 and stat.S_ISSOCK(os.fstat(fd).st_mode):
                os.set_inheritable(fd, False)
        except OSError:
            pass  # closed meanwhile, or the directory's own descriptor
