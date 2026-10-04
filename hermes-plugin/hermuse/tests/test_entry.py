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
        self.prompt_sections = {}
        self.aux_tasks = {}
        self.llm = None  # no model in tests: task summaries stay heuristic

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

    def register_system_prompt_section(self, id, content, **kwargs):
        self.prompt_sections[id] = {"content": content, **kwargs}

    def register_auxiliary_task(self, key, *, display_name, description, defaults=None):
        self.aux_tasks[key] = {"display_name": display_name, "description": description}


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


def test_registration_does_not_seed_feed_or_schedule_jobs(registered, hermes_home):
    import store as plugin_store
    from cron import jobs

    assert plugin_store.list_feed(plugin_store.hermuse_root(hermes_home)) == []
    with jobs.use_cron_store(hermes_home):
        assert jobs.load_jobs() == []


def test_feed_tool_uses_active_profile_at_invocation(registered, hermes_home):
    import store as plugin_store
    from hermes_constants import reset_hermes_home_override, set_hermes_home_override

    handler = registered.tools["feed_post"]["handler"]
    profiles = [hermes_home / "profiles" / name for name in ("work", "personal")]
    published = []
    for profile in profiles:
        token = set_hermes_home_override(profile)
        try:
            result = json.loads(handler({
                "title": f"{profile.name} discovery",
                "body": f"Research result for {profile.name}.",
                "why": "You asked me to watch this topic.",
                "topic": "Research",
                "sources": ["https://example.com/source"],
            }))
        finally:
            reset_hermes_home_override(token)
        assert result["ok"]
        published.append(result)

    for profile, result in zip(profiles, published):
        root = plugin_store.hermuse_root(profile)
        [post] = plugin_store.list_feed(root)
        assert post["id"] == result["id"]
        assert post["title"] == f"{profile.name} discovery"
        assert post["sources"] == ["https://example.com/source"]
        assert post["body"] in (root / "feed" / result["file"]).read_text()
    assert plugin_store.list_feed(plugin_store.hermuse_root(hermes_home)) == []


def test_behaviour_prompt_section_task_hooks_and_aux_task(registered):
    from hermes_cli.plugins import (
        DEFAULT_SYSTEM_PROMPT_SECTION_MAX_CHARS, VALID_HOOKS, is_valid_system_prompt_section_id)

    section = registered.prompt_sections["hermuse_behaviour"]["content"]
    assert is_valid_system_prompt_section_id("hermuse_behaviour")
    # Frozen into every session prompt: kept short, and well under Hermes' cap.
    assert len(section) < 2200 < DEFAULT_SYSTEM_PROMPT_SECTION_MAX_CHARS
    for needle in ('deliver="bot-chat"', "cronjob_manage", "goal_track", 'source="agent"',
                   "cron_job_id", "status_line", "clarify", "why", "NO_REPLY",
                   '"Ask the user"', "do not act on it yourself", 'action="create"',
                   '"in 2m"', "Never wait, sleep or poll", "fire time"):
        assert needle in section, needle
    assert "platform" in section  # never ask which platform/channel
    for hook in ("pre_llm_call", "post_llm_call", "on_session_end"):
        assert hook in VALID_HOOKS
    # Activity recorder + per-turn clock; one post_llm_call / on_session_end each.
    assert len(registered.hooks["pre_llm_call"]) == 2
    assert len(registered.hooks["post_llm_call"]) == 1
    assert len(registered.hooks["on_session_end"]) == 1
    assert "hermuse_task_summary" in registered.aux_tasks


