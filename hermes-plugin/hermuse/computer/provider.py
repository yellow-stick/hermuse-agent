"""The ``hermuse`` browser provider (``browser.cloud_provider: hermuse``).

Hermes' built-in ``browser_*`` tools drive the Chromium of the agent's computer
through the CDP URL returned here, so everything the agent browses is visible
(and can be taken over) in Hermuse.
"""

from __future__ import annotations

import functools
import hashlib
import logging
import shutil
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

from . import runtime

logger = logging.getLogger(__name__)

PROVIDER_NAME = "hermuse"
SESSION_START_TIMEOUT_S = 20.0
# Refused port 9: agent-browser fails the call instead of launching a browser.
UNAVAILABLE_CDP_URL = "ws://127.0.0.1:9/devtools/browser/hermuse-computer-unavailable"
UNAVAILABLE_TTL_S = 5.0  # the next browser call retries create_session after this


def _home() -> Any:
    from hermes_constants import get_hermes_home

    return get_hermes_home()


def _session_key(task_id: str) -> str:
    return hashlib.sha1(str(task_id).encode("utf-8")).hexdigest()[:12]


@functools.cache
def _provider_class() -> type:
    # Lazy: agent.browser_provider only exists inside Hermes.
    from agent.browser_provider import BrowserProvider

    class HermuseComputerProvider(BrowserProvider):
        name = PROVIDER_NAME
        display_name = "Hermuse computer"

        def is_available(self) -> bool:
            # Runs at tool registration and on every `hermes tools` paint, where
            # subprocess/network are off limits: "selectable", not "usable".
            # Usability is the pre_tool_call readiness guard's job.
            return shutil.which("docker") is not None

        def create_session(self, task_id: str) -> Dict[str, object]:
            # Never raises: Hermes falls back to a host Chromium when this does.
            key = _session_key(task_id)
            backend = runtime.get_runtime()
            try:
                rt = backend.ensure_running(_home(), timeout=SESSION_START_TIMEOUT_S)
                return {
                    "session_name": f"hermuse-{key}",
                    "bb_session_id": f"{rt['container']}:{key}",
                    "cdp_url": backend.cdp_ws_url(rt),
                    "features": {"hermuse_computer": True},
                }
            except Exception as exc:  # noqa: BLE001 — fail safe, see above
                logger.warning("hermuse computer unavailable for browser session: %s", exc)
                expires = datetime.now(timezone.utc) + timedelta(seconds=UNAVAILABLE_TTL_S)
                return {
                    "session_name": f"hermuse-unavailable-{key}",
                    "bb_session_id": f"unavailable:{key}",
                    "cdp_url": UNAVAILABLE_CDP_URL,
                    "expires_at": expires.isoformat(),
                    "features": {"hermuse_computer": False},
                }

        def close_session(self, session_id: str) -> bool:
            return True  # the computer is persistent: nothing to release

        def emergency_cleanup(self, session_id: str) -> None:
            return None

        def get_setup_schema(self) -> Dict[str, Any]:
            return {"name": "Hermuse computer", "badge": "local",
                    "tag": "Docker browser visible in Hermuse", "env_vars": []}

    return HermuseComputerProvider


def make_provider() -> Any:
    return _provider_class()()
