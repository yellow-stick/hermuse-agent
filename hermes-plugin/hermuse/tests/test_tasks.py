"""Activity tasks: hooks record one task per turn, classify the source, skip a
silent heartbeat, and fall back to a heuristic summary without a model."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

from cron import jobs as cron_jobs

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
PACKAGE = "hermuse_plugin_tasks_under_test"


def _package_module(name):
    # The recorder uses package-relative imports, like the loaded plugin.
    if PACKAGE not in sys.modules:
        package = importlib.util.module_from_spec(importlib.util.spec_from_file_location(
            PACKAGE, PLUGIN_ROOT / "__init__.py", submodule_search_locations=[str(PLUGIN_ROOT)]))
        sys.modules[PACKAGE] = package
        package.__spec__.loader.exec_module(package)
    return importlib.import_module(f"{PACKAGE}.{name}")


@pytest.fixture()
def recorder_mod():
    return _package_module("task_recorder")


@pytest.fixture()
def tasks_store():
    return _package_module("store")


class FakeLlm:
    def __init__(self, parsed=None, error=None):
        self.parsed, self.error, self.calls = parsed, error, []

    def complete_structured(self, **kwargs):
        self.calls.append(kwargs)
        if self.error is not None:
            raise self.error
        return SimpleNamespace(parsed=self.parsed, text="")


@pytest.fixture()
def make_recorder(recorder_mod, hermuse_root):
    def make(llm=None):
        return recorder_mod.TaskRecorder(llm, resolve_root=lambda: hermuse_root)
    return make


HISTORY = [
    {"role": "user", "content": "Earlier question"},
    {"role": "assistant", "content": None,
     "tool_calls": [{"id": "0", "function": {"name": "old_tool", "arguments": "{}"}}]},
    {"role": "user", "content": "Find me a table for two tonight"},
    {"role": "assistant", "content": None, "tool_calls": [
        {"id": "1", "type": "function", "function": {"name": "web_search", "arguments": "{}"}},
        {"id": "2", "type": "function", "function": {"name": "browser_navigate", "arguments": "{}"}},
    ]},
    {"role": "tool", "tool_call_id": "1", "content": "..."},
    {"role": "assistant", "content": None, "tool_calls": [
        {"id": "3", "type": "function", "function": {"name": "web_search", "arguments": "{}"}}]},
    {"role": "assistant", "content": "Booked **Le Lieu Unique** at 8pm. Enjoy your dinner!"},
]


def _turn(recorder, *, session_id="sess-1", turn_id="turn-1",
          user="Find me a table for two tonight",
          answer="Booked **Le Lieu Unique** at 8pm. Enjoy your dinner!",
          history=HISTORY, platform="tui", completed=True, failed=False, interrupted=False,
          post=True):
    recorder.pre_llm_call(session_id=session_id, turn_id=turn_id, user_message=user,
                          conversation_history=[], platform=platform, model="m")
    if post:
        recorder.post_llm_call(session_id=session_id, turn_id=turn_id, user_message=user,
                               assistant_response=answer, conversation_history=history,
                               model="m", platform=platform, task_id="task")
    recorder.on_session_end(session_id=session_id, turn_id=turn_id, completed=completed,
                            failed=failed, interrupted=interrupted, model="m", platform=platform)
    assert recorder.flush(10)


def test_chat_turn_is_recorded_with_tools_and_heuristic_summary(make_recorder, tasks_store, hermuse_root):
    recorder = make_recorder()  # no model available
    _turn(recorder)
    [task] = tasks_store.list_tasks(hermuse_root)
    assert task == {
        "id": tasks_store.task_id("sess-1", "turn-1"),
        "session_id": "sess-1",
        "turn_id": "turn-1",
        "title": "Find me a table for two tonight",
        "summary": "Booked Le Lieu Unique at 8pm.",
        "status": "completed",
        "source": "chat",
        "started_at": task["started_at"],
        "finished_at": task["finished_at"],
        "tools": ["web_search", "browser_navigate"],
    }
    assert task["started_at"] <= task["finished_at"]


def test_model_summary_replaces_the_heuristic(make_recorder, recorder_mod, tasks_store, hermuse_root):
    llm = FakeLlm(parsed={"title": "Book dinner table", "summary": "Booked Le Lieu Unique for 8 PM"})
    _turn(make_recorder(llm))
    [task] = tasks_store.list_tasks(hermuse_root)
    assert (task["title"], task["summary"]) == ("Book dinner table", "Booked Le Lieu Unique for 8 PM")
    [call] = llm.calls
    assert call["task"] == recorder_mod.AUX_TASK == "hermuse_task_summary"
    assert call["json_schema"]["required"] == ["title", "summary"]
    assert "web_search" in call["input"][0]["text"]


@pytest.mark.parametrize("llm", [
    FakeLlm(error=RuntimeError("no auxiliary model configured")),
    FakeLlm(parsed=None),
    FakeLlm(parsed={"title": "", "summary": "x"}),
])
def test_summary_falls_back_to_heuristic_when_model_fails(make_recorder, tasks_store, hermuse_root, llm):
    _turn(make_recorder(llm))
    [task] = tasks_store.list_tasks(hermuse_root)
    assert task["title"] == "Find me a table for two tonight"
    assert task["summary"] == "Booked Le Lieu Unique at 8pm."


def test_heuristic_title_and_summary_helpers(recorder_mod):
    assert recorder_mod.heuristic_title("## Plan my *trip* to Lisbon?\nDetails…") == "Plan my trip to Lisbon"
    assert recorder_mod.heuristic_title("", "Hermuse heartbeat") == "Hermuse heartbeat"
    assert recorder_mod.heuristic_title("") == "Untitled task"
    long = "word " * 60
    assert len(recorder_mod.heuristic_title(long)) <= recorder_mod.TITLE_MAX
    assert recorder_mod.heuristic_summary("See [the docs](https://x.y). More.") == "See the docs."


def test_interrupted_and_failed_turns(make_recorder, tasks_store, hermuse_root):
    recorder = make_recorder()
    _turn(recorder, turn_id="stopped", post=False, completed=False, interrupted=True)
    _turn(recorder, turn_id="broken", completed=False, failed=True)
    stopped = tasks_store.get_task(hermuse_root, tasks_store.task_id("sess-1", "stopped"))
    assert stopped["status"] == "interrupted"
    assert stopped["title"] == "Find me a table for two tonight"
    assert stopped["summary"] == "Stopped before it finished." and stopped["tools"] == []
    broken = tasks_store.get_task(hermuse_root, tasks_store.task_id("sess-1", "broken"))
    assert broken["status"] == "failed" and broken["tools"] == ["web_search", "browser_navigate"]


def test_end_without_start_records_nothing(make_recorder, tasks_store, hermuse_root):
    recorder = make_recorder()
    recorder.on_session_end(session_id="s", turn_id="t", completed=False, interrupted=True)
    assert recorder.flush(5)
    assert tasks_store.list_tasks(hermuse_root) == []


@pytest.fixture()
def cron_registered(hermes_home):
    import cron_specs

    with cron_jobs.use_cron_store(hermes_home):
        heartbeat, _ = cron_specs.register_job(cron_jobs, "heartbeat")
        other = cron_jobs.create_job(prompt="Weather", schedule="0 8 * * *",
                                     name="Morning weather", deliver="bot-chat")
        yield heartbeat, other


def _cron_session(job_id):
    return f"cron_{job_id}_20261003_080000"


def test_one_task_per_scheduled_run_relay_turns_skipped(
        make_recorder, tasks_store, hermuse_root, cron_registered):
    heartbeat, other = cron_registered
    recorder = make_recorder()
    weather_history = [
        {"role": "user", "content": "Weather prompt"},
        {"role": "assistant", "content": None, "tool_calls": [
            {"id": "1", "type": "function", "function": {"name": "web_search", "arguments": "{}"}}]},
        {"role": "assistant", "content": "Sunny, 22°C."},
    ]
    _turn(recorder, session_id=_cron_session(other["id"]), user="Weather prompt",
          answer="Sunny, 22°C.", history=weather_history, platform="cron")
    _turn(recorder, session_id=_cron_session(heartbeat["id"]), user="heartbeat prompt",
          answer="Your trip is in 4 days and the flight is unbooked.", history=[], platform="cron")
    # The Bot Chat turns relaying both runs' output (one stopped mid-way) are not tasks.
    _turn(recorder, session_id="bot-chat", turn_id="relay",
          user='[Cronjob "Hermuse heartbeat" output — scheduled job, not the user.]\n\nTrip soon',
          answer="Your trip is in 4 days. Book now?", history=HISTORY)
    _turn(recorder, session_id="bot-chat", turn_id="relay-weather",
          user='[Cronjob "Morning weather" output — scheduled job, not the user.]\n\nSunny',
          answer="Sunny today.", history=HISTORY)
    _turn(recorder, session_id="bot-chat", turn_id="relay-stopped",
          user='[Cronjob "Morning weather" output — scheduled job, not the user.]\n\nSunny',
          post=False, completed=False, interrupted=True)
    tasks = tasks_store.list_tasks(hermuse_root)
    by_session = {t["session_id"]: t for t in tasks}
    assert len(tasks) == 2
    assert set(by_session) == {_cron_session(other["id"]), _cron_session(heartbeat["id"])}
    weather = by_session[_cron_session(other["id"])]
    assert weather["source"] == "cron" and weather["title"] == "Morning weather"
    assert weather["tools"] == ["web_search"]
    beat = by_session[_cron_session(heartbeat["id"])]
    assert beat["source"] == "heartbeat" and beat["title"] == "Hermuse heartbeat"


@pytest.mark.parametrize("answer", ["NO_REPLY", "  no_reply \n", "[SILENT]"])
def test_silent_heartbeat_is_not_recorded(make_recorder, tasks_store, hermuse_root, cron_registered, answer):
    heartbeat, _ = cron_registered
    recorder = make_recorder(FakeLlm(parsed={"title": "x", "summary": "y"}))
    _turn(recorder, session_id=_cron_session(heartbeat["id"]), user="heartbeat prompt",
          answer=answer, platform="cron")
    _turn(recorder, session_id="bot-chat", turn_id="relay",
          user='[Cronjob "Hermuse heartbeat" output — scheduled job, not the user.]\n\nx',
          answer=answer)
    assert tasks_store.list_tasks(hermuse_root) == []


def test_no_reply_in_chat_is_still_a_task(make_recorder, tasks_store, hermuse_root):
    _turn(make_recorder(), answer="NO_REPLY")
    assert len(tasks_store.list_tasks(hermuse_root)) == 1


def test_subagent_turns_are_not_tasks(make_recorder, tasks_store, hermuse_root):
    _turn(make_recorder(), platform="subagent")
    assert tasks_store.list_tasks(hermuse_root) == []


def test_register_wires_hooks_and_aux_task(recorder_mod):
    registered = {"hooks": {}, "aux": {}}

    class Ctx:
        llm = FakeLlm()

        def register_auxiliary_task(self, key, *, display_name, description, defaults=None):
            registered["aux"][key] = display_name

        def register_hook(self, name, callback):
            registered["hooks"][name] = callback

    recorder = recorder_mod.register(Ctx())
    assert set(registered["hooks"]) == {"pre_llm_call", "post_llm_call", "on_session_end"}
    assert registered["aux"] == {"hermuse_task_summary": recorder_mod.AUX_TASK_DISPLAY_NAME}
    assert recorder.pre_llm_call(session_id="s", turn_id="t", user_message="hi") is None
