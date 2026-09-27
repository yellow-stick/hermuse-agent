#!/usr/bin/env python3
"""screend: the Hermuse computer's screen service (runs inside the container).

Streams X display ``:1`` as JPEG frames over WebSocket and injects the viewer's
input, so Hermuse UIs only paint JPEGs and send small JSON messages:

* ``GET /stream?fps=1..10`` (WebSocket): text ``{"t":"geometry","w","h","mode"}``
  on connect and on every change, then binary JPEG frames (sent only when the
  picture changed). Accepts ``move|down|up|wheel|key|text`` messages whose
  coordinates are in frame space.
* ``GET /thumbnail``: the latest frame re-encoded 640 px wide.
* ``POST /mode`` ``{"mode": "browser"|"desktop"}``: crop to Chromium's window
  or show the whole desktop (204; anything else 400).

Every request must carry ``?token=<SCREEND_TOKEN>`` (401 otherwise).

Capture is Pillow's XCB screen grab (X ``GetImage`` in C, ~4x cheaper than
python-xlib's pure-Python reply parsing) + Pillow's JPEG encoder: no ffmpeg.
"""

from __future__ import annotations

import asyncio
import hmac
import io
import json
import os
import sys
import time
from typing import Optional

from aiohttp import WSMsgType, web
from PIL import Image
from Xlib import X, XK
from Xlib import display as xdisplay
from Xlib.error import XError
from Xlib.ext import xtest

DISPLAY = os.environ.get("DISPLAY", ":1")
TOKEN = os.environ.get("SCREEND_TOKEN", "")
HOST, PORT = "0.0.0.0", 8765

FPS_DEFAULT, FPS_MIN, FPS_MAX = 5, 1, 10
IDLE_STOP_S = 10.0  # stop capturing this long after the last client/thumbnail
CROP_REFRESH_S = 2.0
TICK_S = 0.5
THUMB_WIDTH, THUMB_QUALITY = 640, 70
FRAME_QUALITY = 75
MIN_CROP = 64
MAX_WHEEL_STEPS = 20
MAX_TEXT = 4096
MODES = ("browser", "desktop")
BUTTONS = (1, 2, 3)

Crop = tuple[int, int, int, int]


def log(message: str) -> None:
    print(f"screend: {message}", file=sys.stderr, flush=True)


async def run(*args: str) -> tuple[int, str]:
    proc = await asyncio.create_subprocess_exec(
        *args, stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL)
    out, _ = await proc.communicate()
    return proc.returncode or 0, out.decode("utf-8", "replace")


def grab_screen() -> tuple[tuple[int, int], bytes]:
    """The whole X screen as raw BGRX pixels.

    ``Image.core.grabscreen_x11`` is what ``ImageGrab.grab(xdisplay=...)`` runs,
    minus its RGB conversion: the raw bytes let an unchanged screen skip the
    conversion and the JPEG encoding. It opens its own X connection per call,
    so it is safe off the event loop's thread.
    """
    size, data = Image.core.grabscreen_x11(DISPLAY)
    return (int(size[0]), int(size[1])), data


def encode_frame(size: tuple[int, int], data: bytes, crop: Crop) -> bytes:
    """*crop* of a :func:`grab_screen` result as a JPEG."""
    x, y, w, h = crop
    image = Image.frombuffer("RGB", size, data, "raw", "BGRX", size[0] * 4, 1)
    out = io.BytesIO()
    image.crop((x, y, x + w, y + h)).save(out, "JPEG", quality=FRAME_QUALITY)
    return out.getvalue()


def thumbnail_jpeg(frame: bytes) -> bytes:
    with Image.open(io.BytesIO(frame)) as image:
        rgb = image.convert("RGB")
    height = max(1, round(rgb.height * THUMB_WIDTH / rgb.width))
    out = io.BytesIO()
    rgb.resize((THUMB_WIDTH, height), Image.Resampling.BILINEAR).save(
        out, "JPEG", quality=THUMB_QUALITY)
    return out.getvalue()