def test_behaviour_time_memory_tool_call_and_relay_rules(registered):
    section = registered.prompt_sections["hermuse_behaviour"]["content"]
    for needle in (
            # Time: the per-turn clock, morning default, night ban, explicit confirmation.
            '"Local time now"', '"Tomorrow morning" is 09:00 local', "never schedule 23:00-07:00",
            "weekday, date and local time", 'Before creating, run action="list"',
            # Keep in mind: durable memory + a goal with a status line.
            '"Keep in mind"', "a dated plan (trip, deadline): call goal_track",
            '(title, category, why, source="agent", status_line;',
            'AND memory (target "memory"', "cron_job_id if a job serves it",
            "Other facts: memory only",
            # Deferred tools: one entry per tool_call.
            "ALWAYS tool_describe a deferred tool", "before its first tool_call; never guess",
            "tool_call takes ONE entry for local tools",
            # Ideas offered as quick replies too; feed sources main page first.
            "idea_propose each, and offer them as clarify choices", "sources, main page first",
            # A job's own final response is the deliverable.
            "its final response IS the deliverable", "never narration of its steps",
            # Relay: the content itself, not a receipt.
            "Your reply IS that content for the user", "in their language and tone",
            "formatting and links kept", '"reçu"'):
        assert needle in section, needle


def test_behaviour_schedule_forms_are_the_ones_hermes_accepts(registered):
    import re

    from cron.jobs import parse_schedule

    section = registered.prompt_sections["hermuse_behaviour"]["content"]
    assert "never 6 fields" in section
    forms = re.findall(r'"((?:in \d+[mh])|(?:\d{4}-\d{2}-\d{2}T\d{2}:\d{2})|(?:every [^"]+)|'
                       r'(?:[\d*]+(?: [\d*/,-]+){4}))"', section)
    assert set(forms) == {"in 2m", "in 2h", "2026-10-05T09:00", "every day 8am", "0 8 * * *"}
    kinds = {form: parse_schedule(form)["kind"] for form in forms}
    assert kinds == {"in 2m": "once", "in 2h": "once", "2026-10-05T09:00": "once",
                     "every day 8am": "cron", "0 8 * * *": "cron"}
    assert parse_schedule("every day 8am")["expr"] == "0 8 * * *"
    # The 6-field form the agent once sent is what Hermes rejects.
    with pytest.raises(ValueError):
        parse_schedule("0 57 0 * * *")


def test_turn_clock_hook_gives_local_date_time_and_zone(registered, monkeypatch):
    from datetime import datetime
    from zoneinfo import ZoneInfo

    import hermes_time

    berlin = ZoneInfo("Europe/Berlin")
    monkeypatch.setattr(hermes_time, "now", lambda: datetime(2026, 10, 4, 0, 47, tzinfo=berlin))
    monkeypatch.setattr(hermes_time, "get_timezone_name", lambda: "Europe/Berlin")
    contexts = [hook(session_id="s", turn_id="t", user_message="rappelle-moi demain matin",
                     conversation_history=[], is_first_turn=True, model="m", platform="tui")
                for hook in registered.hooks["pre_llm_call"]]
    clock = [c for c in contexts if isinstance(c, dict) and c.get("context")]
    assert clock == [{"context": (
        "Local time now: Sunday 4 October 2026, 00:47 (Europe/Berlin, UTC+02:00; "
        "ISO 2026-10-04T00:47). Tomorrow is Monday 5 October 2026.")}]
    # Winter time and a month boundary; server-local zones fall back to the abbreviation.
    import turn_clock
    assert turn_clock.clock_line(datetime(2026, 12, 31, 23, 5, tzinfo=berlin)) == (
        "Local time now: Thursday 31 December 2026, 23:05 (Europe/Berlin, UTC+01:00; "
        "ISO 2026-12-31T23:05). Tomorrow is Friday 1 January 2027.")
    local = datetime(2026, 10, 4, 9, 0).astimezone()
    assert local.strftime("%Z") in turn_clock.clock_line(local)


def test_turn_clock_context_reaches_the_user_message(registered, monkeypatch):
    """Hermes appends pre_llm_call context to the turn's user message on every turn."""
    from types import SimpleNamespace

    from agent.turn_context import _collect_pre_llm_call_context
    from hermes_cli import plugins

    manager = plugins.get_plugin_manager()
    hook = next(h for h in registered.hooks["pre_llm_call"] if h.__module__.endswith("turn_clock"))
    monkeypatch.setitem(manager._hooks, "pre_llm_call", [hook])
    agent = SimpleNamespace(session_id="s", model="m", platform="tui")
    context = _collect_pre_llm_call_context(
        agent, effective_task_id="t", turn_id="t", original_user_message="hi",
        messages=[], conversation_history=[])
    assert context.startswith("Local time now: ") and "Tomorrow is " in context


