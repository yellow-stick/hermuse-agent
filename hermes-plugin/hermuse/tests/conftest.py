"""Shared pytest fixtures: a throwaway HERMES_HOME, importable plugin root, fake computer."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
HERMES_AGENT = Path(os.environ.get(
    "HERMES_AGENT_DIR", str(Path.home() / ".hermes" / "hermes-agent")))


@pytest.fixture()
def hermes_home(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HERMES_HOME", str(home))
    # hermes_constants caches nothing for get_hermes_home itself, but the
    # registry key cache + process-home consumers must not leak across tests.
    try:
        from hermes_constants import reset_hermes_home_key_cache
        reset_hermes_home_key_cache()
    except ImportError:
        pass
    return home


@pytest.fixture()
def hermuse_root(hermes_home):
    from store import hermuse_root

    return hermuse_root(hermes_home)


class FakeRuntime:
    """Scriptable ``computer.runtime.ComputerRuntime``: canned answers, recorded calls."""

    def __init__(self):
        self.status_result = {"state": "running", "detail": ""}
        self.ensure_error = None
        self.rt = {"backend": "fake", "container": "c", "cdp_port": 1, "screen_port": 2,
                   "token": "t", "image": "fake", "mode": "browser"}
        self.pages = [{"id": "T1", "url": "https://example.com/", "title": "Example"}]
        self.calls = []

    def status(self, home, timeout=10.0):
        self.calls.append(("status", timeout))
        return dict(self.status_result)

    def prepare(self, home):
        self.calls.append(("prepare",))

    def ensure_running(self, home, timeout=30.0):
        self.calls.append(("ensure_running", timeout))
        if self.ensure_error is not None:
            raise self.ensure_error
        return dict(self.rt)

    def stop(self, home):
        self.calls.append(("stop",))

    def cdp_ws_url(self, rt):
        return f"ws://127.0.0.1:{rt['cdp_port']}/devtools/browser/x"

    def tabs(self, rt):
        return [dict(page) for page in self.pages]

    def activate(self, rt, tab_id):
        self.calls.append(("activate", tab_id))

    def close_tab(self, rt, tab_id):
        self.calls.append(("close_tab", tab_id))

    def thumbnail(self, rt):
        return b"\xff\xd8fake-jpeg\xff\xd9"

    def set_mode(self, rt, mode):
        self.calls.append(("set_mode", mode))


@pytest.fixture()
def fake_runtime(monkeypatch):
    """Installs a FakeRuntime as ``computer.runtime.get_runtime()`` (the top-level
    ``computer`` package the dashboard backend and these tests import)."""
    from computer import runtime

    fake = FakeRuntime()
    monkeypatch.setattr(runtime, "get_runtime", lambda: fake)
    return fake


def _ensure_paths():
    for path in (str(HERMES_AGENT), str(PLUGIN_ROOT)):
        if path not in sys.path:
            sys.path.insert(0, path)


_ensure_paths()
