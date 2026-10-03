"""Hermuse agent-plugin entry point (``register(ctx)`` called by the loader).

Registers the six Hermuse tools, the ``hermuse:hermuse`` skill, conversational
and proactive-behaviour system-prompt sections, the Activity task recorder
(``pre_llm_call`` / ``post_llm_call`` / ``on_session_end`` hooks and the
``hermuse_task_summary`` auxiliary task, see :mod:`task_recorder`), the
``hermes hermuse`` CLI, the ``hermuse`` browser provider (the agent's computer)
and its ``pre_tool_call`` / ``transform_tool_result`` hooks, restarts the
subscription bridge when it was set up and does not run (see
:func:`subscription_bridge.start_if_configured`), and — inside a running
dashboard — mounts the dashboard backend right away (see
:func:`mount_dashboard_api`). Cron jobs are NOT auto-registered here:
installing a plugin must not start background agents as a side effect — the
operator runs ``hermes hermuse enable`` (or the Hermuse app calls the
equivalent REST route).
"""

from __future__ import annotations

import importlib.util
import logging
import sys
from pathlib import Path

from . import agent_tools, plugin_cli, subscription_bridge, task_recorder
from .computer import hooks as computer_hooks
from .computer.provider import make_provider

logger = logging.getLogger(__name__)

SKILL_NAME = "hermuse"
SKILL_DESCRIPTION = (
    "Hermuse feed and automations during chat: publish useful grounded updates "
    "with feed_post, schedule reminders and recurring work with Hermes "
    "cronjob_manage into the main chat, track commitments as goals, and use "
    "Ideas, Library and Reflections, honouring PREFERENCES.md."
)

CONVERSATION_GUIDANCE = (
    "Hermuse surfaces are backed by real tools, not chat prose. Use only tools "
    "available in this session; if one is unavailable or fails, explain the "
    "limitation instead of claiming that something was saved or scheduled. "
    "Load the hermuse:hermuse skill for the product workflow.\n\n"
    "During conversation, use feed_post for genuinely useful discoveries, "
    "research results or completed-work summaries worth keeping in the user's "
    "feed, as well as explicit requests to post. First read the active profile's "
    "HERMES_HOME/hermuse/PREFERENCES.md and FEED_PROMPT.md, honour topic, timing "
    "and format preferences, and check recent feed entries to avoid duplicates. "
    "Ground the post in actual conversation or tool results and link sources "
    "when applicable. Do not post every reply, invent activity, seed sample "
    "content or publish just to fill an empty feed. A successful feed_post "
    "result is what confirms publication.\n\n"
    "When the user requests a reminder, recurring task or automation, use "
    "Hermes cronjob_manage to create or update a real scheduled job in the "
    "current profile. Inspect existing jobs before creating a duplicate or "
    "changing one; clarify missing timing or task details. Job prompts must "
    "be self-contained. For jobs meant to populate Hermuse surfaces, include "
    "the hermuse:hermuse skill and require the appropriate persistence tool "
    "(for a feed job, feed_post), not just a final chat response. Confirm the "
    "schedule and job id only after a successful tool result, and relay any "
    "scheduler or delivery warnings. Never create unsolicited schedules, "
    "bypass approval requirements or approve actions on the user's behalf."
)

BEHAVIOUR_SECTION_ID = "hermuse_behaviour"
BEHAVIOUR_GUIDANCE = (
    "You are a proactive personal agent; the user's main chat is the session "
    "\"Bot Chat\".\n"
    "- Every reminder or later/recurring action, even 1 minute away, MUST be "
    "cronjob_manage action=\"create\", deliver=\"bot-chat\"; schedule \"in 2m\", "
    "\"in 2h\" or an ISO time once, \"every day 8am\" or cron to recur. Its prompt "
    "is self-contained; its final response is the message to the user (\"Rappel : "
    "boire un verre d'eau.\"). Never wait, sleep or poll in a turn to emulate a "
    "timer. Confirm in one short line with the fire time. Never ask which "
    "platform or channel.\n"
    "- Track multi-day commitments and things to keep in mind with goal_track "
    "(source=\"agent\" on your initiative, cron_job_id of its job, parent_id for "
    "a step); keep status_line current with goal_update.\n"
    "- Offer 2-4 choices with clarify. Every feed_post needs why.\n"
    "- [Cronjob \"...\" output messages are scheduled output, not the user: tell "
    "the user what matters, else reply exactly NO_REPLY. If it says \"Ask the "
    "user\", ask with clarify and wait; do not act on it yourself."
)

PLUGIN_NAME = "hermuse"
API_PREFIX = f"/api/plugins/{PLUGIN_NAME}"
# Same module name as Hermes' startup mount (web_server_dashboard._mount_plugin_api_routes).
API_MODULE = f"hermes_dashboard_plugin_{PLUGIN_NAME}"
API_FILE = Path(__file__).resolve().parent / "dashboard" / "plugin_api.py"
SPA_CATCH_ALL = "/{full_path:path}"


