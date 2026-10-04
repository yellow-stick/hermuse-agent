"""Image/video generation through the media provider the user runs
(ContentFlow: ``GET``/``POST /image`` and ``/video``).

Stdlib only (``urllib``), shared by the dashboard routes, the avatar jobs and
the Feed fallback in the agent process. The provider is server-wide: one
``hermuse/media.json`` (mode 0600) in the default profile's home, whatever
profile a request is scoped to; ``HERMUSE_MEDIA_ENDPOINT`` /
``HERMUSE_MEDIA_TOKEN`` override it.

Every generation is submitted once: an error (HTTP 4xx/5xx with
``{error, details}``, or a media item ``failed``) raises :class:`MediaError`
with the provider's message and is never resubmitted, because the credits may
already be spent. Requests to the provider are sent one at a time per process
(the service serialises them anyway). Signed result URLs expire: results are
downloaded at once.
"""

from __future__ import annotations

import base64
import contextlib
import dataclasses
import json
import logging
import os
import re
import shutil
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable, Optional

try:  # agent process: package hermes_plugins.hermuse
    from . import feed_images, store
except ImportError:  # dashboard backend / tests: plugin root on sys.path
    import feed_images  # type: ignore[no-redef]
    import store  # type: ignore[no-redef]

log = logging.getLogger(__name__)

PROVIDER = "contentflow"
CONFIG_FILE = "media.json"
DEFAULT_IMAGE_MODEL = "nano-banana-2-lite"
DEFAULT_VIDEO_MODEL = "Omni 1.1 Flash"
ENV_ENDPOINT = "HERMUSE_MEDIA_ENDPOINT"
ENV_TOKEN = "HERMUSE_MEDIA_TOKEN"

# Animation clips: image → video from a first frame, as the plan fixes them.
VIDEO_ASPECT = "16:9"
VIDEO_DURATION_S = 4
VIDEO_RESOLUTION = "720p"

REQUEST_TIMEOUT_S = 180.0  # a generation waits its turn behind others (~15 s each)
STATUS_TIMEOUT_S = 30.0
POLL_S = 5.0
VIDEO_TIMEOUT_S = 600.0
POLL_ERRORS_MAX = 3  # polling is free and idempotent; submissions are never repeated
MAX_IMAGE_BYTES = 25 * 1024 * 1024
MAX_VIDEO_BYTES = 200 * 1024 * 1024

FFMPEG_MISSING = "ffmpeg is not installed on this server: animations need ffmpeg and ffprobe"

_REQUEST_LOCK = threading.Lock()
_UNSET: Any = object()


class MediaError(Exception):
    """The provider refused or failed; ``str()`` is its own message."""


# --- Config ------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class MediaConfig:
    endpoint: str = ""
    token: str = ""
    image_model: str = DEFAULT_IMAGE_MODEL
    video_model: str = DEFAULT_VIDEO_MODEL
    feed_fallback: bool = True
    from_env: bool = False

    @property
    def configured(self) -> bool:
        return bool(self.endpoint)

    def view(self) -> dict[str, Any]:
        """The REST shape: the token is write-only."""
        return {
            "provider": PROVIDER,
            "endpoint": self.endpoint,
            "has_token": bool(self.token),
            "image_model": self.image_model,
            "video_model": self.video_model,
            "feed_fallback": self.feed_fallback,
            "from_env": self.from_env,
        }


def default_home() -> Path:
    """Home of the default profile, whatever profile the caller is scoped to
    (Hermes' root for profile-level state: ``<root>`` for
    ``HERMES_HOME=<root>/profiles/<name>``)."""
    try:
        from hermes_constants import get_default_hermes_root
    except ImportError:  # standalone use
        return Path(os.environ.get("HERMES_HOME", "").strip() or Path.home() / ".hermes").expanduser()
    return get_default_hermes_root()


def config_path() -> Path:
    return store.hermuse_root(default_home()) / CONFIG_FILE


def normalize_endpoint(endpoint: str) -> str:
    """``http(s)://host[:port][/path]`` without a trailing slash; "" disables."""
    endpoint = endpoint.strip().rstrip("/")
    if not endpoint:
        return ""
    parsed = urllib.parse.urlsplit(endpoint)
    if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.query or parsed.fragment:
        raise ValueError("endpoint must be an http(s) URL")
    return endpoint


