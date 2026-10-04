"""Media provider config/status, avatar jobs and the Feed illustration fallback,
against a fake ContentFlow served on 127.0.0.1 (no network)."""

from __future__ import annotations

import importlib.util
import io
import json
import shutil
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import avatar
import media
import store

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
API = "/api/plugins/hermuse"

needs_ffmpeg = pytest.mark.skipif(media.ffmpeg_paths() is None, reason="ffmpeg/ffprobe not installed")

VIDEO_CATALOGUE = {
    "kind": "video", "credits": 35,
    "models": [
        {"id": "abra", "name": "Omni 1.1 Flash", "aliases": ["Omni Flash"], "usages": [
            {"key": "abra_t2v_4s", "available": True, "credits": 9, "feature_sets": [[1]],
             "duration": 4, "resolutions": ["720p"]},
            {"key": "abra_i2v_4s_360p", "available": True, "credits": 4, "feature_sets": [[1, 5]],
             "duration": 4, "resolutions": ["360p"]},
            {"key": "abra_i2v_8s", "available": True, "credits": 12, "feature_sets": [[1, 5]],
             "duration": 8, "resolutions": ["720p"]},
            {"key": "abra_i2v_4s", "available": True, "credits": 7, "feature_sets": [[1, 5]],
             "duration": 4, "resolutions": ["720p"]},
        ]},
        {"id": "veo_3_1_lite", "name": "Veo 3.1 - Lite", "aliases": [], "usages": [
            {"key": "veo_3_1_i2v_lite_4s", "available": False, "credits": None, "feature_sets": [[1, 5]],
             "duration": 4, "resolutions": ["720p"]},
        ]},
    ],
}


def _image_bytes(width=320, height=180, fmt="JPEG") -> bytes:
    """Blue sides, red centre square: a centre crop is all red."""
    from PIL import Image, ImageDraw

    image = Image.new("RGB", (width, height), (0, 0, 255))
    side = min(width, height)
    left = (width - side) // 2
    ImageDraw.Draw(image).rectangle([left, 0, left + side - 1, height - 1], fill=(255, 0, 0))
    out = io.BytesIO()
    image.save(out, fmt)
    return out.getvalue()


@pytest.fixture(scope="session")
def clip_mp4(tmp_path_factory) -> bytes:
    tools = media.ffmpeg_paths()
    if tools is None:
        pytest.skip("ffmpeg/ffprobe not installed")
    path = tmp_path_factory.mktemp("clip") / "clip.mp4"
    subprocess.run(
        [tools[0], "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=24",
         "-f", "lavfi", "-i", "sine=frequency=440", "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-shortest", str(path)],
        check=True, timeout=60)
    return path.read_bytes()


