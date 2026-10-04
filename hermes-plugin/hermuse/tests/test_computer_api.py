"""Dashboard computer routes and the ticketed WebSocket bridge to screend."""

from __future__ import annotations

import asyncio
import contextlib
import importlib.util
import json
import sys
import threading
import time
from pathlib import Path

import anyio
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from computer import state

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
BASE = "/api/plugins/hermuse"


def _load_plugin_api():
    module_name = "hermuse_dashboard_plugin_api_computer_test"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(
        module_name, PLUGIN_ROOT / "dashboard" / "plugin_api.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture()
def api(hermes_home, fake_runtime, monkeypatch):
    plugin_api = _load_plugin_api()
    monkeypatch.setattr(plugin_api, "_ws_request_is_allowed", lambda ws: True)
    app = FastAPI()
    app.include_router(plugin_api.router, prefix=BASE)
    with TestClient(app) as client:
        yield plugin_api, client


def _receive(ws, timeout=5.0):
    """``ws.receive()`` that fails instead of hanging."""
    async def receive():
        with anyio.fail_after(timeout):
            return await ws._send_rx.receive()
    message = ws.portal.call(receive)
    if message["type"] == "websocket.close":
        raise WebSocketDisconnect(code=message.get("code", 1000), reason=message.get("reason", ""))
    return message


def _next_state(ws, **expected):
    """Skip frames/geometry until a ``state`` message matching *expected*."""
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        message = _receive(ws)
        if message.get("text"):
            data = json.loads(message["text"])
            if data.get("t") == "state" and all(data.get(k) == v for k, v in expected.items()):
                return data
    raise AssertionError(f"no state message matching {expected}")


def _wait_for(predicate, what):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.02)
    raise AssertionError(f"timed out waiting for {what}")


class FakeScreend:
    """Real WebSocket server standing in for screend's /stream."""

    def __init__(self):
        self.connections = []  # per upstream connection: {"path", "received": [...]}
        self._loop = asyncio.new_event_loop()
        self._ready = threading.Event()
        self._thread = threading.Thread(target=self._loop.run_until_complete,
                                        args=(self._serve(),), daemon=True)
        self._thread.start()
        assert self._ready.wait(5)

    async def _serve(self):
        from websockets.asyncio.server import serve

        async def handler(connection):
            record = {"path": connection.request.path, "received": []}
            self.connections.append(record)
            await connection.send(json.dumps({"t": "geometry", "w": 100, "h": 50, "mode": "browser"}))
            await connection.send(b"\xff\xd8frame\xff\xd9")
            async for message in connection:
                record["received"].append(json.loads(message))

        self._stop = asyncio.Event()
        async with serve(handler, "127.0.0.1", 0) as server:
            self.port = server.sockets[0].getsockname()[1]
            self._ready.set()
            await self._stop.wait()

    def close(self):
        self._loop.call_soon_threadsafe(self._stop.set)
        self._thread.join(5)


@pytest.fixture()
def screend(fake_runtime):
    server = FakeScreend()
    fake_runtime.rt["screen_port"] = server.port
    yield server
    server.close()


def _ticket(client):
    response = client.post(f"{BASE}/computer/ticket")
    assert response.status_code == 200
    return response.json()["ticket"]


def test_snapshot_ids_are_validated(api, hermes_home):
    _, client = api
    assert client.get(f"{BASE}/computer/snapshots/..%2Fx").status_code == 400
    assert client.get(f"{BASE}/computer/snapshots/call_1").status_code == 404
    state.save_snapshot(hermes_home, "call_1", b"\xff\xd8jpeg\xff\xd9")
    response = client.get(f"{BASE}/computer/snapshots/call_1")
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/jpeg"
    assert response.content == b"\xff\xd8jpeg\xff\xd9"


def test_status_and_start_report_the_computer(api, fake_runtime):
    _, client = api
    fake_runtime.status_result = {"state": "stopped", "detail": ""}
    assert client.get(f"{BASE}/computer/status").json() == {
        "state": "stopped", "detail": "", "control": "agent", "mode": "browser"}
    fake_runtime.ensure_error = RuntimeError("hermuse computer: daemon_down — docker is off")
    response = client.post(f"{BASE}/computer/start")
    assert response.status_code == 409
    assert response.json()["detail"] == "hermuse computer: daemon_down — docker is off"