def _stored() -> dict[str, Any]:
    try:
        data = json.loads(config_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def load_config() -> MediaConfig:
    data = _stored()
    env_endpoint = os.environ.get(ENV_ENDPOINT, "").strip()
    env_token = os.environ.get(ENV_TOKEN, "").strip()
    endpoint = str(data.get("endpoint") or "")
    with contextlib.suppress(ValueError):
        endpoint = normalize_endpoint(env_endpoint) if env_endpoint else normalize_endpoint(endpoint)
    feed_fallback = data.get("feed_fallback")
    return MediaConfig(
        endpoint=endpoint,
        token=env_token or str(data.get("token") or ""),
        image_model=str(data.get("image_model") or DEFAULT_IMAGE_MODEL),
        video_model=str(data.get("video_model") or DEFAULT_VIDEO_MODEL),
        feed_fallback=feed_fallback if isinstance(feed_fallback, bool) else True,
        from_env=bool(env_endpoint or env_token),
    )


def save_config(
    *,
    endpoint: str,
    token: Optional[str] = _UNSET,
    image_model: Optional[str] = None,
    video_model: Optional[str] = None,
    feed_fallback: Optional[bool] = None,
) -> MediaConfig:
    """Write the stored config: *token* omitted keeps it, "" clears it;
    models and *feed_fallback* omitted keep theirs."""
    data = _stored()
    data["provider"] = PROVIDER
    data["endpoint"] = normalize_endpoint(endpoint)
    if token is not _UNSET and token is not None:
        data["token"] = token.strip()
    if image_model is not None:
        data["image_model"] = image_model.strip() or DEFAULT_IMAGE_MODEL
    if video_model is not None:
        data["video_model"] = video_model.strip() or DEFAULT_VIDEO_MODEL
    if feed_fallback is not None:
        data["feed_fallback"] = bool(feed_fallback)
    path = config_path()
    store.atomic_write_text(path, json.dumps(data, indent=2, sort_keys=True) + "\n")
    os.chmod(path, 0o600)
    return load_config()


# --- ffmpeg ------------------------------------------------------------------


def ffmpeg_paths() -> Optional[tuple[str, str]]:
    """``(ffmpeg, ffprobe)`` when both are on PATH."""
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    return (ffmpeg, ffprobe) if ffmpeg and ffprobe else None


# --- Provider client ---------------------------------------------------------


def _error_message(status: int, raw: bytes) -> str:
    try:
        body = json.loads(raw.decode("utf-8", "replace"))
    except ValueError:
        text = raw.decode("utf-8", "replace").strip()
        return f"HTTP {status}: {text[:300]}" if text else f"HTTP {status}"
    if not isinstance(body, dict):
        return f"HTTP {status}"
    message = str(body.get("error") or f"HTTP {status}")
    details = body.get("details")
    if isinstance(details, dict):
        parts = [f"{k}: {v}" for k, v in details.items() if v not in (None, "", [], {})]
        if parts:
            message += f" ({', '.join(parts)})"
    elif details:
        message += f" ({str(details)[:300]})"
    return message


def _item_error(item: dict[str, Any], body: dict[str, Any]) -> str:
    error = item.get("error") or body.get("error")
    return str(error) if error else f"generation {item.get('status') or 'failed'}"


class Client:
    """One provider endpoint. Not retried: see the module docstring."""

    def __init__(self, config: MediaConfig) -> None:
        if not config.configured:
            raise MediaError("image generation is not configured")
        self.config = config

    def _request(self, method: str, path: str, body: Optional[dict[str, Any]] = None,
                 timeout: float = REQUEST_TIMEOUT_S) -> dict[str, Any]:
        # No Origin header: the service refuses browser-originated calls.
        headers = {"Accept": "application/json"}
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if self.config.token:
            headers["Authorization"] = f"Bearer {self.config.token}"
        request = urllib.request.Request(self.config.endpoint + path, data=data, headers=headers, method=method)
        with _REQUEST_LOCK:
            try:
                with urllib.request.urlopen(request, timeout=timeout) as response:
                    raw = response.read()
            except urllib.error.HTTPError as exc:
                raise MediaError(_error_message(exc.code, exc.read())) from exc
            except (urllib.error.URLError, OSError) as exc:
                reason = getattr(exc, "reason", exc)
                raise MediaError(f"cannot reach {self.config.endpoint}: {reason}") from exc
        try:
            parsed = json.loads(raw.decode("utf-8"))
        except ValueError as exc:
            raise MediaError("the media provider answered with something that is not JSON") from exc
        if not isinstance(parsed, dict):
            raise MediaError("unexpected answer from the media provider")
        return parsed

    def catalogue(self, kind: str) -> dict[str, Any]:
        return self._request("GET", f"/{kind}", timeout=STATUS_TIMEOUT_S)

    def generate_images(self, prompt: str, *, count: int = 1,
                        aspect_ratio: str = "16:9") -> list[tuple[str, bytes, str]]:
        """``[(media id, bytes, ext)]`` of the successful results (at least one)."""
        body = self._request("POST", "/image", {
            "prompt": prompt, "model": self.config.image_model,
            "aspect_ratio": aspect_ratio, "count": count,
        })
        out: list[tuple[str, bytes, str]] = []
        errors: list[str] = []
        for item in _media(body):
            if item.get("status") != "success" or not item.get("url"):
                errors.append(_item_error(item, body))
                continue
            try:
                data, ext = download_image(str(item["url"]))
            except MediaError as exc:
                errors.append(str(exc))
                continue
            out.append((str(item.get("id") or ""), data, ext))
        if not out:
            raise MediaError(errors[0] if errors else str(body.get("error") or "no image was generated"))
        return out

    def upload_image(self, data: bytes, mime_type: str, filename: str) -> str:
        """Media id of *data* uploaded as a reference image."""
        body = self._request("POST", "/image", {
            "action": "upload", "data": base64.b64encode(data).decode("ascii"),
            "mime_type": mime_type, "filename": filename,
        })
        items = _media(body)
        if not items or not items[0].get("id") or items[0].get("status") in ("failed", "canceled"):
            raise MediaError(_item_error(items[0], body) if items else "upload returned no media")
        return str(items[0]["id"])

    def image_ready(self, media_id: str) -> bool:
        """True when the provider still knows *media_id* as a finished image."""
        try:
            items = _media(self._request("POST", "/image", {"action": "status", "media_id": media_id},
                                         timeout=STATUS_TIMEOUT_S))
        except MediaError:
            return False
        return bool(items) and items[0].get("status") == "success"

    def submit_video(self, prompt: str, first_frame: str) -> str:
        """Media id of a scheduled image → video clip."""
        body = self._request("POST", "/video", {
            "prompt": prompt, "model": self.config.video_model,
            "aspect_ratio": VIDEO_ASPECT, "duration": VIDEO_DURATION_S,
            "count": 1, "first_frame": first_frame,
        })
        items = _media(body)
        if not items or not items[0].get("id"):
            raise MediaError(str(body.get("error") or "the video was not scheduled"))
        if items[0].get("status") in ("failed", "canceled"):
            raise MediaError(_item_error(items[0], body))
        return str(items[0]["id"])

    def wait_video(self, media_id: str, *, timeout: float = VIDEO_TIMEOUT_S,
                   sleep: Callable[[float], None] = time.sleep) -> str:
        """Signed URL of the finished clip; polls ``status`` every POLL_S."""
        deadline = time.monotonic() + timeout
        poll_errors = 0
        while True:
            try:
                body = self._request("POST", "/video", {"action": "status", "media_id": media_id},
                                     timeout=STATUS_TIMEOUT_S)
                poll_errors = 0
            except MediaError:
                poll_errors += 1
                if poll_errors >= POLL_ERRORS_MAX:
                    raise
                body = {}
            items = _media(body)
            if items:
                status = items[0].get("status")
                if status == "success" and items[0].get("url"):
                    return str(items[0]["url"])
                if status in ("failed", "canceled"):
                    raise MediaError(_item_error(items[0], body))
            if time.monotonic() >= deadline:
                raise MediaError("the video was not ready in time")
            sleep(POLL_S)

    def generate_video(self, prompt: str, first_frame: str) -> bytes:
        """MP4 bytes of one clip: submitted once, polled, downloaded."""
        url = self.wait_video(self.submit_video(prompt, first_frame))
        return download(url, MAX_VIDEO_BYTES)


def _media(body: dict[str, Any]) -> list[dict[str, Any]]:
    items = body.get("media")
    return [item for item in items if isinstance(item, dict)] if isinstance(items, list) else []


def download(url: str, limit: int) -> bytes:
    """Bytes of a provider result URL (signed, expiring: fetched at once)."""
    if urllib.parse.urlsplit(url).scheme not in ("http", "https"):
        raise MediaError("the media provider returned an unusable URL")
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=REQUEST_TIMEOUT_S) as response:
            data = response.read(limit + 1)
    except (urllib.error.URLError, OSError) as exc:
        raise MediaError(f"could not download the result: {getattr(exc, 'reason', exc)}") from exc
    if len(data) > limit:
        raise MediaError("the result is too large")
    return data


