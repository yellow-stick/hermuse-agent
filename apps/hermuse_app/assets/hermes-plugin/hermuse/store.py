"""Hermuse file store: human-readable Feed/Ideas/Goals/Library/Reflections/Tasks data.

All data lives under ``HERMES_HOME/hermuse/`` as Markdown + JSON so the user can
read and edit it with any tool. This module is stdlib-only: it is imported both
by the agent-plugin entry point (``hermes_plugins.hermuse``) and by the
dashboard backend (``dashboard/plugin_api.py``, loaded from a file path), so it
must not import ``hermes_constants``, ``tools.*`` or ``cron.*`` — the dashboard
process has Hermes on ``sys.path`` but the plugin dir itself is not importable
from ``dashboard/`` without path surgery (``plugin_api.py`` handles that).
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import re
import tempfile
import threading
import uuid
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Optional

DIR_NAME = "hermuse"

FEED_PROMPT_FILE = "FEED_PROMPT.md"
PREFERENCES_FILE = "PREFERENCES.md"
IDENTITY_FILE = "IDENTITY.md"
HEARTBEAT_FILE = "HEARTBEAT.md"

# REST files/<name> allow-list. Keep in sync with the API and README.
MANAGED_FILES = (
    FEED_PROMPT_FILE,
    PREFERENCES_FILE,
    IDENTITY_FILE,
    HEARTBEAT_FILE,
)

GOAL_CATEGORIES = (
    "health",
    "relationships",
    "finance",
    "career",
    "interests",
    "productivity",
    "something_else",
)

REACTIONS = ("love", "discuss")

# Artifact kinds: documents, web artifacts, media (image/video/podcast), other.
ARTIFACT_KINDS = ("document", "web", "image", "video", "podcast", "other")

_INDEX = "index.json"
_INDEX_VERSION = 1

_SLUG_RE = re.compile(r"[^a-z0-9]+")


def hermuse_root(home: Optional[os.PathLike[str] | str] = None) -> Path:
    """``<home>/hermuse``; *home* defaults to ``$HERMES_HOME`` then ``~/.hermes``.

    Hermes proper resolves the home via ``hermes_constants.get_hermes_home()``
    (context-local override → env → platform default). This module cannot import
    it (see module docstring), so callers inside Hermes pass the resolved home
    explicitly; the fallback here exists for standalone use and tests.
    """
    if home is None:
        home = os.environ.get("HERMES_HOME", "").strip() or Path.home() / ".hermes"
    return Path(home).expanduser() / DIR_NAME


def new_id() -> str:
    """Short random id (12 hex chars, like Hermes cron job ids)."""
    return uuid.uuid4().hex[:12]


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def slugify(text: str, limit: int = 48) -> str:
    slug = _SLUG_RE.sub("-", text.strip().lower()).strip("-")
    return slug[:limit].strip("-") or "untitled"


def atomic_write_text(path: Path, content: str) -> None:
    """Write *content* via temp file + fsync + atomic rename (same-dir temp file).

    Mirrors ``utils.atomic_write_text`` (Hermes core) without the dependency.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp_", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise

def _read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def _read_index(root: Path, subdir: str) -> dict[str, dict[str, Any]]:
    data = _read_json(root / subdir / _INDEX, None)
    if not isinstance(data, dict):
        return {}
    items = data.get("items")
    if not isinstance(items, dict):
        return {}
    return {k: v for k, v in items.items() if isinstance(v, dict)}


