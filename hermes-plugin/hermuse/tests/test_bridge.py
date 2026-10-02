"""Subscription bridge: pinned download and checksums, private files, a detached
CLIProxyAPI (a fake one here) on a persisted loopback port, accounts and models
through the dashboard routes. No network: the release download is mocked."""

from __future__ import annotations

import dataclasses
import hashlib
import importlib.util
import io
import json
import socket
import stat
import subprocess
import sys
import tarfile
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import subscription_bridge as bridge

pytestmark = pytest.mark.skipif(not sys.platform.startswith("linux"),
                                reason="the bridge runs on Linux hosts")

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
DESKTOP_LOCK = PLUGIN_ROOT.parent.parent / "packages" / "hermuse_host" / "cliproxy.lock"
BASE = "/api/plugins/hermuse/bridge"
NAME = "claude-dev@shop.com.json"
ACCOUNT = json.dumps({"type": "claude", "email": "dev@shop.com", "access_token": "at-1",
                      "refresh_token": "rt-1"})

# The routes of CLIProxyAPI the bridge uses, with its auth and file semantics.
FAKE_CLIPROXY = '''#!{python}
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

config, api_keys = {}, []
with open(sys.argv[sys.argv.index("-config") + 1]) as fh:
    for line in fh:
        line = line.strip()
        if line.startswith("- "):
            api_keys.append(json.loads(line[2:]))
        elif ": " in line and not line.startswith("#"):
            name, value = line.split(": ", 1)
            config[name] = value
auth_dir = json.loads(config["auth-dir"])
management = json.loads(config["secret-key"])


def accounts():
    for name in sorted(os.listdir(auth_dir)):
        with open(os.path.join(auth_dir, name)) as fh:
            yield name, json.load(fh)


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def route(self, key):
        if self.headers.get("Authorization") != "Bearer " + key:
            self.reply(401, {"error": "invalid key"})
            return None, {}
        url = urlparse(self.path)
        return url.path, {k: v[0] for k, v in parse_qs(url.query).items()}

    def do_GET(self):
        if self.path == "/v1/models":
            if self.route(api_keys[0])[0] is not None:
                self.reply(200, {"object": "list", "data": [
                    {"id": "claude-opus-9", "object": "model", "owned_by": "anthropic"}
                    for _, account in accounts() if account.get("type") == "claude"]})
            return
        path, _ = self.route(management)
        if path == "/v0/management/config":
            self.reply(200, {"debug": False})
        elif path == "/v0/management/auth-files":
            self.reply(200, {"files": [
                {"name": name, "provider": account.get("type"), "email": account.get("email"),
                 "status": "active", "disabled": False, "unavailable": False}
                for name, account in accounts()]})
        elif path is not None:
            self.reply(404, {"error": "not found"})

    def do_POST(self):
        path, query = self.route(management)
        if path != "/v0/management/auth-files":
            return
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        try:
            json.loads(body)
        except ValueError:
            return self.reply(400, {"error": "invalid auth file"})
        target = os.path.join(auth_dir, os.path.basename(query["name"]))
        with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as fh:
            fh.write(body)
        self.reply(200, {"status": "ok"})

    def do_DELETE(self):
        path, query = self.route(management)
        if path != "/v0/management/auth-files":
            return
        target = os.path.join(auth_dir, os.path.basename(query.get("name", "")))
        if not os.path.isfile(target):
            return self.reply(404, {"error": "auth file not found"})
        os.remove(target)
        self.reply(200, {"status": "ok"})

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("127.0.0.1", int(config["port"])), Handler).serve_forever()
'''


@pytest.fixture()
def release(hermes_home, monkeypatch):
    """A pinned release whose archive holds the fake CLIProxyAPI; downloads are recorded."""
    script = FAKE_CLIPROXY.replace("{python}", sys.executable).encode()
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tar:
        for name, data in (("LICENSE", b"MIT\n"), (bridge.ARCHIVE_BINARY, script)):
            info = tarfile.TarInfo(name)
            info.size, info.mode = len(data), 0o755
            tar.addfile(info, io.BytesIO(data))
    archive = buffer.getvalue()
    asset = bridge.Asset("CLIProxyAPI_test_linux_amd64.tar.gz",
                         hashlib.sha256(archive).hexdigest(), hashlib.sha256(script).hexdigest())
    downloads: list[str] = []

    def fetch(url, out):
        downloads.append(url)
        out.write(archive)

    monkeypatch.setattr(bridge, "platform_key", lambda: "linux-amd64")
    monkeypatch.setattr(bridge, "ASSETS", {"linux-amd64": asset})
    monkeypatch.setattr(bridge, "_download", fetch)
    yield SimpleNamespace(asset=asset, script=script, downloads=downloads)
    bridge.stop(hermes_home)


