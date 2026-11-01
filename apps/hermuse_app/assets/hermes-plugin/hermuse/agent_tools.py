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

from . import feed_images, media, store

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


def _image_url(args: dict) -> Optional[str]:
    value = _optional(args, "image_url", 2000)
    if value and not value.lower().startswith(("https://", "http://")):
        raise ValueError("image_url must be an http(s) URL")
    return value or None


def handle_feed_post(args: dict, **kwargs: Any) -> str:
    try:
        title = _nonblank(args, "title", "title", 200)
        body = _nonblank(args, "body", "body", 20000)
        topic = _optional(args, "topic", 120)
        sources = _string_list(args, "sources")
        why = _nonblank(args, "why", "why", 1000)
        image_url = _image_url(args)
        # The image is copied now (the agent's named image, else the first
        # sources' share image); none found leaves the post without one,
        # unless the media provider illustrates it in the background.
        root = _resolve_root()
        record = store.post_feed(
            root,
            title=title,
            body=body,
            topic=topic,
            sources=sources,
            why=why,
            image=feed_images.find_post_image(image_url, sources or []),
        )
    except ValueError as exc:
        return _fail(str(exc))
    illustrating = media.illustrate_feed_post(root, record) is not None
    return _ok({"ok": True, "id": record["id"], "file": record["file"],
                "image": record["image_url"] is not None, "illustrating": illustrating})


def handle_idea_propose(args: dict, **kwargs: Any) -> str:
    try:
        title = _nonblank(args, "title", "title", 200)
        pitch = _nonblank(args, "pitch", "pitch", 8000)
        group = _nonblank(args, "group", "group", 80)
        first_step = _optional(args, "first_step", 2000)
        icon = _optional(args, "icon", 40).lower()
        root = _resolve_root()
        # Re-proposing a live idea returns it instead of listing it twice.
        existing = store.find_similar_idea(root, title=title, pitch=pitch)
        if existing is not None:
            return _ok({"ok": True, "id": existing["id"], "duplicate": True,
                        "existing_title": existing["title"]})
        record = store.propose_idea(
            root, title=title, pitch=pitch, group=group, first_step=first_step, icon=icon)
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
            source=(_optional(args, "source", 10) or "agent").lower(),
            parent_id=_optional(args, "parent_id", 64) or None,
            cron_job_id=_optional(args, "cron_job_id", 64) or None,
            status_line=_optional(args, "status_line", 300),
        )
    except ValueError as exc:
        return _fail(str(exc))
    return _ok({"ok": True, "id": record["id"]})


def handle_goal_update(args: dict, **kwargs: Any) -> str:
    try:
        goal_id = _nonblank(args, "goal_id", "goal_id", 64)
        note = _optional(args, "note", 8000)
        progress = _optional(args, "progress", 500)
        status_line = _optional(args, "status_line", 300) if "status_line" in args else None
        if not note and not status_line:
            raise ValueError("note or status_line is required")
    except ValueError as exc:
        return _fail(str(exc))
    record = store.update_goal(_resolve_root(), goal_id, note, progress, status_line=status_line)
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
    "Publish a real card to the current profile's Hermuse feed. Use for useful "
    "grounded discoveries, research results or completed-work summaries during "
    "chat, or when the user asks to post. Read PREFERENCES.md and FEED_PROMPT.md "
    "first; avoid duplicates and do not post routine replies or invented activity.",
    {
        "title": {**_STR, "description": "Post title (shown on the card)."},
        "body": {**_STR, "description": "Post body in Markdown."},
        "why": {**_STR, "description": "Why I created this: one sentence on why it matters to the user."},
        "topic": {**_STR, "description": "Short topic label (optional)."},
        "sources": {**_STR_ARRAY, "description": (
            "Source URLs, main page first: the card shows that page's share image.")},
        "image_url": {**_STR, "description": (
            "Direct http(s) URL of a better image for the card (optional; overrides the source's image).")},
    },
    ("title", "body", "why"),
)

IDEA_PROPOSE_SCHEMA = _schema(
    "idea_propose",
    "Propose an idea for the Hermuse Ideas surface (stored under HERMES_HOME/hermuse/ideas/). "
    "An idea matching a live one (similar title or pitch) is not added again: the result "
    "returns the existing id with duplicate=true.",
    {
        "title": {**_STR, "description": "Idea title, first person when it reads well."},
        "pitch": {**_STR, "description": "What the agent would do, in Markdown."},
        "group": {**_STR, "description": "Group label (e.g. Productivity, Health & Fitness)."},
        "first_step": {**_STR, "description": "Concrete first step (optional)."},
        "icon": {
            "type": "string",
            "enum": list(store.IDEA_ICONS),
            "description": "Icon key (optional; derived from the group when omitted).",
        },
    },
    ("title", "pitch", "group"),
)

GOAL_TRACK_SCHEMA = _schema(
    "goal_track",
    "Track a trip, deadline or commitment the user wants kept in mind, or a goal. "
    "Shown on the Hermuse Goals surface (stored under HERMES_HOME/hermuse/goals/). "
    "Use source=\"agent\" for commitments you track on your own initiative (a trip, a deadline, "
    "a scheduled briefing) and source=\"user\" when the user asked you to track the goal. "
    "Give its status_line from the start; keep it current with goal_update.",
    {
        "title": {**_STR, "description": "Goal title."},
        "category": {
            "type": "string",
            "enum": list(store.GOAL_CATEGORIES),
            "description": "One of: health, relationships, finance, career, interests, productivity, something_else.",
        },
        "why": {**_STR, "description": "Why this goal matters / what done looks like."},
        "target_date": {**_STR, "description": "Target date, free text (optional)."},
        "source": {
            "type": "string",
            "enum": list(store.GOAL_SOURCES),
            "description": "agent (default): you track it on your own; user: the user asked for it.",
        },
        "parent_id": {**_STR, "description": "Id of the goal this one is a step of (optional)."},
        "cron_job_id": {**_STR, "description": "Id of the cron job scheduled for this goal (optional)."},
        "status_line": {**_STR, "description": (
            "Current state in one short line, shown under the title "
            "(e.g. 'Vol non réservé ; départ mercredi 7 octobre').")},
    },
    ("title", "category", "why"),
)

GOAL_UPDATE_SCHEMA = _schema(
    "goal_update",
    "Update a tracked Hermuse goal: append a timeline entry (note) and/or replace its "
    "status line (the latest state shown under its title). Give at least one of note / status_line.",
    {
        "goal_id": {**_STR, "description": "Goal id from goal_track."},
        "note": {**_STR, "description": "What happened / check-in note."},
        "progress": {**_STR, "description": "Short progress summary (optional)."},
        "status_line": {**_STR, "description": "Current state in one short line, e.g. 'Flight booked, hotel open'."},
    },
    ("goal_id",),
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
