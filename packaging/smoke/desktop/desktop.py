#!/usr/bin/env python3
"""GUI automation, protocol probes and result files of the macOS and Windows
release smoke (stdlib only; sourced by nothing, run by macos.sh / windows.ps1).

The smoke runs on the GitHub-hosted runner itself, as its desktop user, and
drives the INSTALLED app like a user: full-screen screenshots, text located by
OCR (ImageMagick + Tesseract, the same pipeline as guest/gui.sh) and clicked
with real pointer events (Quartz events on macOS, SendInput on Windows). The
probes talk to the stack the app prepared exactly like the app does: the
loopback backend it supervises (dashboard REST with the
``X-Hermes-Session-Token`` header) and the CLIProxy management API. The
backend is the ``hermes serve`` process whose environment carries
``HERMES_DESKTOP=1`` and the session token the app minted, read from the
process itself (KERN_PROCARGS2 on macOS, its PEB on Windows); secrets are
never printed.

  desktop.py shot <png>                        full-screen PNG
  desktop.py locate <png> <phrase> [--mode line|any|filled]
                                               screen point "x y" of the phrase
  desktop.py click <phrase> --shots DIR [--timeout S] [--mode line|any|filled]
                                               wait for the phrase, click it; prints the shot
  desktop.py wait-text <phrase> --shots DIR [--timeout S] [--mode line|any]
                                               prints the shot that shows the phrase
  desktop.py window <title> [--timeout S]      "x y width height" of a visible window
  desktop.py maximize <title> | close <title>  window management like a user
  desktop.py rail <n|last> <title>             click the n-th item of the app's icon rail
  desktop.py scroll up|down <notches> <title>  mouse wheel over the window
  desktop.py type <text> | key return|escape|tab
  desktop.py backend                           the app-supervised backend and /api/status
  desktop.py rest METHOD PATH [--body JSON]    authenticated REST call to that backend
  desktop.py cliproxy --config PATH --expect-exe PATH
                                               bridge process + management API 401/200
  desktop.py processes                         the user's processes (pid, ppid, exe, argv)
  desktop.py dpapi roundtrip | dpapi decrypt <file>   (Windows) DPAPI CurrentUser
  desktop.py result check <out> <id> <criterion> <name> <status> <detail> [evidence...]
  desktop.py result finalize <out> --runner R --format F --scenario S --run ID --expect ID=CRITERION...

A probe prints one JSON object and exits 0 when its check passed, 1 when it
failed, 2 on usage. Result files follow packaging/smoke/linux.sh:
results/<id>.json = {schema, id, criterion, guest, format, scenario, run,
status, checks[], gui_proof[]}, status pass | fail | manual-gate |
skipped-missing-prereq.
"""

from __future__ import annotations

import argparse
import ctypes
import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Optional

IS_MAC = sys.platform == "darwin"
IS_WIN = os.name == "nt"

TESSERACT = shutil.which("tesseract") or (
    os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "Tesseract-OCR", "tesseract.exe")
    if IS_WIN else "tesseract")
MAGICK = shutil.which("magick") or "magick"
TMP = Path(tempfile.mkdtemp(prefix="hermuse-gui-"))


def emit(payload: dict[str, Any], ok: bool) -> None:
    payload["ok"] = ok
    print(json.dumps(payload, indent=2, sort_keys=True))
    sys.exit(0 if ok else 1)


def run(cmd: list[str], timeout: float = 120) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def slug(text: str) -> str:
    return re.sub(r"-+", "-", re.sub(r"[^A-Za-z0-9._-]", "-", text))[:60]


# --- native input and windows ------------------------------------------------

if IS_WIN:
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    user32.SetProcessDPIAware()

    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                    ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                    ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

    class _INPUTUNION(ctypes.Union):
        _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT), ("pad", ctypes.c_byte * 32)]

    class INPUT(ctypes.Structure):
        _fields_ = [("type", wintypes.DWORD), ("u", _INPUTUNION)]

    def _send(*inputs: INPUT) -> None:
        array = (INPUT * len(inputs))(*inputs)
        if user32.SendInput(len(inputs), array, ctypes.sizeof(INPUT)) != len(inputs):
            raise OSError(ctypes.get_last_error(), "SendInput")

    def _mouse(flags: int, data: int = 0) -> INPUT:
        return INPUT(type=0, u=_INPUTUNION(mi=MOUSEINPUT(0, 0, data & 0xFFFFFFFF, flags, 0, 0)))

    def _key(vk: int = 0, scan: int = 0, flags: int = 0) -> INPUT:
        return INPUT(type=1, u=_INPUTUNION(ki=KEYBDINPUT(vk, scan, flags, 0, 0)))

    def pointer_click(x: int, y: int) -> None:
        user32.SetCursorPos(int(x), int(y))
        time.sleep(0.2)
        _send(_mouse(0x0002), _mouse(0x0004))  # LEFTDOWN, LEFTUP

    def pointer_move(x: int, y: int) -> None:
        user32.SetCursorPos(int(x), int(y))

    def wheel(notches: int) -> None:  # positive = up
        for _ in range(abs(notches)):
            _send(_mouse(0x0800, 120 if notches > 0 else -120))
            time.sleep(0.05)

    VK = {"return": 0x0D, "escape": 0x1B, "tab": 0x09}

    def key_press(name: str) -> None:
        _send(_key(VK[name]), _key(VK[name], flags=0x0002))

    def type_text(text: str) -> None:
        for char in text:
            _send(_key(scan=ord(char), flags=0x0004), _key(scan=ord(char), flags=0x0004 | 0x0002))
            time.sleep(0.03)

    def _windows() -> list[tuple[int, str, tuple[int, int, int, int]]]:
        found = []

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def visit(hwnd, _):
            if user32.IsWindowVisible(hwnd):
                length = user32.GetWindowTextLengthW(hwnd)
                buf = ctypes.create_unicode_buffer(length + 1)
                user32.GetWindowTextW(hwnd, buf, length + 1)
                rect = wintypes.RECT()
                user32.GetWindowRect(hwnd, ctypes.byref(rect))
                found.append((hwnd, buf.value, (rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top)))
            return True

        user32.EnumWindows(visit, 0)
        return found

    def window_rect(title: str) -> Optional[tuple[int, int, int, int]]:
        for _, name, rect in _windows():
            if name == title and rect[2] > 0 and rect[3] > 0:
                return rect
        return None

    def _hwnd(title: str) -> Optional[int]:
        for hwnd, name, _ in _windows():
            if name == title:
                return hwnd
        return None

    def client_rect(title: str) -> Optional[tuple[int, int, int, int]]:
        """The window's client area (below the title bar) in screen pixels."""
        hwnd = _hwnd(title)
        if hwnd is None:
            return None
        rect, origin = wintypes.RECT(), wintypes.POINT(0, 0)
        if not user32.GetClientRect(hwnd, ctypes.byref(rect)) or not user32.ClientToScreen(hwnd, ctypes.byref(origin)):
            return None
        return origin.x, origin.y, rect.right, rect.bottom

    def window_maximize(title: str) -> bool:
        hwnd = _hwnd(title)
        if hwnd is None:
            return False
        user32.ShowWindow(hwnd, 3)  # SW_MAXIMIZE
        user32.SetForegroundWindow(hwnd)
        return True

    def window_close(title: str) -> bool:
        hwnd = _hwnd(title)
        if hwnd is None:
            return False
        return bool(user32.PostMessageW(hwnd, 0x0010, 0, 0))  # WM_CLOSE, like the titlebar button

    def window_focus(title: str) -> None:
        hwnd = _hwnd(title)
        if hwnd is not None:
            user32.SetForegroundWindow(hwnd)

    def screenshot(path: Path) -> None:
        proc = run([MAGICK, "screenshot:[0]", str(path)])
        if proc.returncode != 0 or not path.exists():
            raise OSError(f"magick screenshot: {proc.stderr.strip()}")

    def point_scale(_: Path) -> float:
        return 1.0

