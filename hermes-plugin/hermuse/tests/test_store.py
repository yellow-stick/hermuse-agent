"""Store behaviour: tool writes produce the files, defaults never clobber."""

from __future__ import annotations

import contextlib
import json

import pytest

import store


def test_ensure_defaults_creates_all_managed_files(hermuse_root):
    created = store.ensure_defaults(hermuse_root)
    assert created == list(store.MANAGED_FILES)
    for name in store.MANAGED_FILES:
        assert (hermuse_root / name).is_file()


def test_ensure_defaults_is_idempotent_and_keeps_edits(hermuse_root):
    store.ensure_defaults(hermuse_root)
    edited = "# mine\n\nCustom preferences.\n"
    (hermuse_root / store.PREFERENCES_FILE).write_text(edited)
    assert store.ensure_defaults(hermuse_root) == []
    assert (hermuse_root / store.PREFERENCES_FILE).read_text() == edited


def test_ensure_defaults_backfills_only_missing(hermuse_root):
    store.ensure_defaults(hermuse_root)
    (hermuse_root / store.IDENTITY_FILE).unlink()
    assert store.ensure_defaults(hermuse_root) == [store.IDENTITY_FILE]


def test_preferences_round_trip(hermuse_root):
    body = "# prefs\n\n## Tell me about\n\n- launches\n"
    store.write_managed(hermuse_root, store.PREFERENCES_FILE, body)
    assert store.read_managed(hermuse_root, store.PREFERENCES_FILE) == body


def test_feed_post_writes_markdown_and_index(hermuse_root):
    record = store.post_feed(
        hermuse_root, title="Hello!", body="First **post**.",
        topic="intro", sources=["https://example.com"],
    )
    md = (hermuse_root / "feed" / record["file"]).read_text()
    assert md.startswith("---\n")
    assert '"Hello!"' in md and "First **post**." in md
    index = json.loads((hermuse_root / "feed" / "index.json").read_text())
    assert index["items"][record["id"]]["title"] == "Hello!"
    assert store.get_feed_post(hermuse_root, record["id"])["sources"] == ["https://example.com"]


def test_feed_reactions_toggle(hermuse_root):
    record = store.post_feed(hermuse_root, title="t", body="b")
    reacted = store.react_feed(hermuse_root, record["id"], "love")
    assert "love" in reacted["reactions"]
    reacted = store.react_feed(hermuse_root, record["id"], "discuss")
    assert set(reacted["reactions"]) == {"love", "discuss"}
    assert store.react_feed(hermuse_root, record["id"], "love")["reactions"] == {"discuss": reacted["reactions"]["discuss"]}
    assert store.react_feed(hermuse_root, "missing", "love") is None


def test_idea_feedback_appends(hermuse_root):
    record = store.propose_idea(
        hermuse_root, title="Triage", pitch="Let me triage.", group="Productivity",
        first_step="Connect inbox.",
    )
    md = (hermuse_root / "ideas" / record["file"]).read_text()
    assert "Productivity" in md and "Let me triage." in md
    updated = store.feedback_idea(hermuse_root, record["id"], "do it")
    assert updated["feedback"][-1]["text"] == "do it"
    assert store.feedback_idea(hermuse_root, "missing", "x") is None


def test_goal_timeline_appends_to_md_and_index(hermuse_root):
    record = store.track_goal(
        hermuse_root, title="Run", category="health", why="Stay fit.", target_date="Oct",
    )
    updated = store.update_goal(hermuse_root, record["id"], "Ran 5k", progress="week 1")
    assert len(updated["timeline"]) == 2
    md = (hermuse_root / "goals" / f"{record['id']}.md").read_text()
    assert "Ran 5k" in md and "week 1" in md
    assert store.update_goal(hermuse_root, "missing", "x") is None


def test_artifact_content_and_copy(hermuse_root, tmp_path):
    text = store.save_artifact(
        hermuse_root, title="Notes", kind="document", content="# hi", tags=["a"])
    assert store.artifact_file(hermuse_root, text["id"]).read_text() == "# hi"
    assert text["size"] == 4

    src = tmp_path / "clip.mp4"
    src.write_bytes(b"\x00\x01binary")
    media = store.save_artifact(hermuse_root, title="Clip", kind="video", source_path=str(src))
    assert store.artifact_file(hermuse_root, media["id"]).read_bytes() == b"\x00\x01binary"


def test_artifact_file_contained(hermuse_root):
    record = store.save_artifact(hermuse_root, title="t", kind="document", content="x")
    # A poisoned index entry pointing outside must not resolve.
    index_path = hermuse_root / "artifacts" / "index.json"
    index = json.loads(index_path.read_text())
    index["items"][record["id"]]["file"] = "../../FEED_PROMPT.md"
    index_path.write_text(json.dumps(index))
    assert store.artifact_file(hermuse_root, record["id"]) is None