def _write_index(root: Path, subdir: str, items: dict[str, dict[str, Any]]) -> None:
    atomic_write_text(
        root / subdir / _INDEX,
        json.dumps(
            {"version": _INDEX_VERSION, "items": items},
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
    )


def _front_matter(meta: dict[str, Any], body: str) -> str:
    lines = ["---"]
    for key, value in meta.items():
        if isinstance(value, list):
            lines.append(f"{key}: [{', '.join(json.dumps(str(v)) for v in value)}]")
        elif isinstance(value, bool):
            lines.append(f"{key}: {'true' if value else 'false'}")
        else:
            lines.append(f"{key}: {json.dumps(str(value))}")
    lines.append("---")
    lines.append(body.strip() + "\n" if body.strip() else "")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Managed root files (created with defaults on first use, never overwritten)
# ---------------------------------------------------------------------------

FEED_PROMPT_DEFAULT = """\
# Feed prompt

Make me a feed about my interests. Keep the tone clear and direct. Ensure it is
quick to skim. Try to avoid clickbait.

Posts are based on our conversations, my goals, and this prompt. I can be as
specific as I like here — everything is written by the agent and shaped by me.
"""

PREFERENCES_DEFAULT = """\
# Proactive preferences

What you want to hear about without asking, what you never want brought up, and
when. The agent reads this whole file before composing anything proactive, so
plain words anywhere in it count.

## Tell me about

- (things worth a proactive message)

## Never tell me about

- (topics to never raise unprompted)

## When

Messages may arrive from 09:00 to 21:30 local time. Timing preferences guide
composition; delivery may wait for a quiet moment.

## How

Format wishes: one brief line, a card stack, a full page when it needs one, a
particular tone.
"""

IDENTITY_DEFAULT = """\
# Identity

_Fill this in as you figure out who you are._

- **Name:** (what you will be called)
- **Character:** (an AI? a familiar? something stranger?)
- **Vibe:** (how you come across: sharp, warm, calm, playful?)
- **Emoji:** (your signature, if you want one)
"""

HEARTBEAT_DEFAULT = """\
# Heartbeat

Recurring checks for the heartbeat worker. Add one per line, and the next tick
picks them up. This file holds only the checklist, never results — an empty
checklist means nothing runs.

- (e.g. check whether the Nantes flight dropped below EUR 120)
"""

_DEFAULTS = {
    FEED_PROMPT_FILE: FEED_PROMPT_DEFAULT,
    PREFERENCES_FILE: PREFERENCES_DEFAULT,
    IDENTITY_FILE: IDENTITY_DEFAULT,
    HEARTBEAT_FILE: HEARTBEAT_DEFAULT,
}


def ensure_defaults(root: Path) -> list[str]:
    """Create missing managed files with defaults. Never touches existing files.

    Returns the names of files created (empty when everything already existed).
    """
    created: list[str] = []
    root.mkdir(parents=True, exist_ok=True)
    for name, content in _DEFAULTS.items():
        path = root / name
        if not path.exists():
            atomic_write_text(path, content)
            created.append(name)
    return created


def read_managed(root: Path, name: str) -> str:
    """Read a managed file, creating defaults first. *name* must be allow-listed."""
    if name not in MANAGED_FILES:
        raise ValueError(f"unknown managed file: {name!r}")
    ensure_defaults(root)
    return (root / name).read_text(encoding="utf-8")


def write_managed(root: Path, name: str, content: str) -> None:
    """Overwrite a managed file. *name* must be allow-listed (no path traversal)."""
    if name not in MANAGED_FILES:
        raise ValueError(f"unknown managed file: {name!r}")
    atomic_write_text(root / name, content if content.endswith("\n") else content + "\n")


# ---------------------------------------------------------------------------
# Feed
# ---------------------------------------------------------------------------

def _feed_view(record: dict[str, Any]) -> dict[str, Any]:
    """Posts written before ``why``/``image_url`` existed read with their defaults."""
    return {**record, "why": str(record.get("why") or ""), "image_url": record.get("image_url") or None}


def post_feed(
    root: Path,
    *,
    title: str,
    body: str,
    topic: str = "",
    sources: Optional[list[str]] = None,
    why: str = "",
    image_url: Optional[str] = None,
    post_id: Optional[str] = None,
    created_at: Optional[str] = None,
) -> dict[str, Any]:
    """Append a feed post; returns the stored record (incl. reactions ``{}``)."""
    ensure_defaults(root)
    pid = post_id or new_id()
    stamp = created_at or utcnow_iso()
    day = stamp[:10] if len(stamp) >= 10 else date.today().isoformat()
    filename = f"{day}-{slugify(title)}-{pid}.md"
    meta: dict[str, Any] = {
        "id": pid,
        "title": title,
        "topic": topic,
        "created_at": stamp,
        "sources": sources or [],
        "why": why,
    }
    if image_url:
        meta["image_url"] = image_url
    atomic_write_text(root / "feed" / filename, _front_matter(meta, body))
    items = _read_index(root, "feed")
    record = {
        "id": pid,
        "title": title,
        "topic": topic,
        "body": body,
        "sources": sources or [],
        "why": why,
        "image_url": image_url or None,
        "file": filename,
        "created_at": stamp,
        "reactions": {},
    }
    items[pid] = record
    _write_index(root, "feed", items)
    return record


def list_feed(root: Path, limit: int = 50) -> list[dict[str, Any]]:
    items = sorted(
        _read_index(root, "feed").values(),
        key=lambda r: str(r.get("created_at", "")),
        reverse=True,
    )
    return [_feed_view(r) for r in items[: max(0, limit)]]


def get_feed_post(root: Path, post_id: str) -> Optional[dict[str, Any]]:
    record = _read_index(root, "feed").get(post_id)
    return _feed_view(record) if record is not None else None


def delete_feed_post(root: Path, post_id: str) -> bool:
    """Remove a post (index entry and its Markdown file); False when unknown."""
    items = _read_index(root, "feed")
    record = items.pop(post_id, None)
    if record is None:
        return False
    _write_index(root, "feed", items)
    _unlink_in(root / "feed", record.get("file"))
    return True


def _unlink_in(directory: Path, filename: Any) -> None:
    """Delete ``directory/filename`` when it is a plain file name inside *directory*."""
    if not isinstance(filename, str) or not filename or Path(filename).name != filename:
        return
    with contextlib.suppress(OSError):
        (directory / filename).unlink()


def react_feed(root: Path, post_id: str, reaction: str) -> Optional[dict[str, Any]]:
    """Toggle *reaction* (``love``/``discuss``) on a post; None when unknown."""
    if reaction not in REACTIONS:
        raise ValueError(f"unknown reaction: {reaction!r}")
    items = _read_index(root, "feed")
    record = items.get(post_id)
    if record is None:
        return None
    reactions = record.get("reactions")
    if not isinstance(reactions, dict):
        reactions = {}
    if reaction in reactions:
        del reactions[reaction]
    else:
        reactions[reaction] = utcnow_iso()
    record["reactions"] = reactions
    items[post_id] = record
    _write_index(root, "feed", items)
    return _feed_view(record)


# ---------------------------------------------------------------------------
# Ideas
# ---------------------------------------------------------------------------

# Icon keys the apps map to their own icons (design tokens), never raw glyphs.
IDEA_ICONS = (
    "workout", "shopping", "people", "city", "documents",
    "returns", "inbox", "money", "health", "travel",
)

# Default icon of an agent idea by its group label (lower-cased); "inbox" otherwise.
_GROUP_ICONS = {
    "productivity": "inbox",
    "health & fitness": "workout",
    "health": "health",
    "fitness": "workout",
    "shopping": "shopping",
    "money": "money",
    "finance": "money",
    "relationships": "people",
    "travel": "travel",
    "home & city": "city",
}

_DISMISSED_FILE = "dismissed.json"


def _seed(slug: str, group: str, icon: str, title: str, pitch: str, first_step: str) -> dict[str, Any]:
    return {
        "id": f"seed-{slug}",
        "title": title,
        "pitch": pitch,
        "group": group,
        "icon": icon,
        "first_step": first_step,
        "seeded": True,
        "file": None,
        "created_at": None,
        "feedback": [],
    }


# Starter catalog shipped with the plugin (static data, not files): always
# offered next to the agent's own ideas until the user dismisses one.
SEED_IDEAS: tuple[dict[str, Any], ...] = (
    _seed("inbox-triage", "Productivity", "inbox",
          "I'll sort your inbox every morning",
          "Each morning I go through new mail, flag what needs you today, draft "
          "replies for the quick ones and summarise the rest in one message.",
          "Tell me which mailbox to watch and what counts as urgent for you."),
    _seed("paperwork", "Productivity", "documents",
          "I'll keep track of your paperwork deadlines",
          "Renewals, tax forms, insurance and subscriptions: I keep a list of "
          "what is due when and remind you early enough to act calmly.",
          "List the documents or contracts you worry about forgetting."),
    _seed("workout-plan", "Health & Fitness", "workout",
          "I'll plan your workouts around your week",
          "I build a weekly training plan that fits your schedule and level, "
          "check in after each session and adjust the next ones.",
          "Tell me your goal, your level and the days you can train."),
    _seed("health-checkups", "Health & Fitness", "health",
          "I'll remind you of check-ups and refills",
          "Dentist, eye exam, vaccines, prescriptions: I track when each one is "
          "due and nudge you before it slips.",
          "Share your last check-up dates and any regular prescriptions."),
    _seed("price-watch", "Shopping", "shopping",
          "I'll watch prices on things you want to buy",
          "Give me the items you are eyeing; I check prices regularly and tell "
          "you when one drops or a better deal shows up.",
          "Name one item and the price you would happily pay."),
    _seed("returns", "Shopping", "returns",
          "I'll make sure you never miss a return window",
          "When you buy something you are unsure about, I note the return "
          "deadline and remind you a few days before it closes.",
          "Tell me about a recent purchase you might send back."),
    _seed("budget-check", "Money", "money",
          "I'll give you a weekly spending check-in",
          "Once a week I go over what you tell me you spent, compare it with "
          "your budget and point out anything worth adjusting.",
          "Tell me your monthly budget and the categories you care about."),
    _seed("subscriptions", "Money", "money",
          "I'll find subscriptions you no longer use",
          "We list your recurring payments together; I flag the ones you have "
          "not used lately and remind you before the next renewal.",
          "List the subscriptions you remember paying for."),
    _seed("birthdays", "Relationships", "people",
          "I'll remember birthdays and suggest gifts",
          "I keep the important dates of the people you care about and remind "
          "you a week ahead with a few gift or message ideas.",
          "Give me three people and their birthdays to start with."),
    _seed("keep-in-touch", "Relationships", "people",
          "I'll help you keep in touch with friends",
          "Tell me who you want to see more often; I nudge you when it has "
          "been a while and suggest an easy way to reach out.",
          "Name a few friends and how often you would like to catch up."),
    _seed("trip-planner", "Travel", "travel",
          "I'll plan your next trip with you",
          "From dates and budget to bookings and a day-by-day plan, I research "
          "options, keep track of what is booked and what is still open.",
          "Tell me where you would like to go and roughly when."),
    _seed("travel-checklist", "Travel", "documents",
          "I'll make sure you're ready before every trip",
          "Passport validity, check-in times, packing and local tips: I prepare "
          "a checklist for each trip and remind you of each step.",
          "Tell me about your next trip."),
    _seed("local-events", "Home & city", "city",
          "I'll find things to do in your city each week",
          "Every week I look for concerts, markets, exhibitions and events near "
          "you that match your interests, and share a short pick.",
          "Tell me your city and what you enjoy doing."),
    _seed("home-upkeep", "Home & city", "city",
          "I'll keep your home maintenance on schedule",
          "Boiler service, filters, plants, seasonal chores: I keep the list "
          "and remind you when each task comes due.",
          "List a few recurring chores you tend to forget."),
)

_SEEDS_BY_ID = {seed["id"]: seed for seed in SEED_IDEAS}


def _idea_view(record: dict[str, Any]) -> dict[str, Any]:
    """Agent ideas written before ``icon``/``seeded`` existed read with their defaults."""
    icon = record.get("icon")
    if icon not in IDEA_ICONS:
        icon = _GROUP_ICONS.get(str(record.get("group", "")).strip().lower(), "inbox")
    return {**record, "icon": icon, "seeded": False}


def _dismissed(root: Path) -> set[str]:
    data = _read_json(root / "ideas" / _DISMISSED_FILE, None)
    ids = data.get("ids") if isinstance(data, dict) else None
    return {str(i) for i in ids} if isinstance(ids, list) else set()


def propose_idea(
    root: Path,
    *,
    title: str,
    pitch: str,
    group: str,
    first_step: str = "",
    icon: str = "",
    idea_id: Optional[str] = None,
    created_at: Optional[str] = None,
) -> dict[str, Any]:
    if icon and icon not in IDEA_ICONS:
        raise ValueError(f"unknown idea icon: {icon!r}")
    ensure_defaults(root)
    iid = idea_id or new_id()
    stamp = created_at or utcnow_iso()
    filename = f"{iid}.md"
    resolved_icon = icon or _GROUP_ICONS.get(group.strip().lower(), "inbox")
    atomic_write_text(
        root / "ideas" / filename,
        _front_matter(
            {
                "id": iid,
                "title": title,
                "group": group,
                "icon": resolved_icon,
                "created_at": stamp,
                "first_step": first_step,
            },
            pitch,
        ),
    )
    items = _read_index(root, "ideas")
    record = {
        "id": iid,
        "title": title,
        "pitch": pitch,
        "group": group,
        "icon": resolved_icon,
        "first_step": first_step,
        "file": filename,
        "created_at": stamp,
        "feedback": [],
        "seeded": False,
    }
    items[iid] = record
    _write_index(root, "ideas", items)
    return record


def list_ideas(root: Path, limit: int = 200) -> list[dict[str, Any]]:
    """Agent ideas (newest first), then the starter catalog; dismissed ones hidden."""
    hidden = _dismissed(root)
    agent = sorted(
        (r for r in _read_index(root, "ideas").values() if r.get("id") not in hidden),
        key=lambda r: str(r.get("created_at", "")),
        reverse=True,
    )
    merged = [_idea_view(r) for r in agent]
    merged.extend(dict(seed) for seed in SEED_IDEAS if seed["id"] not in hidden)
    return merged[: max(0, limit)]


def get_idea(root: Path, idea_id: str) -> Optional[dict[str, Any]]:
    seed = _SEEDS_BY_ID.get(idea_id)
    if seed is not None:
        return dict(seed)
    record = _read_index(root, "ideas").get(idea_id)
    return _idea_view(record) if record is not None else None


def dismiss_idea(root: Path, idea_id: str) -> bool:
    """Hide an idea (seeded or agent) from :func:`list_ideas`; False when unknown."""
    if idea_id not in _SEEDS_BY_ID and idea_id not in _read_index(root, "ideas"):
        return False
    ids = _dismissed(root)
    if idea_id not in ids:
        ids.add(idea_id)
        atomic_write_text(
            root / "ideas" / _DISMISSED_FILE,
            json.dumps({"version": _INDEX_VERSION, "ids": sorted(ids)}, indent=2) + "\n",
        )
    return True


def feedback_idea(root: Path, idea_id: str, feedback: str) -> Optional[dict[str, Any]]:
    """Append user feedback to an agent idea; None when unknown."""
    items = _read_index(root, "ideas")
    record = items.get(idea_id)
    if record is None:
        return None
    entries = record.get("feedback")
    if not isinstance(entries, list):
        entries = []
    entries.append({"at": utcnow_iso(), "text": feedback})
    record["feedback"] = entries
    items[idea_id] = record
    _write_index(root, "ideas", items)
    return _idea_view(record)


# ---------------------------------------------------------------------------
# Goals
# ---------------------------------------------------------------------------

GOAL_SOURCES = ("user", "agent")


def _goal_path(root: Path, goal_id: str) -> Path:
    return root / "goals" / f"{goal_id}.md"


def _goal_view(record: dict[str, Any]) -> dict[str, Any]:
    """Goal with every contract field; records from before them read as user goals
    (``done`` from ``status``, ``status_line`` from the latest timeline progress)."""
    view = dict(record)
    if view.get("source") not in GOAL_SOURCES:
        view["source"] = "user"
    if not isinstance(view.get("done"), bool):
        view["done"] = view.get("status") == "done"
    if not isinstance(view.get("status_line"), str):
        timeline = view.get("timeline") if isinstance(view.get("timeline"), list) else []
        progress = [str(e.get("progress") or "") for e in timeline if isinstance(e, dict)]
        view["status_line"] = next((p for p in reversed(progress) if p.strip()), "")
    view["parent_id"] = view.get("parent_id") or None
    view["cron_job_id"] = view.get("cron_job_id") or None
    return view


def _set_front_matter(path: Path, updates: dict[str, str]) -> None:
    """Rewrite ``key: value`` lines of a Markdown file's front matter (added when missing)."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return
    lines = text.split("\n")
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        return
    end = lines.index("---", 1)
    pending = dict(updates)
    for i in range(1, end):
        key = lines[i].split(":", 1)[0]
        if key in pending:
            lines[i] = f"{key}: {json.dumps(pending.pop(key))}"
    lines[end:end] = [f"{key}: {json.dumps(value)}" for key, value in pending.items()]
    atomic_write_text(path, "\n".join(lines))


def track_goal(
    root: Path,
    *,
    title: str,
    category: str,
    why: str,
    target_date: str = "",
    source: str = "user",
    parent_id: Optional[str] = None,
    cron_job_id: Optional[str] = None,
    status_line: str = "",
    goal_id: Optional[str] = None,
    created_at: Optional[str] = None,
) -> dict[str, Any]:
    if category not in GOAL_CATEGORIES:
        raise ValueError(f"unknown goal category: {category!r}")
    if source not in GOAL_SOURCES:
        raise ValueError(f"unknown goal source: {source!r}")
    items = _read_index(root, "goals")
    if parent_id and parent_id not in items:
        raise ValueError(f"unknown parent goal: {parent_id!r}")
    ensure_defaults(root)
    gid = goal_id or new_id()
    stamp = created_at or utcnow_iso()
    meta: dict[str, Any] = {
        "id": gid,
        "title": title,
        "category": category,
        "why": why,
        "target_date": target_date,
        "created_at": stamp,
        "status": "tracking",
        "source": source,
    }
    if parent_id:
        meta["parent_id"] = parent_id
    if cron_job_id:
        meta["cron_job_id"] = cron_job_id
    atomic_write_text(
        _goal_path(root, gid),
        _front_matter(
            meta,
            f"# {title}\n\n{why.strip()}\n\n## Timeline\n\n- {stamp[:10]} — tracking started.\n",
        ),
    )
    record = {
        "id": gid,
        "title": title,
        "category": category,
        "why": why,
        "target_date": target_date,
        "status": "tracking",
        "done": False,
        "source": source,
        "status_line": status_line,
        "parent_id": parent_id or None,
        "cron_job_id": cron_job_id or None,
        "file": f"{gid}.md",
        "created_at": stamp,
        "timeline": [{"at": stamp, "note": "tracking started.", "progress": ""}],
    }
    items[gid] = record
    _write_index(root, "goals", items)
    return dict(record)


def list_goals(root: Path, limit: int = 200) -> list[dict[str, Any]]:
    items = sorted(
        _read_index(root, "goals").values(),
        key=lambda r: str(r.get("created_at", "")),
        reverse=True,
    )
    return [_goal_view(r) for r in items[: max(0, limit)]]


def get_goal(root: Path, goal_id: str) -> Optional[dict[str, Any]]:
    record = _read_index(root, "goals").get(goal_id)
    return _goal_view(record) if record is not None else None


def _append_goal_timeline(root: Path, goal_id: str, stamp: str, note: str, progress: str = "") -> None:
    """Keep the Markdown file in sync: append to its timeline section."""
    path = _goal_path(root, goal_id)
    try:
        existing = path.read_text(encoding="utf-8")
    except OSError:
        existing = ""
    suffix = f"- {stamp[:10]} — {note.strip()}"
    if progress.strip():
        suffix += f" (progress: {progress.strip()})"
    if "## Timeline" in existing:
        updated = existing.rstrip("\n") + f"\n{suffix}\n"
    else:
        updated = existing.rstrip("\n") + f"\n\n## Timeline\n\n{suffix}\n"
    atomic_write_text(path, updated)


def update_goal(
    root: Path,
    goal_id: str,
    note: str,
    progress: str = "",
    status: str = "",
    status_line: Optional[str] = None,
) -> Optional[dict[str, Any]]:
    """Append a timeline entry (when *note* is set) and/or replace the status line;
    None when unknown."""
    items = _read_index(root, "goals")
    record = items.get(goal_id)
    if record is None:
        return None
    record = _goal_view(record)
    stamp = utcnow_iso()
    if note.strip():
        timeline = record.get("timeline")
        if not isinstance(timeline, list):
            timeline = []
        timeline.append({"at": stamp, "note": note, "progress": progress})
        record["timeline"] = timeline
    if status in ("tracking", "done"):
        record["status"] = status
        record["done"] = status == "done"
    if status_line is not None:
        record["status_line"] = status_line
    elif progress.strip():
        record["status_line"] = progress.strip()
    items[goal_id] = record
    _write_index(root, "goals", items)
    if note.strip():
        _append_goal_timeline(root, goal_id, stamp, note, progress)
    if status in ("tracking", "done"):
        _set_front_matter(_goal_path(root, goal_id), {"status": status})
    return dict(record)


def patch_goal(
    root: Path,
    goal_id: str,
    *,
    title: Optional[str] = None,
    done: Optional[bool] = None,
) -> Optional[dict[str, Any]]:
    """Rename and/or complete (reopen) a goal; None when unknown."""
    items = _read_index(root, "goals")
    record = items.get(goal_id)
    if record is None:
        return None
    record = _goal_view(record)
    front: dict[str, str] = {}
    stamp = utcnow_iso()
    if title is not None and title != record.get("title"):
        record["title"] = title
        front["title"] = title
    note = ""
    if done is not None and done != record["done"]:
        record["done"] = done
        record["status"] = "done" if done else "tracking"
        front["status"] = record["status"]
        note = "marked done." if done else "reopened."
        timeline = record.get("timeline") if isinstance(record.get("timeline"), list) else []
        timeline.append({"at": stamp, "note": note, "progress": ""})
        record["timeline"] = timeline
    items[goal_id] = record
    _write_index(root, "goals", items)
    path = _goal_path(root, goal_id)
    if front:
        _set_front_matter(path, front)
    if "title" in front:
        with contextlib.suppress(OSError):
            text = path.read_text(encoding="utf-8")
            renamed = re.sub(r"(?m)^# .*$", lambda _m: f"# {title}", text, count=1)
            if renamed != text:
                atomic_write_text(path, renamed)
    if note:
        _append_goal_timeline(root, goal_id, stamp, note)
    return dict(record)


def delete_goal(root: Path, goal_id: str) -> list[str]:
    """Delete a goal and all its subgoals (any depth); returns the deleted ids
    (empty when unknown)."""
    items = _read_index(root, "goals")
    if goal_id not in items:
        return []
    doomed = [goal_id]
    frontier = [goal_id]
    while frontier:
        parent = frontier.pop()
        children = [gid for gid, r in items.items()
                    if r.get("parent_id") == parent and gid not in doomed]
        doomed.extend(children)
        frontier.extend(children)
    for gid in doomed:
        record = items.pop(gid)
        _unlink_in(root / "goals", record.get("file") or f"{gid}.md")
    _write_index(root, "goals", items)
    return doomed


# ---------------------------------------------------------------------------
# Artifacts (Library)
# ---------------------------------------------------------------------------

_EXTENSIONS = {
    "document": ".md",
    "web": ".html",
    "image": ".png",
    "video": ".mp4",
    "podcast": ".mp3",
    "other": ".bin",
}


def save_artifact(
    root: Path,
    *,
    title: str,
    kind: str,
    content: str = "",
    source_path: str = "",
    filename: str = "",
    tags: Optional[list[str]] = None,
    artifact_id: Optional[str] = None,
    created_at: Optional[str] = None,
) -> dict[str, Any]:
    """Save an artifact's bytes under ``artifacts/files/`` + index entry.

    Either *content* (text, written as-is) or *source_path* (an existing file on
    disk, copied in) must be given — never both.
    """
    if kind not in ARTIFACT_KINDS:
        raise ValueError(f"unknown artifact kind: {kind!r}")
    if bool(content) == bool(source_path):
        raise ValueError("give exactly one of content / source_path")
    ensure_defaults(root)
    aid = artifact_id or new_id()
    stamp = created_at or utcnow_iso()
    safe = Path(filename).name if filename else ""
    if safe in ("", ".", ".."):
        safe = f"{slugify(title)}-{aid}{_EXTENSIONS[kind]}"
    dest = root / "artifacts" / "files" / aid / safe
    dest.parent.mkdir(parents=True, exist_ok=True)
    if source_path:
        src = Path(source_path).expanduser()
        data = src.read_bytes()
        dest.write_bytes(data)
    else:
        dest.write_text(content, encoding="utf-8")
    try:
        size = dest.stat().st_size
    except OSError:
        size = 0
    items = _read_index(root, "artifacts")
    record = {
        "id": aid,
        "title": title,
        "kind": kind,
        "file": f"files/{aid}/{safe}",
        "size": size,
        "tags": tags or [],
        "created_at": stamp,
    }
    items[aid] = record
    _write_index(root, "artifacts", items)
    return record


def list_artifacts(root: Path, limit: int = 200) -> list[dict[str, Any]]:
    items = sorted(
        _read_index(root, "artifacts").values(),
        key=lambda r: str(r.get("created_at", "")),
        reverse=True,
    )
    return items[: max(0, limit)]


def get_artifact(root: Path, artifact_id: str) -> Optional[dict[str, Any]]:
    return _read_index(root, "artifacts").get(artifact_id)


def artifact_file(root: Path, artifact_id: str) -> Optional[Path]:
    """Resolve an artifact's stored file, contained under ``artifacts/files/``."""
    record = get_artifact(root, artifact_id)
    if record is None:
        return None
    rel = str(record.get("file") or "")
    base = (root / "artifacts" / "files").resolve()
    candidate = (root / "artifacts" / rel).resolve()
    try:
        candidate.relative_to(base)
    except ValueError:
        return None
    if not candidate.is_file():
        return None
    return candidate


# ---------------------------------------------------------------------------
# Reflections
# ---------------------------------------------------------------------------

_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def write_reflection(
    root: Path, day: str, body: str, created_at: Optional[str] = None
) -> dict[str, Any]:
    """Write (or replace) ``reflections/<YYYY-MM-DD>.md``; returns the record."""
    if not _DATE_RE.match(day):
        raise ValueError(f"date must be YYYY-MM-DD, got {day!r}")
    ensure_defaults(root)
    stamp = created_at or utcnow_iso()
    atomic_write_text(
        root / "reflections" / f"{day}.md",
        _front_matter({"date": day, "written_at": stamp}, body),
    )
    items = _read_index(root, "reflections")
    record = {"date": day, "file": f"{day}.md", "written_at": stamp, "body": body}
    items[day] = record
    _write_index(root, "reflections", items)
    return record


def list_reflections(root: Path, limit: int = 90) -> list[dict[str, Any]]:
    items = sorted(
        _read_index(root, "reflections").values(),
        key=lambda r: str(r.get("date", "")),
        reverse=True,
    )
    return items[: max(0, limit)]


def get_reflection(root: Path, day: str) -> Optional[dict[str, Any]]:
    return _read_index(root, "reflections").get(day)


# ---------------------------------------------------------------------------
# Tasks (Activity: one record per agent turn)
# ---------------------------------------------------------------------------

TASK_STATUSES = ("completed", "failed", "interrupted")
TASK_SOURCES = ("chat", "cron", "heartbeat", "other")
TASKS_CAP = 1000  # newest records kept in tasks/index.json

_TASKS_LOCK = threading.Lock()


def task_id(session_id: str, turn_id: str) -> str:
    """Stable id of one turn, so every hook of that turn upserts the same record."""
    return hashlib.sha256(f"{session_id}\x00{turn_id}".encode("utf-8")).hexdigest()[:12]


def parse_iso(text: str) -> datetime:
    """ISO-8601 timestamp (``Z`` accepted) as an aware datetime; naive reads as UTC.
    Raises ``ValueError`` for anything else."""
    value = datetime.fromisoformat(text.strip().replace("Z", "+00:00"))
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


@contextlib.contextmanager
def _tasks_lock(root: Path):
    """Serialise read-modify-write of the tasks index across threads and, where
    ``fcntl`` exists, across processes (agent workers and the dashboard)."""
    try:
        import fcntl
    except ImportError:  # Windows: thread lock only
        fcntl = None  # type: ignore[assignment]
    with _TASKS_LOCK:
        if fcntl is None:
            yield
            return
        lock_path = root / "tasks" / ".lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with open(lock_path, "a+", encoding="utf-8") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(fh, fcntl.LOCK_UN)


def _task_started(record: dict[str, Any]) -> str:
    return str(record.get("started_at") or record.get("finished_at") or "")


def save_task(root: Path, task: dict[str, Any]) -> dict[str, Any]:
    """Insert *task* or merge it into the record with the same ``id``; keeps the
    :data:`TASKS_CAP` newest records. Returns the stored record."""
    if task.get("status") not in TASK_STATUSES:
        raise ValueError(f"unknown task status: {task.get('status')!r}")
    if task.get("source") not in TASK_SOURCES:
        raise ValueError(f"unknown task source: {task.get('source')!r}")
    with _tasks_lock(root):
        items = _read_index(root, "tasks")
        record = {**items.get(task["id"], {}), **task}
        items[record["id"]] = record
        if len(items) > TASKS_CAP:
            newest = sorted(items.values(), key=_task_started, reverse=True)[:TASKS_CAP]
            items = {r["id"]: r for r in newest}
        _write_index(root, "tasks", items)
    return dict(record)


def update_task(root: Path, tid: str, **fields: Any) -> Optional[dict[str, Any]]:
    """Merge *fields* into an existing task; None when unknown."""
    if "status" in fields and fields["status"] not in TASK_STATUSES:
        raise ValueError(f"unknown task status: {fields['status']!r}")
    with _tasks_lock(root):
        items = _read_index(root, "tasks")
        record = items.get(tid)
        if record is None:
            return None
        record.update(fields)
        _write_index(root, "tasks", items)
    return dict(record)


def get_task(root: Path, tid: str) -> Optional[dict[str, Any]]:
    return _read_index(root, "tasks").get(tid)


def list_tasks(root: Path, limit: int = 100, before: Optional[datetime] = None) -> list[dict[str, Any]]:
    """Tasks newest first (by ``started_at``); with *before*, only those started earlier."""
    items = sorted(_read_index(root, "tasks").values(), key=_task_started, reverse=True)
    if before is not None:
        kept = []
        for record in items:
            try:
                started = parse_iso(_task_started(record))
            except ValueError:
                continue
            if started < before:
                kept.append(record)
        items = kept
    return items[: max(0, limit)]


# ---------------------------------------------------------------------------
# Hermes memory files (HERMES_HOME/memories/{MEMORY,USER}.md)
# ---------------------------------------------------------------------------

MEMORY_TARGETS = {"memory": "MEMORY.md", "user": "USER.md"}
# Same separator as Hermes' ``tools.memory_tool_store.ENTRY_DELIMITER``.
MEMORY_ENTRY_DELIMITER = "\n§\n"


def memory_path(home: os.PathLike[str] | str, target: str) -> Path:
    """``<home>/memories/MEMORY.md`` (``memory``) or ``USER.md`` (``user``)."""
    if target not in MEMORY_TARGETS:
        raise ValueError(f"unknown memory target: {target!r}")
    return Path(home) / "memories" / MEMORY_TARGETS[target]


def read_memory(home: os.PathLike[str] | str, target: str) -> dict[str, Any]:
    """``{"target", "entries", "updated_at"}``; a missing file has no entries and
    ``updated_at`` None."""
    path = memory_path(home, target)
    try:
        raw = path.read_text(encoding="utf-8-sig")
        updated_at: Optional[str] = datetime.fromtimestamp(
            path.stat().st_mtime, timezone.utc).isoformat()
    except FileNotFoundError:
        raw, updated_at = "", None
    entries = [e for e in (x.strip() for x in raw.split(MEMORY_ENTRY_DELIMITER)) if e]
    return {"target": target, "entries": entries, "updated_at": updated_at}


def write_memory(
    home: os.PathLike[str] | str,
    target: str,
    entries: list[str],
    lock: Optional[Any] = None,
) -> list[str]:
    """Replace every entry of *target*; blank entries are dropped. *lock* is a
    ``path -> context manager`` (Hermes' ``MemoryStore._file_lock``) held around
    the atomic write so a concurrent agent memory edit cannot interleave.
    Returns the stored entries."""
    path = memory_path(home, target)
    cleaned = [e.strip() for e in entries if e.strip()]
    for entry in cleaned:
        if MEMORY_ENTRY_DELIMITER.strip() in entry.split("\n"):
            raise ValueError("a memory entry cannot contain a line holding only '§'")
    with lock(path) if lock is not None else contextlib.nullcontext():
        atomic_write_text(path, MEMORY_ENTRY_DELIMITER.join(cleaned))
    return cleaned
