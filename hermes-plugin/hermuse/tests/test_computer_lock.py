"""Lifecycle lock across processes, stale-lock reclaim, and the global deadline,
against a fake `docker` executable on PATH."""

from __future__ import annotations

import json
import multiprocessing
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from computer import runtime, state

pytestmark = pytest.mark.skipif(os.name == "nt", reason="fake docker is a POSIX script")

FAKE_DOCKER = '''#!{python}
import json, os, sys, time
args = sys.argv[1:]
log = os.environ["FAKE_DOCKER_LOG"]
with open(log, "a") as fh:
    fh.write(json.dumps(args) + "\\n")
with open(log) as fh:
    ran = any(json.loads(line)[0] == "run" for line in fh if line.strip())
mode = os.environ.get("FAKE_DOCKER_MODE", "fresh")
cmd = args[0]
if cmd == "version":
    print("29.0.0")
elif cmd == "image":
    print("sha256:1")
elif cmd == "run":
    time.sleep(1)
    print("cid")
elif cmd == "start":
    time.sleep(30)
elif cmd == "inspect":
    fmt = args[args.index("--format") + 1]
    if mode == "fresh" and not ran:
        sys.stderr.write("Error: No such container: " + args[-1] + "\\n")
        sys.exit(1)
    if "State.Running" in fmt:
        print("true" if mode == "fresh" else "false")
    elif "Config.Image" in fmt:
        print("{image}")
    else:
        print("SCREEND_TOKEN=t")
elif cmd == "port":
    print("127.0.0.1:" + os.environ["FAKE_CDP_PORT"])
'''


class _CdpHandler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 — http.server API
        body = json.dumps({"webSocketDebuggerUrl": "ws://127.0.0.1/devtools/browser/x"}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


@pytest.fixture()
def fake_docker(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    script = bin_dir / "docker"
    script.write_text(FAKE_DOCKER.replace("{python}", sys.executable)
                      .replace("{image}", runtime.IMAGE))
    script.chmod(0o755)
    log = tmp_path / "docker.log"
    log.touch()
    server = ThreadingHTTPServer(("127.0.0.1", 0), _CdpHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}")
    monkeypatch.setattr(runtime, "needs_docker_group", lambda: False)  # never via `sg docker`
    monkeypatch.setenv("FAKE_DOCKER_LOG", str(log))
    monkeypatch.setenv("FAKE_CDP_PORT", str(server.server_address[1]))
    yield lambda: [json.loads(line) for line in log.read_text().splitlines() if line.strip()]
    server.shutdown()
    server.server_close()


def _ensure_running(home, results):
    try:
        rt = runtime.DockerComputerRuntime().ensure_running(home)
        results.put(("ok", rt["container"]))
    except Exception as exc:  # noqa: BLE001 — reported to the parent
        results.put(("error", repr(exc)))


def test_concurrent_starts_create_one_container(hermes_home, fake_docker):
    ctx = multiprocessing.get_context("fork")
    results = ctx.Queue()
    workers = [ctx.Process(target=_ensure_running, args=(hermes_home, results)) for _ in range(2)]
    for worker in workers:
        worker.start()
    outcomes = [results.get(timeout=30) for _ in workers]
    for worker in workers:
        worker.join(timeout=10)
    assert outcomes == [("ok", "hermuse-computer-home")] * 2
    assert [call[0] for call in fake_docker()].count("run") == 1
    assert not (state.computer_root(hermes_home) / state.LOCK_DIR).exists()


def test_lock_of_a_dead_process_is_reclaimed_at_once(hermes_home):
    finished = subprocess.Popen([sys.executable, "-c", ""])
    finished.wait()
    lock = state.computer_root(hermes_home) / state.LOCK_DIR
    lock.mkdir(parents=True)
    (lock / state.LOCK_OWNER).write_text(json.dumps({"pid": finished.pid, "since": time.time()}))
    started = time.monotonic()
    with state.lifecycle_lock(hermes_home, time.monotonic() + 5):
        assert json.loads((lock / state.LOCK_OWNER).read_text())["pid"] == os.getpid()
    assert time.monotonic() - started < 0.5
    assert not lock.exists()


def test_live_lock_makes_start_give_up_at_its_deadline(hermes_home, fake_docker):
    lock = state.computer_root(hermes_home) / state.LOCK_DIR
    lock.mkdir(parents=True)
    (lock / state.LOCK_OWNER).write_text(json.dumps({"pid": os.getpid(), "since": time.time()}))
    started = time.monotonic()
    with pytest.raises(RuntimeError, match="another Hermuse process is starting the computer"):
        runtime.DockerComputerRuntime().ensure_running(hermes_home, timeout=1)
    assert time.monotonic() - started <= 1.5
    assert fake_docker() == []
    assert lock.exists()  # someone else's lock is never removed


def test_hanging_docker_cannot_outlive_the_deadline(hermes_home, fake_docker, monkeypatch):
    monkeypatch.setenv("FAKE_DOCKER_MODE", "stopped")  # exists, not running → `docker start`
    started = time.monotonic()
    with pytest.raises(RuntimeError, match="docker start timed out"):
        runtime.DockerComputerRuntime().ensure_running(hermes_home, timeout=2)
    assert time.monotonic() - started <= 3
    assert [call[0] for call in fake_docker()][-1] == "start"
    assert not (state.computer_root(hermes_home) / state.LOCK_DIR).exists()
