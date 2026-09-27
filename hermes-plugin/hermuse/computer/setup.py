"""``setup(home)``: point Hermes' browser tools at the computer and bootstrap it.

Used by ``hermes hermuse computer setup`` (the Hermuse desktop installer) and
``POST /api/plugins/hermuse/computer/setup`` (the one-click remote install).
Safe to repeat: config writes are idempotent and ``prepare`` only starts the
background bootstrap (Docker install when missing and installable, then image
pull or build) when something is missing and none runs — so it also retries a
failed attempt.
"""

from __future__ import annotations

import contextlib
import io
import logging
from typing import Any

from . import runtime

logger = logging.getLogger(__name__)

CONFIG = (
    ("browser.cloud_provider", "hermuse"),
    # Otherwise private URLs go to an invisible host sidecar Chromium.
    ("browser.auto_local_for_private_urls", "false"),
    # Built-in browser_* tools (they drive the provider's CDP URL) instead of the
    # default Browser Use mode, whose browser_exec runs model-written Python on the host.
    ("browser.backend", "off"),
)


def setup(home: Any) -> dict:
    from hermes_cli.config import set_config_value

    for key, value in CONFIG:
        try:
            with contextlib.redirect_stdout(io.StringIO()):  # keep `setup` output pure JSON
                set_config_value(key, value)
        except SystemExit as exc:
            return {"state": "error", "detail": f"config: {exc.code}"}
    backend = runtime.get_runtime()
    try:
        backend.prepare(home)
    except RuntimeError as exc:
        logger.warning("hermuse computer: bootstrap not started: %s", exc)
    return backend.status(home)
