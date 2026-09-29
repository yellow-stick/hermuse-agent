"""DockerComputerRuntime against a scripted `docker`: states, bootstrap, upgrades, `sg docker`."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from types import SimpleNamespace

import pytest

from computer import runtime, state

DOCKER = "/usr/bin/docker"
REAL_POPEN = subprocess.Popen
DAEMON_DOWN = ("Cannot connect to the Docker daemon at unix:///var/run/docker.sock. "
               "Is the docker daemon running?")


class ScriptedDocker:
    """``subprocess.run`` stand-in: ``answer(args) -> (returncode, stdout, stderr)``."""

    def __init__(self, answer):
        self.answer = answer
        self.calls = []

    def __call__(self, cmd, **kwargs):
        assert cmd[0] == DOCKER
        self.calls.append(cmd[1:])
        code, out, err = self.answer(cmd[1:])
        return subprocess.CompletedProcess(cmd, code, out, err)


PULLED_DIGEST = f"{runtime.REGISTRY_REPOSITORY}@sha256:{'1' * 64}"


def docker_with(*, image=True, pulled=True, container=None, running=False,
                config_image=runtime.IMAGE):
    """Answers for a daemon that is up; *container* None = absent."""
    def answer(args):
        if args[0] == "version":
            return 0, "29.0.0\n", ""
        if args[:2] == ["image", "inspect"]:
            if not image:
                return 1, "", "Error: No such image\n"
            return 0, json.dumps([PULLED_DIGEST] if pulled else []) + "\n", ""
        if args[0] == "inspect":
            if container is None:
                return 1, "", f"Error: No such container: {args[-1]}\n"
            fmt = args[args.index("--format") + 1]
            if "State.Running" in fmt:
                return 0, f"{str(running).lower()}\n", ""
            if "Config.Image" in fmt:
                return 0, f"{config_image}\n", ""
            return 0, "PATH=/usr/bin\nSCREEND_TOKEN=tok\n", ""
        if args[0] == "port":
            return 0, "127.0.0.1:49153\n" if args[2] == "9223/tcp" else "127.0.0.1:49154\n", ""
        return 0, "", ""
    return answer


@pytest.fixture()
def docker(monkeypatch):
    def install(answer):
        scripted = ScriptedDocker(answer)
        monkeypatch.setattr(shutil, "which", lambda name: DOCKER if name == "docker" else None)
        monkeypatch.setattr(subprocess, "run", scripted)
        monkeypatch.setattr(runtime, "needs_docker_group", lambda: False)
        return scripted
    return install


class FakePopen:
    """``subprocess.Popen`` stand-in whose pid is this (live) test process."""

    launched = []

    def __init__(self, cmd, **kwargs):
        FakePopen.launched.append(cmd)
        self.pid = os.getpid()

    def wait(self):
        return 0


@pytest.fixture()
def popen(monkeypatch):
    FakePopen.launched = []
    monkeypatch.setattr(subprocess, "Popen", FakePopen)
    return FakePopen.launched


def _dead_pid():
    finished = REAL_POPEN([sys.executable, "-c", ""])  # the popen fixture may have replaced Popen
    finished.wait()
    return finished.pid


def test_no_docker_binary(hermes_home, monkeypatch):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    monkeypatch.setattr(runtime, "current_user", lambda: "admin")
    monkeypatch.setattr(runtime.sys, "platform", "linux")
    assert runtime.DockerComputerRuntime().status(hermes_home) == {
        "state": "docker_missing",
        "detail": "curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker admin"}
    with pytest.raises(RuntimeError, match="docker_missing"):
        runtime.DockerComputerRuntime().ensure_running(hermes_home)


@pytest.mark.parametrize("platform", ["darwin", "win32"])
def test_no_docker_binary_on_desktop_os_points_at_docker_desktop(hermes_home, monkeypatch, platform):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    monkeypatch.setattr(runtime.sys, "platform", platform)
    assert runtime.DockerComputerRuntime().status(hermes_home)["detail"] == (
        "Install Docker Desktop: https://docs.docker.com/get-started/get-docker/")


@pytest.mark.parametrize(("step", "detail"), [
    ("docker", "Installing Docker…"),
    ("pull", "Downloading the computer image…"),
    ("build", "Building the computer image…"),
])
def test_running_bootstrap_is_building_even_without_docker(hermes_home, docker, monkeypatch,
                                                          step, detail):
    scripted = docker(docker_with(image=False))
    monkeypatch.setattr(shutil, "which", lambda name: None)  # Docker not installed yet
    state.write_build(hermes_home, os.getpid(), time.time(), step)
    assert runtime.DockerComputerRuntime().status(hermes_home) == {
        "state": "building", "detail": detail}
    with pytest.raises(RuntimeError, match="building"):
        runtime.DockerComputerRuntime().ensure_running(hermes_home)
    assert scripted.calls == []


def test_setup_installs_docker_in_the_background_when_it_can(hermes_home, monkeypatch, popen):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    monkeypatch.setattr(runtime, "docker_installer", lambda timeout=5.0: "apt")
    runtime.DockerComputerRuntime().prepare(hermes_home)
    assert popen == [[sys.executable, str(runtime.BOOTSTRAP), str(hermes_home), "apt"]]
    assert runtime.DockerComputerRuntime().status(hermes_home) == {
        "state": "building", "detail": "Installing Docker…"}
    runtime.DockerComputerRuntime().prepare(hermes_home)  # already running: no second bootstrap
    assert len(popen) == 1


def test_docker_the_user_must_install_starts_nothing(hermes_home, monkeypatch, popen):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    monkeypatch.setattr(runtime, "docker_installer", lambda timeout=5.0: None)
    runtime.DockerComputerRuntime().prepare(hermes_home)
    assert popen == []
    assert runtime.DockerComputerRuntime().status(hermes_home)["state"] == "docker_missing"


def _sudo_and_apt(monkeypatch):
    """Passwordless sudo and apt-get on a Linux host; returns the commands run."""
    ran = []

    def run(cmd, **kwargs):
        ran.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, b"", b"")

    monkeypatch.setattr(runtime.sys, "platform", "linux")
    monkeypatch.setattr(shutil, "which", lambda name: {
        "sudo": "/usr/bin/sudo", "apt-get": "/usr/bin/apt-get"}.get(name))
    monkeypatch.setattr(subprocess, "run", run)
    return ran


def test_a_server_with_passwordless_sudo_installs_docker_itself(monkeypatch):
    ran = _sudo_and_apt(monkeypatch)
    assert runtime.docker_installer() == "apt"
    assert ran == [["/usr/bin/sudo", "-n", "true"]]


def test_the_desktop_app_installs_docker_not_the_plugin(hermes_home, monkeypatch, popen):
    ran = _sudo_and_apt(monkeypatch)
    monkeypatch.setenv("HERMES_DESKTOP", "1")

    runtime.DockerComputerRuntime().prepare(hermes_home)

    assert popen == []  # no bootstrap
    assert ran == []  # sudo not even probed
    status = runtime.DockerComputerRuntime().status(hermes_home)
    assert status["state"] == "docker_missing"
    assert status["hint"] == "desktop_setup"
    assert "sudo" not in status["detail"]


def test_a_server_docker_missing_status_has_no_desktop_hint(hermes_home, monkeypatch):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    assert "hint" not in runtime.DockerComputerRuntime().status(hermes_home)



def test_a_failed_docker_install_is_not_an_image_failure(hermes_home, docker):
    state.write_build(hermes_home, _dead_pid(), time.time(), "docker")
    state.build_log_path(hermes_home).write_text("E: Unable to locate package docker.io\n")
    docker(docker_with(image=False))  # the user installed Docker by hand meanwhile
    assert runtime.DockerComputerRuntime().status(hermes_home)["state"] == "image_missing"


def test_daemon_down(hermes_home, docker):
    docker(lambda args: (1, "", DAEMON_DOWN + "\n") if args[0] == "version" else (0, "", ""))
    status = runtime.DockerComputerRuntime().status(hermes_home)
    assert status["state"] == "daemon_down"
    assert status["detail"].startswith("Cannot connect")
    with pytest.raises(RuntimeError, match="daemon_down"):
        runtime.DockerComputerRuntime().ensure_running(hermes_home)


@pytest.mark.parametrize(("container", "running", "expected"), [
    (None, False, "stopped"),   # absent: ensure_running creates it
    ("c", False, "stopped"),    # created or exited: ensure_running starts it
    ("c", True, "running"),
])
def test_container_states(hermes_home, docker, container, running, expected):
    docker(docker_with(container=container, running=running))
    assert runtime.DockerComputerRuntime().status(hermes_home)["state"] == expected


@pytest.mark.parametrize("running", [False, True])
def test_a_ready_image_says_it_was_pulled(hermes_home, docker, running):
    docker(docker_with(container="c", running=running))
    status = runtime.DockerComputerRuntime().status(hermes_home)
    assert status["image_source"] == "registry"
    assert status["image_digest"] == PULLED_DIGEST


def test_a_locally_built_image_is_never_reported_as_pulled(hermes_home, docker):
    docker(docker_with(pulled=False))
    status = runtime.DockerComputerRuntime().status(hermes_home)
    assert status["state"] == "stopped"
    assert status["image_source"] == "local"
    assert "image_digest" not in status


def test_failed_build_is_reported_and_retried(hermes_home, docker, popen):
    state.write_build(hermes_home, _dead_pid(), 0, "build")
    state.build_log_path(hermes_home).write_text(
        "#6 [2/4] RUN apt-get update\n#6 ERROR: exit code 100\nERROR: failed to solve: apt-get\n\n")
    scripted = docker(docker_with(image=False))
    assert runtime.DockerComputerRuntime().status(hermes_home) == {
        "state": "error", "detail": "Computer image build failed: ERROR: failed to solve: apt-get"}

    runtime.DockerComputerRuntime().prepare(hermes_home)
    assert popen == [[sys.executable, str(runtime.BOOTSTRAP), str(hermes_home)]]  # no install
    build = state.read_build(hermes_home)
    assert build["pid"] == os.getpid() and build["step"] == "pull"
    assert state.build_log_path(hermes_home).read_text() == ""  # previous attempt's log dropped
    assert runtime.DockerComputerRuntime().status(hermes_home) == {
        "state": "building", "detail": "Downloading the computer image…"}


def test_docker_group_granted_after_start_goes_through_sg(tmp_path, monkeypatch):
    socket = tmp_path / "docker.sock"
    socket.write_text("")
    monkeypatch.setattr(runtime, "DOCKER_SOCKET", str(socket))
    monkeypatch.setattr(runtime, "current_user", lambda: "admin")
    monkeypatch.setattr(shutil, "which", lambda name: {"sg": "/usr/bin/sg"}.get(name))
    members = ["admin"]
    monkeypatch.setattr("grp.getgrnam", lambda name: SimpleNamespace(gr_mem=members))
    accessible = False
    real_access = os.access
    monkeypatch.setattr(os, "access", lambda path, mode: accessible if path == str(socket)
                        else real_access(path, mode))
    args = ["inspect", "--format", "{{.State.Running}}", "hermuse-computer-default"]

    assert runtime.docker_command(DOCKER, args) == [
        "/usr/bin/sg", "docker", "-c",
        "/usr/bin/docker inspect --format '{{.State.Running}}' hermuse-computer-default"]
    members.clear()  # not (yet) in the group: sg would ask for a password
    assert runtime.docker_command(DOCKER, args) == [DOCKER, *args]
    members.append("admin")
    accessible = True  # this process already has the group
    assert runtime.docker_command(DOCKER, args) == [DOCKER, *args]
    socket.unlink()  # no local daemon socket (Docker Desktop VM, remote DOCKER_HOST)
    accessible = False
    assert runtime.docker_command(DOCKER, args) == [DOCKER, *args]


def test_docker_calls_use_sg_when_needed(hermes_home, monkeypatch):
    calls = []

    def run(cmd, **kwargs):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 1, "", DAEMON_DOWN)

    monkeypatch.setattr(shutil, "which", lambda name: {"docker": DOCKER, "sg": "/usr/bin/sg"}.get(name))
    monkeypatch.setattr(runtime, "needs_docker_group", lambda: True)
    monkeypatch.setattr(subprocess, "run", run)
    assert runtime.DockerComputerRuntime().status(hermes_home)["state"] == "daemon_down"
    assert calls == [["/usr/bin/sg", "docker", "-c",
                      "/usr/bin/docker version --format '{{.Server.Version}}'"]]


def test_upgrade_recreates_the_container_on_the_same_volume(tmp_path, docker, monkeypatch):
    home = tmp_path / "default"
    scripted = docker(docker_with(container="c", running=True,
                                  config_image="hermuse-computer:0.1.0"))
    monkeypatch.setattr(runtime, "loopback_request", lambda url, timeout, **kw: b"{}")
    rt = runtime.DockerComputerRuntime().ensure_running(home)

    removed = scripted.calls.index(["rm", "-f", "hermuse-computer-default"])
    run = next(i for i, call in enumerate(scripted.calls) if call[0] == "run")
    assert removed < run
    created = scripted.calls[run]
    assert created[created.index("-v") + 1] == "hermuse-computer-default-home:/home/hermuse"
    assert created[-1] == "hermuse-computer:0.2.0"
    assert created[created.index("--name") + 1] == "hermuse-computer-default"
    assert ["127.0.0.1::9223", "127.0.0.1::8765"] == [
        created[i + 1] for i, arg in enumerate(created) if arg == "-p"]
    assert not any(call[0] == "start" for call in scripted.calls)
    assert rt == {"backend": "docker", "container": "hermuse-computer-default",
                  "cdp_port": 49153, "screen_port": 49154, "token": "tok",
                  "image": runtime.IMAGE, "mode": "browser"}
    assert state.read_runtime(home) == rt


def test_cdp_urls_and_tabs_stay_on_loopback(monkeypatch):
    answers = {
        "/json/version": {"webSocketDebuggerUrl": "ws://172.17.0.2:9222/devtools/browser/abc"},
        "/json/list": [
            {"id": "P2", "type": "page", "url": "https://en.wikipedia.org/", "title": "Wiki"},
            {"id": "W1", "type": "service_worker", "url": "https://x/sw.js", "title": ""},
            {"id": "P1", "type": "page", "url": "about:blank", "title": ""},
        ],
    }
    seen = []

    def fake_request(url, timeout, **kwargs):
        seen.append(url)
        return json.dumps(answers[url.split(":49153", 1)[1]]).encode()

    monkeypatch.setattr(runtime, "loopback_request", fake_request)
    rt = {"cdp_port": 49153, "screen_port": 49154, "token": "tok"}
    docker_runtime = runtime.DockerComputerRuntime()
    assert docker_runtime.cdp_ws_url(rt) == "ws://127.0.0.1:49153/devtools/browser/abc"
    assert docker_runtime.tabs(rt) == [
        {"id": "P2", "url": "https://en.wikipedia.org/", "title": "Wiki"},
        {"id": "P1", "url": "about:blank", "title": ""},
    ]
    assert all(url.startswith("http://127.0.0.1:49153/") for url in seen)


@pytest.mark.parametrize(("home_name", "container"), [
    ("default", "hermuse-computer-default"),
    (".hermes", "hermuse-computer-hermes"),
    ("Work_Profile", "hermuse-computer-work-profile"),
    ("...", "hermuse-computer-default"),
])
def test_container_name_per_profile(tmp_path, home_name, container):
    assert runtime.container_name(tmp_path / home_name) == container
    assert runtime.volume_name(tmp_path / home_name) == container + "-home"