def download_image(url: str) -> tuple[bytes, str]:
    data = download(url, MAX_IMAGE_BYTES)
    ext = feed_images.sniff_image(data)
    if not ext:
        raise MediaError("the result is not an image")
    return data, ext


# --- Status ------------------------------------------------------------------


def _model_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", name.lower())


def video_cost(catalogue: dict[str, Any], model: str) -> Optional[int]:
    """Credits per animation clip with *model*: its available image → video
    usage (first frame only) of VIDEO_DURATION_S at VIDEO_RESOLUTION."""
    wanted = _model_key(model)
    for entry in catalogue.get("models") or []:
        if not isinstance(entry, dict):
            continue
        names = [entry.get("id"), entry.get("name"), *(entry.get("aliases") or [])]
        if wanted not in {_model_key(str(n)) for n in names if n}:
            continue
        for usage in entry.get("usages") or []:
            if not isinstance(usage, dict) or not usage.get("available"):
                continue
            sets = usage.get("feature_sets") or []
            resolutions = usage.get("resolutions") or [VIDEO_RESOLUTION]
            if ([1, 5] in sets and usage.get("duration") == VIDEO_DURATION_S
                    and VIDEO_RESOLUTION in resolutions and isinstance(usage.get("credits"), int)):
                return usage["credits"]
        return None
    return None


