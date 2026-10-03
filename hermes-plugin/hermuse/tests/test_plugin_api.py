"""REST backend: routes answer, allow-list rejects traversal, shapes hold."""

from __future__ import annotations

import importlib.util
import os
import sys
import threading
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import dashboard_restart

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


# How the dashboard runs: the `hermes` launcher of the installer (it `exec`s
# the venv Python on the checkout's `hermes` script), `python -m`, `serve`.
LAUNCHER = [sys.executable, "/home/hermes/.hermes/hermes-agent/hermes",
            "dashboard", "--port", "9119", "--host", "127.0.0.1", "--no-open"]


@pytest.fixture()
def restart(monkeypatch):
    """Restarts recorded instead of run: what happened, in order, once ``exec`` came."""
    events: list[object] = []
    replaced = threading.Event()

    def execv(path, argv):
        events.append(("exec", path, list(argv)))
        replaced.set()

    monkeypatch.setattr(dashboard_restart, "_scheduled", False)
    monkeypatch.setattr(dashboard_restart, "DELAY_S", 0)
    monkeypatch.setattr(dashboard_restart, "_finish_sessions", lambda: events.append("sessions"))
    monkeypatch.setattr(os, "execv", execv)
    monkeypatch.setattr(sys, "orig_argv", LAUNCHER)
    monkeypatch.delenv("HERMES_DASHBOARD_SESSION_TOKEN", raising=False)
    return events, replaced


def test_dashboard_restart_reexecutes_its_launch_command_after_the_sessions(client, restart):
    events, replaced = restart
    boot = client.get("/api/plugins/hermuse/dashboard").json()["boot"]

    answer = client.post("/api/plugins/hermuse/dashboard/restart")

    assert answer.status_code == 202, answer.text
    assert answer.json() == {"boot": boot}
    assert replaced.wait(5)
    # Same interpreter and command line (flags, launcher, options) in place:
    # open chats were persisted first.
    assert events == ["sessions", ("exec", sys.executable, LAUNCHER)]


def test_dashboard_restart_runs_once(client, restart):
    _, replaced = restart
    assert client.post("/api/plugins/hermuse/dashboard/restart").status_code == 202
    assert replaced.wait(5)

    again = client.post("/api/plugins/hermuse/dashboard/restart")

    assert again.status_code == 409


@pytest.mark.parametrize("argv, env", [
    (["python", "-m", "pytest", "tests/"], {}),
    (["python", "/opt/hermes/hermes", "chat"], {}),
    ([*LAUNCHER, "--ssh-session-token-file", "/tmp/token"], {}),
    (LAUNCHER, {"HERMES_DESKTOP": "1", "HERMES_DASHBOARD_SESSION_TOKEN": "t"}),
])
def test_dashboard_restart_refused_where_it_cannot_restart_in_place(
        client, restart, monkeypatch, argv, env):
    events, _ = restart
    monkeypatch.setattr(sys, "orig_argv", argv)
    for name, value in env.items():
        monkeypatch.setenv(name, value)

    answer = client.post("/api/plugins/hermuse/dashboard/restart")

    assert answer.status_code == 501
    assert events == []


@pytest.mark.parametrize("argv", [
    LAUNCHER,
    ["/srv/venv/bin/python", "/srv/venv/bin/hermes", "dashboard"],
    ["/srv/venv/bin/python", "-I", "-m", "hermes_cli.main", "-p", "default", "dashboard"],
    ["/srv/venv/bin/python", "/srv/venv/bin/hermes", "serve", "--port", "9120"],
])
def test_dashboard_launches_that_restart_in_place(argv):
    assert dashboard_restart.command_line(argv, environ={}) == argv


def test_profile_feeds_are_isolated_under_concurrent_requests(client, hermes_home):
    from concurrent.futures import ThreadPoolExecutor

    for name in ("noah", "aya"):
        home = hermes_home / "profiles" / name
        home.mkdir(parents=True)
        (home / "SOUL.md").write_text(f"You are {name}.")

    def create(name):
        response = client.post(
            f"/api/plugins/hermuse/feed?profile={name}",
            json={"title": name, "body": f"Only for {name}."},
        )
        assert response.status_code == 201, response.text
        return name, response.json()["id"]

    with ThreadPoolExecutor(max_workers=2) as pool:
        created = list(pool.map(create, ["noah", "aya"]))
    for name in ("noah", "aya"):
        posts = client.get(f"/api/plugins/hermuse/feed?profile={name}").json()["posts"]
        assert {post["id"] for post in posts} == {
            post_id for owner, post_id in created if owner == name
        }
        assert all(post["title"] == name for post in posts)
    other_id = next(post_id for name, post_id in created if name == "aya")
    assert client.get(
        f"/api/plugins/hermuse/feed/{other_id}?profile=noah"
    ).status_code == 404
    assert client.get("/api/plugins/hermuse/feed").json()["posts"] == []


def test_profile_routes_reject_unknown_and_traversal(client, hermes_home):
    for name in ("../outside", "/tmp/outside", "a/b", ""):
        response = client.get("/api/plugins/hermuse/feed", params={"profile": name})
        assert response.status_code == 400
    response = client.get("/api/plugins/hermuse/feed?profile=missing")
    assert response.status_code == 404
    assert not (hermes_home / "profiles" / "missing").exists()