@pytest.fixture()
def client(hermes_home):
    # Loaded like the dashboard host does: from the file path.
    module_name = "hermuse_dashboard_plugin_api_bridge_test"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(
        module_name, PLUGIN_ROOT / "dashboard" / "plugin_api.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    app = FastAPI()
    app.include_router(module.router, prefix="/api/plugins/hermuse")
    with TestClient(app) as test_client:
        yield test_client


def _mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


def _pid(home) -> int:
    return json.loads((bridge.bridge_root(home) / bridge.PROCESS_FILE).read_text())["pid"]


def test_pins_are_the_linux_entries_of_the_desktop_lock():
    if not DESKTOP_LOCK.is_file():
        pytest.skip("outside the Hermuse repository")
    lock = json.loads(DESKTOP_LOCK.read_text())
    assert lock["version"] == bridge.VERSION
    assert set(bridge.ASSETS) == {"linux-amd64", "linux-arm64"}
    for key, asset in bridge.ASSETS.items():
        entry = lock["platforms"][key]
        assert (asset.name, asset.archive_sha256, asset.binary_sha256) == (
            entry["asset"], entry["archive_sha256"], entry["binary_sha256"])


def test_ensure_installs_the_pinned_release_and_runs_it_privately(hermes_home, release):
    info = bridge.ensure(hermes_home)

    assert release.downloads == [
        bridge.RELEASE_URL.format(version=bridge.VERSION, asset=release.asset.name)]
    keys = bridge.load_keys(hermes_home)
    assert info == {"base_url": f"http://127.0.0.1:{keys['port']}", "api_key": keys["api_key"],
                    "version": bridge.VERSION}
    root = bridge.bridge_root(hermes_home)
    binary = bridge.binary_path(hermes_home)
    assert binary.read_bytes() == release.script
    assert [_mode(p) for p in (root, bridge.auth_dir(hermes_home), binary)] == [0o700] * 3
    for name in (bridge.KEYS_FILE, bridge.CONFIG_FILE, bridge.LOG_FILE):
        assert _mode(root / name) == 0o600, name
    assert [p.name for p in binary.parent.iterdir()] == [binary.name]  # no download left over
    config = (root / bridge.CONFIG_FILE).read_text()
    assert config == bridge.config_text(keys["port"], bridge.auth_dir(hermes_home),
                                        keys["api_key"], keys["management_key"])
    assert 'host: "127.0.0.1"' in config and "allow-remote: false" in config

    status = bridge.status(hermes_home)
    assert (status["supported"], status["installed"], status["running"]) == (True, True, True)
    assert (status["base_url"], status["accounts"]) == (info["base_url"], [])


def test_ensure_again_reuses_the_running_bridge(hermes_home, release):
    first = bridge.ensure(hermes_home)
    pid = _pid(hermes_home)
    assert bridge.ensure(hermes_home) == first
    assert _pid(hermes_home) == pid
    assert len(release.downloads) == 1


@pytest.mark.parametrize("pin", ["archive_sha256", "binary_sha256"])
def test_a_release_off_its_pins_is_never_installed(hermes_home, release, monkeypatch, pin):
    monkeypatch.setattr(bridge, "ASSETS", {
        "linux-amd64": dataclasses.replace(release.asset, **{pin: "0" * 64})})
    with pytest.raises(bridge.BridgeError, match="checksum"):
        bridge.ensure(hermes_home)
    assert list(bridge.binary_path(hermes_home).parent.iterdir()) == []
    assert bridge.load_keys(hermes_home) is None
    assert bridge.status(hermes_home)["installed"] is False


def test_plugin_load_brings_a_stopped_bridge_back_on_its_port(hermes_home, release):
    first = bridge.ensure(hermes_home)
    bridge.stop(hermes_home)
    assert bridge._bridge_process(hermes_home) is None

    bridge.start_if_configured(hermes_home)

    assert bridge._bridge_process(hermes_home) is not None
    assert bridge.ensure(hermes_home) == first  # same port and key: Hermes' endpoint still works
    assert len(release.downloads) == 1


def test_a_stopped_bridge_lists_its_accounts_and_restarts(hermes_home, release):
    bridge.ensure(hermes_home)
    bridge.upload_account(hermes_home, NAME, ACCOUNT)
    bridge.stop(hermes_home)

    stopped = bridge.status(hermes_home)

    assert (stopped["running"], stopped["detail"]) == (False, bridge.STARTING_DETAIL)
    assert [(a["name"], a["provider"], a["email"], a["usable"]) for a in stopped["accounts"]] == [
        (NAME, "claude", "dev@shop.com", False)]
    restarted = bridge._bridge_process(hermes_home)
    assert restarted is not None  # started in the background by the status call
    bridge.ensure(hermes_home)
    assert _pid(hermes_home) == restarted["pid"]


def test_a_recycled_pid_is_never_taken_for_the_bridge(hermes_home, release):
    first = bridge.ensure(hermes_home)
    bridge.stop(hermes_home)
    stranger = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    try:
        record = {"pid": stranger.pid, "binary": str(bridge.binary_path(hermes_home)),
                  "port": bridge.load_keys(hermes_home)["port"], "started": 0}
        (bridge.bridge_root(hermes_home) / bridge.PROCESS_FILE).write_text(json.dumps(record))
        assert bridge._bridge_process(hermes_home) is None
        assert bridge.ensure(hermes_home) == first
        assert stranger.poll() is None  # left alone
    finally:
        stranger.kill()
        stranger.wait()


def test_a_taken_port_moves_the_bridge_and_keeps_its_key(hermes_home, release):
    first = bridge.ensure(hermes_home)
    bridge.stop(hermes_home)
    port = bridge.load_keys(hermes_home)["port"]
    with socket.socket() as squatter:
        squatter.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        squatter.bind(("127.0.0.1", port))
        squatter.listen()
        second = bridge.ensure(hermes_home)
    assert second["base_url"] != first["base_url"]
    assert second["api_key"] == first["api_key"]
    assert bridge.load_keys(hermes_home)["port"] != port


def test_accounts_and_models_through_the_routes(hermes_home, release, client):
    upload = {"name": NAME, "content": ACCOUNT}
    not_set_up = client.post(f"{BASE}/accounts", json=upload)
    assert (not_set_up.status_code, not_set_up.json()["detail"]) == (409, bridge.NOT_SET_UP_DETAIL)

    ensured = client.post(f"{BASE}/ensure").json()
    assert ensured["base_url"].startswith("http://127.0.0.1:") and ensured["api_key"]
    assert client.post(f"{BASE}/accounts", json=upload).json() == {"ok": True, "name": NAME}

    stored = bridge.auth_dir(hermes_home) / NAME
    assert (stored.read_text(), _mode(stored)) == (ACCOUNT, 0o600)
    status = client.get(f"{BASE}/status").json()
    assert status["running"] is True and status["base_url"] == ensured["base_url"]
    assert status["accounts"] == [{"name": NAME, "provider": "claude", "email": "dev@shop.com",
                                   "usable": True, "status": "active", "status_message": ""}]
    assert client.get(f"{BASE}/models").json() == {"object": "list", "data": [
        {"id": "claude-opus-9", "object": "model", "owned_by": "anthropic"}]}

    assert client.delete(f"{BASE}/accounts/{NAME}").json() == {"ok": True, "name": NAME}
    assert not stored.exists()
    assert client.delete(f"{BASE}/accounts/{NAME}").status_code == 404
    assert client.get(f"{BASE}/models").json()["data"] == []


@pytest.mark.parametrize("name", [
    "../keys.json", "auth/x.json", "a\\b.json", ".hidden.json", "..json", "x.txt", "x.json/",
    "x\x00.json", "", "x" * 200 + ".json",
])
def test_account_names_are_one_plain_json_file(name):
    with pytest.raises(ValueError):
        bridge.check_account_name(name)


def test_routes_refuse_traversal_and_bad_account_files(hermes_home, client):
    assert client.delete(f"{BASE}/accounts/..%2Fkeys.json").status_code == 400
    bad = [
        ({"name": "../keys.json", "content": ACCOUNT}, 400),
        ({"name": "x.json", "content": "not json"}, 400),
        ({"name": "x.json", "content": json.dumps({"email": "dev@shop.com"})}, 400),
        ({"name": "x.json", "content": json.dumps(
            {"type": "claude", "pad": "x" * bridge.MAX_ACCOUNT_BYTES})}, 422),
    ]
    for body, code in bad:
        assert client.post(f"{BASE}/accounts", json=body).status_code == code, body
    assert not bridge.bridge_root(hermes_home).exists()


def test_unsupported_hosts_say_so(hermes_home, client, monkeypatch):
    monkeypatch.setattr(bridge, "platform_key", lambda: None)
    status = client.get(f"{BASE}/status").json()
    assert (status["supported"], status["detail"]) == (False, bridge.UNSUPPORTED_DETAIL)
    ensured = client.post(f"{BASE}/ensure")
    assert (ensured.status_code, ensured.json()["detail"]) == (409, bridge.UNSUPPORTED_DETAIL)
    assert client.get(f"{BASE}/models").status_code == 409