@pytest.mark.parametrize("args", [
    {"title": "Missing body", "why": "w"},
    {"body": "Missing title", "why": "w"},
    {"title": "Missing why", "body": "b"},
    {"title": "t", "body": "b", "why": "w", "image_url": "file:///etc/passwd"},
])
def test_invalid_feed_tool_call_does_not_publish(registered, hermes_home, args):
    import store as plugin_store

    result = json.loads(registered.tools["feed_post"]["handler"](args))
    assert "error" in result
    assert plugin_store.list_feed(plugin_store.hermuse_root(hermes_home)) == []


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
    assert set(registered.hooks) == {
        "pre_tool_call", "transform_tool_result",  # the agent's computer
        "pre_llm_call", "post_llm_call", "on_session_end",  # Activity tasks
    }
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

    feed = json.loads(handlers["feed_post"]({
        "title": "t", "body": "b", "why": "w", "image_url": "https://example.com/a.png"}))
    post = plugin_store.get_feed_post(root, feed["id"])
    # No network in tests: the named image cannot be copied, so none is shown.
    assert feed["ok"] and post["why"] == "w" and post["image_url"] is None and feed["image"] is False

    idea = json.loads(handlers["idea_propose"](
        {"title": "t", "pitch": "p", "group": "g"}))
    assert idea["ok"] and plugin_store.get_idea(root, idea["id"]) is not None
    assert "duplicate" not in idea
    trip = json.loads(handlers["idea_propose"]({
        "title": "Je peux te chercher et comparer des vols Madrid → Nantes",
        "pitch": "Google Flights / Skyscanner pour le 7 et le 12 octobre.", "group": "Voyage"}))
    again = json.loads(handlers["idea_propose"]({
        "title": "Je cherche les meilleurs vols Madrid → Nantes",
        "pitch": "Options aller/retour triées par prix.", "group": "Voyage"}))
    assert again == {"ok": True, "id": trip["id"], "duplicate": True,
                     "existing_title": "Je peux te chercher et comparer des vols Madrid → Nantes"}
    assert sum(1 for i in plugin_store.list_ideas(root) if i["group"] == "Voyage") == 1

    goal = json.loads(handlers["goal_track"]({
        "title": "Trip to Lyon", "category": "something_else", "why": "Leaving on the 20th.",
        "status_line": "Départ mardi 20 octobre, rien de réservé"}))
    assert goal["ok"]
    assert plugin_store.get_goal(root, goal["id"])["status_line"] == (
        "Départ mardi 20 octobre, rien de réservé")
    goal = json.loads(handlers["goal_track"](
        {"title": "t", "category": "health", "why": "w"}))
    assert goal["ok"]
    tracked = plugin_store.get_goal(root, goal["id"])
    assert tracked["source"] == "agent" and tracked["parent_id"] is None
    update = json.loads(handlers["goal_update"](
        {"goal_id": goal["id"], "note": "n"}))
    assert update["ok"]
    assert len(plugin_store.get_goal(root, goal["id"])["timeline"]) == 2
    status = json.loads(handlers["goal_update"](
        {"goal_id": goal["id"], "status_line": "Flight booked, hotel open"}))
    assert status["ok"]
    assert plugin_store.get_goal(root, goal["id"])["status_line"] == "Flight booked, hotel open"
    assert len(plugin_store.get_goal(root, goal["id"])["timeline"]) == 2
    assert "error" in json.loads(handlers["goal_update"]({"goal_id": goal["id"]}))

    sub = json.loads(handlers["goal_track"]({
        "title": "Book flight", "category": "something_else", "why": "Trip",
        "source": "user", "parent_id": goal["id"], "cron_job_id": "abc123"}))
    subgoal = plugin_store.get_goal(root, sub["id"])
    assert subgoal["source"] == "user" and subgoal["parent_id"] == goal["id"]
    assert subgoal["cron_job_id"] == "abc123"
    assert "error" in json.loads(handlers["goal_track"]({
        "title": "t", "category": "health", "why": "w", "parent_id": "missing"}))

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
