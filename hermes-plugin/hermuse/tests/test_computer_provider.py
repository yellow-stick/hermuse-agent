"""The `hermuse` browser provider: session contract, availability, fail-safe."""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import time
from datetime import datetime

import pytest

from computer import provider


@pytest.fixture()
def no_subprocess(monkeypatch):
    calls = []
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: calls.append(a))
    return calls


def test_session_points_hermes_at_the_computer_cdp(hermes_home, fake_runtime):
    session = provider.make_provider().create_session("task-1")
    key = hashlib.sha1(b"task-1").hexdigest()[:12]
    assert session == {
        "session_name": f"hermuse-{key}",
        "bb_session_id": f"c:{key}",
        "cdp_url": "ws://127.0.0.1:1/devtools/browser/x",
        "features": {"hermuse_computer": True},
    }
    assert ("ensure_running", 20) in fake_runtime.calls
    assert provider.make_provider().close_session(session["bb_session_id"]) is True


@pytest.mark.parametrize("docker_path", ["/usr/bin/docker", None])
def test_availability_is_only_the_docker_binary(monkeypatch, no_subprocess, docker_path):
    monkeypatch.setattr(shutil, "which", lambda name: docker_path if name == "docker" else None)
    assert provider.make_provider().is_available() is (docker_path is not None)
    assert no_subprocess == []


def test_unavailable_computer_never_falls_back_to_a_host_browser(hermes_home, fake_runtime):
    from tools.browser_tool_cdp import _resolve_cdp_override
    from tools.browser_tool_lifecycle import _session_has_expired

    fake_runtime.ensure_error = RuntimeError("hermuse computer: daemon_down — docker is off")
    before = time.time()
    session = provider.make_provider().create_session("s")  # must not raise

    assert session["cdp_url"] == provider.UNAVAILABLE_CDP_URL
    assert session["bb_session_id"].startswith("unavailable:")
    assert session["features"] == {"hermuse_computer": False}
    expires = datetime.fromisoformat(session["expires_at"]).timestamp()
    assert before < expires <= time.time() + 6
    # Hermes keeps the refused endpoint as-is (no discovery, no local Chromium)…
    assert _resolve_cdp_override(session["cdp_url"]) == session["cdp_url"]
    # …and re-runs create_session once the fail-safe session expires.
    assert not _session_has_expired(session, now=before)
    assert _session_has_expired(session, now=before + 6)
