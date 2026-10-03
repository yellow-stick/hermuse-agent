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


API = "/api/plugins/hermuse"


def test_feed_why_image_and_delete(client):
    created = client.post(f"{API}/feed", json={
        "title": "Rain", "body": "**Bring** a coat.", "why": "You bike to work.",
        "image_url": "https://example.com/rain.png"})
    assert created.status_code == 201, created.text
    post = created.json()
    assert post["why"] == "You bike to work." and post["image_url"] == "https://example.com/rain.png"
    assert client.get(f"{API}/feed").json()["posts"][0]["why"] == "You bike to work."
    bad_image = client.post(f"{API}/feed", json={"title": "x", "body": "y", "image_url": "file:///x"})
    assert bad_image.status_code == 422

    assert client.delete(f"{API}/feed/{post['id']}").json() == {"ok": True}
    assert client.get(f"{API}/feed").json()["posts"] == []
    assert client.delete(f"{API}/feed/{post['id']}").status_code == 404


def test_feed_generate_triggers_the_registered_feed_job(client, hermes_home):
    from cron import jobs as cron_jobs

    assert client.post(f"{API}/feed/generate").status_code == 409
    assert client.post(f"{API}/cron/enable").status_code == 200
    with cron_jobs.use_cron_store(hermes_home):
        cron_jobs.pause_job(
            next(j["id"] for j in cron_jobs.load_jobs() if j["origin"]["key"] == "feed"), "test")
    response = client.post(f"{API}/feed/generate")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["started"] is True
    with cron_jobs.use_cron_store(hermes_home):
        job = cron_jobs.get_job(body["job_id"])
    assert job["origin"] == {"source": "hermuse", "key": "feed"}
    assert job["enabled"] is True and job["manual_run_at"]
    assert job["next_run_at"] == job["manual_run_at"]


def test_ideas_merge_seeds_and_dismiss(client):
    import store

    created = client.post(f"{API}/ideas", json={
        "title": "Triage", "pitch": "Let me triage.", "group": "Productivity", "icon": "inbox"})
    assert created.status_code == 201, created.text
    agent_id = created.json()["id"]
    ideas = client.get(f"{API}/ideas").json()["ideas"]
    assert ideas[0]["id"] == agent_id and ideas[0]["seeded"] is False and ideas[0]["icon"] == "inbox"
    seeds = [i for i in ideas if i["seeded"]]
    assert [i["id"] for i in seeds] == [s["id"] for s in store.SEED_IDEAS]
    assert all(i["id"].startswith("seed-") and i["icon"] for i in seeds)
    assert client.get(f"{API}/ideas/{seeds[0]['id']}").json()["title"] == seeds[0]["title"]

    assert client.post(f"{API}/ideas/{seeds[0]['id']}/dismiss").json() == {"ok": True}
    assert client.post(f"{API}/ideas/{agent_id}/dismiss").json() == {"ok": True}
    assert client.post(f"{API}/ideas/nope/dismiss").status_code == 404
    remaining = [i["id"] for i in client.get(f"{API}/ideas").json()["ideas"]]
    assert seeds[0]["id"] not in remaining and agent_id not in remaining
    assert len(remaining) == len(store.SEED_IDEAS) - 1
    bad_icon = client.post(f"{API}/ideas", json={"title": "t", "pitch": "p", "group": "g", "icon": "rocket"})
    assert bad_icon.status_code == 422