def status(config: Optional[MediaConfig] = None) -> dict[str, Any]:
    """``{configured, reachable, credits, video_cost, error}``; never raises."""
    config = config or load_config()
    missing_ffmpeg = None if ffmpeg_paths() else FFMPEG_MISSING
    out: dict[str, Any] = {"configured": config.configured, "reachable": False,
                           "credits": None, "video_cost": None, "error": missing_ffmpeg}
    if not config.configured:
        return out
    try:
        catalogue = Client(config).catalogue("video")
    except MediaError as exc:
        out["error"] = str(exc)
        return out
    credits = catalogue.get("credits")
    out.update(reachable=True, credits=credits if isinstance(credits, int) else None,
               video_cost=video_cost(catalogue, config.video_model))
    if out["video_cost"] is None and not missing_ffmpeg:
        out["error"] = f"the video model {config.video_model!r} has no {VIDEO_DURATION_S} s image animation available"
    return out


# --- Feed fallback -----------------------------------------------------------

FEED_PROMPT = (
    "Wordless editorial illustration for a short article titled \"{title}\". {why} "
    "Evoke the idea with one scene or visual metaphor, not a diagram, chart or infographic. "
    "Clean modern editorial style, rich harmonious colours, wide composition. "
    "No text anywhere in the image: no words, letters, numbers, labels or captions. "
    "No logos, no watermark, no real person's likeness."
)


def illustrate_feed_post(root: Path, post: dict[str, Any]) -> Optional[threading.Thread]:
    """Starts generating an illustration for a post stored without an image,
    when the provider is configured and the fallback on; returns the thread
    (None when nothing starts). The post is left untouched on failure."""
    if post.get("image_url"):
        return None
    config = load_config()
    if not (config.configured and config.feed_fallback):
        return None
    prompt = FEED_PROMPT.format(title=str(post.get("title") or "").strip(),
                                why=str(post.get("why") or "").strip())
    thread = threading.Thread(target=_illustrate, args=(config, root, str(post["id"]), prompt),
                              name=f"hermuse-feed-illustration-{post['id']}", daemon=True)
    thread.start()
    return thread


def _illustrate(config: MediaConfig, root: Path, post_id: str, prompt: str) -> None:
    try:
        _, data, ext = Client(config).generate_images(prompt, count=1, aspect_ratio="16:9")[0]
        if store.attach_feed_image(root, post_id, (data, ext)) is None:
            log.info("hermuse feed: post %s is gone, illustration dropped", post_id)
    except MediaError as exc:
        log.warning("hermuse feed: no illustration for post %s: %s", post_id, exc)
    except Exception:  # noqa: BLE001 - a background thread must not die silently
        log.exception("hermuse feed: illustration for post %s failed", post_id)
