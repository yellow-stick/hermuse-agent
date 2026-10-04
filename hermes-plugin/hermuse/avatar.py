"""Generated agent avatars: portrait candidates, the chosen portrait and its
state animations, under ``<profile home>/hermuse/avatar/``::

    avatar.json                 portrait media id at the provider, updated_at
    jobs.json                   recent jobs (GET /avatar/jobs/{id} across requests)
    candidates/<job>/<n>.jpg    portrait candidates (16:9)
    portrait.jpg                the chosen candidate, 16:9: first frame of every clip
    portrait-square.jpg         its centre square, 512 px: what the apps show
    clips/<state>.mp4           the provider's clip, as downloaded
    states/<state>.webp         the loop the apps play: 256 px, 20 fps, silent

Jobs run one at a time per profile on a daemon thread of the dashboard
process. A job still ``running`` in ``jobs.json`` but started by another
process (the dashboard restarted meanwhile) reads as failed, "interrupted".
Each clip is submitted once; a failed clip marks its state failed and the job
goes on with the next one; nothing is retried. Pillow (a Hermes dependency)
crops the portrait; ffmpeg exports the clips.
"""

from __future__ import annotations

import contextlib
import io
import json
import logging
import os
import shutil
import subprocess
import tempfile
import threading
import uuid
from pathlib import Path
from typing import Any, Optional

try:  # agent process: package hermes_plugins.hermuse
    from . import media, store
except ImportError:  # dashboard backend / tests: plugin root on sys.path
    import media  # type: ignore[no-redef]
    import store  # type: ignore[no-redef]

log = logging.getLogger(__name__)

DIR_NAME = "avatar"
ROUTE = "/api/plugins/hermuse/avatar"
STATES = ("idle", "thinking", "replying", "working")
PORTRAIT_FILE = "portrait.jpg"
SQUARE_FILE = "portrait-square.jpg"
SQUARE_PX = 512
CLIP_PX = 256
CLIP_FPS = 20
WEBP_QUALITY = 70
EXPORT_TIMEOUT_S = 180
JOBS_KEPT = 10
DESCRIPTION_MAX = 1000

PORTRAIT_PROMPT = (
    "{description}\n\n"
    "Portrait of this one character only, head and shoulders, centred in the frame with "
    "generous headroom above the head and wide empty margins on both sides, so the whole head "
    "and shoulders fit inside the central square of the picture. Facing the camera, looking at "
    "the viewer, neutral relaxed expression with the mouth closed. Plain uniform light "
    "background, soft even studio light. No text, no letters, no logo, no watermark, no frame."
)

_CLIP_RULES = (
    "Static locked-off camera: no camera movement, no zoom, no cut. Keep exactly the same "
    "character, framing, plain background and lighting as the first frame. The character "
    "starts and ends in the same neutral pose, facing the camera. No text, no music."
)
STATE_PROMPTS = {
    "idle": "The character is idle and calm: gentle breathing, a natural blink, very slight head "
            "movement. The mouth stays closed the whole time: no talking, no lip movement, silent.",
    "thinking": "The character is thinking: looks up and slightly to the side with a small head "
                "tilt and a pensive expression, then looks back at the camera. The mouth stays "
                "closed: no talking, no lip movement.",
    "replying": "The character is speaking to the viewer, expressive and friendly: natural lip "
                "movement, lively facial expressions, small head movements, then returns to the "
                "neutral pose.",
    "working": "The character is focused on a task: concentrated expression, eyes glancing down, "
               "small hand and shoulder gestures, then looks back at the camera. The mouth stays "
               "closed: no talking, no lip movement.",
}

_BOOT = uuid.uuid4().hex  # this process: jobs owned by another one were interrupted
_LOCK = threading.RLock()


class AvatarBusy(Exception):
    """A job is already running for this profile."""


class AvatarUnavailable(Exception):
    """Generation cannot run on this server (provider not configured, no ffmpeg)."""