def test_reflection_write_and_replace(hermuse_root):
    first = store.write_reflection(hermuse_root, "2026-09-26", "Night one.")
    assert (hermuse_root / "reflections" / "2026-09-26.md").is_file()
    second = store.write_reflection(hermuse_root, "2026-09-26", "Night one, revised.")
    assert second["written_at"] >= first["written_at"]
    assert "revised" in (hermuse_root / "reflections" / "2026-09-26.md").read_text()
    assert [d["date"] for d in store.list_reflections(hermuse_root)] == ["2026-09-26"]


def test_feed_why_image_and_delete(hermuse_root):
    record = store.post_feed(
        hermuse_root, title="Rain", body="Bring a coat.", why="You bike to work.",
        image_url="https://example.com/rain.png")
    md = (hermuse_root / "feed" / record["file"]).read_text()
    assert "You bike to work." in md and "rain.png" in md
    post = store.get_feed_post(hermuse_root, record["id"])
    assert post["why"] == "You bike to work." and post["image_url"].endswith("rain.png")
    assert store.delete_feed_post(hermuse_root, record["id"]) is True
    assert not (hermuse_root / "feed" / record["file"]).exists()
    assert store.get_feed_post(hermuse_root, record["id"]) is None
    assert store.delete_feed_post(hermuse_root, record["id"]) is False


def test_legacy_feed_post_reads_with_defaults(hermuse_root):
    (hermuse_root / "feed").mkdir(parents=True)
    (hermuse_root / "feed" / "index.json").write_text(json.dumps({"version": 1, "items": {
        "old": {"id": "old", "title": "t", "body": "b", "created_at": "2026-01-01T00:00:00+00:00"}}}))
    [post] = store.list_feed(hermuse_root)
    assert post["why"] == "" and post["image_url"] is None


def test_idea_catalog_groups_and_shape():
    assert 12 <= len(store.SEED_IDEAS) <= 16
    assert {seed["group"] for seed in store.SEED_IDEAS} == {
        "Productivity", "Health & Fitness", "Shopping", "Money", "Relationships",
        "Travel", "Home & city"}
    for seed in store.SEED_IDEAS:
        assert seed["id"].startswith("seed-") and seed["seeded"] is True
        assert seed["icon"] in store.IDEA_ICONS
        assert seed["title"].startswith("I'll ") and seed["pitch"]
    assert len({seed["id"] for seed in store.SEED_IDEAS}) == len(store.SEED_IDEAS)


def test_ideas_merge_agent_first_then_seeds_and_dismiss(hermuse_root):
    agent = store.propose_idea(hermuse_root, title="Triage", pitch="p", group="Money")
    listed = store.list_ideas(hermuse_root)
    assert listed[0]["id"] == agent["id"] and listed[0]["seeded"] is False
    assert listed[0]["icon"] == "money"
    assert [i["id"] for i in listed[1:]] == [s["id"] for s in store.SEED_IDEAS]

    seed_id = store.SEED_IDEAS[0]["id"]
    assert store.dismiss_idea(hermuse_root, seed_id) is True
    assert store.dismiss_idea(hermuse_root, agent["id"]) is True
    assert store.dismiss_idea(hermuse_root, seed_id) is True  # idempotent
    assert store.dismiss_idea(hermuse_root, "nope") is False
    ids = [i["id"] for i in store.list_ideas(hermuse_root)]
    assert seed_id not in ids and agent["id"] not in ids
    assert len(ids) == len(store.SEED_IDEAS) - 1
    assert json.loads((hermuse_root / "ideas" / "dismissed.json").read_text())["ids"] == sorted(
        [seed_id, agent["id"]])
    assert store.get_idea(hermuse_root, seed_id)["seeded"] is True


def test_legacy_goal_record_reads_with_contract_fields(hermuse_root):
    (hermuse_root / "goals").mkdir(parents=True)
    legacy = {
        "id": "old", "title": "Run", "category": "health", "why": "Fit.", "target_date": "",
        "status": "done", "file": "old.md", "created_at": "2026-01-01T00:00:00+00:00",
        "timeline": [{"at": "2026-01-01", "note": "start", "progress": ""},
                     {"at": "2026-01-02", "note": "ran", "progress": "5k done"}],
    }
    (hermuse_root / "goals" / "index.json").write_text(
        json.dumps({"version": 1, "items": {"old": legacy}}))
    goal = store.get_goal(hermuse_root, "old")
    assert goal["source"] == "user" and goal["done"] is True
    assert goal["status_line"] == "5k done"
    assert goal["parent_id"] is None and goal["cron_job_id"] is None
    assert store.list_goals(hermuse_root)[0] == goal
    reopened = store.patch_goal(hermuse_root, "old", done=False)
    assert reopened["done"] is False and reopened["status"] == "tracking"


