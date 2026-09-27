"""Plugin entry point: register(ctx) wires tools + skill + CLI; handlers persist;
inside a running dashboard it mounts the backend routes without a restart."""

from __future__ import annotations

import importlib.util
import json
import sys
import types
from pathlib import Path

import pytest

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
API_MODULE = "hermes_dashboard_plugin_hermuse"  # Hermes' own name for the mounted backend
SPA_CATCH_ALL = "/{full_path:path}"


def _load_entry():
    # Load the plugin package __init__ the way hermes_plugins.<slug> would see
    # it: as a package whose relative imports resolve inside the plugin dir.
    name = "hermuse_plugin_under_test"
    for mod in [m for m in sys.modules if m == name or m.startswith(name + ".")]:
        sys.modules.pop(mod)
    package = importlib.util.module_from_spec(
        importlib.util.spec_from_file_location(
            name, PLUGIN_ROOT / "__init__.py",
            submodule_search_locations=[str(PLUGIN_ROOT)]))
    sys.modules[name] = package
    assert package.__spec__ is not None and package.__spec__.loader is not None
    package.__spec__.loader.exec_module(package)
    return package


class _Ctx:
    def __init__(self):
        self.tools = {}
        self.skills = {}
        self.cli = {}
        self.browser_providers = []
        self.hooks = {}

    def register_tool(self, name, toolset, schema, handler, **kwargs):
        self.tools[name] = {
            "toolset": toolset, "schema": schema, "handler": handler, **kwargs}

    def register_skill(self, name, path, description="", frontmatter=None):
        path = Path(path)
        assert path.is_file(), path
        self.skills[name] = {"path": path, "description": description}

    def register_cli_command(self, name, help, setup_fn, handler_fn=None, description=""):
        self.cli[name] = {"help": help, "setup": setup_fn, "handler": handler_fn}

    def register_browser_provider(self, provider):
        self.browser_providers.append(provider)

    def register_hook(self, hook_name, callback):
        self.hooks.setdefault(hook_name, []).append(callback)


@pytest.fixture()
def registered(hermes_home):
    ctx = _Ctx()
    _load_entry().register(ctx)
    return ctx


def test_tools_registered_with_valid_schemas(registered):
    assert set(registered.tools) == {
        "feed_post", "idea_propose", "goal_track",
        "goal_update", "artifact_save", "reflection_write",
    }
    for name, entry in registered.tools.items():
        assert entry["toolset"] == "hermuse", name
        schema = entry["schema"]
        assert schema["name"] == name
        params = schema["parameters"]
        assert params["type"] == "object"
        assert set(params["required"]) <= set(params["properties"]), name


def test_registered_in_real_registry(registered):
    from tools.registry import registry

    for name, entry in registered.tools.items():
        registry.register(
            name=name, toolset=entry["toolset"], schema=entry["schema"],
            handler=entry["handler"])
    try:
        for name in registered.tools:
            assert registry.get_entry(name) is not None
    finally:
        for name in registered.tools:
            registry.deregister(name)


def test_skill_registered(registered):
    assert set(registered.skills) == {"hermuse"}
    skill_md = registered.skills["hermuse"]["path"]
    assert skill_md.name == "SKILL.md"
    text = skill_md.read_text()
    assert text.startswith("---\n")
    assert "PREFERENCES.md" in text


def test_cli_registered_and_dispatches_status(registered, hermes_home, capsys):
    import argparse

    assert set(registered.cli) == {"hermuse"}
    parser = argparse.ArgumentParser()
    registered.cli["hermuse"]["setup"](parser)
    args = parser.parse_args(["status"])
    assert args.func(args) == 0
    out = capsys.readouterr().out
    assert "Hermuse store" in out and str(hermes_home) in out


def test_computer_provider_and_hooks_are_accepted_by_hermes(registered):
    from agent.browser_provider import BrowserProvider
    from hermes_cli.plugins import VALID_HOOKS

    [provider] = registered.browser_providers
    assert isinstance(provider, BrowserProvider)  # Hermes ignores anything else
    assert provider.name == "hermuse"  # the browser.cloud_provider value setup writes
    assert set(registered.hooks) == {"pre_tool_call", "transform_tool_result"}
    assert set(registered.hooks) <= VALID_HOOKS


class _StatusRuntime:
    def __init__(self, state):
        self.state = state

    def prepare(self, home):
        pass

    def status(self, home, timeout=10.0):
        return {"state": self.state, "detail": "d"}