class FakeContentFlow:
    """Scriptable provider: records every request, serves its own result files."""

    def __init__(self):
        self.requests: list[tuple[str, str, dict, dict]] = []
        self.files: dict[str, tuple[bytes, str]] = {}
        self.known_images: set[str] = set()
        self.image_bytes = _image_bytes()
        self.image_gate: threading.Event | None = None
        self.image_error: tuple[int, dict] | None = None
        self.video_fail_words: tuple[str, ...] = ()
        self.clip = b""
        self.pending_polls = 1
        self._polls: dict[str, int] = {}
        self._next = 0
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _send(self, code, payload, content_type="application/json"):
                body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
                self.send_response(code)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                fake.requests.append(("GET", self.path, {}, dict(self.headers)))
                if self.path == "/video":
                    return self._send(200, VIDEO_CATALOGUE)
                if self.path == "/image":
                    return self._send(200, {"kind": "image", "credits": 35, "models": []})
                name = self.path.split("?", 1)[0][len("/files/"):]
                if self.path.startswith("/files/") and name in fake.files:
                    data, mime = fake.files[name]
                    return self._send(200, data, mime)
                self._send(404, {"error": "not found"})

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                fake.requests.append(("POST", self.path, body, dict(self.headers)))
                code, payload = fake.answer(self.path, body, self.server.server_address[1])
                self._send(code, payload)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.endpoint = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def _id(self, prefix):
        self._next += 1
        return f"{prefix}-{self._next}"

    def _file(self, name, data, mime, port):
        self.files[name] = (data, mime)
        return f"http://127.0.0.1:{port}/files/{name}?Signature=x"

    def answer(self, path, body, port):
        action = body.get("action", "generate")
        if path == "/image" and action == "generate":
            if self.image_gate is not None:
                self.image_gate.wait(10)
            if self.image_error:
                return self.image_error
            media_items = []
            for _ in range(body["count"]):
                media_id = self._id("img")
                self.known_images.add(media_id)
                media_items.append({"id": media_id, "status": "success",
                                    "url": self._file(f"{media_id}.jpg", self.image_bytes, "image/jpeg", port)})
            return 200, {"media": media_items}
        if path == "/image" and action == "upload":
            media_id = self._id("up")
            self.known_images.add(media_id)
            return 200, {"media": [{"id": media_id, "status": "success"}]}
        if path == "/image" and action == "status":
            if body["media_id"] in self.known_images:
                return 200, {"media": [{"id": body["media_id"], "status": "success"}]}
            return 502, {"error": "Flow rejected RPC as29s.", "details": {"code": 5, "reasons": []}}
        if path == "/video" and action == "generate":
            if any(word in body["prompt"] for word in self.video_fail_words):
                return 502, {"error": "WafRejectionError",
                             "details": {"reason": "PUBLIC_ERROR_UNUSUAL_ACTIVITY"}}
            return 202, {"media": [{"id": self._id("vid"), "status": "scheduled"}]}
        if path == "/video" and action == "status":
            media_id = body["media_id"]
            self._polls[media_id] = self._polls.get(media_id, 0) + 1
            if self._polls[media_id] <= self.pending_polls:
                return 202, {"media": [{"id": media_id, "status": "pending"}]}
            return 200, {"media": [{"id": media_id, "status": "success",
                                    "url": self._file(f"{media_id}.mp4", self.clip, "video/mp4", port)}]}
        return 422, {"error": "unexpected request"}

    def posts(self, path, action="generate"):
        return [b for m, p, b, _ in self.requests if m == "POST" and p == path and b.get("action", "generate") == action]


@pytest.fixture()
def provider(monkeypatch):
    fake = FakeContentFlow()
    monkeypatch.setattr(media, "POLL_S", 0.01)
    yield fake
    fake.server.shutdown()


