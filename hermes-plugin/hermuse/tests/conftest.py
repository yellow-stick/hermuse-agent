"""Shared pytest fixtures: a throwaway HERMES_HOME + importable plugin root."""

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


def _ensure_paths():
    for path in (str(HERMES_AGENT), str(PLUGIN_ROOT)):
        if path not in sys.path:
            sys.path.insert(0, path)


_ensure_paths()
