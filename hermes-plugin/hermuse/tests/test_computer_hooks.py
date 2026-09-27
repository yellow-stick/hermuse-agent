"""pre_tool_call (Take control gate + readiness guard), snapshots, setup config."""

from __future__ import annotations

import os
import time

import pytest

from computer import hooks, state


def _block(message):
    return {"action": "block", "message": message}


def test_human_control_blocks_browser_tools_only(hermes_home, fake_runtime):
    state.take_control(hermes_home)
    assert hooks.pre_tool_call(tool_name="browser_navigate", args={}) == _block(
        hooks.BROWSER_BLOCK_MESSAGE)
    assert hooks.pre_tool_call(tool_name="web_search", args={}) is None
    assert fake_runtime.calls == []


def test_missing_control_file_lets_the_agent_browse(hermes_home, fake_runtime):
    assert hooks.pre_tool_call(tool_name="browser_click", args={}) is None


def test_unreachable_docker_blocks_with_the_state(hermes_home, fake_runtime):
    fake_runtime.status_result = {"state": "daemon_down",
                                  "detail": "Cannot connect to the Docker daemon"}
    result = hooks.pre_tool_call(tool_name="browser_navigate", args={})
    assert result["action"] == "block"
    assert result["message"] == hooks.COMPUTER_UNAVAILABLE_MESSAGE.format(
        state="daemon_down", detail="Cannot connect to the Docker daemon")
    assert ("ensure_running", 18) not in fake_runtime.calls


def test_missing_image_starts_the_build_and_blocks(hermes_home, fake_runtime):
    fake_runtime.status_result = {"state": "image_missing", "detail": "not built"}
    result = hooks.pre_tool_call(tool_name="browser_navigate", args={})
    assert result["action"] == "block" and "image_missing" in result["message"]
    assert fake_runtime.calls.count(("prepare",)) == 1


def test_stopped_computer_is_started_before_the_tool(hermes_home, fake_runtime):
    fake_runtime.status_result = {"state": "stopped", "detail": ""}
    assert hooks.pre_tool_call(tool_name="browser_navigate", args={}) is None
    assert fake_runtime.calls == [("status", 5), ("ensure_running", 18)]


def test_failed_start_blocks_with_the_parsed_state(hermes_home, fake_runtime):
    fake_runtime.status_result = {"state": "stopped", "detail": ""}
    fake_runtime.ensure_error = RuntimeError(
        "hermuse computer: error — Chromium did not answer on CDP within 18 s")
    result = hooks.pre_tool_call(tool_name="browser_navigate", args={})
    assert result == _block(hooks.COMPUTER_UNAVAILABLE_MESSAGE.format(
        state="error", detail="Chromium did not answer on CDP within 18 s"))


def test_browser_results_keep_the_newest_snapshots(hermes_home, fake_runtime):
    tool_call_id = "call_new"
    assert hooks.transform_tool_result(
        tool_name="browser_click", result="{}", tool_call_id=tool_call_id) is None
    assert not (state.computer_root(hermes_home) / "snapshots").exists()  # no runtime.json yet

    state.write_runtime(hermes_home, fake_runtime.rt)
    snapshots = state.computer_root(hermes_home) / "snapshots"
    snapshots.mkdir(parents=True)
    old = time.time() - 3600
    for index in range(state.SNAPSHOT_KEEP):
        path = snapshots / f"old{index:03d}.jpg"
        path.write_bytes(b"x")
        os.utime(path, (old + index, old + index))

    assert hooks.transform_tool_result(
        tool_name="browser_click", result="{}", tool_call_id=tool_call_id) is None
    assert (snapshots / "call_new.jpg").read_bytes() == fake_runtime.thumbnail(None)
    names = {p.name for p in snapshots.glob("*.jpg")}
    assert len(names) == state.SNAPSHOT_KEEP and "old000.jpg" not in names

    hooks.transform_tool_result(tool_name="browser_click", result="{}", tool_call_id="../escape")
    hooks.transform_tool_result(tool_name="web_search", result="{}", tool_call_id="call_web")
    assert not (state.computer_root(hermes_home) / "escape.jpg").exists()
    assert not (snapshots / "call_web.jpg").exists()


def test_setup_points_hermes_browser_tools_at_the_computer(hermes_home, fake_runtime, monkeypatch):
    import hermes_cli.config
    from computer import setup as computer_setup

    written = []
    monkeypatch.setattr(hermes_cli.config, "set_config_value",
                        lambda key, value, force=False: written.append((key, value)))
    fake_runtime.status_result = {"state": "building", "detail": "building"}
    assert computer_setup.setup(hermes_home) == {"state": "building", "detail": "building"}
    assert written == [("browser.cloud_provider", "hermuse"),
                       ("browser.auto_local_for_private_urls", "false"),
                       ("browser.backend", "off")]
    assert ("prepare",) in fake_runtime.calls


def test_setup_reports_a_refused_config_write(hermes_home, fake_runtime, monkeypatch):
    import hermes_cli.config
    from computer import setup as computer_setup

    def refuse(key, value, force=False):
        raise SystemExit(1)

    monkeypatch.setattr(hermes_cli.config, "set_config_value", refuse)
    assert computer_setup.setup(hermes_home) == {"state": "error", "detail": "config: 1"}
    assert fake_runtime.calls == []


@pytest.mark.parametrize("tool_name", ["", None, "web_search", "browserish"])
def test_non_browser_tools_are_never_touched(hermes_home, fake_runtime, tool_name):
    state.take_control(hermes_home)
    assert hooks.pre_tool_call(tool_name=tool_name, args={}) is None