class NoPortrait(Exception):
    """Animation needs a selected portrait."""


class ExportError(Exception):
    """ffmpeg could not turn a clip into a loop."""


def avatar_dir(root: Path) -> Path:
    return root / DIR_NAME


def portrait_prompt(description: str) -> str:
    return PORTRAIT_PROMPT.format(description=description.strip())


def state_prompt(state: str) -> str:
    return f"{STATE_PROMPTS[state]} {_CLIP_RULES}"


# --- Persistence -------------------------------------------------------------


def _read(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _write(path: Path, data: dict[str, Any]) -> None:
    store.atomic_write_text(path, json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def _meta(root: Path) -> dict[str, Any]:
    return _read(avatar_dir(root) / "avatar.json")


def _write_meta(root: Path, **changes: Any) -> None:
    with _LOCK:
        meta = {**_meta(root), **changes, "updated_at": store.utcnow_iso()}
        _write(avatar_dir(root) / "avatar.json", meta)


def _jobs(root: Path) -> dict[str, dict[str, Any]]:
    """Jobs by id; running jobs of another process are marked interrupted."""
    with _LOCK:
        jobs = _read(avatar_dir(root) / "jobs.json").get("jobs")
        jobs = {k: v for k, v in jobs.items() if isinstance(v, dict)} if isinstance(jobs, dict) else {}
        stale = [job for job in jobs.values() if job.get("status") == "running" and job.get("owner") != _BOOT]
        for job in stale:
            job.update(status="failed", error="interrupted", finished_at=store.utcnow_iso())
            job["states"] = {s: ("failed" if v in ("queued", "running") else v)
                             for s, v in (job.get("states") or {}).items()}
        if stale:
            _write_jobs(root, jobs)
        return jobs


def _write_jobs(root: Path, jobs: dict[str, dict[str, Any]]) -> None:
    _write(avatar_dir(root) / "jobs.json", {"jobs": jobs})


def _update_job(root: Path, job_id: str, **changes: Any) -> None:
    with _LOCK:
        jobs = _jobs(root)
        if job_id in jobs:
            jobs[job_id].update(changes)
            _write_jobs(root, jobs)


def _set_state(root: Path, job_id: str, state: str, value: str) -> None:
    with _LOCK:
        jobs = _jobs(root)
        if job_id in jobs:
            jobs[job_id].setdefault("states", {})[state] = value
            _write_jobs(root, jobs)


def _job_view(job: dict[str, Any]) -> dict[str, Any]:
    job_id = job["id"]
    return {
        "id": job_id,
        "kind": job.get("kind"),
        "status": job.get("status"),
        "candidates": [f"{ROUTE}/candidates/{job_id}/{n}" for n in range(len(job.get("candidate_media_ids") or []))],
        "states": dict(job.get("states") or {}),
        "error": job.get("error"),
        "started_at": job.get("started_at"),
        "finished_at": job.get("finished_at"),
    }


def _latest(jobs: dict[str, dict[str, Any]], kind: Optional[str] = None,
            status: Optional[str] = None) -> Optional[dict[str, Any]]:
    found = [j for j in jobs.values()
             if (kind is None or j.get("kind") == kind) and (status is None or j.get("status") == status)]
    return max(found, key=lambda j: str(j.get("started_at") or ""), default=None)


# --- Reads -------------------------------------------------------------------


def get_avatar(root: Path) -> dict[str, Any]:
    base = avatar_dir(root)
    latest = _latest(_jobs(root))
    has_portrait = (base / SQUARE_FILE).is_file()
    return {
        "portrait_url": f"{ROUTE}/portrait" if has_portrait else None,
        "states": {s: f"{ROUTE}/states/{s}" for s in STATES if (base / "states" / f"{s}.webp").is_file()},
        "job": _job_view(latest) if latest else None,
        "updated_at": _meta(root).get("updated_at") if has_portrait else None,
    }


def get_job(root: Path, job_id: str) -> Optional[dict[str, Any]]:
    job = _jobs(root).get(job_id)
    return _job_view(job) if job else None


def portrait_file(root: Path) -> Optional[Path]:
    path = avatar_dir(root) / SQUARE_FILE
    return path if path.is_file() else None


def state_file(root: Path, state: str) -> Optional[Path]:
    if state not in STATES:
        return None
    path = avatar_dir(root) / "states" / f"{state}.webp"
    return path if path.is_file() else None


def candidate_file(root: Path, job_id: str, n: int) -> Optional[Path]:
    job = _jobs(root).get(job_id)
    if job is None or not 0 <= n < len(job.get("candidate_media_ids") or []):
        return None
    path = avatar_dir(root) / "candidates" / job_id / f"{n}.jpg"
    return path if path.is_file() else None


# --- Jobs --------------------------------------------------------------------


def _start(root: Path, kind: str, target: Any, args: tuple, states: tuple[str, ...] = ()) -> dict[str, Any]:
    """Records a running job and starts its thread; AvatarBusy when one runs."""
    with _LOCK:
        jobs = _jobs(root)
        if _latest(jobs, status="running"):
            raise AvatarBusy("an avatar job is already running")
        job_id = store.new_id()
        jobs[job_id] = {
            "id": job_id, "kind": kind, "status": "running", "owner": _BOOT,
            "candidate_media_ids": [], "states": {s: "queued" for s in states},
            "error": None, "started_at": store.utcnow_iso(), "finished_at": None,
        }
        _prune(root, jobs)
        _write_jobs(root, jobs)
        threading.Thread(target=_guarded, args=(target, root, job_id, *args),
                         name=f"hermuse-avatar-{kind}-{job_id}", daemon=True).start()
        return _job_view(jobs[job_id])


def _prune(root: Path, jobs: dict[str, dict[str, Any]]) -> None:
    """Keeps the JOBS_KEPT most recent jobs (and their candidates)."""
    ordered = sorted(jobs.values(), key=lambda j: str(j.get("started_at") or ""), reverse=True)
    for job in ordered[JOBS_KEPT:]:
        jobs.pop(job["id"], None)
        shutil.rmtree(avatar_dir(root) / "candidates" / job["id"], ignore_errors=True)


def _guarded(target: Any, root: Path, job_id: str, *args: Any) -> None:
    try:
        target(root, job_id, *args)
    except Exception as exc:  # noqa: BLE001 - the job must end, whatever happened
        log.exception("hermuse avatar: job %s failed", job_id)
        _update_job(root, job_id, status="failed", error=str(exc) or type(exc).__name__,
                    finished_at=store.utcnow_iso())


def _ready_config(*, ffmpeg: bool = False) -> media.MediaConfig:
    config = media.load_config()
    if not config.configured:
        raise AvatarUnavailable("image generation is not configured on this server")
    if ffmpeg and media.ffmpeg_paths() is None:
        raise AvatarUnavailable(media.FFMPEG_MISSING)
    return config


def start_portrait(root: Path, description: str, count: int = 4) -> dict[str, Any]:
    description = description.strip()
    if not description or len(description) > DESCRIPTION_MAX:
        raise ValueError(f"description must be 1 to {DESCRIPTION_MAX} characters")
    if not 1 <= count <= 4:
        raise ValueError("count must be 1 to 4")
    config = _ready_config()
    return _start(root, "portrait", _run_portrait, (config, description, count))


def _run_portrait(root: Path, job_id: str, config: media.MediaConfig, description: str, count: int) -> None:
    try:
        results = media.Client(config).generate_images(portrait_prompt(description), count=count,
                                                       aspect_ratio="16:9")
    except media.MediaError as exc:
        _update_job(root, job_id, status="failed", error=str(exc), finished_at=store.utcnow_iso())
        return
    folder = avatar_dir(root) / "candidates" / job_id
    ids = []
    for n, (media_id, data, ext) in enumerate(results):
        store.atomic_write_bytes(folder / f"{n}.jpg", _jpeg(data, ext))
        ids.append(media_id)
    _update_job(root, job_id, status="done", candidate_media_ids=ids, finished_at=store.utcnow_iso())


def select(root: Path, candidate: int) -> dict[str, Any]:
    """Make candidate *candidate* of the latest finished portrait job the
    portrait; old animations go (they show the previous face)."""
    with _LOCK:
        jobs = _jobs(root)
        if _latest(jobs, status="running"):
            raise AvatarBusy("an avatar job is already running")
        job = _latest(jobs, kind="portrait", status="done")
        if job is None:
            raise LookupError("no finished portrait job")
        source = candidate_file(root, job["id"], candidate)
        if source is None:
            raise LookupError("candidate not found")
        data = source.read_bytes()
        base = avatar_dir(root)
        store.atomic_write_bytes(base / PORTRAIT_FILE, data)
        store.atomic_write_bytes(base / SQUARE_FILE, _square_jpeg(data, SQUARE_PX))
        for folder in ("states", "clips"):
            shutil.rmtree(base / folder, ignore_errors=True)
        _write_meta(root, portrait_media_id=job["candidate_media_ids"][candidate],
                    portrait_source=f"{job['id']}/{candidate}")
    return get_avatar(root)


def start_animate(root: Path, states: Optional[list[str]] = None) -> dict[str, Any]:
    wanted = tuple(dict.fromkeys(states if states is not None else STATES))
    if not wanted or any(s not in STATES for s in wanted):
        raise ValueError(f"states must be among {', '.join(STATES)}")
    with _LOCK:
        if _latest(_jobs(root), status="running"):
            raise AvatarBusy("an avatar job is already running")
        if not (avatar_dir(root) / PORTRAIT_FILE).is_file():
            raise NoPortrait("select a portrait first")
        config = _ready_config(ffmpeg=True)
        return _start(root, "animate", _run_animate, (config, wanted), states=wanted)


def _run_animate(root: Path, job_id: str, config: media.MediaConfig, states: tuple[str, ...]) -> None:
    client = media.Client(config)
    try:
        first_frame = _portrait_media_id(root, client)
    except media.MediaError as exc:
        for state in states:
            _set_state(root, job_id, state, "failed")
        _update_job(root, job_id, status="failed", error=f"portrait upload: {exc}", finished_at=store.utcnow_iso())
        return
    base = avatar_dir(root)
    errors = []
    done = 0
    for state in states:
        _set_state(root, job_id, state, "running")
        try:
            clip = client.generate_video(state_prompt(state), first_frame)
            store.atomic_write_bytes(base / "clips" / f"{state}.mp4", clip)
            export_loop(base / "clips" / f"{state}.mp4", base / "states" / f"{state}.webp")
        except (media.MediaError, ExportError) as exc:
            log.warning("hermuse avatar: %s clip failed: %s", state, exc)
            errors.append(f"{state}: {exc}")
            _set_state(root, job_id, state, "failed")
            continue
        done += 1
        _set_state(root, job_id, state, "done")
        _write_meta(root)
    _update_job(root, job_id, status="done" if done else "failed", error="; ".join(errors) or None,
                finished_at=store.utcnow_iso())


def _portrait_media_id(root: Path, client: media.Client) -> str:
    """The portrait's media id at the provider, uploaded again when the
    provider no longer knows it."""
    media_id = str(_meta(root).get("portrait_media_id") or "")
    if media_id and client.image_ready(media_id):
        return media_id
    data = (avatar_dir(root) / PORTRAIT_FILE).read_bytes()
    media_id = client.upload_image(data, "image/jpeg", PORTRAIT_FILE)
    _write_meta(root, portrait_media_id=media_id)
    return media_id


def clear(root: Path) -> None:
    """Back to a bundled portrait: everything generated goes."""
    with _LOCK:
        if _latest(_jobs(root), status="running"):
            raise AvatarBusy("an avatar job is already running")
        shutil.rmtree(avatar_dir(root), ignore_errors=True)


# --- Images and clips --------------------------------------------------------


def _jpeg(data: bytes, ext: str) -> bytes:
    if ext == ".jpg":
        return data
    from PIL import Image

    with Image.open(io.BytesIO(data)) as image:
        out = io.BytesIO()
        image.convert("RGB").save(out, "JPEG", quality=92)
        return out.getvalue()


def _square_jpeg(data: bytes, size: int) -> bytes:
    """Centre square of *data*, *size* px, as JPEG (the same region the clips keep)."""
    from PIL import Image

    with Image.open(io.BytesIO(data)) as image:
        rgb = image.convert("RGB")
    side = min(rgb.size)
    left, top = (rgb.width - side) // 2, (rgb.height - side) // 2
    square = rgb.crop((left, top, left + side, top + side)).resize((size, size), Image.Resampling.LANCZOS)
    out = io.BytesIO()
    square.save(out, "JPEG", quality=90)
    return out.getvalue()


def _duration(ffprobe: str, src: Path) -> float:
    result = subprocess.run(
        [ffprobe, "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=duration:format=duration",
         "-of", "json", str(src)],
        capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise ExportError(f"unreadable clip: {result.stderr.strip()[-300:]}")
    with contextlib.suppress(ValueError, TypeError, KeyError, IndexError):
        info = json.loads(result.stdout)
        for value in ((info.get("streams") or [{}])[0].get("duration"), info.get("format", {}).get("duration")):
            if value not in (None, "N/A"):
                return float(value)
    raise ExportError("clip without a duration")


def export_loop(src: Path, dest: Path) -> None:
    """*src* video → looping animated WebP *dest*: centre square, CLIP_PX,
    CLIP_FPS, played forward then backward (ping-pong), no audio."""
    tools = media.ffmpeg_paths()
    if tools is None:
        raise ExportError(media.FFMPEG_MISSING)
    ffmpeg, ffprobe = tools
    duration = _duration(ffprobe, src)
    if duration * CLIP_FPS < 3:
        raise ExportError(f"clip too short ({duration:.2f} s)")
    # Frames 0..n-1, then n-2..1: the loop turns at both ends without repeating
    # a frame, so the clip's last pose never jumps back to its first.
    graph = (
        f"[0:v]crop=w='min(iw,ih)':h='min(iw,ih)',scale={CLIP_PX}:{CLIP_PX}:flags=lanczos,"
        f"fps={CLIP_FPS},setsar=1,format=yuv420p,split=2[forward][back];"
        f"[back]trim=start_frame=1,reverse,trim=start_frame=1,setpts=PTS-STARTPTS[backward];"
        f"[forward][backward]concat=n=2:v=1:a=0[out]"
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp_", suffix=".webp", dir=str(dest.parent))
    os.close(fd)
    try:
        result = subprocess.run(
            [ffmpeg, "-nostdin", "-y", "-v", "error", "-i", str(src), "-filter_complex", graph,
             "-map", "[out]", "-an", "-c:v", "libwebp", "-lossless", "0", "-q:v", str(WEBP_QUALITY),
             "-compression_level", "6", "-preset", "picture", "-loop", "0", "-f", "webp", tmp],
            capture_output=True, text=True, timeout=EXPORT_TIMEOUT_S)
        if result.returncode != 0 or os.path.getsize(tmp) == 0:
            raise ExportError(f"ffmpeg failed: {result.stderr.strip()[-300:]}")
        os.replace(tmp, dest)
    except subprocess.TimeoutExpired as exc:
        raise ExportError("ffmpeg took too long") from exc
    finally:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
