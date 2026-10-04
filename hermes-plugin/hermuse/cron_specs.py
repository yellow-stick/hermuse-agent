"""Hermuse cron jobs: feed (daily), ideas (weekly), goals check-in (weekly),
reflection (nightly) and the heartbeat (every 30 minutes). Job authorship goes
through ``cron.jobs.create_job`` / ``update_job`` — the same API the
``cronjob_manage`` agent tool uses — so records are always scheduler-valid.
Hermuse jobs are tagged ``origin={"source": "hermuse", "key": <spec key>}`` for
idempotent registration; the delivery layer ignores marker origins without
platform/chat_id (``cron/scheduler_delivery.py::_resolve_origin`` requires both).
Maintenance jobs deliver ``local`` (persist only; surfaces render from the files)
and are hidden from the app's Upcoming list; the heartbeat delivers
``bot-chat`` (the profile's "Bot Chat" session, the app's main chat) and stays
silent with ``NO_REPLY`` when nothing needs the user.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional

ORIGIN_SOURCE = "hermuse"
CRON_TOOLSET = "hermes-cron"
SKILL_REF = "hermuse:hermuse"


@dataclass(frozen=True)
class CronSpec:
    key: str
    name: str
    schedule: str
    skill_ref: str
    prompt: str
    deliver: str = "local"
    # Maintenance jobs the app keeps out of its Upcoming list.
    hidden: bool = True


def _prompt(intro: str, task: str) -> str:
    return (
        f"You are the Hermuse maintenance worker. {intro}\n\n"
        "First read HERMES_HOME/hermuse/PREFERENCES.md and honour it "
        "(Tell me about / Never tell me about / When / How): skip anything the "
        "user never wants to hear about, and stay silent when there is nothing "
        "worth writing.\n\n"
        f"{task}\n\n"
        "Hermuse tools available: feed_post, idea_propose, goal_track, "
        "goal_update, artifact_save, reflection_write."
    )


HEARTBEAT_KEY = "heartbeat"
HEARTBEAT_NAME = "Hermuse heartbeat"

HEARTBEAT_PROMPT = (
    "You are the Hermuse heartbeat: a quiet check-in on the user's behalf. You "
    "only review and report; you never book, buy, send or change anything for "
    "the user.\n\n"
    "Review, in this order: durable memory (HERMES_HOME/memories/MEMORY.md and "
    "USER.md), the tracked goals under HERMES_HOME/hermuse/goals/ (index.json "
    "holds each goal with its status_line), the checklist in "
    "HERMES_HOME/hermuse/HEARTBEAT.md, and the upcoming scheduled jobs "
    "(cronjob_manage action=list). Honour HERMES_HOME/hermuse/PREFERENCES.md "
    "(what never to bring up, when and how to write). Keep every open goal's "
    "status_line current: when it is empty or no longer true (a step done, the "
    "days left changed), set it with goal_update in one short line in the user's "
    "language (e.g. \"Vol non réservé ; départ mercredi 7 octobre, dans 3 jours\"). "
    "Call goal_update once per goal: tool_call takes one entry per call.\n\n"
    "Something needs the user when it needs them now or soon: a deadline "
    "approaching with a step still open (e.g. a trip in 4 days with the flight "
    "unbooked), a commitment drifting, a decision only they can make. Your "
    "final answer is then a brief for the agent of the user's main chat (not "
    "a message to the user), in exactly this form:\n\n"
    "Ask the user: <one or two sentences: what you noticed and why it matters "
    "now>\n"
    "Offer these choices with clarify: <choice A> | <choice B> | <choice C>\n"
    "Do not act before the user answers.\n\n"
    "Use 2-4 short choices (a few words each, e.g. \"Search flights now | "
    "Remind me tomorrow | Already booked\"). Do not repeat a nudge you already "
    "sent unless something changed. When nothing needs the user, reply exactly "
    "NO_REPLY and nothing else."
)

SPECS: tuple[CronSpec, ...] = (
    CronSpec(
        key="feed",
        name="Hermuse feed (daily)",
        schedule="0 8 * * *",
        skill_ref=SKILL_REF,
        prompt=_prompt(
            "Write today's feed edition.",
            "Read HERMES_HOME/hermuse/FEED_PROMPT.md for the user's feed brief, "
            "then use web_search and recent conversation context to publish 1-5 "
            "posts with feed_post. Every post needs why and sources: put the main "
            "article or page the post is about first in sources (the card's image "
            "is that page's share image; a search results page has none). Keep the "
            "tone clear and direct, quick to skim, no clickbait. Skip publishing when "
            "nothing genuinely new turned up.",
        ),
    ),
    CronSpec(
        key="ideas",
        name="Hermuse ideas (weekly)",
        schedule="0 9 * * 1",
        skill_ref=SKILL_REF,
        prompt=_prompt(
            "Refresh the ideas list.",
            "Look at what you learned about the user this week (memory, recent "
            "sessions) and propose 1-3 fresh, specific ideas with idea_propose, "
            "grouped sensibly. Prefer ideas you can actually carry out; skip the "
            "week when nothing good comes to mind.",
        ),
    ),
    CronSpec(
        key="goals",
        name="Hermuse goals check-in (weekly)",
        schedule="0 9 * * 0",
        skill_ref=SKILL_REF,
        prompt=_prompt(
            "Check in on tracked goals.",
            "Read every goal under HERMES_HOME/hermuse/goals/ and, for each one "
            "where you have something real to report, append a timeline entry "
            "with goal_update. Also read HERMES_HOME/hermuse/HEARTBEAT.md: each "
            "checklist line is a recurring watch — investigate it and report via "
            "goal_update when there is news, otherwise stay quiet.",
        ),
    ),
    CronSpec(
        key="reflection",
        name="Hermuse reflection (nightly)",
        schedule="0 2 * * *",
        skill_ref=SKILL_REF,
        prompt=_prompt(
            "Write tonight's reflection journal entry.",
            "Look back on today's conversations: what helped, what missed, what "
            "to do differently. Write one journal entry in your own voice with "
            "reflection_write for the effective date (today's local date). Then "
            "update MEMORY.md-style durable memory as usual.",
        ),
    ),
    CronSpec(
        key=HEARTBEAT_KEY,
        name=HEARTBEAT_NAME,
        schedule="*/30 * * * *",
        skill_ref=SKILL_REF,
        prompt=HEARTBEAT_PROMPT,
        deliver="bot-chat",
        hidden=False,
    ),
)


def spec_by_key(key: str) -> CronSpec:
    for spec in SPECS:
        if spec.key == key:
            return spec
    raise KeyError(f"unknown hermuse cron spec: {key!r}")


def _marker_origin(key: str) -> dict[str, str]:
    return {"source": ORIGIN_SOURCE, "key": key}


def find_job(jobs_module: Any, key: str) -> Optional[dict[str, Any]]:
    """Return the live record for *key*, or None.

    Matches the marker origin first, then the spec name (for jobs created
    before the marker existed or hand-renamed records).
    """
    spec = spec_by_key(key)
    want_origin = _marker_origin(key)
    fallback: Optional[dict[str, Any]] = None
    for job in jobs_module.load_jobs():
        if not isinstance(job, dict):
            continue
        if job.get("origin") == want_origin:
            return job
        if fallback is None and job.get("name") == spec.name:
            fallback = job
    return fallback


def _desired(spec: CronSpec) -> dict[str, Any]:
    return {
        "name": spec.name,
        "prompt": spec.prompt,
        "schedule": spec.schedule,
        "skills": [spec.skill_ref],
        "deliver": spec.deliver,
        "origin": _marker_origin(spec.key),
    }


def register_job(jobs_module: Any, key: str) -> tuple[dict[str, Any], bool]:
    """Create or refresh the job for *key*. Returns ``(record, created)``.

    Refresh rewrites the authored fields (name/prompt/schedule/skills/deliver)
    but preserves scheduler-owned state (enabled/paused, run counters,
    next_run_at anchoring) — an operator-paused Hermuse job stays paused across
    re-registration. Manual prompt edits inside the dashboard are overwritten:
    specs are the source of truth.
    """
    spec = spec_by_key(key)
    existing = find_job(jobs_module, key)
    if existing is None:
        record = jobs_module.create_job(
            prompt=spec.prompt,
            schedule=spec.schedule,
            name=spec.name,
            skills=[spec.skill_ref],
            deliver=spec.deliver,
            origin=_marker_origin(spec.key),
        )
        return record, True
    updates = {
        field: value
        for field, value in _desired(spec).items()
        if existing.get(field) != value
    }
    if not updates:
        return existing, False
    # ``schedule`` updates recompute next_run_at via _apply_schedule_update;
    # paused records keep next_run_at=None until resumed (cron/jobs.py).
    record = jobs_module.update_job(existing["id"], updates)
    return (record if record is not None else existing), False


def register_all(jobs_module: Any) -> dict[str, tuple[dict[str, Any], bool]]:
    """Idempotently register every Hermuse job; returns key -> (record, created)."""
    return {spec.key: register_job(jobs_module, spec.key) for spec in SPECS}


def remove_all(jobs_module: Any) -> list[str]:
    """Remove every Hermuse-managed job; returns the removed job ids."""
    removed: list[str] = []
    for spec in SPECS:
        job = find_job(jobs_module, spec.key)
        if job is not None and jobs_module.remove_job(job["id"]):
            removed.append(job["id"])
    return removed