def test_ws_refuses_foreign_origins_before_accepting(api, monkeypatch):
    plugin_api, client = api
    monkeypatch.setattr(plugin_api, "_ws_request_is_allowed", lambda ws: False)
    with pytest.raises(WebSocketDisconnect) as refused:
        with client.websocket_connect(f"{BASE}/computer/ws?ticket={_ticket(client)}"):
            pass
    assert refused.value.code == 4403


def test_ws_needs_a_fresh_ticket_then_a_startable_computer(api, fake_runtime):
    _, client = api
    with client.websocket_connect(f"{BASE}/computer/ws") as ws:
        with pytest.raises(WebSocketDisconnect) as missing:
            _receive(ws)
    assert missing.value.code == 4401

    fake_runtime.ensure_error = RuntimeError("hermuse computer: daemon_down — docker is off")
    ticket = _ticket(client)
    with client.websocket_connect(f"{BASE}/computer/ws?ticket={ticket}") as ws:
        with pytest.raises(WebSocketDisconnect) as unavailable:
            _receive(ws)
    assert unavailable.value.code == 4001
    assert "daemon_down" in unavailable.value.reason

    with client.websocket_connect(f"{BASE}/computer/ws?ticket={ticket}") as ws:  # single use
        with pytest.raises(WebSocketDisconnect) as reused:
            _receive(ws)
    assert reused.value.code == 4401


def test_second_viewer_takes_control_from_the_first(api, fake_runtime, screend, hermes_home):
    plugin_api, client = api
    with contextlib.ExitStack() as sessions:  # a failure must not leave sessions hanging
        first = sessions.enter_context(
            client.websocket_connect(f"{BASE}/computer/ws?ticket={_ticket(client)}&fps=8"))
        _next_state(first, control="agent", mine=False)
        second = sessions.enter_context(
            client.websocket_connect(f"{BASE}/computer/ws?ticket={_ticket(client)}"))
        _next_state(second, control="agent", mine=False)
        _wait_for(lambda: len(screend.connections) == 2, "both upstream connections")
        upstream_first, upstream_second = screend.connections
        assert "token=t" in upstream_first["path"] and "fps=8" in upstream_first["path"]

        first.send_json({"t": "take"})
        _next_state(first, control="human", mine=True)
        second.send_json({"t": "take"})
        state_first = _next_state(first, control="human", mine=False)
        assert state_first["tabs"] == [{"id": "T1", "url": "https://example.com/",
                                       "title": "Example", "active": True}]
        _next_state(second, control="human", mine=True)

        # The replaced viewer's input is dropped; the holder's reaches screend.
        first.send_json({"t": "move", "x": 1, "y": 1})
        first.send_json({"t": "tab", "action": "activate", "id": "T1"})
        _wait_for(lambda: ("activate", "T1") in fake_runtime.calls, "tab activation")
        second.send_json({"t": "move", "x": 2, "y": 2})
        _wait_for(lambda: upstream_second["received"], "the holder's input upstream")
        assert upstream_second["received"] == [{"t": "move", "x": 2, "y": 2}]
        assert upstream_first["received"] == []

        first.close(1000)
        _wait_for(lambda: len(plugin_api._viewers) == 1, "the first viewer to leave")
        assert state.read_control(hermes_home)["holder"] == "human"
        second.close(1000)
        _wait_for(lambda: not plugin_api._viewers, "the second viewer to leave")
        assert state.read_control(hermes_home) == {"holder": "agent", "lease_id": None}


def test_profile_snapshots_and_tickets_cannot_cross_agents(api, hermes_home):
    plugin, client = api
    for name, content in (("noah", b"noah-screen"), ("aya", b"aya-screen")):
        home = hermes_home / "profiles" / name
        home.mkdir(parents=True)
        (home / "SOUL.md").write_text(f"You are {name}.")
        path = state.snapshot_path(home, "same-tool-id")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        response = client.get(
            f"{BASE}/computer/snapshots/same-tool-id?profile={name}"
        )
        assert response.status_code == 200
        assert response.content == content

    ticket = client.post(f"{BASE}/computer/ticket?profile=noah").json()["ticket"]
    with client.websocket_connect(f"{BASE}/computer/ws?profile=aya&ticket={ticket}") as ws:
        with pytest.raises(WebSocketDisconnect) as error:
            _receive(ws)
        assert error.value.code == 4401
    assert client.get(f"{BASE}/computer/snapshots/same-tool-id").status_code == 404