class Client:
    """One /stream socket: latest-frame slot (slow viewers drop frames) + ordered text."""

    def __init__(self, ws: web.WebSocketResponse, fps: int) -> None:
        self.ws = ws
        self.fps = fps
        self.texts: list[str] = []
        self.frame: Optional[bytes] = None
        self.wake = asyncio.Event()
        self.keys: set[int] = set()  # keycodes this viewer holds down
        self.buttons: set[int] = set()

    def push_text(self, text: str) -> None:
        self.texts.append(text)
        self.wake.set()

    def push_frame(self, frame: bytes) -> None:
        self.frame = frame
        self.wake.set()

    async def pump(self) -> None:
        while not self.ws.closed:
            await self.wake.wait()
            self.wake.clear()
            while self.texts:
                await self.ws.send_str(self.texts.pop(0))
            frame, self.frame = self.frame, None
            if frame is not None:
                await self.ws.send_bytes(frame)


class Screen:
    def __init__(self) -> None:
        self.display = xdisplay.Display(DISPLAY)
        screen = self.display.screen()
        self.full: Crop = (0, 0, screen.width_in_pixels, screen.height_in_pixels)
        self.mode = "browser"
        self.crop: Crop = self.full
        self.clients: set[Client] = set()
        self.latest: Optional[bytes] = None
        self.capture: Optional[asyncio.Task] = None
        self.capture_key: Optional[tuple[Crop, int]] = None
        self.last_thumbnail = float("-inf")
        self.capture_lock = asyncio.Lock()
        self.inputs: asyncio.Queue = asyncio.Queue()

    # --- geometry --------------------------------------------------------

    def geometry_message(self) -> str:
        _, _, w, h = self.crop
        return json.dumps({"t": "geometry", "w": w, "h": h, "mode": self.mode})

    def clamp(self, rect: Optional[Crop]) -> Crop:
        if rect is None:
            return self.full
        _, _, screen_w, screen_h = self.full
        x, y, w, h = rect
        x, y = min(max(0, x), screen_w - 1), min(max(0, y), screen_h - 1)
        w, h = min(w, screen_w - x), min(h, screen_h - y)
        if w < MIN_CROP or h < MIN_CROP:
            return self.full
        return (x, y, w, h)

    async def chromium_window(self) -> Optional[Crop]:
        """Geometry of the largest visible Chromium window, or None."""
        ids: list[str] = []
        for window_class in ("chromium", "Chromium"):
            _, out = await run("xdotool", "search", "--onlyvisible", "--class", window_class)
            ids = out.split()
            if ids:
                break
        best: Optional[Crop] = None
        for window_id in ids:
            rect = self.window_rect(int(window_id))
            if rect is not None and (best is None or rect[2] * rect[3] > best[2] * best[3]):
                best = rect
        return best

    def window_rect(self, window_id: int) -> Optional[Crop]:
        # `xdotool getwindowgeometry` counts the WM frame offset twice under
        # xfwm4 (Y 24 px too low): ask the server for the absolute origin.
        try:
            window = self.display.create_resource_object("window", window_id)
            geometry = window.get_geometry()
            origin = self.display.screen().root.translate_coords(window, 0, 0)
        except XError:
            return None  # closed meanwhile
        return (origin.x, origin.y, geometry.width, geometry.height)

    async def refresh_crop(self, announce: bool = False) -> None:
        crop = self.full if self.mode == "desktop" else self.clamp(await self.chromium_window())
        if crop != self.crop:
            async with self.capture_lock:
                # Frames of the old crop must never follow the new geometry;
                # sync_capture() starts the new capture.
                await self._stop_capture()
                self.crop = crop
                self.latest = None
                for client in self.clients:
                    client.frame = None
            announce = True
        if announce:
            message = self.geometry_message()
            for client in self.clients:
                client.push_text(message)

    async def set_mode(self, mode: str) -> None:
        changed = mode != self.mode
        self.mode = mode
        await self.refresh_crop(announce=changed)
        await self.sync_capture()

    # --- capture ---------------------------------------------------------

    def capture_wanted(self) -> bool:
        return bool(self.clients) or time.monotonic() - self.last_thumbnail < IDLE_STOP_S

    def capture_running(self) -> bool:
        return self.capture is not None and not self.capture.done()

    def fps(self) -> int:
        return max((client.fps for client in self.clients), default=FPS_DEFAULT)

    async def sync_capture(self) -> None:
        """Start, restart (crop or fps changed) or stop the shared capture loop."""
        async with self.capture_lock:
            if not self.capture_wanted():
                if self.capture is not None:
                    await self._stop_capture()
                    self.latest = None
                return
            key = (self.crop, self.fps())
            if self.capture_running() and self.capture_key == key:
                return
            await self._stop_capture()
            self.capture_key = key
            self.capture = asyncio.create_task(self._capture_loop(*key))

    async def _stop_capture(self) -> None:
        # Cancelling interrupts the loop at an await, before it could publish
        # a frame of the old crop.
        task, self.capture, self.capture_key = self.capture, None, None
        if task is not None:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    async def _capture_loop(self, crop: Crop, fps: int) -> None:
        interval = 1.0 / fps
        previous: Optional[bytes] = None  # raw pixels of the last grab
        failing = False
        while True:
            started = time.monotonic()
            try:
                size, raw = await asyncio.to_thread(grab_screen)
                if raw != previous:  # an unchanged screen costs one grab, no encoding
                    previous = raw
                    self.publish(await asyncio.to_thread(encode_frame, size, raw, crop))
                failing = False
            except (OSError, ValueError) as exc:  # X unreachable: retry, log once per outage
                if not failing:
                    log(f"capture failed: {exc!r}")
                failing = True
            await asyncio.sleep(max(0.0, interval - (time.monotonic() - started)))

    def publish(self, frame: bytes) -> None:
        if frame == self.latest:
            return  # nothing moved inside the crop: send nothing
        self.latest = frame
        for client in self.clients:
            client.push_frame(frame)

    async def grab_once(self) -> Optional[bytes]:
        crop = self.crop
        try:
            size, raw = await asyncio.to_thread(grab_screen)
            return await asyncio.to_thread(encode_frame, size, raw, crop)
        except (OSError, ValueError) as exc:
            log(f"grab failed: {exc!r}")
            return None

    async def supervise(self) -> None:
        next_crop = 0.0
        while True:
            try:
                now = time.monotonic()
                if self.capture_wanted() and self.mode == "browser" and now >= next_crop:
                    next_crop = now + CROP_REFRESH_S
                    await self.refresh_crop()
                await self.sync_capture()
            except Exception as exc:  # noqa: BLE001 — keep serving
                log(f"supervisor: {exc!r}")
            await asyncio.sleep(TICK_S)

    # --- input -----------------------------------------------------------

    def enqueue(self, client: Client, message: dict) -> None:
        self.inputs.put_nowait((client, message))

    async def input_worker(self) -> None:
        # One ordered queue: typed text (xdotool) must not overtake later keys.
        while True:
            client, message = await self.inputs.get()
            try:
                await self._apply(client, message)
            except Exception as exc:  # noqa: BLE001 — a bad message must not stop input
                log(f"input {message.get('t')!r}: {exc!r}")

    def _point(self, message: dict) -> tuple[int, int]:
        x0, y0, w, h = self.crop
        x = min(max(int(float(message.get("x", 0))), 0), w - 1)
        y = min(max(int(float(message.get("y", 0))), 0), h - 1)
        return x0 + x, y0 + y

    def _fake(self, event_type: int, detail: int = 0, x: int = 0, y: int = 0) -> None:
        xtest.fake_input(self.display, event_type, detail, x=x, y=y)

    async def _apply(self, client: Client, message: dict) -> None:
        kind = message.get("t")
        if kind == "move":
            x, y = self._point(message)
            self._fake(X.MotionNotify, x=x, y=y)
        elif kind in ("down", "up"):
            button = int(message.get("b", 1))
            if button not in BUTTONS:
                return
            x, y = self._point(message)
            self._fake(X.MotionNotify, x=x, y=y)
            if kind == "down":
                self._fake(X.ButtonPress, button)
                client.buttons.add(button)
            else:
                self._fake(X.ButtonRelease, button)
                client.buttons.discard(button)
        elif kind == "wheel":
            dy = int(float(message.get("dy", 0)))
            x, y = self._point(message)
            self._fake(X.MotionNotify, x=x, y=y)
            button = 5 if dy > 0 else 4
            for _ in range(min(abs(dy), MAX_WHEEL_STEPS)):
                self._fake(X.ButtonPress, button)
                self._fake(X.ButtonRelease, button)
        elif kind == "key":
            name, action = message.get("k"), message.get("a")
            keysym = XK.string_to_keysym(name) if isinstance(name, str) else 0
            keycode = self.display.keysym_to_keycode(keysym) if keysym else 0
            if not keycode or action not in ("down", "up"):
                return
            if action == "down":
                self._fake(X.KeyPress, keycode)
                client.keys.add(keycode)
            else:
                self._fake(X.KeyRelease, keycode)
                client.keys.discard(keycode)
        elif kind == "text":
            text = message.get("s")
            if isinstance(text, str) and text:
                # Non-ASCII characters need a temporary keymap entry; with no
                # delay Chromium can read the key before the remap lands (é, 日
                # were dropped). ASCII is in the keymap: type it at once.
                delay = "0" if text.isascii() else "12"
                await run("xdotool", "type", "--delay", delay, "--", text[:MAX_TEXT])
            return
        elif kind == "release_all":  # internal: a viewer left mid-press
            for keycode in client.keys:
                self._fake(X.KeyRelease, keycode)
            for button in client.buttons:
                self._fake(X.ButtonRelease, button)
            client.keys.clear()
            client.buttons.clear()
        else:
            return
        self.display.sync()


