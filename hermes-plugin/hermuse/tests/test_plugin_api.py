"""REST backend: routes answer, allow-list rejects traversal, shapes hold."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

PLUGIN_ROOT = Path(__file__).resolve().parent.parent


def _load_plugin_api():
    # Load dashboard/plugin_api.py exactly like the dashboard host does: from
    # a file path via spec_from_file_location.
    module_name = "hermuse_dashboard_plugin_api_under_test"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(
        module_name, PLUGIN_ROOT / "dashboard" / "plugin_api.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture()
def client(hermes_home):
    plugin_api = _load_plugin_api()
    app = FastAPI()
    app.include_router(plugin_api.router, prefix="/api/plugins/hermuse")
    with TestClient(app) as test_client:
        yield test_client


def test_feed_round_trip_and_react(client):
    created = client.post(
        "/api/plugins/hermuse/feed",
        json={"title": "Hi", "body": "Hello.", "topic": "intro",
              "sources": ["https://example.com"]},
    )
    assert created.status_code == 201, created.text
    post_id = created.json()["id"]
    assert created.json()["reactions"] == {}

    listed = client.get("/api/plugins/hermuse/feed")
    assert [p["id"] for p in listed.json()["posts"]] == [post_id]

    reacted = client.post(
        f"/api/plugins/hermuse/feed/{post_id}/react", json={"reaction": "love"})
    assert reacted.status_code == 200
    assert "love" in reacted.json()["reactions"]

    bad_reaction = client.post(
        f"/api/plugins/hermuse/feed/{post_id}/react", json={"reaction": "hate"})
    assert bad_reaction.status_code == 422

    missing = client.post(
        "/api/plugins/hermuse/feed/nope/react", json={"reaction": "love"})
    assert missing.status_code == 404


def test_ideas_and_feedback(client):
    created = client.post(
        "/api/plugins/hermuse/ideas",
        json={"title": "Triage", "pitch": "Let me triage.", "group": "Productivity"},
    )
    assert created.status_code == 201, created.text
    idea_id = created.json()["id"]

    feedback = client.post(
        f"/api/plugins/hermuse/ideas/{idea_id}/feedback", json={"feedback": "do it"})
    assert feedback.status_code == 200
    assert feedback.json()["feedback"][-1]["text"] == "do it"

    assert client.get("/api/plugins/hermuse/ideas").json()["ideas"][0]["id"] == idea_id
    assert client.get("/api/plugins/hermuse/ideas/nope").status_code == 404


def test_goals_and_updates(client):
    created = client.post(
        "/api/plugins/hermuse/goals",
        json={"title": "Run", "category": "health", "why": "Stay fit."},
    )
    assert created.status_code == 201, created.text
    goal_id = created.json()["id"]

    updated = client.post(
        f"/api/plugins/hermuse/goals/{goal_id}/update",
        json={"note": "Ran 5k", "progress": "week 1"},
    )
    assert updated.status_code == 200
    assert len(updated.json()["timeline"]) == 2

    bad_category = client.post(
        "/api/plugins/hermuse/goals",
        json={"title": "x", "category": "nope", "why": "y"},
    )
    assert bad_category.status_code == 422
    assert client.get("/api/plugins/hermuse/goals/nope").status_code == 404


def test_preferences_round_trip(client):
    first = client.get("/api/plugins/hermuse/preferences")
    assert first.status_code == 200
    assert "Tell me about" in first.json()["content"]

    body = "# prefs\n\n## Tell me about\n\n- launches\n"
    updated = client.put("/api/plugins/hermuse/preferences", json={"content": body})
    assert updated.status_code == 200
    assert client.get("/api/plugins/hermuse/preferences").json()["content"] == body


def test_managed_files_allow_list(client):
    listed = client.get("/api/plugins/hermuse/files")
    assert set(listed.json()["files"]) == {
        "FEED_PROMPT.md", "PREFERENCES.md", "IDENTITY.md", "HEARTBEAT.md"}

    ok = client.get("/api/plugins/hermuse/files/IDENTITY.md")
    assert ok.status_code == 200
    assert "Name:" in ok.json()["content"]

    put = client.put(
        "/api/plugins/hermuse/files/HEARTBEAT.md", json={"content": "# hb\n"})
    assert put.status_code == 200
    assert client.get("/api/plugins/hermuse/files/HEARTBEAT.md").json()["content"] == "# hb\n"


@pytest.mark.parametrize("name", [
    "..",
    "../config.yaml",
    "..%2Fconfig.yaml",
    "%2e%2e%2fconfig.yaml",
    "/etc/passwd",
    "config.yaml",
    "feed/index.json",
    "FEED_PROMPT.md.bak",
    "feed_prompt.md",
])
def test_managed_files_reject_traversal_and_unknown(client, name):
    assert client.get(f"/api/plugins/hermuse/files/{name}").status_code == 404
    put = client.put(f"/api/plugins/hermuse/files/{name}", json={"content": "x"})
    assert put.status_code in (404, 405)


def test_managed_files_empty_name_hits_list_route(client):
    # "/files/" (empty name) routes to the list endpoint, never to a file read.
    response = client.get("/api/plugins/hermuse/files/")
    assert response.status_code == 200
    assert "files" in response.json()
def test_reflections_and_artifacts_lists(client):
    assert client.get("/api/plugins/hermuse/reflections").json() == {"reflections": []}
    assert client.get("/api/plugins/hermuse/artifacts").json() == {"artifacts": []}
    assert client.get("/api/plugins/hermuse/reflections/2026-01-01").status_code == 404
    assert client.get("/api/plugins/hermuse/artifacts/nope").status_code == 404
