"""Plugin entry point: register(ctx) wires tools + skill + CLI; handlers persist."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

PLUGIN_ROOT = Path(__file__).resolve().parent.parent


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

    def register_tool(self, name, toolset, schema, handler, **kwargs):
        self.tools[name] = {
            "toolset": toolset, "schema": schema, "handler": handler, **kwargs}

    def register_skill(self, name, path, description="", frontmatter=None):
        path = Path(path)
        assert path.is_file(), path
        self.skills[name] = {"path": path, "description": description}

    def register_cli_command(self, name, help, setup_fn, handler_fn=None, description=""):
        self.cli[name] = {"help": help, "setup": setup_fn, "handler": handler_fn}


@pytest.fixture()
def registered():
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
