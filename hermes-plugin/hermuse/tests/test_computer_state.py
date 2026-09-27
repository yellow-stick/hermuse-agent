"""Take control lease: latest human wins, only the holder hands back, restarts reset."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from computer import state

PLUGIN_ROOT = Path(__file__).resolve().parent.parent


def test_latest_take_wins_and_only_the_current_lease_releases(hermes_home):
    first = state.take_control(hermes_home)
    second = state.take_control(hermes_home)
    assert first != second
    assert state.read_control(hermes_home)["lease_id"] == second

    assert state.release_control(hermes_home, first) is False  # replaced viewer
    assert state.read_control(hermes_home)["holder"] == state.HUMAN

    assert state.release_control(hermes_home, second) is True
    assert state.read_control(hermes_home) == {"holder": state.AGENT, "lease_id": None}
    assert state.release_control(hermes_home, None) is False


def test_missing_or_corrupt_control_means_agent(hermes_home):
    assert state.read_control(hermes_home)["holder"] == state.AGENT
    path = state.computer_root(hermes_home) / state.CONTROL_FILE
    path.parent.mkdir(parents=True)
    for content in ("not json", '{"holder": "human"}', '["human"]'):
        path.write_text(content)
        assert state.read_control(hermes_home) == {"holder": state.AGENT, "lease_id": None}


def test_dashboard_import_hands_control_back_to_the_agent(hermes_home):
    state.take_control(hermes_home)
    name = "hermuse_dashboard_plugin_api_reset_test"
    sys.modules.pop(name, None)
    spec = importlib.util.spec_from_file_location(name, PLUGIN_ROOT / "dashboard" / "plugin_api.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    finally:
        sys.modules.pop(name, None)
    assert state.read_control(hermes_home)["holder"] == state.AGENT
