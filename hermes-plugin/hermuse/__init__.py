"""Hermuse agent-plugin entry point (``register(ctx)`` called by the loader).

Registers the six Hermuse tools, the ``hermuse:hermuse`` skill and the
``hermes hermuse`` CLI. Cron jobs are NOT auto-registered here: installing a
plugin must not start background agents as a side effect — the operator runs
``hermes hermuse enable`` (or the Hermuse app calls the equivalent REST route).
"""

from __future__ import annotations

import logging
from pathlib import Path

from . import agent_tools, plugin_cli

logger = logging.getLogger(__name__)

SKILL_NAME = "hermuse"
SKILL_DESCRIPTION = (
    "Hermuse product layer: when to call feed_post, idea_propose, goal_track, "
    "goal_update, artifact_save and reflection_write, honouring PREFERENCES.md."
)


def register(ctx) -> None:
    agent_tools.register_tools(ctx)
    try:
        skill_md = Path(__file__).parent / "skills" / "hermuse" / "SKILL.md"
        ctx.register_skill(SKILL_NAME, skill_md, SKILL_DESCRIPTION)
    except (FileNotFoundError, ValueError) as exc:
        logger.warning("hermuse: skill registration skipped: %s", exc)
    ctx.register_cli_command(
        name="hermuse",
        help="Hermuse product layer (status, enable/disable cron jobs, doctor)",
        setup_fn=plugin_cli.register_cli,
        handler_fn=plugin_cli.dispatch,
        description=(
            "Feed, Ideas, Goals, Library artifacts, Reflections and proactive "
            "preferences stored under HERMES_HOME/hermuse/. See: hermes hermuse doctor"
        ),
    )