def _load_plugin_api():
    module_name = "hermuse_dashboard_plugin_api_under_test"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(module_name, PLUGIN_ROOT / "dashboard" / "plugin_api.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture()
def client(hermes_home):
    app = FastAPI()
    app.include_router(_load_plugin_api().router, prefix=API)
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def configured(client, provider):
    assert client.put(f"{API}/media/config", json={"endpoint": provider.endpoint}).status_code == 200
    return provider


def _wait_job(client, job_id, timeout=60.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        job = client.get(f"{API}/avatar/jobs/{job_id}").json()
        if job["status"] != "running":
            return job
        time.sleep(0.05)
    raise AssertionError(f"job {job_id} still running")


def _portrait(client, count=2):
    job = client.post(f"{API}/avatar/portrait", json={"description": "A cheerful robot gardener", "count": count})
    assert job.status_code == 202, job.text
    return _wait_job(client, job.json()["id"])


# --- Config and status --------------------------------------------------------


def test_config_round_trip_token_write_only_and_env_override(client, hermes_home, monkeypatch):
    assert client.get(f"{API}/media/config").json() == {
        "provider": "contentflow", "endpoint": "", "has_token": False, "image_model": "nano-banana-2-lite",
        "video_model": "Omni 1.1 Flash", "feed_fallback": True, "from_env": False}
    saved = client.put(f"{API}/media/config", json={
        "endpoint": "http://127.0.0.1:9400/", "token": "s3cret", "feed_fallback": False}).json()
    assert saved["endpoint"] == "http://127.0.0.1:9400" and saved["has_token"] is True
    assert saved["feed_fallback"] is False and "token" not in saved
    path = hermes_home / "hermuse" / "media.json"
    assert path.stat().st_mode & 0o777 == 0o600
    assert json.loads(path.read_text())["token"] == "s3cret"

    kept = client.put(f"{API}/media/config", json={"endpoint": "http://127.0.0.1:9400"}).json()
    assert kept["has_token"] is True and kept["feed_fallback"] is False  # omitted: unchanged
    cleared = client.put(f"{API}/media/config", json={"endpoint": "http://127.0.0.1:9400", "token": ""}).json()
    assert cleared["has_token"] is False
    assert client.put(f"{API}/media/config", json={"endpoint": "ftp://x"}).status_code == 422
    assert client.put(f"{API}/media/config", json={"endpoint": ""}).json()["endpoint"] == ""

    monkeypatch.setenv("HERMUSE_MEDIA_ENDPOINT", "https://flow.example.net/")
    monkeypatch.setenv("HERMUSE_MEDIA_TOKEN", "from-env")
    env = client.get(f"{API}/media/config").json()
    assert env["endpoint"] == "https://flow.example.net" and env["has_token"] and env["from_env"]
    assert media.load_config().token == "from-env"


def test_config_is_server_wide_whatever_the_profile(hermes_home):
    from hermes_constants import reset_hermes_home_override, set_hermes_home_override

    token = set_hermes_home_override(hermes_home / "profiles" / "aya")
    try:
        media.save_config(endpoint="http://127.0.0.1:1")
        assert media.config_path() == hermes_home / "hermuse" / "media.json"
    finally:
        reset_hermes_home_override(token)
    assert media.load_config().endpoint == "http://127.0.0.1:1"


def test_status_reads_credits_and_video_cost(client, configured, monkeypatch):
    status = client.get(f"{API}/media/status").json()
    assert status == {"configured": True, "reachable": True, "credits": 35, "video_cost": 7, "error": None}
    headers = configured.requests[-1][3]
    assert "Origin" not in headers and "Authorization" not in headers

    client.put(f"{API}/media/config", json={"endpoint": configured.endpoint, "token": "t0k",
                                            "video_model": "veo 3.1 - lite"})
    status = client.get(f"{API}/media/status").json()
    assert status["video_cost"] is None and "no 4 s image animation" in status["error"]
    assert configured.requests[-1][3]["Authorization"] == "Bearer t0k"

    monkeypatch.setattr(media.shutil, "which", lambda name: None)
    assert client.get(f"{API}/media/status").json()["error"] == media.FFMPEG_MISSING


def test_video_cost_matches_aliases():
    assert media.video_cost(VIDEO_CATALOGUE, "omni flash") == 7
    assert media.video_cost(VIDEO_CATALOGUE, "abra") == 7
    assert media.video_cost(VIDEO_CATALOGUE, "unknown") is None
    assert media.video_cost({"models": "junk"}, "abra") is None


def test_status_unreachable_and_unconfigured(client):
    assert client.get(f"{API}/media/status").json()["configured"] is False
    client.put(f"{API}/media/config", json={"endpoint": "http://127.0.0.1:9"})
    status = client.get(f"{API}/media/status").json()
    assert status["reachable"] is False and status["credits"] is None
    assert status["error"].startswith("cannot reach http://127.0.0.1:9")


def test_provider_errors_carry_its_message(provider):
    provider.image_error = (502, {"error": "WafRejectionError", "details": {"reason": "PUBLIC_ERROR_UNUSUAL_ACTIVITY"}})
    client = media.Client(media.MediaConfig(endpoint=provider.endpoint))
    with pytest.raises(media.MediaError, match=r"WafRejectionError \(reason: PUBLIC_ERROR_UNUSUAL_ACTIVITY\)"):
        client.generate_images("x")
    assert len(provider.posts("/image")) == 1  # never resubmitted


# --- Avatar -------------------------------------------------------------------


def test_avatar_needs_a_configured_provider(client):
    assert client.get(f"{API}/avatar").json() == {"portrait_url": None, "states": {}, "job": None, "updated_at": None}
    refused = client.post(f"{API}/avatar/portrait", json={"description": "x"})
    assert refused.status_code == 409 and "not configured" in refused.json()["detail"]
    assert client.post(f"{API}/avatar/portrait", json={"description": ""}).status_code == 422
    assert client.post(f"{API}/avatar/portrait", json={"description": "x", "count": 5}).status_code == 422


def test_portrait_job_candidates_and_select(client, configured, hermuse_root):
    job = _portrait(client, count=3)
    assert job["kind"] == "portrait" and job["status"] == "done" and job["error"] is None
    assert job["candidates"] == [f"{API}/avatar/candidates/{job['id']}/{n}" for n in range(3)]
    sent = configured.posts("/image")[0]
    assert sent["aspect_ratio"] == "16:9" and sent["count"] == 3 and sent["model"] == "nano-banana-2-lite"
    assert sent["prompt"].startswith("A cheerful robot gardener") and "head and shoulders" in sent["prompt"]

    candidate = client.get(job["candidates"][1])
    assert candidate.status_code == 200 and candidate.headers["content-type"] == "image/jpeg"
    assert candidate.headers["cache-control"].startswith("private")
    assert client.get(f"{API}/avatar/candidates/{job['id']}/7").status_code == 404
    assert client.get(f"{API}/avatar/portrait").status_code == 404

    assert client.post(f"{API}/avatar/select", json={"candidate": 3}).status_code == 404
    selected = client.post(f"{API}/avatar/select", json={"candidate": 1}).json()
    assert selected["portrait_url"] == f"{API}/avatar/portrait" and selected["states"] == {}
    assert selected["updated_at"] and selected["job"]["id"] == job["id"]

    from PIL import Image

    portrait = client.get(selected["portrait_url"])
    assert portrait.headers["content-type"] == "image/jpeg" and portrait.headers["cache-control"] == "private, no-cache"
    square = Image.open(io.BytesIO(portrait.content)).convert("RGB")
    assert square.size == (512, 512)
    for xy in ((3, 3), (508, 508), (256, 256)):  # only the red centre square is kept
        r, g, b = square.getpixel(xy)
        assert r > 200 and b < 60, xy
    base = hermuse_root / "avatar"
    assert Image.open(base / "portrait.jpg").size == (320, 180)  # the 16:9 original
    assert json.loads((base / "avatar.json").read_text())["portrait_media_id"] == "img-2"


def test_png_candidates_are_stored_as_jpeg(client, configured):
    configured.image_bytes = _image_bytes(fmt="PNG")
    job = _portrait(client, count=1)
    assert client.get(job["candidates"][0]).content[:3] == b"\xff\xd8\xff"


def test_failed_portrait_job_keeps_the_provider_message(client, configured):
    configured.image_error = (502, {"error": "WafRejectionError", "details": {"reason": "PUBLIC_ERROR_UNUSUAL_ACTIVITY"}})
    job = _portrait(client)
    assert job["status"] == "failed" and job["candidates"] == []
    assert job["error"] == "WafRejectionError (reason: PUBLIC_ERROR_UNUSUAL_ACTIVITY)"
    assert client.post(f"{API}/avatar/select", json={"candidate": 0}).status_code == 404


def test_one_job_at_a_time_and_animate_needs_a_portrait(client, configured):
    assert client.post(f"{API}/avatar/animate", json={}).status_code == 422
    configured.image_gate = threading.Event()
    started = client.post(f"{API}/avatar/portrait", json={"description": "owl"}).json()
    try:
        assert client.get(f"{API}/avatar").json()["job"]["status"] == "running"
        for method, path, body in (("post", "/avatar/portrait", {"description": "owl"}),
                                   ("post", "/avatar/animate", {}),
                                   ("post", "/avatar/select", {"candidate": 0}),
                                   ("delete", "/avatar", None)):
            kwargs = {"json": body} if body is not None else {}
            refused = getattr(client, method)(f"{API}{path}", **kwargs)
            assert refused.status_code == 409, path
            assert refused.json()["detail"] == "an avatar job is already running"
    finally:
        configured.image_gate.set()
    assert _wait_job(client, started["id"])["status"] == "done"
    assert client.post(f"{API}/avatar/animate", json={"states": ["dancing"]}).status_code == 422


def test_job_of_a_previous_dashboard_reads_interrupted(client, configured, hermuse_root):
    job = _portrait(client)
    path = hermuse_root / "avatar" / "jobs.json"
    jobs = json.loads(path.read_text())
    jobs["jobs"][job["id"]].update(status="running", owner="old-process", finished_at=None,
                                   states={"idle": "running", "thinking": "queued"})
    path.write_text(json.dumps(jobs))
    interrupted = client.get(f"{API}/avatar/jobs/{job['id']}").json()
    assert interrupted["status"] == "failed" and interrupted["error"] == "interrupted"
    assert interrupted["states"] == {"idle": "failed", "thinking": "failed"}
    assert client.post(f"{API}/avatar/portrait", json={"description": "again"}).status_code == 202


@needs_ffmpeg
def test_animate_exports_loops_and_goes_on_after_a_failed_clip(client, configured, clip_mp4, hermuse_root):
    from PIL import Image

    configured.clip = clip_mp4
    _portrait(client)
    client.post(f"{API}/avatar/select", json={"candidate": 0})
    configured.video_fail_words = ("thinking:",)
    started = client.post(f"{API}/avatar/animate", json={"states": ["idle", "thinking", "replying"]})
    assert started.status_code == 202
    assert started.json()["kind"] == "animate" and set(started.json()["states"]) == {"idle", "thinking", "replying"}
    job = _wait_job(client, started.json()["id"])
    assert job["status"] == "done"
    assert job["states"] == {"idle": "done", "thinking": "failed", "replying": "done"}
    assert job["error"] == "thinking: WafRejectionError (reason: PUBLIC_ERROR_UNUSUAL_ACTIVITY)"

    submitted = configured.posts("/video")
    assert len(submitted) == 3  # one submission per state, the failed one not retried
    assert all(s["first_frame"] == "img-1" and s["aspect_ratio"] == "16:9" and s["duration"] == 4
               and s["model"] == "Omni 1.1 Flash" and s["count"] == 1 for s in submitted)
    assert "no lip movement" in submitted[0]["prompt"] and "locked-off" in submitted[0]["prompt"]
    assert configured.posts("/image", "upload") == []  # the portrait's media id was still known

    current = client.get(f"{API}/avatar").json()
    assert current["states"] == {"idle": f"{API}/avatar/states/idle", "replying": f"{API}/avatar/states/replying"}
    loop = client.get(current["states"]["idle"])
    assert loop.status_code == 200 and loop.headers["content-type"] == "image/webp"
    assert loop.headers["cache-control"] == "private, no-cache"
    image = Image.open(io.BytesIO(loop.content))
    # 2 s clip at 20 fps minus the 0.4 s crossfaded into the head.
    assert image.size == (256, 256) and image.n_frames == 32 and image.info.get("loop") == 0
    assert client.get(f"{API}/avatar/states/thinking").status_code == 404
    assert client.get(f"{API}/avatar/states/nope").status_code == 404
    assert (hermuse_root / "avatar" / "clips" / "idle.mp4").read_bytes() == clip_mp4

    # A new portrait drops the animations of the previous face.
    client.post(f"{API}/avatar/select", json={"candidate": 1})
    assert client.get(f"{API}/avatar").json()["states"] == {}


@needs_ffmpeg
def test_expired_portrait_media_id_is_uploaded_again(client, configured, clip_mp4):
    configured.clip = clip_mp4
    _portrait(client, count=1)
    client.post(f"{API}/avatar/select", json={"candidate": 0})
    configured.known_images.clear()  # the provider forgot it
    job = _wait_job(client, client.post(f"{API}/avatar/animate", json={"states": ["idle"]}).json()["id"])
    assert job["states"] == {"idle": "done"}
    uploads = configured.posts("/image", "upload")
    assert len(uploads) == 1 and uploads[0]["mime_type"] == "image/jpeg" and uploads[0]["data"]
    assert configured.posts("/video")[0]["first_frame"] == "up-2"


def test_animate_refused_without_ffmpeg(client, configured, monkeypatch):
    _portrait(client, count=1)
    client.post(f"{API}/avatar/select", json={"candidate": 0})
    monkeypatch.setattr(media.shutil, "which", lambda name: None)
    refused = client.post(f"{API}/avatar/animate", json={})
    assert refused.status_code == 409 and refused.json()["detail"] == media.FFMPEG_MISSING
    assert configured.posts("/video") == []


def test_delete_avatar(client, configured, hermuse_root):
    _portrait(client, count=1)
    client.post(f"{API}/avatar/select", json={"candidate": 0})
    assert client.delete(f"{API}/avatar").json() == {"ok": True}
    assert not (hermuse_root / "avatar").exists()
    assert client.get(f"{API}/avatar").json()["portrait_url"] is None
    assert client.get(f"{API}/avatar/portrait").status_code == 404


# --- Feed fallback ------------------------------------------------------------


def _wait_image(client, post_id, timeout=10.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        post = client.get(f"{API}/feed/{post_id}").json()
        if post["image_url"]:
            return post
        time.sleep(0.05)
    raise AssertionError("no illustration attached")


def test_feed_post_without_image_gets_an_illustration(client, configured, hermuse_root):
    configured.image_gate = threading.Event()  # the post is answered before generation ends
    created = client.post(f"{API}/feed", json={"title": "Rain gardens", "body": "b", "why": "you garden"})
    assert created.status_code == 201 and created.json()["image_url"] is None
    configured.image_gate.set()
    post = _wait_image(client, created.json()["id"])
    assert post["image_url"] == f"{API}/feed/{post['id']}/image"
    assert client.get(post["image_url"]).content == configured.image_bytes
    prompt = configured.posts("/image")[0]
    assert prompt["count"] == 1 and prompt["aspect_ratio"] == "16:9"
    assert "Rain gardens" in prompt["prompt"] and "you garden" in prompt["prompt"] and "No text" in prompt["prompt"]
    markdown = next((hermuse_root / "feed").glob("*.md")).read_text()
    assert f'image_file: "images/{post["id"]}.jpg"' in markdown.split("---")[1]


def test_feed_fallback_does_nothing_when_disabled_or_failing(client, configured):
    client.put(f"{API}/media/config", json={"endpoint": configured.endpoint, "feed_fallback": False})
    post = client.post(f"{API}/feed", json={"title": "t", "body": "b"}).json()
    time.sleep(0.2)
    assert configured.posts("/image") == [] and client.get(f"{API}/feed/{post['id']}").json()["image_url"] is None

    client.put(f"{API}/media/config", json={"endpoint": configured.endpoint, "feed_fallback": True})
    configured.image_error = (502, {"error": "WafRejectionError"})
    record = store.get_feed_post(store.hermuse_root(), post["id"])
    thread = media.illustrate_feed_post(store.hermuse_root(), record)
    thread.join(10)
    assert len(configured.posts("/image")) == 1
    assert client.get(f"{API}/feed/{post['id']}").json()["image_url"] is None


def test_feed_post_with_an_image_is_not_illustrated(client, configured, monkeypatch):
    jpeg = b"\xff\xd8\xff\xe0" + b"\0" * 32
    monkeypatch.setattr(sys.modules["feed_images"], "find_post_image", lambda image_url, sources, get=None: (jpeg, ".jpg"))
    client.post(f"{API}/feed", json={"title": "t", "body": "b", "sources": ["https://news.example/a"]})
    time.sleep(0.2)
    assert configured.posts("/image") == []


def test_illustration_of_a_deleted_post_is_dropped(hermuse_root):
    post = store.post_feed(hermuse_root, title="t", body="b")
    store.delete_feed_post(hermuse_root, post["id"])
    assert store.attach_feed_image(hermuse_root, post["id"], (b"\xff\xd8\xff", ".jpg")) is None
    assert list((hermuse_root / "feed").glob("images/*")) == []


def test_feed_tool_illustrates_in_the_background(hermes_home, provider):
    from .test_entry import _Ctx, _load_entry

    ctx = _Ctx()
    _load_entry().register(ctx)
    media.save_config(endpoint=provider.endpoint)
    provider.image_gate = threading.Event()
    result = json.loads(ctx.tools["feed_post"]["handler"]({"title": "t", "body": "b", "why": "w"}))
    assert result["ok"] and result["image"] is False and result["illustrating"] is True
    provider.image_gate.set()
    root = store.hermuse_root(hermes_home)
    deadline = time.monotonic() + 10
    while store.feed_image(root, result["id"]) is None and time.monotonic() < deadline:
        time.sleep(0.05)
    assert store.feed_image(root, result["id"]) is not None
