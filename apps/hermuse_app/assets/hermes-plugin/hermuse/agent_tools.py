"""Hermuse agent tools: feed_post / idea_propose / goal_track / goal_update /
artifact_save / reflection_write.

Handlers are sync ``(args, **kwargs) -> str`` per the Hermes tool contract
(``tools/registry.py``): they return ``tool_result``/``tool_error`` JSON strings.
Imports of ``tools.registry`` and ``hermes_constants`` are lazy so the store
logic stays testable without Hermes on ``sys.path``.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable, Optional

from . import store

TOOLSET = "hermuse"


def _resolve_root() -> Path:
    from hermes_constants import get_hermes_home

    return store.hermuse_root(get_hermes_home())


def _ok(payload: dict[str, Any]) -> str:
    from tools.registry import tool_result

    return tool_result(payload)


def _fail(message: str) -> str:
    from tools.registry import tool_error

    return tool_error(message)


def _nonblank(args: dict, key: str, what: str, limit: int = 0) -> str:
    value = str(args.get(key) or "").strip()
    if not value:
        raise ValueError(f"{what} is required")
    if limit and len(value) > limit:
        raise ValueError(f"{what} exceeds {limit} characters")
    return value


def _optional(args: dict, key: str, limit: int = 0) -> str:
    value = str(args.get(key) or "").strip()
    if limit and len(value) > limit:
        raise ValueError(f"{key} exceeds {limit} characters")
    return value


def _string_list(args: dict, key: str, limit: int = 20) -> list[str]:
    raw = args.get(key)
    if raw is None:
        return []
    items = raw if isinstance(raw, list) else [raw]
    out = [str(v).strip() for v in items if str(v).strip()]
    if len(out) > limit:
        raise ValueError(f"{key} has more than {limit} entries")
    return out


def handle_feed_post(args: dict, **kwargs: Any) -> str:
    try:
        record = store.post_feed(
            _resolve_root(),
            title=_nonblank(args, "title", "title", 200),
            body=_nonblank(args, "body", "body", 20000),
            topic=_optional(args, "topic", 120),
            sources=_string_list(args, "sources"),
        )
    except ValueError as exc:
        return _fail(str(exc))
    return _ok({"ok": True, "id": record["id"], "file": record["file"]})


def handle_idea_propose(args: dict, **kwargs: Any) -> str:
    try:
        record = store.propose_idea(
            _resolve_root(),
            title=_nonblank(args, "title", "title", 200),
            pitch=_nonblank(args, "pitch", "pitch", 8000),
            group=_nonblank(args, "group", "group", 80),
            first_step=_optional(args, "first_step", 2000),
        )
    except ValueError as exc:
        return _fail(str(exc))
    return _ok({"ok": True, "id": record["id"]})


def handle_goal_track(args: dict, **kwargs: Any) -> str:
    try:
        record = store.track_goal(
            _resolve_root(),
            title=_nonblank(args, "title", "title", 200),
            category=_nonblank(args, "category", "category", 40).lower(),
            why=_nonblank(args, "why", "why", 8000),
            target_date=_optional(args, "target_date", 40),
        )
    except ValueError as exc:
        return _fail(str(exc))
    return _ok({"ok": True, "id": record["id"]})


def handle_goal_update(args: dict, **kwargs: Any) -> str:
    try:
        goal_id = _nonblank(args, "goal_id", "goal_id", 64)
        note = _nonblank(args, "note", "note", 8000)
        progress = _optional(args, "progress", 500)
    except ValueError as exc:
        return _fail(str(exc))
    record = store.update_goal(_resolve_root(), goal_id, note, progress)
    if record is None:
        return _fail(f"unknown goal: {goal_id}")
    return _ok({"ok": True, "id": goal_id})


def handle_artifact_save(args: dict, **kwargs: Any) -> str:
    try:
        title = _nonblank(args, "title", "title", 200)
        kind = _nonblank(args, "kind", "kind", 20).lower()
        content = str(args.get("content") or "")
        source_path = str(args.get("path") or args.get("source_path") or "").strip()
        record = store.save_artifact(
            _resolve_root(),
            title=title,
            kind=kind,
            content=content,
            source_path=source_path,
            filename=_optional(args, "filename", 120),
            tags=_string_list(args, "tags"),
        )
    except (ValueError, OSError) as exc:
        return _fail(str(exc))
    return _ok({"ok": True, "id": record["id"], "file": record["file"]})


def handle_reflection_write(args: dict, **kwargs: Any) -> str:
    try:
        record = store.write_reflection(
            _resolve_root(),
            _nonblank(args, "date", "date", 10),
            _nonblank(args, "body", "body", 30000),
        )
    except ValueError as exc:
        return _fail(str(exc))
    return _ok({"ok": True, "date": record["date"]})


def _schema(name: str, description: str, properties: dict, required: tuple) -> dict:
    return {
        "name": name,
        "description": description,
        "parameters": {
            "type": "object",
            "properties": properties,
            "required": list(required),
        },
    }


_STR = {"type": "string"}
_STR_ARRAY = {"type": "array", "items": _STR}

FEED_POST_SCHEMA = _schema(
    "feed_post",
    "Publish a post to the Hermuse feed (stored under HERMES_HOME/hermuse/feed/).",
    {
        "title": {**_STR, "description": "Post title (shown on the card)."},
        "body": {**_STR, "description": "Post body in Markdown."},
        "topic": {**_STR, "description": "Short topic label (optional)."},
        "sources": {**_STR_ARRAY, "description": "Source URLs, if any."},
    },
    ("title", "body"),
)

IDEA_PROPOSE_SCHEMA = _schema(
    "idea_propose",
    "Propose an idea for the Hermuse Ideas surface (stored under HERMES_HOME/hermuse/ideas/).",
    {
        "title": {**_STR, "description": "Idea title, first person when it reads well."},
        "pitch": {**_STR, "description": "What the agent would do, in Markdown."},
        "group": {**_STR, "description": "Group label (e.g. Productivity, Health & Fitness)."},
        "first_step": {**_STR, "description": "Concrete first step (optional)."},
    },
    ("title", "pitch", "group"),
)

GOAL_TRACK_SCHEMA = _schema(
    "goal_track",
    "Start tracking a goal on the Hermuse Goals surface (stored under HERMES_HOME/hermuse/goals/).",
    {
        "title": {**_STR, "description": "Goal title."},
        "category": {
            "type": "string",
            "enum": list(store.GOAL_CATEGORIES),
            "description": "One of: health, relationships, finance, career, interests, productivity, something_else.",
        },
        "why": {**_STR, "description": "Why this goal matters / what done looks like."},
        "target_date": {**_STR, "description": "Target date, free text (optional)."},
    },
    ("title", "category", "why"),
)

GOAL_UPDATE_SCHEMA = _schema(
    "goal_update",
    "Append a timeline entry to a tracked Hermuse goal.",
    {
        "goal_id": {**_STR, "description": "Goal id from goal_track."},
        "note": {**_STR, "description": "What happened / check-in note."},
        "progress": {**_STR, "description": "Short progress summary (optional)."},
    },
    ("goal_id", "note"),
)

ARTIFACT_SAVE_SCHEMA = _schema(
    "artifact_save",
    "Save a Library artifact under HERMES_HOME/hermuse/artifacts/. Give exactly one of content / path.",
    {
        "title": {**_STR, "description": "Artifact title."},
        "kind": {
            "type": "string",
            "enum": list(store.ARTIFACT_KINDS),
            "description": "One of: document, web, image, video, podcast, other.",
        },
        "content": {**_STR, "description": "Text content to store (for document/web)."},
        "path": {**_STR, "description": "Existing file to copy in (for media)."},
        "filename": {**_STR, "description": "Stored file name (optional)."},
        "tags": {**_STR_ARRAY, "description": "Tags (optional)."},
    },
    ("title", "kind"),
)

REFLECTION_WRITE_SCHEMA = _schema(
    "reflection_write",
    "Write the nightly reflection journal entry (reflections/<YYYY-MM-DD>.md) in the agent's own voice.",
    {
        "date": {**_STR, "description": "Effective date YYYY-MM-DD."},
        "body": {**_STR, "description": "Journal entry in Markdown."},
    },
    ("date", "body"),
)

TOOLS: tuple[tuple[str, dict, Callable, str], ...] = (
    ("feed_post", FEED_POST_SCHEMA, handle_feed_post, "📰"),
    ("idea_propose", IDEA_PROPOSE_SCHEMA, handle_idea_propose, "💡"),
    ("goal_track", GOAL_TRACK_SCHEMA, handle_goal_track, "🎯"),
    ("goal_update", GOAL_UPDATE_SCHEMA, handle_goal_update, "📈"),
    ("artifact_save", ARTIFACT_SAVE_SCHEMA, handle_artifact_save, "📚"),
    ("reflection_write", REFLECTION_WRITE_SCHEMA, handle_reflection_write, "💭"),
)


def register_tools(ctx: Any) -> None:
    """Register all Hermuse tools on a PluginContext (or the NoopPluginContext)."""
    for name, schema, handler, emoji in TOOLS:
        ctx.register_tool(name=name, toolset=TOOLSET, schema=schema, handler=handler, emoji=emoji)


def check_hermuse_available() -> bool:
    """Availability gate: the store only needs a writable HERMES_HOME/hermuse/."""
    try:
        root = _resolve_root()
        root.mkdir(parents=True, exist_ok=True)
        return True
    except OSError:
        return False