@pytest.mark.parametrize(("state", "code"), [
    ("building", 0), ("stopped", 0), ("running", 0),
    ("docker_missing", 3), ("daemon_down", 4), ("image_missing", 1), ("error", 1),
])
def test_cli_computer_setup_configures_hermes_and_exits_with_docker_state(
        registered, hermes_home, monkeypatch, capsys, state, code):
    import argparse

    from hermes_cli.config import read_raw_config

    runtime = sys.modules["hermuse_plugin_under_test.computer.runtime"]
    monkeypatch.setattr(runtime, "get_runtime", lambda: _StatusRuntime(state))
    parser = argparse.ArgumentParser()
    registered.cli["hermuse"]["setup"](parser)
    args = parser.parse_args(["computer", "setup"])
    assert args.func(args) == code
    assert json.loads(capsys.readouterr().out) == {"state": state, "detail": "d"}  # JSON only
    browser = read_raw_config()["browser"]
    assert browser["cloud_provider"] == "hermuse"
    assert browser["auto_local_for_private_urls"] is False
    assert browser["backend"] == "off"


def test_tool_handlers_persist_files(registered, hermes_home):
    import store as plugin_store

    handlers = {n: e["handler"] for n, e in registered.tools.items()}
    root = plugin_store.hermuse_root(hermes_home)

    feed = json.loads(handlers["feed_post"]({"title": "t", "body": "b"}))
    assert feed["ok"] and plugin_store.get_feed_post(root, feed["id"]) is not None

    idea = json.loads(handlers["idea_propose"](
        {"title": "t", "pitch": "p", "group": "g"}))
    assert idea["ok"] and plugin_store.get_idea(root, idea["id"]) is not None

    goal = json.loads(handlers["goal_track"](
        {"title": "t", "category": "health", "why": "w"}))
    assert goal["ok"]
    update = json.loads(handlers["goal_update"](
        {"goal_id": goal["id"], "note": "n"}))
    assert update["ok"]
    assert len(plugin_store.get_goal(root, goal["id"])["timeline"]) == 2

    artifact = json.loads(handlers["artifact_save"](
        {"title": "t", "kind": "document", "content": "x"}))
    assert artifact["ok"]
    assert plugin_store.artifact_file(root, artifact["id"]) is not None

    reflection = json.loads(handlers["reflection_write"]({"date": "2026-09-26", "body": "b"}))
    assert reflection == {"ok": True, "date": "2026-09-26"}

    # Validation failures are tool_error JSON, never raised.
    bad = json.loads(handlers["goal_track"](
        {"title": "t", "category": "nope", "why": "w"}))
    assert "error" in bad


@pytest.fixture()
def dashboard(hermes_home, monkeypatch):
    """A dashboard that was running before the install: ``hermes_cli.web_server.app``
    with an API route and the SPA catch-all, hermuse enabled."""
    from fastapi import FastAPI
    from fastapi.responses import JSONResponse
    from hermes_cli import plugins_cmd

    app = FastAPI()

    @app.get("/api/status")
    def status():
        return {"ok": True}

    @app.get(SPA_CATCH_ALL)
    def spa(full_path: str):
        if full_path.startswith("api/"):
            return JSONResponse({"detail": f"No such API endpoint: /{full_path}"}, status_code=404)
        return {"spa": full_path}

    web_server = types.ModuleType("hermes_cli.web_server")
    web_server.app = app
    monkeypatch.setitem(sys.modules, "hermes_cli.web_server", web_server)
    enabled = {"hermuse"}
    monkeypatch.setattr(plugins_cmd, "_get_enabled_set", lambda: set(enabled))
    monkeypatch.setattr(plugins_cmd, "_get_disabled_set", lambda: set())
    sys.modules.pop(API_MODULE, None)
    yield app, enabled
    sys.modules.pop(API_MODULE, None)


def _plugin_routes(app):
    return [route for route in app.router.routes
            if str(getattr(route, "path", "")).startswith("/api/plugins/hermuse/")]


def test_install_into_a_running_dashboard_serves_the_routes_at_once(dashboard):
    from fastapi.testclient import TestClient

    import store as plugin_store

    app, _ = dashboard
    client = TestClient(app)
    assert client.get("/api/plugins/hermuse/files").status_code == 404  # the catch-all's answer

    _load_entry().register(_Ctx())
    assert client.get("/api/plugins/hermuse/files").json() == {"files": list(plugin_store.MANAGED_FILES)}
    assert client.get("/chat").json() == {"spa": "chat"}  # the catch-all still serves the SPA
    assert client.get("/api/status").json() == {"ok": True}
    mounted = _plugin_routes(app)
    assert "/api/plugins/hermuse/computer/ws" in {route.path for route in mounted}

    _load_entry().register(_Ctx())  # a forced rediscovery calls register() again
    assert _plugin_routes(app) == mounted


def test_disabled_plugin_backend_is_not_imported(dashboard):
    app, enabled = dashboard
    enabled.clear()
    _load_entry().register(_Ctx())
    assert _plugin_routes(app) == []
    assert API_MODULE not in sys.modules


def test_register_during_dashboard_import_leaves_the_mount_to_hermes(dashboard):
    app, _ = dashboard
    # Before mount_spa(): Hermes' own _mount_plugin_api_routes() is still to come.
    app.router.routes[:] = [r for r in app.router.routes if getattr(r, "path", "") != SPA_CATCH_ALL]
    _load_entry().register(_Ctx())
    assert _plugin_routes(app) == []