def make_app(screen: Screen) -> web.Application:
    @web.middleware
    async def require_token(request: web.Request, handler):
        supplied = request.query.get("token", "")
        if not hmac.compare_digest(supplied.encode(), TOKEN.encode()):
            raise web.HTTPUnauthorized(text="missing or wrong token")
        return await handler(request)

    async def stream(request: web.Request) -> web.WebSocketResponse:
        try:
            fps = int(request.query.get("fps", FPS_DEFAULT))
        except ValueError:
            fps = FPS_DEFAULT
        fps = min(max(fps, FPS_MIN), FPS_MAX)
        ws = web.WebSocketResponse(heartbeat=30, compress=False)
        await ws.prepare(request)
        await screen.refresh_crop()
        client = Client(ws, fps)
        screen.clients.add(client)
        pump = asyncio.create_task(client.pump())
        try:
            client.push_text(screen.geometry_message())
            if screen.latest is not None:
                client.push_frame(screen.latest)
            await screen.sync_capture()
            async for msg in ws:
                if msg.type != WSMsgType.TEXT:
                    continue
                try:
                    message = json.loads(msg.data)
                except ValueError:
                    continue
                if isinstance(message, dict) and message.get("t") in (
                        "move", "down", "up", "wheel", "key", "text"):
                    screen.enqueue(client, message)
        finally:
            screen.clients.discard(client)
            pump.cancel()
            await asyncio.gather(pump, return_exceptions=True)
            screen.enqueue(client, {"t": "release_all"})
            await screen.sync_capture()
        return ws

    async def thumbnail(request: web.Request) -> web.Response:
        screen.last_thumbnail = time.monotonic()
        if not screen.capture_running():
            await screen.refresh_crop()
            await screen.sync_capture()
        frame = screen.latest or await screen.grab_once()
        if frame is None:
            raise web.HTTPServiceUnavailable(text="no frame captured")
        body = await asyncio.to_thread(thumbnail_jpeg, frame)
        return web.Response(body=body, content_type="image/jpeg",
                            headers={"Cache-Control": "no-store"})

    async def mode(request: web.Request) -> web.Response:
        try:
            body = await request.json()
        except ValueError:
            body = None
        value = body.get("mode") if isinstance(body, dict) else None
        if value not in MODES:
            raise web.HTTPBadRequest(text='mode must be "browser" or "desktop"')
        await screen.set_mode(value)
        return web.Response(status=204)

    async def background(app: web.Application):
        tasks = [asyncio.create_task(screen.supervise()),
                 asyncio.create_task(screen.input_worker())]
        yield
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await screen._stop_capture()

    app = web.Application(middlewares=[require_token])
    app.router.add_get("/stream", stream)
    app.router.add_get("/thumbnail", thumbnail)
    app.router.add_post("/mode", mode)
    app.cleanup_ctx.append(background)
    return app


def main() -> None:
    if not TOKEN:
        log("SCREEND_TOKEN is required")
        sys.exit(2)
    web.run_app(make_app(Screen()), host=HOST, port=PORT, print=None, access_log=None)


if __name__ == "__main__":
    main()
