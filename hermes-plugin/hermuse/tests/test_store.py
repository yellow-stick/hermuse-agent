"""Store behaviour: tool writes produce the files, defaults never clobber."""

from __future__ import annotations

import json

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