elif IS_MAC:
    _cg = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
    _cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")

    class CGPoint(ctypes.Structure):
        _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

    _cg.CGEventCreateMouseEvent.restype = ctypes.c_void_p
    _cg.CGEventCreateMouseEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint32, CGPoint, ctypes.c_uint32]
    _cg.CGEventCreateScrollWheelEvent2.restype = ctypes.c_void_p
    _cg.CGEventCreateScrollWheelEvent2.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32,
                                                    ctypes.c_int32, ctypes.c_int32, ctypes.c_int32]
    _cg.CGEventCreateKeyboardEvent.restype = ctypes.c_void_p
    _cg.CGEventCreateKeyboardEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_bool]
    _cg.CGEventKeyboardSetUnicodeString.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p]
    _cg.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
    _cg.CGMainDisplayID.restype = ctypes.c_uint32
    _cg.CGDisplayPixelsWide.restype = ctypes.c_size_t
    _cg.CGDisplayPixelsWide.argtypes = [ctypes.c_uint32]
    _cf.CFRelease.argtypes = [ctypes.c_void_p]

    def _post(event: int) -> None:
        if not event:
            raise OSError("CGEvent creation failed")
        _cg.CGEventPost(0, event)  # kCGHIDEventTap
        _cf.CFRelease(event)

    def pointer_move(x: int, y: int) -> None:
        _post(_cg.CGEventCreateMouseEvent(None, 5, CGPoint(x, y), 0))  # kCGEventMouseMoved

    def pointer_click(x: int, y: int) -> None:
        pointer_move(x, y)
        time.sleep(0.2)
        _post(_cg.CGEventCreateMouseEvent(None, 1, CGPoint(x, y), 0))  # LeftMouseDown
        time.sleep(0.05)
        _post(_cg.CGEventCreateMouseEvent(None, 2, CGPoint(x, y), 0))  # LeftMouseUp

    def wheel(notches: int) -> None:  # positive = up (content moves down)
        for _ in range(abs(notches)):
            _post(_cg.CGEventCreateScrollWheelEvent2(None, 1, 1, 3 if notches > 0 else -3, 0, 0))
            time.sleep(0.05)

    KEYCODE = {"return": 36, "escape": 53, "tab": 48}

    def key_press(name: str) -> None:
        for down in (True, False):
            _post(_cg.CGEventCreateKeyboardEvent(None, KEYCODE[name], down))
            time.sleep(0.03)

    def type_text(text: str) -> None:
        for char in text:
            unit = (ctypes.c_uint16 * 1)(ord(char))
            for down in (True, False):
                event = _cg.CGEventCreateKeyboardEvent(None, 0, down)
                _cg.CGEventKeyboardSetUnicodeString(event, 1, unit)
                _post(event)
            time.sleep(0.03)

    def _osascript(script: str) -> str:
        path = TMP / "script.applescript"
        path.write_text(script)
        proc = run(["osascript", str(path)], timeout=60)
        if proc.returncode != 0:
            raise OSError(proc.stderr.strip())
        return proc.stdout.strip()

    def _window_script(title: str, body: str) -> str:
        """Runs <body> for the first visible window named <title>, with `w` the
        window and `p` its process; a process refusing Accessibility is skipped."""
        quoted = json.dumps(title)
        return ("tell application \"System Events\"\n"
                "  repeat with p in (every process whose background only is false)\n"
                "    set found to missing value\n"
                "    try\n"
                f"      set found to (first window of p whose name is {quoted})\n"
                "    end try\n"
                "    if found is not missing value then\n"
                "      set w to found\n"
                f"{body}\n"
                "    end if\n"
                "  end repeat\n  return \"\"\nend tell")

    def window_rect(title: str) -> Optional[tuple[int, int, int, int]]:
        try:
            out = _osascript(_window_script(title, "        set {x, y} to position of w\n"
                                                   "        set {ww, hh} to size of w\n"
                                                   "        return (x as text) & \" \" & (y as text) & \" \" & "
                                                   "(ww as text) & \" \" & (hh as text)"))
        except OSError:
            return None
        parts = out.split()
        return tuple(int(float(p)) for p in parts) if len(parts) == 4 else None  # type: ignore[return-value]

    TITLE_BAR = 28  # points of a standard NSWindow title bar

    def client_rect(title: str) -> Optional[tuple[int, int, int, int]]:
        """The window's content area (below the title bar) in screen points."""
        rect = window_rect(title)
        if rect is None:
            return None
        x, y, w, h = rect
        return x, y + TITLE_BAR, w, h - TITLE_BAR

    def window_maximize(title: str) -> bool:
        # The visible frame (below the menu bar, above the Dock), as the
        # green zoom button fills it. AppKit's frames start at the bottom
        # left of the main screen, System Events' at its top left.
        try:
            frame = _osascript("use AppleScript version \"2.4\"\nuse framework \"AppKit\"\nuse scripting additions\n"
                               "set mainScreen to (current application's NSScreen's screens()'s objectAtIndex:0)\n"
                               "set visibleArea to mainScreen's visibleFrame()\n"
                               "set screenArea to mainScreen's frame()\n"
                               "return ((item 1 of item 1 of visibleArea) as integer as text) & \" \" & "
                               "(((item 2 of item 2 of screenArea) - (item 2 of item 1 of visibleArea) - "
                               "(item 2 of item 2 of visibleArea)) as integer as text) & \" \" & "
                               "((item 1 of item 2 of visibleArea) as integer as text) & \" \" & "
                               "((item 2 of item 2 of visibleArea) as integer as text)")
            x, y, w, h = (int(v) for v in frame.split())
            _osascript(_window_script(title, f"        set frontmost of p to true\n"
                                             f"        set position of w to {{{x}, {y}}}\n"
                                             f"        set size of w to {{{w}, {h}}}\n        return \"ok\""))
            return True
        except (OSError, ValueError) as exc:
            print(f"maximize: {exc}", file=sys.stderr)
            return False

    def click_alert_button(label: str) -> str:
        """Clicks the button <label> of any process's window through
        Accessibility (system alerts may ignore synthetic pointer events);
        the owning process, or "" when no window has that button."""
        names = sorted({label, label.replace("'", "\u2019")})
        whose = " or ".join(f"name is {json.dumps(name)}" for name in names)
        return _osascript("tell application \"System Events\"\n"
                          "  repeat with p in every process\n"
                          "    try\n"
                          "      repeat with w in (every window of p)\n"
                          f"        set hits to (every button of w whose {whose})\n"
                          "        if (count of hits) > 0 then\n"
                          "          click item 1 of hits\n"
                          "          return name of p\n"
                          "        end if\n"
                          "      end repeat\n"
                          "    end try\n"
                          "  end repeat\n  return \"\"\nend tell")

    def window_close(title: str) -> bool:
        try:
            out = _osascript(_window_script(
                title, "        click (first button of w whose subrole is \"AXCloseButton\")\n        return \"ok\""))
        except OSError:
            return False
        return out == "ok"

    def window_focus(title: str) -> None:
        try:
            _osascript(_window_script(title, "        set frontmost of p to true\n        return \"ok\""))
        except OSError:
            pass

    def screenshot(path: Path) -> None:
        proc = run(["screencapture", "-x", "-t", "png", str(path)])
        if proc.returncode != 0 or not path.exists():
            raise OSError(f"screencapture: {proc.stderr.strip()}")

    def point_scale(png: Path) -> float:
        """Screenshot pixels per screen point (2 on a Retina display)."""
        width = image_size(png)[0]
        points = _cg.CGDisplayPixelsWide(_cg.CGMainDisplayID()) or width
        return width / points


