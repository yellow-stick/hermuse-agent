"""The background bootstrap: Docker install through sudo, then image pull or local
build — run for real by ``prepare()`` against a fake `docker` executable on PATH."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time

import pytest

from computer import bootstrap, runtime, state

pytestmark = pytest.mark.skipif(os.name == "nt", reason="fake docker is a POSIX script")

FAKE_DOCKER = '''#!{python}
import json, os, sys, time
args = sys.argv[1:]
root = os.environ["FAKE_DOCKER_DIR"]
with open(os.path.join(root, "calls.log"), "a") as fh:
    fh.write(json.dumps(args) + "\\n")
image = os.path.join(root, "image")
cmd = args[0]
if cmd == "version":
    print("29.0.0")
elif args[:2] == ["image", "inspect"]:
    if not os.path.exists(image):
        sys.stderr.write("Error: No such image: " + args[-1] + "\\n")
        sys.exit(1)
    print("sha256:1")
elif cmd == "pull":
    time.sleep(0.3)
    if os.environ.get("FAKE_DOCKER_PULL") != "ok":
        sys.stderr.write("Error response from daemon: denied\\n")
        sys.exit(1)
    print("Status: Downloaded newer image for " + args[1])
elif cmd == "tag":
    open(image, "w").close()
elif cmd == "build":
    print("#5 [1/4] FROM docker.io/library/debian:trixie-slim")
    if os.environ.get("FAKE_DOCKER_BUILD") == "fail":
        print("ERROR: failed to solve: boom")
        sys.exit(1)
    open(image, "w").close()
elif cmd == "inspect":
    sys.stderr.write("Error: No such container: " + args[-1] + "\\n")
    sys.exit(1)
'''


@pytest.fixture()
def fake_docker(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    script = bin_dir / "docker"
    script.write_text(FAKE_DOCKER.replace("{python}", sys.executable))
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}")
    monkeypatch.setenv("FAKE_DOCKER_DIR", str(tmp_path))
    monkeypatch.setattr(runtime, "needs_docker_group", lambda: False)
    calls = tmp_path / "calls.log"
    return lambda: [json.loads(line)[:2] for line in calls.read_text().splitlines() if line.strip()]


def _bootstrap_to_finish(home):
    deadline = time.monotonic() + 30
    while runtime.DockerComputerRuntime._running_bootstrap(home) is not None:
        assert time.monotonic() < deadline, state.build_log_path(home).read_text()
        time.sleep(0.1)


def test_missing_image_is_pulled_in_the_background(hermes_home, fake_docker, monkeypatch):
    monkeypatch.setenv("FAKE_DOCKER_PULL", "ok")
    computer = runtime.DockerComputerRuntime()
    assert computer.status(hermes_home)["state"] == "image_missing"
    computer.prepare(hermes_home)
    assert computer.status(hermes_home) == {
        "state": "building", "detail": "Downloading the computer image…"}
    _bootstrap_to_finish(hermes_home)
    assert computer.status(hermes_home)["state"] == "stopped"  # startable
    assert ["pull", runtime.REGISTRY_IMAGE] in fake_docker()
    assert ["tag", runtime.REGISTRY_IMAGE] in fake_docker()
    assert not any(call[0] == "build" for call in fake_docker())


def test_unpublished_image_is_built_locally(hermes_home, fake_docker):
    computer = runtime.DockerComputerRuntime()
    computer.prepare(hermes_home)
    _bootstrap_to_finish(hermes_home)
    assert computer.status(hermes_home)["state"] == "stopped"
    commands = [call[0] for call in fake_docker()]
    assert commands.index("pull") < commands.index("build")
    assert state.read_build(hermes_home)["step"] == "build"


def test_failed_build_reports_its_error_line(hermes_home, fake_docker, monkeypatch):
    monkeypatch.setenv("FAKE_DOCKER_BUILD", "fail")
    computer = runtime.DockerComputerRuntime()
    computer.prepare(hermes_home)
    _bootstrap_to_finish(hermes_home)
    assert computer.status(hermes_home) == {
        "state": "error", "detail": "Computer image build failed: ERROR: failed to solve: boom"}


@pytest.fixture()
def scripted(hermes_home, monkeypatch):
    """bootstrap.run stand-in: records commands (and the step recorded meanwhile);
    commands containing a word of ``failing`` exit non-zero."""
    ran, failing = [], set()

    def run(command):
        ran.append((command, (state.read_build(hermes_home) or {}).get("step")))
        return not failing & set(command)

    monkeypatch.setattr(bootstrap, "run", run)
    monkeypatch.setattr(bootstrap, "wait_for_daemon", lambda docker: True)
    monkeypatch.setattr(runtime, "needs_docker_group", lambda: False)
    monkeypatch.setattr(runtime, "current_user", lambda: "admin")
    monkeypatch.setattr(shutil, "which", lambda name: "/usr/bin/docker" if name == "docker" else None)
    state.write_build(hermes_home, os.getpid(), time.time(), runtime.STEP_DOCKER)  # as prepare() does
    return ran, failing


@pytest.mark.parametrize("installer", ["apt", "script"])
def test_docker_is_installed_through_sudo_before_the_pull(hermes_home, scripted, installer):
    ran, _ = scripted
    assert bootstrap.main(["bootstrap.py", str(hermes_home), installer]) == 0
    commands = [command for command, _ in ran]
    pull = commands.index(["/usr/bin/docker", "pull", runtime.REGISTRY_IMAGE])
    install = [c for c in commands[:pull] if c[0] != "curl"]
    assert install and all(c[:2] == ["sudo", "-n"] for c in install)
    assert ["sudo", "-n", "systemctl", "enable", "--now", "docker"] in install
    assert install[-1] == ["sudo", "-n", "usermod", "-aG", "docker", "admin"]
    assert all(step == runtime.STEP_DOCKER for _, step in ran[:pull])
    assert ran[pull][1] == runtime.STEP_PULL


def test_failed_docker_install_stops_there(hermes_home, scripted):
    ran, failing = scripted
    failing.add("docker.io")
    assert bootstrap.main(["bootstrap.py", str(hermes_home), "apt"]) == 1
    assert not any(command[0] == "/usr/bin/docker" for command, _ in ran)


def test_daemon_wait_switches_to_sg_once_the_group_socket_appears(monkeypatch):
    # First probe: the new daemon has no socket yet; then a docker-group socket
    # this process (started before usermod) can only reach through `sg docker`.
    needs_group = iter([False, True])
    monkeypatch.setattr(runtime, "needs_docker_group", lambda: next(needs_group, True))
    monkeypatch.setattr(shutil, "which", lambda name: "/usr/bin/sg" if name == "sg" else None)
    monkeypatch.setattr(bootstrap, "DAEMON_POLL_S", 0.01)
    monkeypatch.setattr(bootstrap, "DAEMON_WAIT_S", 0.5)
    ran = []

    def run(command, **kwargs):
        ran.append(command[0])
        return subprocess.CompletedProcess(command, 0 if command[0] == "/usr/bin/sg" else 1, "",
                                           "permission denied while trying to connect")

    monkeypatch.setattr(subprocess, "run", run)
    assert bootstrap.wait_for_daemon("/usr/bin/docker") is True
    assert ran == ["/usr/bin/docker", "/usr/bin/sg"]