def test_goal_fields_patch_and_cascading_delete(client):
    parent = client.post(f"{API}/goals", json={
        "title": "Lisbon trip", "category": "something_else", "why": "May.", "source": "agent"}).json()
    assert parent["source"] == "agent" and parent["done"] is False
    assert parent["status_line"] == "" and parent["parent_id"] is None and parent["cron_job_id"] is None
    child = client.post(f"{API}/goals", json={
        "title": "Book flight", "category": "something_else", "why": "Trip.",
        "parent_id": parent["id"]}).json()
    assert child["source"] == "user" and child["parent_id"] == parent["id"]
    orphan = client.post(f"{API}/goals", json={
        "title": "x", "category": "health", "why": "y", "parent_id": "missing"})
    assert orphan.status_code == 422

    patched = client.patch(f"{API}/goals/{child['id']}", json={"title": "Book flights", "done": True})
    assert patched.status_code == 200, patched.text
    assert patched.json()["title"] == "Book flights" and patched.json()["done"] is True
    assert client.patch(f"{API}/goals/{child['id']}", json={"title": "  "}).status_code == 422
    assert client.patch(f"{API}/goals/missing", json={"done": True}).status_code == 404

    status = client.post(f"{API}/goals/{parent['id']}/update", json={
        "note": "Flight booked", "status_line": "Hotel still open"})
    assert status.json()["status_line"] == "Hotel still open"

    assert client.delete(f"{API}/goals/{parent['id']}").json() == {"ok": True}
    assert client.get(f"{API}/goals").json()["goals"] == []
    assert client.get(f"{API}/goals/{child['id']}").status_code == 404
    assert client.delete(f"{API}/goals/{parent['id']}").status_code == 404


def test_tasks_route_newest_first_with_before(client, hermes_home):
    import store

    root = store.hermuse_root(hermes_home)
    for i, day in enumerate(("01", "02", "03")):
        store.save_task(root, {
            "id": f"t{i}", "session_id": "s", "turn_id": f"turn{i}", "title": f"Task {i}",
            "summary": "Done.", "status": "completed", "source": "chat",
            "started_at": f"2026-10-{day}T08:00:00+00:00",
            "finished_at": f"2026-10-{day}T08:01:00+00:00", "tools": []})
    assert [t["id"] for t in client.get(f"{API}/tasks").json()["tasks"]] == ["t2", "t1", "t0"]
    page = client.get(f"{API}/tasks", params={"limit": 1, "before": "2026-10-03T00:00:00Z"})
    assert [t["id"] for t in page.json()["tasks"]] == ["t1"]
    assert client.get(f"{API}/tasks", params={"before": "yesterday"}).status_code == 422
    assert client.get(f"{API}/tasks", params={"limit": 0}).status_code == 422


def test_memory_routes_round_trip_under_hermes_lock(client, hermes_home):
    assert client.get(f"{API}/memory/user").json() == {
        "target": "user", "entries": [], "updated_at": None}
    put = client.put(f"{API}/memory/memory", json={"entries": ["Prefers trains", " ", "Vegetarian"]})
    assert put.json() == {"ok": True}
    raw = (hermes_home / "memories" / "MEMORY.md").read_text(encoding="utf-8")
    assert raw == "Prefers trains\n§\nVegetarian"
    # Written under Hermes' MemoryStore lock file.
    assert (hermes_home / "memories" / "MEMORY.md.lock").exists()
    got = client.get(f"{API}/memory/memory").json()
    assert got["entries"] == ["Prefers trains", "Vegetarian"] and got["updated_at"]

    from tools.memory_tool_store import MemoryStore

    assert MemoryStore._read_file(hermes_home / "memories" / "MEMORY.md") == got["entries"]
    assert client.get(f"{API}/memory/soul").status_code == 404
    assert client.put(f"{API}/memory/soul", json={"entries": []}).status_code == 404
    assert client.put(f"{API}/memory/user", json={"entries": ["a\n§\nb"]}).status_code == 422


def test_cron_rows_flag_hidden_maintenance_jobs(client):
    rows = {row["key"]: row for row in client.get(f"{API}/cron").json()["jobs"]}
    assert set(rows) == {"feed", "ideas", "goals", "reflection", "heartbeat"}
    assert {key for key, row in rows.items() if row["hidden"]} == {"feed", "ideas", "goals", "reflection"}
    assert rows["heartbeat"]["hidden"] is False and rows["heartbeat"]["registered"] is False