def test_goal_patch_renames_and_completes(hermuse_root):
    goal = store.track_goal(hermuse_root, title="Trip", category="something_else",
                            why="Lisbon in May.", source="agent", cron_job_id="job1")
    assert goal["source"] == "agent" and goal["cron_job_id"] == "job1" and goal["done"] is False
    patched = store.patch_goal(hermuse_root, goal["id"], title="Lisbon trip", done=True)
    assert patched["title"] == "Lisbon trip" and patched["done"] is True
    assert patched["status"] == "done" and patched["timeline"][-1]["note"] == "marked done."
    md = (hermuse_root / "goals" / f"{goal['id']}.md").read_text()
    assert 'title: "Lisbon trip"' in md and 'status: "done"' in md
    assert "# Lisbon trip" in md and "marked done." in md
    assert store.patch_goal(hermuse_root, "missing", title="x") is None


def test_goal_status_line_from_update(hermuse_root):
    goal = store.track_goal(hermuse_root, title="Trip", category="something_else", why="w")
    updated = store.update_goal(hermuse_root, goal["id"], "", status_line="Flight booked")
    assert updated["status_line"] == "Flight booked" and len(updated["timeline"]) == 1
    updated = store.update_goal(hermuse_root, goal["id"], "Hotel found", progress="2 of 3 booked")
    assert updated["status_line"] == "2 of 3 booked"


def test_goal_delete_cascades_to_subgoals(hermuse_root):
    parent = store.track_goal(hermuse_root, title="Trip", category="something_else", why="w")
    child = store.track_goal(hermuse_root, title="Flight", category="something_else", why="w",
                             parent_id=parent["id"])
    grandchild = store.track_goal(hermuse_root, title="Seat", category="something_else", why="w",
                                  parent_id=child["id"])
    other = store.track_goal(hermuse_root, title="Run", category="health", why="w")
    deleted = store.delete_goal(hermuse_root, parent["id"])
    assert set(deleted) == {parent["id"], child["id"], grandchild["id"]}
    assert [g["id"] for g in store.list_goals(hermuse_root)] == [other["id"]]
    for gid in deleted:
        assert not (hermuse_root / "goals" / f"{gid}.md").exists()
    assert store.delete_goal(hermuse_root, parent["id"]) == []


def test_goal_rejects_unknown_parent_and_source(hermuse_root):
    with pytest.raises(ValueError):
        store.track_goal(hermuse_root, title="t", category="health", why="w", parent_id="nope")
    with pytest.raises(ValueError):
        store.track_goal(hermuse_root, title="t", category="health", why="w", source="bot")


def _task(tid, started, **extra):
    return {"id": tid, "session_id": "s", "turn_id": tid, "title": "t", "summary": "s",
            "status": "completed", "source": "chat", "started_at": started,
            "finished_at": started, "tools": [], **extra}


def test_tasks_upsert_order_before_and_cap(hermuse_root, monkeypatch):
    monkeypatch.setattr(store, "TASKS_CAP", 3)
    for i in range(5):
        store.save_task(hermuse_root, _task(f"t{i}", f"2026-10-0{i + 1}T08:00:00+00:00"))
    assert [t["id"] for t in store.list_tasks(hermuse_root)] == ["t4", "t3", "t2"]
    store.save_task(hermuse_root, {**_task("t4", "2026-10-05T08:00:00+00:00"), "status": "failed"})
    assert store.get_task(hermuse_root, "t4")["status"] == "failed"
    before = store.parse_iso("2026-10-05T00:00:00Z")
    assert [t["id"] for t in store.list_tasks(hermuse_root, 10, before)] == ["t3", "t2"]
    assert store.update_task(hermuse_root, "t3", title="New")["title"] == "New"
    assert store.update_task(hermuse_root, "missing", title="x") is None
    with pytest.raises(ValueError):
        store.save_task(hermuse_root, _task("bad", "2026-10-01T00:00:00+00:00", status="done"))


def test_memory_round_trip(hermes_home):
    assert store.read_memory(hermes_home, "memory") == {
        "target": "memory", "entries": [], "updated_at": None}
    locked = []

    @contextlib.contextmanager
    def lock(path):
        locked.append(path)
        yield

    stored = store.write_memory(hermes_home, "user", ["  Name: Ana ", "", "Lives in Nantes"], lock=lock)
    assert stored == ["Name: Ana", "Lives in Nantes"]
    assert locked == [hermes_home / "memories" / "USER.md"]
    assert (hermes_home / "memories" / "USER.md").read_text() == "Name: Ana\n§\nLives in Nantes"
    read = store.read_memory(hermes_home, "user")
    assert read["entries"] == ["Name: Ana", "Lives in Nantes"] and read["updated_at"]
    with pytest.raises(ValueError):
        store.write_memory(hermes_home, "memory", ["a\n§\nb"])
    with pytest.raises(ValueError):
        store.read_memory(hermes_home, "soul")