def image_size(png: Path) -> tuple[int, int]:
    with open(png, "rb") as handle:
        head = handle.read(24)
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def shot(shots: Path, name: str) -> Path:
    shots.mkdir(parents=True, exist_ok=True)
    path = shots / f"{time.strftime('%H%M%S')}-{slug(name)}.png"
    screenshot(path)
    return path


# --- OCR (as guest/gui.sh) -------------------------------------------------------


class Word:
    def __init__(self, line: str, text: str, left: int, top: int, width: int, height: int):
        self.line, self.text = line, text
        self.left, self.top, self.right, self.bottom = left, top, left + width, top + height


def _norm(word: str) -> str:
    return re.sub(r"[^a-z0-9]", "", word.lower())


_OCR_CACHE: dict[tuple[str, str, str], list[Word]] = {}

# ImageMagick operators of each OCR tone. A dark UI reads reliably only
# negated, through its brightness channel (a red warning stays as light as
# white text); a light one as plain gray. Muted text (a placeholder, a hint)
# reads once its contrast is stretched from the background to the text.
_TONES = {
    "negated": ["-colorspace", "HSB", "-channel", "B", "-separate", "+channel", "-negate"],
    "gray": ["-colorspace", "Gray"],
    "muted-dark": ["-colorspace", "HSB", "-channel", "B", "-separate", "+channel", "-level", "20%,60%", "-negate"],
    "muted-light": ["-colorspace", "Gray", "-level", "40%,80%"],
}


