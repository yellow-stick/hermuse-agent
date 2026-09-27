"""Hermes hooks of the agent's computer.

* ``pre_tool_call``: blocks every ``browser_*`` tool while a human holds the
  Take control lease, then makes sure the computer is up (readiness guard) so
  an unusable computer yields an explanation instead of a silent fallback.
* ``transform_tool_result``: saves the screen right after each browser call
  (``snapshots/<tool_call_id>.jpg``) for the chat's Browser card.
"""

from __future__ import annotations

import logging
import re
from typing import Any, Optional

from . import runtime, state

logger = logging.getLogger(__name__)

BROWSER_BLOCK_MESSAGE = (
    "The user has taken control of the browser. Do not use browser tools until they hand "
    "control back; tell the user you are waiting for them.")
COMPUTER_UNAVAILABLE_MESSAGE = (
    "The agent's computer is not available ({state}: {detail}). Do not retry browser tools "
    "now; tell the user to open Hermuse to finish setting up the computer.")

# Budget under Hermes' default 30 s plugins.hook_callback_timeout: 1 + 5 + 18 = 24 s.
_PROBE_TIMEOUT_S = 1.0
_STATUS_TIMEOUT_S = 5.0
_START_TIMEOUT_S = 18.0
_ERROR_RE = re.compile(r"^hermuse computer: ([a-z_]+) — (.*)$", re.DOTALL)


def _home() -> Any:
    from hermes_constants import get_hermes_home

    return get_hermes_home()


def is_browser_tool(tool_name: Any) -> bool:
    return isinstance(tool_name, str) and tool_name.startswith("browser_")


def _cdp_answers(home: Any) -> bool:
    rt = state.read_runtime(home)
    if rt is None:
        return False
    try:
        runtime.loopback_request(f"http://127.0.0.1:{int(rt['cdp_port'])}/json/version",
                                 _PROBE_TIMEOUT_S)
    except Exception:  # noqa: BLE001 — any failure means "not ready"
        return False
    return True


def _unavailable(state_name: str, detail: str) -> dict:
    return {"action": "block",
            "message": COMPUTER_UNAVAILABLE_MESSAGE.format(state=state_name, detail=detail)}


def _unavailable_from(exc: Exception) -> dict:
    match = _ERROR_RE.match(str(exc))
    if match:
        return _unavailable(match.group(1), match.group(2))
    return _unavailable("error", str(exc) or type(exc).__name__)


def pre_tool_call(tool_name: str = "", **kwargs: Any) -> Optional[dict]:
    if not is_browser_tool(tool_name):
        return None
    home = _home()
    if state.read_control(home)["holder"] == state.HUMAN:
        return {"action": "block", "message": BROWSER_BLOCK_MESSAGE}
    if _cdp_answers(home):
        return None
    backend = runtime.get_runtime()
    try:
        current = backend.status(home, timeout=_STATUS_TIMEOUT_S)
        if current["state"] in ("stopped", "running"):
            backend.ensure_running(home, timeout=_START_TIMEOUT_S)
            return None
    except Exception as exc:  # noqa: BLE001 — the hook explains, never crashes
        return _unavailable_from(exc)
    if current["state"] == "image_missing":
        try:
            backend.prepare(home)
        except Exception as exc:  # noqa: BLE001
            logger.warning("hermuse computer: could not start the bootstrap: %s", exc)
    return _unavailable(current["state"], current.get("detail", ""))


def transform_tool_result(tool_name: str = "", result: Any = None,
                          tool_call_id: Optional[str] = None, **kwargs: Any) -> None:
    if is_browser_tool(tool_name) and tool_call_id:
        try:
            home = _home()
            rt = state.read_runtime(home)
            if rt is not None and state.snapshot_path(home, str(tool_call_id)) is not None:
                state.save_snapshot(home, str(tool_call_id), runtime.get_runtime().thumbnail(rt))
        except Exception as exc:  # noqa: BLE001 — best effort, never touches the result
            logger.debug("hermuse computer: no snapshot for %s: %s", tool_call_id, exc)
    return None
