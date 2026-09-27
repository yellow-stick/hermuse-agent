"""Hermuse file store: human-readable Feed/Ideas/Goals/Library/Reflections data.

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
import json
import os
import re
import tempfile
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

def post_feed(
    root: Path,
    *,
    title: str,
    body: str,
    topic: str = "",
    sources: Optional[list[str]] = None,
    post_id: Optional[str] = None,
    created_at: Optional[str] = None,
) -> dict[str, Any]:
    """Append a feed post; returns the stored record (incl. reactions ``{}``)."""
    ensure_defaults(root)
    pid = post_id or new_id()
    stamp = created_at or utcnow_iso()
    day = stamp[:10] if len(stamp) >= 10 else date.today().isoformat()
    filename = f"{day}-{slugify(title)}-{pid}.md"
    atomic_write_text(
        root / "feed" / filename,
        _front_matter(
            {
                "id": pid,
                "title": title,
                "topic": topic,
                "created_at": stamp,
                "sources": sources or [],
            },
            body,
        ),
    )
    items = _read_index(root, "feed")
    record = {
        "id": pid,
        "title": title,
        "topic": topic,
        "body": body,
        "sources": sources or [],
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
    return items[: max(0, limit)]


def get_feed_post(root: Path, post_id: str) -> Optional[dict[str, Any]]:
    return _read_index(root, "feed").get(post_id)


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
    return record


# ---------------------------------------------------------------------------
# Ideas
# ---------------------------------------------------------------------------

def propose_idea(
    root: Path,
    *,
    title: str,
    pitch: str,
    group: str,
    first_step: str = "",
    idea_id: Optional[str] = None,
    created_at: Optional[str] = None,
) -> dict[str, Any]:
    ensure_defaults(root)
    iid = idea_id or new_id()
    stamp = created_at or utcnow_iso()
    filename = f"{iid}.md"
    atomic_write_text(
        root / "ideas" / filename,
        _front_matter(
            {
                "id": iid,
                "title": title,
                "group": group,
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
        "first_step": first_step,
        "file": filename,
        "created_at": stamp,
        "feedback": [],
    }
    items[iid] = record
    _write_index(root, "ideas", items)
    return record


def list_ideas(root: Path, limit: int = 200) -> list[dict[str, Any]]:
    items = sorted(
        _read_index(root, "ideas").values(),
        key=lambda r: str(r.get("created_at", "")),
        reverse=True,
    )
    return items[: max(0, limit)]


def get_idea(root: Path, idea_id: str) -> Optional[dict[str, Any]]:
    return _read_index(root, "ideas").get(idea_id)


def feedback_idea(root: Path, idea_id: str, feedback: str) -> Optional[dict[str, Any]]:
    """Append user feedback to an idea; None when unknown."""
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
    return record


# ---------------------------------------------------------------------------
# Goals
# ---------------------------------------------------------------------------

def _goal_path(root: Path, goal_id: str) -> Path:
    return root / "goals" / f"{goal_id}.md"


def track_goal(
    root: Path,
    *,
    title: str,
    category: str,
    why: str,
    target_date: str = "",
    goal_id: Optional[str] = None,
    created_at: Optional[str] = None,
) -> dict[str, Any]:
    if category not in GOAL_CATEGORIES:
        raise ValueError(f"unknown goal category: {category!r}")
    ensure_defaults(root)
    gid = goal_id or new_id()
    stamp = created_at or utcnow_iso()
    atomic_write_text(
        _goal_path(root, gid),
        _front_matter(
            {
                "id": gid,
                "title": title,
                "category": category,
                "why": why,
                "target_date": target_date,
                "created_at": stamp,
                "status": "tracking",
            },
            f"# {title}\n\n{why.strip()}\n\n## Timeline\n\n- {stamp[:10]} — tracking started.\n",
        ),
    )
    items = _read_index(root, "goals")
    record = {
        "id": gid,
        "title": title,
        "category": category,
        "why": why,
        "target_date": target_date,
        "status": "tracking",
        "file": f"{gid}.md",
        "created_at": stamp,
        "timeline": [{"at": stamp, "note": "tracking started.", "progress": ""}],
    }
    items[gid] = record
    _write_index(root, "goals", items)
    return record


def list_goals(root: Path, limit: int = 200) -> list[dict[str, Any]]:
    items = sorted(
        _read_index(root, "goals").values(),
        key=lambda r: str(r.get("created_at", "")),
        reverse=True,
    )
    return items[: max(0, limit)]


def get_goal(root: Path, goal_id: str) -> Optional[dict[str, Any]]:
    return _read_index(root, "goals").get(goal_id)


def update_goal(
    root: Path,
    goal_id: str,
    note: str,
    progress: str = "",
    status: str = "",
) -> Optional[dict[str, Any]]:
    """Append a timeline entry (and to the .md file); None when unknown."""
    items = _read_index(root, "goals")
    record = items.get(goal_id)
    if record is None:
        return None
    stamp = utcnow_iso()
    timeline = record.get("timeline")
    if not isinstance(timeline, list):
        timeline = []
    timeline.append({"at": stamp, "note": note, "progress": progress})
    record["timeline"] = timeline
    if status in ("tracking", "done"):
        record["status"] = status
    items[goal_id] = record
    _write_index(root, "goals", items)
    # Keep the Markdown file in sync: append to its timeline section.
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
    return record


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