def ocr_words(png: Path, tone: str, crop: str = "") -> list[Word]:
    """Tesseract TSV words of a 2x upscaled grayscale copy in one of the
    [_TONES], in screenshot pixels. The alpha channel of a screenshot is
    dropped first (it would be separated as a fourth channel and read as
    white). Cached per screenshot, tone and crop."""
    key = (str(png), tone, crop)
    if key in _OCR_CACHE:
        return _OCR_CACHE[key]
    region = ["-crop", crop, "+repage"] if crop else []
    offset = [int(v) for v in re.split(r"[x+]", crop)[2:]] if crop else [0, 0]
    base = TMP / f"ocr-{len(_OCR_CACHE)}"
    words: list[Word] = []
    if run([MAGICK, str(png), "-alpha", "off", *region, *_TONES[tone], "-resize", "200%", f"{base}.png"]).returncode == 0 \
            and run([TESSERACT, f"{base}.png", str(base), "--psm", "11", "tsv"]).returncode == 0:
        for row in Path(f"{base}.tsv").read_text(errors="replace").splitlines()[1:]:
            fields = row.split("\t")
            if len(fields) < 12 or fields[0] != "5" or not fields[11].strip():
                continue
            left, top, width, height = (int(v) // 2 for v in fields[6:10])
            words.append(Word("-".join(fields[2:5]), fields[11], left + offset[0], top + offset[1], width, height))
    _OCR_CACHE[key] = words
    return words


def is_dark(png: Path) -> bool:
    proc = run([MAGICK, str(png), "-alpha", "off", "-colorspace", "Gray", "-format", "%[fx:mean<0.5?1:0]", "info:"])
    return proc.stdout.strip() == "1"


def tones(png: Path) -> tuple[str, str, str]:
    """The screenshot's own tone, the other one (a light title bar over a dark
    app), then its muted text."""
    return ("negated", "gray", "muted-dark") if is_dark(png) else ("gray", "negated", "muted-light")


def find_phrase(words: list[Word], phrase: str, mode: str) -> Optional[tuple[int, int]]:
    """Pixel centre of the phrase: a whole OCR line (mode line) or inside one."""
    want = [w for w in (_norm(p) for p in phrase.split()) if w]
    lines: dict[str, list[Word]] = {}
    for word in words:
        if _norm(word.text):
            lines.setdefault(word.line, []).append(word)
    for line in lines.values():
        if mode == "line" and len(line) != len(want):
            continue
        for start in range(len(line) - len(want) + 1):
            span = line[start:start + len(want)]
            if [_norm(w.text) for w in span] == want:
                left, top = min(w.left for w in span), min(w.top for w in span)
                right, bottom = max(w.right for w in span), max(w.bottom for w in span)
                return (left + right) // 2, (top + bottom) // 2
    return None


def label_matches(text: str, phrase: str) -> bool:
    """A cropped button read as the phrase plus at most one-character edge artifacts."""
    want = [w for w in (_norm(p) for p in phrase.split()) if w]
    tokens = [t for t in (_norm(p) for p in re.split(r"\s+", text)) if t]
    for start in range(len(tokens) - len(want) + 1):
        if tokens[start:start + len(want)] == want and all(
                len(t) <= 1 for i, t in enumerate(tokens) if i < start or i >= start + len(want)):
            return True
    return False


def locate_filled(png: Path, phrase: str) -> Optional[tuple[int, int]]:
    """Filled accent buttons (dark label on a saturated bright fill), each read alone."""
    mask = TMP / "filled-mask.png"
    # Saturation above 40% and brightness above 50%, from the three HSB
    # channels of the opaque screenshot.
    if run([MAGICK, str(png), "-alpha", "off", "-colorspace", "HSB", "-separate", "(", "-clone", "1",
            "-threshold", "40%", ")", "(", "-clone", "2", "-threshold", "50%", ")", "-delete", "0-2",
            "-compose", "multiply", "-composite", str(mask)]).returncode != 0:
        return None
    report = run([MAGICK, str(mask), "-define", "connected-components:verbose=true",
                  "-define", "connected-components:area-threshold=400", "-connected-components", "8", "null:"])
    crop = TMP / "filled.png"
    for line in (report.stdout + report.stderr).splitlines():
        fields = line.split()
        if len(fields) < 2 or not re.fullmatch(r"\d+x\d+\+\d+\+\d+", fields[1]) or "255" not in fields[-1]:
            continue
        w, h, x, y = (int(v) for v in re.split(r"[x+]", fields[1]))
        if not (40 <= w <= 600 and 20 <= h <= 120):
            continue
        # Rounded corners leave background in the box: flood it white from the
        # corners (the label is enclosed by the fill), shave the antialiased edge.
        if run([MAGICK, str(png), "-alpha", "off", "-crop", f"{w}x{h}+{x}+{y}", "+repage", "-fuzz", "40%",
                "-fill", "white",
                "-draw", "color 0,0 floodfill", "-draw", f"color {w - 1},0 floodfill",
                "-draw", f"color 0,{h - 1} floodfill", "-draw", f"color {w - 1},{h - 1} floodfill",
                "-shave", "2x2", "-colorspace", "Gray", "-resize", "300%", "-normalize", str(crop)]).returncode:
            continue
        text = run([TESSERACT, str(crop), "-", "--psm", "7"]).stdout
        if label_matches(text, phrase):
            return x + w // 2, y + h // 2
    return None


def locate(png: Path, phrase: str, mode: str = "line") -> Optional[tuple[int, int]]:
    """Screen point of the phrase, read in each of the screenshot's [tones];
    `filled` only reads the filled buttons, `line`/`any` fall back to them."""
    found = None
    if mode != "filled":
        for tone in tones(png):
            found = find_phrase(ocr_words(png, tone), phrase, mode)
            if found:
                break
    if found is None:
        found = locate_filled(png, phrase)
    if found is None:
        return None
    scale = point_scale(png)
    return int(found[0] / scale), int(found[1] / scale)


def screen_text(png: Path, crop: str = "") -> str:
    """Every OCR line of a screenshot or of a crop of it, in each of its [tones]."""
    lines: list[str] = []
    for tone in tones(png):
        current: dict[str, list[str]] = {}
        for word in ocr_words(png, tone, crop):
            current.setdefault(word.line, []).append(word.text)
        lines += [" ".join(words) for words in current.values()]
    return "\n".join(dict.fromkeys(lines))


def title_bar_crop(png: Path, title: str) -> str:
    """Crop geometry (screenshot pixels) of a window's title bar: from the top
    of the window (clamped to the screen) to the top of its client area."""
    rect, client = window_rect(title), client_rect(title)
    if rect is None or client is None:
        raise OSError(f"no window titled {title!r}")
    scale = point_scale(png)
    top = max(0, rect[1])
    return (f"{int(client[2] * scale)}x{int(max(1, client[1] - top) * scale)}"
            f"+{max(0, int(client[0] * scale))}+{int(top * scale)}")


# --- GUI commands ----------------------------------------------------------------


def cmd_shot(args: argparse.Namespace) -> None:
    screenshot(Path(args.png))
    print(args.png)


def cmd_locate(args: argparse.Namespace) -> None:
    found = locate(Path(args.png), args.phrase, args.mode)
    if found is None:
        sys.exit(1)
    print(f"{found[0]} {found[1]}")


def cmd_text(args: argparse.Namespace) -> None:
    png = Path(args.png)
    crop = title_bar_crop(png, args.title_bar) if args.title_bar else args.crop
    print(screen_text(png, crop))


def cmd_click(args: argparse.Namespace) -> None:
    shots = Path(args.shots)
    deadline = time.monotonic() + args.timeout
    tries = 0
    while True:
        png = shot(shots, f"click-{args.phrase}")
        found = locate(png, args.phrase, args.mode)
        if found is not None:
            pointer_click(*found)
            print(png)
            time.sleep(1)
            return
        png.unlink()
        if time.monotonic() >= deadline:
            break
        # A long page hides its lower buttons: scroll down, now and then back up.
        tries += 1
        if args.window:
            scroll_window(args.window, 30 if tries % 4 == 0 else -5)
        time.sleep(2)
    shot(shots, f"missing-{args.phrase}")
    sys.exit(1)


def cmd_wait_text(args: argparse.Namespace) -> None:
    shots = Path(args.shots)
    deadline = time.monotonic() + args.timeout
    while True:
        png = shot(shots, f"wait-{args.phrase}")
        if locate(png, args.phrase, args.mode) is not None:
            print(png)
            return
        png.unlink()
        if time.monotonic() >= deadline:
            break
        time.sleep(3)
    shot(shots, f"missing-{args.phrase}")
    sys.exit(1)


def cmd_window(args: argparse.Namespace) -> None:
    deadline = time.monotonic() + args.timeout
    while True:
        rect = window_rect(args.title)
        if rect:
            print(" ".join(str(v) for v in rect))
            return
        if time.monotonic() >= deadline:
            sys.exit(1)
        time.sleep(2)


def cmd_maximize(args: argparse.Namespace) -> None:
    sys.exit(0 if window_maximize(args.title) else 1)


def cmd_close(args: argparse.Namespace) -> None:
    sys.exit(0 if window_close(args.title) else 1)


def scroll_window(title: str, notches: int) -> None:
    rect = window_rect(title)
    if rect is None:
        return
    x, y, w, h = rect
    pointer_move(x + w // 2, y + h // 2)
    time.sleep(0.2)
    wheel(notches)


def cmd_scroll(args: argparse.Namespace) -> None:
    scroll_window(args.title, args.notches if args.direction == "up" else -args.notches)


def rail_items(title: str, rail: int = 72) -> list[tuple[int, int]]:
    """Screen centres of the icon rail items, top to bottom (icon-only: their
    labels are tooltips, out of reach of OCR). The rail is the first <rail>
    points of the window below its title bar; each item is a band of rows
    holding bright icon pixels, whose own gaps (a bulb and its base, stacked
    shapes, the lines of a menu icon) are narrower than 12 points."""
    client = client_rect(title)
    if client is None:
        return []
    x, top, _, height = client
    png = TMP / "rail-screen.png"
    screenshot(png)
    scale = point_scale(png)
    gap = 12 * scale
    crop = f"{int(rail * scale)}x{int(height * scale)}+{int(x * scale)}+{int(top * scale)}"
    proc = run([MAGICK, str(png), "-alpha", "off", "-crop", crop, "+repage", "-colorspace", "Gray", "-threshold", "55%",
                "-scale", f"1x{int(height * scale)}!", "-depth", "8", "txt:-"])
    items, start, last = [], -1, -1
    for line in proc.stdout.splitlines()[1:]:
        match = re.match(r"\d+,(\d+):.*#([0-9A-Fa-f]{2})", line)
        if not match:
            continue
        row, on = int(match.group(1)), match.group(2) != "00"
        if on and start < 0:
            start = row
        if on:
            last = row
        if not on and start >= 0 and row - last > gap:
            items.append((x + rail // 2, int(top + (start + last) / 2 / scale)))
            start = -1
    if start >= 0:
        items.append((x + rail // 2, int(top + (start + last) / 2 / scale)))
    return items


def cmd_rail(args: argparse.Namespace) -> None:
    rect = window_rect(args.title)
    if rect is None:
        sys.exit(1)
    x, y, w, h = rect
    pointer_move(x + w // 2, y + h // 2)  # a hovered rail item shows a tooltip over the rail
    time.sleep(1)
    items = rail_items(args.title)
    print(json.dumps(items))
    if len(items) < 6:
        sys.exit(1)
    target = items[-1] if args.item == "last" else items[int(args.item) - 1]
    pointer_click(*target)
    time.sleep(1)
    pointer_move(x + w // 2, y + h // 2)


def cmd_type(args: argparse.Namespace) -> None:
    type_text(args.text)


def cmd_pointer(args: argparse.Namespace) -> None:
    pointer_click(args.x, args.y)


def cmd_key(args: argparse.Namespace) -> None:
    key_press(args.name)


def cmd_focus(args: argparse.Namespace) -> None:
    window_focus(args.title)


def cmd_alert(args: argparse.Namespace) -> None:
    """macOS: clicks a button of a system alert; prints its owning process."""
    if not IS_MAC:
        sys.exit(2)
    owner = click_alert_button(args.button)
    print(owner)
    sys.exit(0 if owner else 1)


# --- processes -------------------------------------------------------------------


class Proc:
    def __init__(self, pid: int, ppid: int, exe: str, argv: list[str], env: dict[str, str]):
        self.pid, self.ppid, self.exe, self.argv, self.env = pid, ppid, exe, argv, env

    def describe(self) -> dict[str, Any]:
        return {"pid": self.pid, "ppid": self.ppid, "exe": self.exe, "argv": self.argv}


def _env_dict(items: list[str]) -> dict[str, str]:
    """Environment block to a dict; Windows names are case-insensitive (upper-cased)."""
    env = {}
    for item in items:
        key, sep, value = item.partition("=")
        if sep and key:  # Windows keeps "=C:"-style entries: key "" is dropped
            env[key.upper() if IS_WIN else key] = value
    return env


if IS_MAC:
    _libc = ctypes.CDLL("/usr/lib/libc.dylib", use_errno=True)
    _libproc = ctypes.CDLL("/usr/lib/libproc.dylib")

    def _procargs(pid: int) -> tuple[list[str], list[str]]:
        argmax, size = ctypes.c_int(0), ctypes.c_size_t(ctypes.sizeof(ctypes.c_int))
        _libc.sysctl((ctypes.c_int * 2)(1, 8), 2, ctypes.byref(argmax), ctypes.byref(size), None, 0)
        buf, size = ctypes.create_string_buffer(argmax.value), ctypes.c_size_t(argmax.value)
        if _libc.sysctl((ctypes.c_int * 3)(1, 49, pid), 3, buf, ctypes.byref(size), None, 0) != 0:
            raise OSError(ctypes.get_errno(), f"KERN_PROCARGS2 {pid}")
        data = buf.raw[:size.value]
        argc = int.from_bytes(data[:4], sys.byteorder)
        rest = data[4:]
        rest = rest[rest.index(b"\0"):].lstrip(b"\0")  # the exec path, then padding
        parts = rest.split(b"\0")
        env = []
        for item in parts[argc:]:
            if not item:
                break
            env.append(item.decode(errors="replace"))
        return [p.decode(errors="replace") for p in parts[:argc]], env

    def _exe(pid: int) -> str:
        buf = ctypes.create_string_buffer(4096)
        n = _libproc.proc_pidpath(pid, buf, 4096)
        return buf.value.decode(errors="replace") if n > 0 else ""

    def user_processes() -> list[Proc]:
        uid = os.getuid()
        out = run(["ps", "-axo", "pid=,ppid=,uid="]).stdout
        procs = []
        for line in out.splitlines():
            fields = line.split()
            if len(fields) != 3 or int(fields[2]) != uid:
                continue
            pid, ppid = int(fields[0]), int(fields[1])
            try:
                argv, env = _procargs(pid)
            except OSError:
                continue
            procs.append(Proc(pid, ppid, _exe(pid), argv, _env_dict(env)))
        return procs

    def listening_ports(pid: int) -> list[int]:
        out = run(["lsof", "-nP", "-a", "-p", str(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"]).stdout
        return sorted({int(line.rsplit(":", 1)[1]) for line in out.splitlines()
                       if line.startswith("n") and line.rsplit(":", 1)[-1].isdigit()})

elif IS_WIN:
    ntdll = ctypes.WinDLL("ntdll")

    class PBI(ctypes.Structure):
        _fields_ = [("ExitStatus", ctypes.c_void_p), ("PebBaseAddress", ctypes.c_void_p),
                    ("AffinityMask", ctypes.c_void_p), ("BasePriority", ctypes.c_void_p),
                    ("UniqueProcessId", ctypes.c_void_p), ("InheritedFromUniqueProcessId", ctypes.c_void_p)]

    class PROCESSENTRY32W(ctypes.Structure):
        _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD), ("th32ProcessID", wintypes.DWORD),
                    ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", wintypes.DWORD),
                    ("cntThreads", wintypes.DWORD), ("th32ParentProcessID", wintypes.DWORD),
                    ("pcPriClassBase", wintypes.LONG), ("dwFlags", wintypes.DWORD),
                    ("szExeFile", wintypes.WCHAR * 260)]

    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.ReadProcessMemory.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                           ctypes.POINTER(ctypes.c_size_t)]
    kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    ntdll.NtQueryInformationProcess.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, ctypes.c_ulong,
                                                ctypes.POINTER(ctypes.c_ulong)]

    def _read(handle: int, address: int, size: int) -> bytes:
        buf = ctypes.create_string_buffer(size)
        got = ctypes.c_size_t(0)
        if not kernel32.ReadProcessMemory(handle, ctypes.c_void_p(address), buf, size, ctypes.byref(got)):
            raise OSError(ctypes.get_last_error(), "ReadProcessMemory")
        return buf.raw[:got.value]

    def _peb_strings(pid: int) -> tuple[str, str, list[str]]:
        """(image path, command line, environment) from the 64-bit PEB."""
        handle = kernel32.OpenProcess(0x1000 | 0x0010, False, pid)  # QUERY_LIMITED_INFORMATION | VM_READ
        if not handle:
            raise OSError(ctypes.get_last_error(), f"OpenProcess {pid}")
        try:
            pbi = PBI()
            status = ntdll.NtQueryInformationProcess(handle, 0, ctypes.byref(pbi), ctypes.sizeof(pbi), None)
            if status != 0:
                raise OSError(status, "NtQueryInformationProcess")
            params = int.from_bytes(_read(handle, pbi.PebBaseAddress + 0x20, 8), "little")
            image_len = int.from_bytes(_read(handle, params + 0x60, 2), "little")
            image = _read(handle, int.from_bytes(_read(handle, params + 0x68, 8), "little"), image_len)
            cmd_len = int.from_bytes(_read(handle, params + 0x70, 2), "little")
            cmd = _read(handle, int.from_bytes(_read(handle, params + 0x78, 8), "little"), cmd_len)
            env_ptr = int.from_bytes(_read(handle, params + 0x80, 8), "little")
            env_size = int.from_bytes(_read(handle, params + 0x3F0, 8), "little")
            env = _read(handle, env_ptr, env_size).decode("utf-16-le", errors="replace")
            return (image.decode("utf-16-le", errors="replace").split("\0", 1)[0],
                    cmd.decode("utf-16-le", errors="replace"),
                    [item for item in env.split("\0") if item])
        finally:
            kernel32.CloseHandle(handle)

    def _split_cmdline(cmd: str) -> list[str]:
        # The PEB string may carry a terminating NUL (and garbage after it)
        # inside its length: CommandLineToArgvW takes a C string.
        cmd = cmd.split("\0", 1)[0]
        if not cmd:
            return []
        argc = ctypes.c_int(0)
        shell32 = ctypes.WinDLL("shell32")
        shell32.CommandLineToArgvW.restype = ctypes.POINTER(wintypes.LPWSTR)
        argv = shell32.CommandLineToArgvW(cmd, ctypes.byref(argc))
        if not argv:
            return [cmd]
        try:
            return [argv[i] for i in range(argc.value)]
        finally:
            kernel32.LocalFree(argv)

    def user_processes() -> list[Proc]:
        snapshot = kernel32.CreateToolhelp32Snapshot(0x2, 0)  # TH32CS_SNAPPROCESS
        entry = PROCESSENTRY32W()
        entry.dwSize = ctypes.sizeof(entry)
        pairs = []
        if kernel32.Process32FirstW(snapshot, ctypes.byref(entry)):
            while True:
                pairs.append((entry.th32ProcessID, entry.th32ParentProcessID))
                if not kernel32.Process32NextW(snapshot, ctypes.byref(entry)):
                    break
        kernel32.CloseHandle(snapshot)
        procs = []
        for pid, ppid in pairs:
            if pid in (0, 4, os.getpid()):
                continue
            try:
                image, cmd, env = _peb_strings(pid)
            except OSError:
                continue  # other users' and protected processes
            procs.append(Proc(pid, ppid, image, _split_cmdline(cmd) if cmd else [], _env_dict(env)))
        return procs

    def listening_ports(pid: int) -> list[int]:
        out = run(["netstat", "-ano", "-p", "TCP"]).stdout + run(["netstat", "-ano", "-p", "TCPv6"]).stdout
        ports = set()
        for line in out.splitlines():
            fields = line.split()
            if len(fields) == 5 and fields[3] == "LISTENING" and fields[4] == str(pid):
                ports.add(int(fields[1].rsplit(":", 1)[1]))
        return sorted(ports)


def cmd_processes(_: argparse.Namespace) -> None:
    print(json.dumps([p.describe() for p in user_processes()], indent=1))


# --- HTTP and probes ------------------------------------------------------------------


def http_call(port: int, method: str, path: str, *, token: Optional[str] = None, body: Any = None,
              headers: Optional[dict[str, str]] = None, timeout: float = 30.0) -> tuple[int, Any]:
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    all_headers = {"Accept": "application/json"}
    if token:
        all_headers["X-Hermes-Session-Token"] = token
    all_headers.update(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        all_headers["Content-Type"] = "application/json"
    try:
        conn.request(method, path, body=data, headers=all_headers)
        response = conn.getresponse()
        raw = response.read()
    except OSError as exc:
        return 0, f"{type(exc).__name__}: {exc}"
    finally:
        conn.close()
    try:
        return response.status, json.loads(raw)
    except ValueError:
        return response.status, raw.decode(errors="replace")[:2000]


class Backend:
    def __init__(self, proc: Proc, port: int, token: str):
        self.proc, self.port, self.token = proc, port, token

    def describe(self) -> dict[str, Any]:
        env = self.proc.env
        return {**self.proc.describe(), "port": self.port,
                "hermes_home": env.get("HERMES_HOME", ""),
                "home": env.get("HOME", ""),
                "userprofile": env.get("USERPROFILE", ""),
                "hermes_desktop": env.get("HERMES_DESKTOP", ""),
                "path": env.get("PATH", "")}


def find_backend() -> Optional[Backend]:
    """The app-supervised ``hermes serve``: HERMES_DESKTOP=1 + a session token."""
    for proc in user_processes():
        token = proc.env.get("HERMES_DASHBOARD_SESSION_TOKEN", "")
        if proc.env.get("HERMES_DESKTOP") != "1" or not token:
            continue
        for port in listening_ports(proc.pid):
            status, body = http_call(port, "GET", "/api/status", timeout=10)
            if status == 200 and isinstance(body, dict):
                return Backend(proc, port, token)
    return None


def require_backend() -> Backend:
    backend = find_backend()
    if backend is None:
        emit({"error": "no app-supervised hermes serve (HERMES_DESKTOP=1 + session token) is listening"}, False)
    assert backend is not None
    return backend


def cmd_backend(_: argparse.Namespace) -> None:
    backend = require_backend()
    status, body = http_call(backend.port, "GET", "/api/status")
    emit({"backend": backend.describe(), "status": status, "api_status": body}, status == 200)


def cmd_rest(args: argparse.Namespace) -> None:
    backend = require_backend()
    body = json.loads(args.body) if args.body else None
    status, response = http_call(backend.port, args.method.upper(), args.path, token=backend.token, body=body,
                                 timeout=args.timeout)
    emit({"method": args.method.upper(), "path": args.path, "status": status, "body": response},
         200 <= status < 300)


def cmd_plaintext(args: argparse.Namespace) -> None:
    """Files under the given paths holding the session token the app minted for
    its backend (UTF-8 or UTF-16), or the app's secret key names: the app keeps
    both in the platform keystore only. The token itself is never printed."""
    backend = require_backend()
    needles = [backend.token.encode(), backend.token.encode("utf-16-le")]
    names = [name.encode() for name in args.name]
    token_hits, name_hits, scanned = [], [], 0
    for root in args.paths:
        for dirpath, _, files in os.walk(root):
            for file in files:
                path = os.path.join(dirpath, file)
                try:
                    data = Path(path).read_bytes()
                except OSError:
                    continue
                scanned += 1
                if any(n in data for n in needles):
                    token_hits.append(path)
                if any(n in data for n in names):
                    name_hits.append(path)
    emit({"paths": args.paths, "files_scanned": scanned, "token_in": token_hits, "secret_names_in": name_hits,
          "token_length": len(backend.token)}, scanned > 0 and not token_hits and not name_hits)


def _yaml_scalar(text: str, key: str, section: Optional[str] = None) -> Optional[str]:
    """Scalar of the flat YAML the app generates (JSON-quoted strings)."""
    current = None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            current = line.split(":", 1)[0].strip()
            if section is None and current == key:
                value = line.split(":", 1)[1].strip()
                return json.loads(value) if value.startswith('"') else value
        elif section is not None and current == section:
            name, _, value = line.strip().partition(":")
            if name == key:
                value = value.strip()
                return json.loads(value) if value.startswith('"') else value
    return None


def _same_file(a: str, b: str) -> bool:
    try:
        return os.path.samefile(a, b)
    except OSError:
        return os.path.normcase(os.path.realpath(a)) == os.path.normcase(os.path.realpath(b))


def cmd_cliproxy(args: argparse.Namespace) -> None:
    config = Path(args.config).read_text()
    port = int(_yaml_scalar(config, "port") or 0)
    key = _yaml_scalar(config, "secret-key", section="remote-management") or ""
    report: dict[str, Any] = {"config": args.config, "port": port}
    procs = [p for p in user_processes() if any(_same_file(a, args.config) or a.endswith(args.config)
                                                   for a in p.argv if os.path.isabs(a))]
    report["processes"] = [p.describe() for p in procs]
    report["exe_is_bundle_slot"] = bool(procs) and all(_same_file(p.exe, args.expect_exe) for p in procs)
    unauthenticated, _ = http_call(port, "GET", "/v0/management/config", timeout=10)
    authenticated, body = http_call(port, "GET", "/v0/management/config", timeout=10,
                                    headers={"Authorization": f"Bearer {key}"})
    report.update(unauthenticated_status=unauthenticated, authenticated_status=authenticated,
                  authenticated_is_json=isinstance(body, dict))
    emit(report, bool(key) and report["exe_is_bundle_slot"] and unauthenticated in (401, 403)
         and authenticated == 200 and isinstance(body, dict))


# --- DPAPI (Windows) --------------------------------------------------------------------


def _dpapi(data: bytes, protect: bool) -> bytes:
    class BLOB(ctypes.Structure):
        _fields_ = [("cbData", ctypes.c_ulong), ("pbData", ctypes.POINTER(ctypes.c_char))]

    crypt32 = ctypes.WinDLL("crypt32", use_last_error=True)
    source = ctypes.create_string_buffer(data, len(data))
    blob_in, blob_out = BLOB(len(data), ctypes.cast(source, ctypes.POINTER(ctypes.c_char))), BLOB()
    call = crypt32.CryptProtectData if protect else crypt32.CryptUnprotectData
    # CRYPTPROTECT_UI_FORBIDDEN: never a prompt.
    if not call(ctypes.byref(blob_in), None, None, None, None, 0x1, ctypes.byref(blob_out)):
        raise OSError(ctypes.get_last_error(), "CryptProtectData" if protect else "CryptUnprotectData")
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        kernel32.LocalFree(blob_out.pbData)


def cmd_dpapi(args: argparse.Namespace) -> None:
    if not IS_WIN:
        emit({"error": "DPAPI is Windows only"}, False)
    if args.action == "roundtrip":
        value = os.urandom(24).hex().encode()
        sealed = _dpapi(value, True)
        emit({"sealed_bytes": len(sealed), "plaintext_in_sealed": value in sealed,
              "roundtrip": _dpapi(sealed, False) == value}, _dpapi(sealed, False) == value and value not in sealed)
    raw = Path(args.file).read_bytes()
    report: dict[str, Any] = {"file": args.file, "bytes": len(raw)}
    try:
        json.loads(raw)
        report["raw_is_json"] = True
    except ValueError:
        report["raw_is_json"] = False
    try:
        data = json.loads(_dpapi(raw, False))
    except (OSError, ValueError) as exc:
        emit({**report, "error": f"{type(exc).__name__}: {exc}"}, False)
    report["keys"] = sorted(data) if isinstance(data, dict) else None  # names only, never values
    report["keys_in_raw_bytes"] = [k for k in report["keys"] or [] if k.encode() in raw or k.encode("utf-16-le") in raw]
    emit(report, isinstance(data, dict) and not report["raw_is_json"] and not report["keys_in_raw_bytes"])


# --- result files ---------------------------------------------------------------------


def cmd_check(args: argparse.Namespace) -> None:
    out = Path(args.out)
    evidence = []
    for path in args.evidence:
        if path and os.path.exists(path):
            evidence.append(Path(os.path.relpath(os.path.abspath(path), os.path.abspath(out))).as_posix())
    record = {"id": args.id, "criterion": args.criterion, "name": args.name, "status": args.status,
              "detail": args.detail, "evidence": evidence}
    with open(out / "checks.jsonl", "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record) + "\n")
    print(f"[{time.strftime('%H:%M:%S')}] [{args.status}] {args.id}/{args.name}: {args.detail}", file=sys.stderr)


def cmd_finalize(args: argparse.Namespace) -> None:
    out = Path(args.out)
    checks = []
    path = out / "checks.jsonl"
    if path.exists():
        checks = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    expected = dict(item.split("=", 1) for item in args.expect)
    for result_id, criterion in expected.items():
        if not any(c["id"] == result_id for c in checks):
            checks.append({"id": result_id, "criterion": criterion, "name": "reached", "status": "fail",
                           "detail": f"the scenario stopped before this criterion (runner exit {args.exit_code})",
                           "evidence": []})
    (out / "results").mkdir(parents=True, exist_ok=True)
    for result_id in dict.fromkeys(c["id"] for c in checks):
        group = [c for c in checks if c["id"] == result_id]
        statuses = {c["status"] for c in group}
        status = ("fail" if "fail" in statuses else "manual-gate" if "manual-gate" in statuses
                  else "skipped-missing-prereq" if "skipped-missing-prereq" in statuses else "pass")
        result = {"schema": 1, "id": result_id, "criterion": group[0]["criterion"], "guest": args.runner,
                  "format": args.format, "scenario": args.scenario, "run": args.run_id, "status": status,
                  "checks": [{k: v for k, v in c.items() if k not in ("id", "criterion")} for c in group],
                  "gui_proof": sorted({e for c in group if c["status"] == "manual-gate" for e in c["evidence"]})}
        (out / "results" / f"{result_id}.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    (out / "runner-exit-code").write_text(f"{args.exit_code}\n")


# --- CLI --------------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("shot")
    p.add_argument("png")
    p.set_defaults(run=cmd_shot)
    p = sub.add_parser("locate")
    p.add_argument("png")
    p.add_argument("phrase")
    p.add_argument("--mode", choices=("line", "any", "filled"), default="line")
    p.set_defaults(run=cmd_locate)
    p = sub.add_parser("text")
    p.add_argument("png")
    p.add_argument("--crop", default="", help="WxH+X+Y in screenshot pixels")
    p.add_argument("--title-bar", default="", help="only the title bar of this window")
    p.set_defaults(run=cmd_text)
    for name, run_fn, modes, default in (("click", cmd_click, ("line", "any", "filled"), "line"),
                                         ("wait-text", cmd_wait_text, ("line", "any"), "any")):
        p = sub.add_parser(name)
        p.add_argument("phrase")
        p.add_argument("--shots", required=True)
        p.add_argument("--timeout", type=float, default=30)
        p.add_argument("--mode", choices=modes, default=default)
        p.add_argument("--window", default="", help="title of the window to scroll while looking")
        p.set_defaults(run=run_fn)
    p = sub.add_parser("window")
    p.add_argument("title")
    p.add_argument("--timeout", type=float, default=0)
    p.set_defaults(run=cmd_window)
    for name, run_fn in (("maximize", cmd_maximize), ("close", cmd_close), ("focus", cmd_focus)):
        p = sub.add_parser(name)
        p.add_argument("title")
        p.set_defaults(run=run_fn)
    p = sub.add_parser("rail")
    p.add_argument("item")
    p.add_argument("title")
    p.set_defaults(run=cmd_rail)
    p = sub.add_parser("scroll")
    p.add_argument("direction", choices=("up", "down"))
    p.add_argument("notches", type=int)
    p.add_argument("title")
    p.set_defaults(run=cmd_scroll)
    p = sub.add_parser("type")
    p.add_argument("text")
    p.set_defaults(run=cmd_type)
    p = sub.add_parser("pointer")
    p.add_argument("x", type=int)
    p.add_argument("y", type=int)
    p.set_defaults(run=cmd_pointer)
    p = sub.add_parser("key")
    p.add_argument("name", choices=("return", "escape", "tab"))
    p.set_defaults(run=cmd_key)
    p = sub.add_parser("alert")
    p.add_argument("button")
    p.set_defaults(run=cmd_alert)
    sub.add_parser("processes").set_defaults(run=cmd_processes)
    sub.add_parser("backend").set_defaults(run=cmd_backend)
    p = sub.add_parser("plaintext")
    p.add_argument("paths", nargs="+")
    p.add_argument("--name", action="append", default=[], help="a secret key name that must not appear either")
    p.set_defaults(run=cmd_plaintext)
    p = sub.add_parser("rest")
    p.add_argument("method")
    p.add_argument("path")
    p.add_argument("--body")
    p.add_argument("--timeout", type=float, default=60.0)
    p.set_defaults(run=cmd_rest)
    p = sub.add_parser("cliproxy")
    p.add_argument("--config", required=True)
    p.add_argument("--expect-exe", required=True)
    p.set_defaults(run=cmd_cliproxy)
    p = sub.add_parser("dpapi")
    p.add_argument("action", choices=("roundtrip", "decrypt"))
    p.add_argument("file", nargs="?")
    p.set_defaults(run=cmd_dpapi)
    result = sub.add_parser("result")
    rsub = result.add_subparsers(dest="result_command", required=True)
    p = rsub.add_parser("check")
    p.add_argument("out")
    p.add_argument("id")
    p.add_argument("criterion")
    p.add_argument("name")
    p.add_argument("status", choices=("pass", "fail", "manual-gate", "skipped-missing-prereq"))
    p.add_argument("detail")
    p.add_argument("evidence", nargs="*")
    p.set_defaults(run=cmd_check)
    p = rsub.add_parser("finalize")
    p.add_argument("out")
    p.add_argument("--runner", required=True)
    p.add_argument("--format", required=True)
    p.add_argument("--scenario", required=True)
    p.add_argument("--run", dest="run_id", required=True)
    p.add_argument("--exit-code", default="0")
    p.add_argument("--expect", action="append", default=[], help="ID=CRITERION of every expected result")
    p.set_defaults(run=cmd_finalize)
    args = parser.parse_args()
    try:
        args.run(args)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as exc:
        if args.command in ("backend", "rest", "cliproxy", "dpapi", "plaintext"):
            emit({"command": args.command, "error": f"{type(exc).__name__}: {exc}"}, False)
        print(f"desktop.py {args.command}: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)
    finally:
        shutil.rmtree(TMP, ignore_errors=True)


if __name__ == "__main__":
    main()
