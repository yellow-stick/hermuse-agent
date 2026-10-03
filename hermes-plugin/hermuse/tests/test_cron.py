"""Cron registration: idempotent, refresh-safe, real cron backend.

Runs against the real ``cron.jobs`` store, routed to the throwaway HERMES_HOME
via ``cron.jobs.use_cron_store`` (no fake jobs module: the point is proving the
records the real scheduler reads).
"""

from __future__ import annotations

import json

import pytest

import cron_specs
from cron import jobs as cron_jobs


@pytest.fixture()
def cron_home(hermes_home):
    with cron_jobs.use_cron_store(hermes_home):
        yield hermes_home


def _hermuse_jobs():
    return [
        job for job in cron_jobs.load_jobs()
        if isinstance(job.get("origin"), dict)
        and job["origin"].get("source") == cron_specs.ORIGIN_SOURCE
    ]


def test_register_all_creates_five_scheduler_valid_jobs(cron_home):
    results = cron_specs.register_all(cron_jobs)
    assert set(results) == {"feed", "ideas", "goals", "reflection", "heartbeat"}
    for key, (record, created) in results.items():
        assert created is True
        assert cron_jobs.is_job_runnable(record), key
        assert record["next_run_at"], key
        assert record["schedule"]["kind"] == "cron", key
        assert record["skills"] == [cron_specs.SKILL_REF], key
        assert record["deliver"] == ("bot-chat" if key == "heartbeat" else "local"), key
    assert len(_hermuse_jobs()) == 5


def test_heartbeat_spec_delivers_to_bot_chat_every_30_minutes(cron_home):
    spec = cron_specs.spec_by_key("heartbeat")
    assert spec.deliver == "bot-chat" and spec.hidden is False
    assert spec.schedule == "*/30 * * * *"
    assert "NO_REPLY" in spec.prompt and "clarify" in spec.prompt
    for needle in ("Ask the user:", "Offer these choices with clarify:",
                   "Do not act before the user answers."):
        assert needle in spec.prompt, needle
    for key in ("feed", "ideas", "goals", "reflection"):
        assert cron_specs.spec_by_key(key).deliver == "local"
        assert cron_specs.spec_by_key(key).hidden is True

    (record, _) = cron_specs.register_job(cron_jobs, "heartbeat")
    assert record["name"] == cron_specs.HEARTBEAT_NAME
    assert record["deliver"] == "bot-chat"
    # A diverged deliver value is healed back to the spec's on refresh.
    cron_jobs.update_job(record["id"], {"deliver": "local"})
    (refreshed, created) = cron_specs.register_job(cron_jobs, "heartbeat")
    assert created is False and refreshed["deliver"] == "bot-chat"


def test_register_all_is_idempotent(cron_home):
    first = cron_specs.register_all(cron_jobs)
    second = cron_specs.register_all(cron_jobs)
    assert len(_hermuse_jobs()) == 5
    for key in first:
        assert second[key][0]["id"] == first[key][0]["id"]
        assert second[key][1] is False


def test_refresh_preserves_pause_but_updates_spec_fields(cron_home):
    (record, _) = cron_specs.register_job(cron_jobs, "feed")
    cron_jobs.pause_job(record["id"], "operator break")
    paused = cron_jobs.get_job(record["id"])
    assert paused is not None and not paused["enabled"]

    (refreshed, created) = cron_specs.register_job(cron_jobs, "feed")
    assert created is False
    assert refreshed["id"] == record["id"]
    assert not refreshed["enabled"]
    assert refreshed["state"] == "paused"
    assert refreshed["prompt"] == cron_specs.spec_by_key("feed").prompt
    assert refreshed["origin"] == {"source": "hermuse", "key": "feed"}


def test_refresh_heals_diverged_schedule(cron_home):
    (record, _) = cron_specs.register_job(cron_jobs, "reflection")
    cron_jobs.update_job(record["id"], {"schedule": "0 5 * * *"})
    assert cron_jobs.get_job(record["id"])["schedule"]["expr"] == "0 5 * * *"

    (refreshed, _) = cron_specs.register_job(cron_jobs, "reflection")
    assert refreshed["schedule"]["expr"] == "0 2 * * *"


def test_remove_all_only_touches_hermuse_jobs(cron_home):
    cron_specs.register_all(cron_jobs)
    other = cron_jobs.create_job(
        prompt="Someone else's job", schedule="0 6 * * *",
        name="Unrelated", deliver="local")
    removed = cron_specs.remove_all(cron_jobs)
    assert len(removed) == 5
    assert _hermuse_jobs() == []
    assert cron_jobs.get_job(other["id"]) is not None
    # Second removal is a no-op.
    assert cron_specs.remove_all(cron_jobs) == []


def test_spec_schedules_are_valid_cron_expressions():
    for spec in cron_specs.SPECS:
        parsed = cron_jobs.parse_schedule(spec.schedule)
        assert parsed["kind"] == "cron"
        assert parsed["expr"] == spec.schedule


def test_conversational_cron_tool_persists_requested_feed_job_in_profile(
        cron_home, monkeypatch):
    from hermes_constants import reset_hermes_home_override, set_hermes_home_override
    from tools import cronjob_tools
    from tools.registry import registry

    monkeypatch.setenv("HERMES_INTERACTIVE", "1")
    assert cronjob_tools.check_cronjob_requirements()
    entry = registry.get_entry("cronjob_manage")
    assert entry is not None and entry.toolset == "cronjob"
    profile = cron_home / "profiles" / "research"
    profile.mkdir(parents=True)
    token = set_hermes_home_override(profile)
    try:
        with cron_jobs.use_cron_store(profile):
            result = json.loads(entry.handler({
                "action": "create",
                "name": "Requested research briefing",
                "schedule": "0 8 * * 1",
                "prompt": cron_specs.spec_by_key("feed").prompt,
                "skills": [cron_specs.SKILL_REF],
                "deliver": "local",
            }))
            assert result["success"], result
            job = cron_jobs.get_job(result["job_id"])
            assert job is not None
            assert cron_jobs.is_job_runnable(job)
            assert job["schedule"]["expr"] == "0 8 * * 1"
            assert job["skills"] == [cron_specs.SKILL_REF]
            assert job["deliver"] == "local"
            assert job["next_run_at"] == result["next_run_at"]
            listed = json.loads(entry.handler({"action": "list"}))
            assert listed["success"] and listed["count"] == 1
            updated = json.loads(entry.handler({
                "action": "update",
                "job_id": job["id"],
                "schedule": "0 9 * * 1",
            }))
            assert updated["success"], updated
            assert cron_jobs.get_job(job["id"])["schedule"]["expr"] == "0 9 * * 1"
            assert len(cron_jobs.load_jobs()) == 1
    finally:
        reset_hermes_home_override(token)
    assert cron_jobs.load_jobs() == []
