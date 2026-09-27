"""Hermuse dashboard backend, mounted at /api/plugins/hermuse/.

Loaded by the dashboard plugin system (``hermes_cli/web_server_dashboard.py``)
from this file path via ``importlib`` — NOT as part of the plugin package — so
it adds its parent dir to ``sys.path`` to import the sibling ``store`` module
(stdlib-only, shared with the agent tools). Auth is enforced by Hermes'
existing ``/api/`` gate; this router adds no auth of its own.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path
from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import store  # noqa: E402
from hermes_constants import get_hermes_home  # noqa: E402

log = logging.getLogger(__name__)
router = APIRouter()


def _root() -> Path:
    return store.hermuse_root(get_hermes_home())


def _not_found(what: str) -> HTTPException:
    return HTTPException(status_code=404, detail=f"{what} not found")


# --- Feed ------------------------------------------------------------------


class FeedPostBody(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1, max_length=20000)
    topic: str = Field(default="", max_length=120)
    sources: list[str] = Field(default_factory=list, max_length=20)


class ReactBody(BaseModel):
    reaction: str = Field(pattern="^(love|discuss)$")


@router.get("/feed")
def list_feed(limit: int = Query(default=50, ge=1, le=200)):
    return {"posts": store.list_feed(_root(), limit)}


@router.get("/feed/{post_id}")
def get_feed_post(post_id: str):
    record = store.get_feed_post(_root(), post_id)
    if record is None:
        raise _not_found("feed post")
    return record


@router.post("/feed", status_code=201)
def create_feed_post(payload: FeedPostBody):
    return store.post_feed(
        _root(),
        title=payload.title.strip(),
        body=payload.body,
        topic=payload.topic.strip(),
        sources=[s for s in (s.strip() for s in payload.sources) if s],
    )


@router.post("/feed/{post_id}/react")
def react_feed_post(post_id: str, payload: ReactBody):
    record = store.react_feed(_root(), post_id, payload.reaction)
    if record is None:
        raise _not_found("feed post")
    return record


# --- Ideas -----------------------------------------------------------------


class IdeaBody(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    pitch: str = Field(min_length=1, max_length=8000)
    group: str = Field(min_length=1, max_length=80)
    first_step: str = Field(default="", max_length=2000)


class IdeaFeedbackBody(BaseModel):
    feedback: str = Field(min_length=1, max_length=4000)


@router.get("/ideas")
def list_ideas(limit: int = Query(default=200, ge=1, le=500)):
    return {"ideas": store.list_ideas(_root(), limit)}


@router.get("/ideas/{idea_id}")
def get_idea(idea_id: str):
    record = store.get_idea(_root(), idea_id)
    if record is None:
        raise _not_found("idea")
    return record


@router.post("/ideas", status_code=201)
def create_idea(payload: IdeaBody):
    return store.propose_idea(
        _root(),
        title=payload.title.strip(),
        pitch=payload.pitch,
        group=payload.group.strip(),
        first_step=payload.first_step,
    )


@router.post("/ideas/{idea_id}/feedback")
def add_idea_feedback(idea_id: str, payload: IdeaFeedbackBody):
    record = store.feedback_idea(_root(), idea_id, payload.feedback)
    if record is None:
        raise _not_found("idea")
    return record


# --- Goals -----------------------------------------------------------------


class GoalBody(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    category: str = Field(pattern="^(health|relationships|finance|career|interests|productivity|something_else)$")
    why: str = Field(min_length=1, max_length=8000)
    target_date: str = Field(default="", max_length=40)


class GoalUpdateBody(BaseModel):
    note: str = Field(min_length=1, max_length=8000)
    progress: str = Field(default="", max_length=500)
    status: str = Field(default="", pattern="^(|tracking|done)$")


@router.get("/goals")
def list_goals(limit: int = Query(default=200, ge=1, le=500)):
    return {"goals": store.list_goals(_root(), limit)}


@router.get("/goals/{goal_id}")
def get_goal(goal_id: str):
    record = store.get_goal(_root(), goal_id)
    if record is None:
        raise _not_found("goal")
    return record


@router.post("/goals", status_code=201)
def create_goal(payload: GoalBody):
    try:
        return store.track_goal(
            _root(),
            title=payload.title.strip(),
            category=payload.category,
            why=payload.why,
            target_date=payload.target_date.strip(),
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post("/goals/{goal_id}/update")
def update_goal_route(goal_id: str, payload: GoalUpdateBody):
    record = store.update_goal(
        _root(), goal_id, payload.note, payload.progress, payload.status
    )
    if record is None:
        raise _not_found("goal")
    return record


# --- Artifacts -------------------------------------------------------------


@router.get("/artifacts")
def list_artifacts(limit: int = Query(default=200, ge=1, le=500)):
    return {"artifacts": store.list_artifacts(_root(), limit)}


@router.get("/artifacts/{artifact_id}")
def get_artifact(artifact_id: str):
    record = store.get_artifact(_root(), artifact_id)
    if record is None:
        raise _not_found("artifact")
    return record


@router.get("/artifacts/{artifact_id}/download")
def download_artifact(artifact_id: str):
    path = store.artifact_file(_root(), artifact_id)
    if path is None:
        raise _not_found("artifact file")
    record = store.get_artifact(_root(), artifact_id) or {}
    return FileResponse(path=str(path), filename=Path(path).name, media_type="application/octet-stream")


# --- Reflections -----------------------------------------------------------


@router.get("/reflections")
def list_reflections(limit: int = Query(default=90, ge=1, le=365)):
    return {"reflections": store.list_reflections(_root(), limit)}


@router.get("/reflections/{day}")
def get_reflection(day: str):
    record = store.get_reflection(_root(), day)
    if record is None:
        raise _not_found("reflection")
    return record


# --- Preferences -----------------------------------------------------------


class MarkdownBody(BaseModel):
    content: str = Field(max_length=100000)


@router.get("/preferences")
def get_preferences():
    return {"name": store.PREFERENCES_FILE, "content": store.read_managed(_root(), store.PREFERENCES_FILE)}


@router.put("/preferences")
def put_preferences(payload: MarkdownBody):
    store.write_managed(_root(), store.PREFERENCES_FILE, payload.content)
    return {"ok": True, "name": store.PREFERENCES_FILE}


# --- Managed files (allow-listed) ------------------------------------------


@router.get("/files")
def list_managed_files():
    return {"files": list(store.MANAGED_FILES)}


@router.get("/files/{name}")
def get_managed_file(name: str):
    # Exact allow-list match — no path joining of user input, so traversal
    # ("../", absolute paths, unknown names) can never resolve to a file.
    if name not in store.MANAGED_FILES:
        raise _not_found("file")
    return {"name": name, "content": store.read_managed(_root(), name)}


@router.put("/files/{name}")
def put_managed_file(name: str, payload: MarkdownBody):
    if name not in store.MANAGED_FILES:
        raise _not_found("file")
    store.write_managed(_root(), name, payload.content)
    return {"ok": True, "name": name}


# --- Cron ------------------------------------------------------------------


@router.get("/cron")
def cron_status():
    try:
        from cron import jobs as cron_jobs
        from cron_specs import SPECS, find_job  # noqa: E402 — plugin-root import, see sys.path above
    except ImportError as exc:
        raise HTTPException(status_code=500, detail=f"cron backend unavailable: {exc}") from exc
    out: list[dict[str, Any]] = []
    for spec in SPECS:
        job = find_job(cron_jobs, spec.key)
        out.append({
            "key": spec.key,
            "name": spec.name,
            "schedule": spec.schedule,
            "registered": job is not None,
            "job_id": job.get("id") if job else None,
            "enabled": bool(job.get("enabled", True)) if job else False,
            "next_run_at": job.get("next_run_at") if job else None,
        })
    return {"jobs": out}


@router.post("/cron/enable")
def cron_enable():
    try:
        from cron import jobs as cron_jobs
        from cron_specs import register_all  # noqa: E402
    except ImportError as exc:
        raise HTTPException(status_code=500, detail=f"cron backend unavailable: {exc}") from exc
    results = register_all(cron_jobs)
    return {
        "jobs": [
            {"key": key, "job_id": record.get("id"), "created": created,
             "next_run_at": record.get("next_run_at")}
            for key, (record, created) in results.items()
        ]
    }


@router.post("/cron/disable")
def cron_disable():
    try:
        from cron import jobs as cron_jobs
        from cron_specs import remove_all  # noqa: E402
    except ImportError as exc:
        raise HTTPException(status_code=500, detail=f"cron backend unavailable: {exc}") from exc
    return {"removed": remove_all(cron_jobs)}
