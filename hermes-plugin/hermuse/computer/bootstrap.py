"""Background bootstrap of the agent's computer: one detached process per attempt.

Started by :meth:`runtime.DockerComputerRuntime.prepare` as
``python bootstrap.py <HERMES_HOME> [apt|script]`` with stdout/stderr in
``computer/build.log``; each stage is recorded as ``step`` in ``build.json``,
which ``status`` reports as the ``building`` detail:

1. ``docker`` (only with an installer argument): install Docker through
   passwordless sudo — apt ``docker.io`` or the get.docker.com script — start
   its daemon and add the user to the ``docker`` group. This process and the
   Hermes processes started before reach the socket through ``sg docker``.
2. ``pull``: ``docker pull`` the published :data:`runtime.REGISTRY_IMAGE` and
   tag it :data:`runtime.IMAGE`.
3. ``build``: when the pull fails, ``docker build`` :data:`runtime.IMAGE` from
   ``image/``.

Exits 0 once the image exists, 1 otherwise; nothing is printed after a failed
command so the last line of ``build.log`` is its error (``status`` shows it).
"""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

if __package__:
    from . import runtime, state
else:  # run as a script: the plugin root replaces this directory on sys.path
    sys.path[0] = str(Path(__file__).resolve().parent.parent)
    from computer import runtime, state  # type: ignore[no-redef]

GET_DOCKER_URL = "https://get.docker.com"
DAEMON_WAIT_S = 60.0
DAEMON_POLL_S = 2.0
DAEMON_PROBE_S = 10.0


def log(message: str) -> None:
    print(f"hermuse bootstrap: {message}", flush=True)


def run(command: list[str]) -> bool:
    """Run *command* with its output in build.log; True on exit code 0."""
    print(f"$ {shlex.join(command)}", flush=True)
    try:
        return subprocess.run(command, stdin=subprocess.DEVNULL).returncode == 0
    except OSError as exc:
        log(f"cannot run {command[0]}: {exc}")
        return False


def sudo(*args: str) -> list[str]:
    return ["sudo", "-n", *args]


def install_docker(installer: str) -> bool:
    if installer == "apt":
        # env: sudo resets the environment; the lock timeout waits out
        # unattended-upgrades on a freshly booted server.
        apt = ["env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "-o", "DPkg::Lock::Timeout=600"]
        run(sudo(*apt, "update"))  # one broken third-party source must not stop the install
        if not run(sudo(*apt, "install", "-y", "docker.io")):
            return False
    elif installer == "script":
        with tempfile.TemporaryDirectory() as tmp:
            script = os.path.join(tmp, "get-docker.sh")
            if not (run(["curl", "-fsSL", GET_DOCKER_URL, "-o", script]) and run(sudo("sh", script))):
                return False
    else:
        log(f"unknown installer {installer!r}")
        return False
    # Packages usually start the daemon already; get.docker.com does not on every distro.
    run(sudo("systemctl", "enable", "--now", "docker"))
    user = runtime.current_user()
    return not user or run(sudo("usermod", "-aG", "docker", user))


def wait_for_daemon(docker: str) -> bool:
    deadline = time.monotonic() + DAEMON_WAIT_S
    while True:
        # Rebuilt each time: whether `sg docker` is needed depends on the socket,
        # which may only appear once the freshly installed daemon is up.
        command = runtime.docker_command(docker, ["version", "--format", "{{.Server.Version}}"])
        try:
            probe = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True,
                                   encoding="utf-8", errors="replace", timeout=DAEMON_PROBE_S)
            if probe.returncode == 0:
                return True
            error = (probe.stderr or "").strip().splitlines()[-1:] or ["no answer"]
        except (OSError, subprocess.TimeoutExpired) as exc:
            error = [str(exc)]
        if time.monotonic() >= deadline:
            log(f"the Docker daemon did not answer: {error[0]}")
            return False
        time.sleep(DAEMON_POLL_S)


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        print("usage: bootstrap.py HERMES_HOME [apt|script]", file=sys.stderr)
        return 2
    home = Path(argv[1])
    if len(argv) == 3:
        log("installing Docker")
        if not install_docker(argv[2]):
            return 1
    docker = shutil.which("docker")
    if docker is None:
        log("docker is not on PATH")
        return 1
    if not wait_for_daemon(docker):
        return 1
    state.set_build_step(home, runtime.STEP_PULL)
    if (run(runtime.docker_command(docker, ["pull", runtime.REGISTRY_IMAGE]))
            and run(runtime.docker_command(docker, ["tag", runtime.REGISTRY_IMAGE, runtime.IMAGE]))):
        log(f"{runtime.IMAGE} is ready")
        return 0
    log(f"no published image: building {runtime.IMAGE} locally")
    state.set_build_step(home, runtime.STEP_BUILD)
    if not run(runtime.docker_command(docker, ["build", "-t", runtime.IMAGE, str(runtime.IMAGE_DIR)])):
        return 1
    log(f"{runtime.IMAGE} is ready")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