def register(ctx) -> None:
    agent_tools.register_tools(ctx)
    ctx.register_system_prompt_section("hermuse.conversation", CONVERSATION_GUIDANCE)
    ctx.register_system_prompt_section(BEHAVIOUR_SECTION_ID, BEHAVIOUR_GUIDANCE)
    task_recorder.register(ctx)
    try:
        skill_md = Path(__file__).parent / "skills" / "hermuse" / "SKILL.md"
        ctx.register_skill(SKILL_NAME, skill_md, SKILL_DESCRIPTION)
    except (FileNotFoundError, ValueError) as exc:
        logger.warning("hermuse: skill registration skipped: %s", exc)
    ctx.register_cli_command(
        name="hermuse",
        help="Hermuse product layer (status, enable/disable cron jobs, doctor, computer)",
        setup_fn=plugin_cli.register_cli,
        handler_fn=plugin_cli.dispatch,
        description=(
            "Feed, Ideas, Goals, Library artifacts, Reflections and proactive "
            "preferences stored under HERMES_HOME/hermuse/. See: hermes hermuse doctor"
        ),
    )
    ctx.register_browser_provider(make_provider())
    # Control is never reset here: register() runs in every Hermes process
    # (agent workers included) and would wipe a live Take control lease.
    ctx.register_hook("pre_tool_call", computer_hooks.pre_tool_call)
    ctx.register_hook("transform_tool_result", computer_hooks.transform_tool_result)
    _start_bridge()
    mount_dashboard_api()


def _start_bridge() -> None:
    """Bring back a subscription bridge set up earlier (server reboot, crash).

    Runs in every Hermes process loading the plugin: one ``/proc`` read when
    the bridge runs, never a wait or a download. Never raises.
    """
    try:
        from hermes_constants import get_hermes_home

        subscription_bridge.start_if_configured(get_hermes_home())
    except Exception as exc:  # noqa: BLE001 — plugin loading must never fail on the bridge
        logger.warning("hermuse: subscription bridge not checked: %s", exc)


def mount_dashboard_api() -> None:
    """Serve ``/api/plugins/hermuse/*`` from a dashboard that was running before the install.

    Hermes imports plugin backends once, while ``hermes_cli.web_server`` is
    imported (``_mount_plugin_api_routes``, just before the SPA catch-all
    ``/{full_path:path}``), so a plugin installed later 404s until the
    dashboard restarts. Installing or enabling it from the dashboard runs this
    ``register`` in the dashboard process, which mounts the same router under
    the same prefix — before the catch-all, which would shadow it otherwise —
    only when:

    * the dashboard is fully imported (the catch-all exists): during that
      import the startup mount is still to come, and does it;
    * no ``/api/plugins/hermuse/`` route exists (startup or an earlier
      ``register`` mounted it: forced rediscoveries call ``register`` again);
    * ``hermuse`` is enabled, the gate Hermes applies before importing a user
      plugin's backend.

    Never raises.
    """
    web_server = sys.modules.get("hermes_cli.web_server")
    app = getattr(web_server, "app", None)
    if app is None:
        return
    try:
        routes = app.router.routes
        catch_all = next((i for i, route in enumerate(routes)
                          if getattr(route, "path", None) == SPA_CATCH_ALL), None)
        if catch_all is None:
            return
        if any(str(getattr(route, "path", "")).startswith(API_PREFIX + "/") for route in routes):
            return
        from hermes_cli.plugins_cmd import _get_disabled_set, _get_enabled_set

        if PLUGIN_NAME not in _get_enabled_set() or PLUGIN_NAME in _get_disabled_set():
            return
        spec = importlib.util.spec_from_file_location(API_MODULE, API_FILE)
        if spec is None or spec.loader is None:
            raise ImportError(f"cannot load {API_FILE}")
        module = importlib.util.module_from_spec(spec)
        # Registered before exec_module like the startup mount (pydantic resolves
        # annotations by module name); setdefault also makes a concurrent
        # register() back off instead of mounting twice.
        if sys.modules.setdefault(API_MODULE, module) is not module:
            return
        count = len(routes)  # include_router appends after the catch-all...
        try:
            spec.loader.exec_module(module)
            app.include_router(module.router, prefix=API_PREFIX)
        except BaseException:
            del routes[count:]
            sys.modules.pop(API_MODULE, None)
            raise
        added = routes[count:]
        del routes[count:]
        routes[catch_all:catch_all] = added  # ...so move them before it
        logger.info("hermuse: mounted %d dashboard routes at %s/ without a restart",
                    len(added), API_PREFIX)
    except (Exception, SystemExit) as exc:  # noqa: BLE001 — a dashboard restart still mounts it
        logger.warning("hermuse: dashboard routes not mounted live (restart the dashboard): %s", exc)
