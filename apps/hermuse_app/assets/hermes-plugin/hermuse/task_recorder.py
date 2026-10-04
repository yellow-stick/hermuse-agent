"""Activity tasks: one record per agent turn, written by lifecycle hooks.

``pre_llm_call`` notes when a turn starts and what asked for it,
``post_llm_call`` records the finished turn (``completed``) with a heuristic
title/summary right away, then a single background worker asks the auxiliary
model (task ``hermuse_task_summary``, via ``ctx.llm.complete_structured``) for a
better title and one-line result. ``on_session_end`` marks turns that ended
``interrupted`` / ``failed`` (recording them when ``post_llm_call`` never fired).

Sources: cron run sessions (``cron_<job>_<stamp>`` / platform ``cron``) are
``cron``, or ``heartbeat`` for the Hermuse heartbeat job; a heartbeat run that
ends in a silence marker (``NO_REPLY``) is not recorded. One scheduled run is
one task: the run session carries the job name and the tools, so the Bot Chat
turn that relays its output (``[Cronjob "<name>" output — …``) is not recorded,
and neither are delegated subagent turns (part of their parent's task).
Everything else is ``chat``.

Hooks run on the agent thread: they only snapshot the turn and enqueue, the
store writes and model call happen on the worker, inside a copy of the hook's
context so the profile's ``HERMES_HOME`` override still applies.
"""

from __future__ import annotations

import atexit
import contextvars
import logging
import queue
import re
import threading
from pathlib import Path
from typing import Any, Callable, Optional

from . import store
from .cron_specs import HEARTBEAT_KEY, HEARTBEAT_NAME, ORIGIN_SOURCE

logger = logging.getLogger(__name__)

AUX_TASK = "hermuse_task_summary"
AUX_TASK_DISPLAY_NAME = "Hermuse task summaries"
AUX_TASK_DESCRIPTION = (
    "Titles each agent task and writes its one-line result for the Hermuse Activity list."
)

SUMMARY_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string", "description": "3-7 words, imperative, in the user's language."},
        "summary": {"type": "string", "description": "One line: what was done and the outcome."},
    },
    "required": ["title", "summary"],
    "additionalProperties": False,
}

SUMMARY_INSTRUCTIONS = (
    "You label one finished task of a personal AI agent for its activity list. "
    "Return a title of 3 to 7 words in the imperative mood (\"Set daily 8am "
    "briefing\", \"Compare flights to Lisbon\") and a summary of one line saying "
    "what was done and the outcome (\"Scheduled a daily 8:00 AM Nantes "
    "briefing\"). Write both in the language the user wrote in. No quotes, no "
    "trailing period in the title, no markdown."
)

TITLE_MAX = 80
SUMMARY_MAX = 200
_INPUT_MAX = 4000
_PENDING_CAP = 512
_DRAIN_TIMEOUT_S = 10.0

_CRON_SESSION_RE = re.compile(r"^cron_(?P<job>[0-9A-Za-z]+)_\d{8}_\d{6}$")
_RELAY_RE = re.compile(r'^\[Cronjob "(?P<name>.*?)" output — ')
_SENTENCE_RE = re.compile(r"^(.+?[.!?])(\s|$)")
_MARKDOWN_RE = re.compile(r"\*+|__|`+|^\s*(?:#+|>)\s*|\[([^\]]*)\]\([^)]*\)")

_FALLBACK_SILENCE = frozenset({"NO_REPLY", "NO REPLY", "[SILENT]", "SILENT"})


def is_silence(text: str) -> bool:
    """Hermes' own loose silence matcher for autonomous lanes when importable."""
    try:
        from gateway.response_filters import is_autonomous_silence_response
    except ImportError:
        return " ".join(text.strip().upper().split()) in _FALLBACK_SILENCE
    return bool(is_autonomous_silence_response(text))


def _text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):  # multimodal content parts
        return " ".join(
            str(part.get("text") or "") for part in value
            if isinstance(part, dict) and part.get("type") == "text")
    return "" if value is None else str(value)


def _plain_line(text: str) -> str:
    """First non-blank line, markdown markers and link targets removed, spaces collapsed."""
    for line in text.splitlines():
        line = _MARKDOWN_RE.sub(lambda m: m.group(1) or "", line).strip(" -•\t")
        if line:
            return " ".join(line.split())
    return ""


def _clip(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    cut = text[: limit - 1].rsplit(" ", 1)[0] or text[: limit - 1]
    return cut.rstrip(" ,;:") + "…"


def heuristic_title(user_message: str, label: str = "") -> str:
    """Scheduled work is titled by its job name; a request by its first line."""
    if label:
        return _clip(label, TITLE_MAX)
    line = _plain_line(user_message)
    return _clip(line.rstrip("?.!:"), TITLE_MAX) if line else "Untitled task"


def heuristic_summary(final_text: str) -> str:
    """First sentence of the final answer."""
    line = _plain_line(final_text)
    match = _SENTENCE_RE.match(line)
    return _clip(match.group(1) if match else line, SUMMARY_MAX)


def turn_tools(conversation_history: Any) -> list[str]:
    """Tool names called since the turn's (last) user message, first-call order."""
    if not isinstance(conversation_history, list):
        return []
    start = 0
    for index in range(len(conversation_history) - 1, -1, -1):
        message = conversation_history[index]
        if isinstance(message, dict) and message.get("role") == "user":
            start = index + 1
            break
    names: list[str] = []
    for message in conversation_history[start:]:
        if not isinstance(message, dict) or message.get("role") != "assistant":
            continue
        for call in message.get("tool_calls") or ():
            function = call.get("function") if isinstance(call, dict) else getattr(call, "function", None)
            name = function.get("name") if isinstance(function, dict) else getattr(function, "name", None)
            if isinstance(name, str) and name and name not in names:
                names.append(name)
    return names


def _cron_job(job_id: str) -> Optional[dict[str, Any]]:
    try:
        from cron import jobs as cron_jobs

        job = cron_jobs.get_job(job_id)
    except Exception as exc:  # store unreadable or cron unavailable in this process
        logger.debug("hermuse tasks: cron job %s not resolved: %s", job_id, exc)
        return None
    return job if isinstance(job, dict) else None


def classify(session_id: str, platform: str, user_message: str) -> Optional[tuple[str, str]]:
    """``(source, label)`` of a turn, or None when it is not a task of its own
    (subagent turns, Bot Chat relays of a cron run's output). *label* is the job
    name for scheduled work ("" otherwise)."""
    if platform == "subagent" or _RELAY_RE.match(user_message.lstrip()):
        return None
    match = _CRON_SESSION_RE.match(session_id or "")
    if match or platform == "cron":
        job = _cron_job(match.group("job")) if match else None
        name = str((job or {}).get("name") or "")
        origin = (job or {}).get("origin")
        heartbeat = origin == {"source": ORIGIN_SOURCE, "key": HEARTBEAT_KEY} or name == HEARTBEAT_NAME
        return ("heartbeat" if heartbeat else "cron"), name
    return "chat", ""


def _default_root() -> Path:
    from hermes_constants import get_hermes_home

    return store.hermuse_root(get_hermes_home())


class TaskRecorder:
    """Hook callbacks + the background worker. One instance per plugin load."""

    def __init__(
        self,
        llm: Any = None,
        *,
        resolve_root: Callable[[], Path] = _default_root,
    ) -> None:
        self._llm = llm
        self._resolve_root = resolve_root
        self._lock = threading.Lock()
        self._turns: dict[tuple[str, str], dict[str, Any]] = {}
        self._queue: "queue.Queue[tuple[contextvars.Context, Callable[[], None]]]" = queue.Queue()
        self._worker: Optional[threading.Thread] = None
        self._exiting = False
        atexit.register(self.drain)

    # --- hooks --------------------------------------------------------------

    def pre_llm_call(self, session_id: str = "", turn_id: str = "", user_message: Any = None,
                     platform: str = "", **_: Any) -> None:
        if not session_id or not turn_id:
            return None
        user_text = _text(user_message)
        kind = classify(session_id, platform or "", user_text)
        with self._lock:
            if len(self._turns) >= _PENDING_CAP:  # turns whose end hook never came
                self._turns.pop(next(iter(self._turns)))
            self._turns[(session_id, turn_id)] = {
                "started_at": store.utcnow_iso(), "user_message": user_text, "kind": kind,
                "recorded": False,
            }
        return None

    def post_llm_call(self, session_id: str = "", turn_id: str = "", user_message: Any = None,
                      assistant_response: Any = None, conversation_history: Any = None,
                      platform: str = "", **_: Any) -> None:
        if not session_id or not turn_id:
            return
        key = (session_id, turn_id)
        with self._lock:
            turn = self._turns.get(key)
        user_text = _text(user_message) or (turn or {}).get("user_message", "")
        kind = turn["kind"] if turn else classify(session_id, platform or "", user_text)
        final_text = _text(assistant_response)
        if kind is None or (kind[0] == "heartbeat" and is_silence(final_text)):
            with self._lock:
                self._turns.pop(key, None)
            return
        source, label = kind
        now = store.utcnow_iso()
        tools = turn_tools(conversation_history)
        task = {
            "id": store.task_id(session_id, turn_id),
            "session_id": session_id,
            "turn_id": turn_id,
            "title": heuristic_title(user_text, label),
            "summary": heuristic_summary(final_text),
            "status": "completed",
            "source": source,
            "started_at": (turn or {}).get("started_at") or now,
            "finished_at": now,
            "tools": tools,
        }
        with self._lock:
            self._turns[key] = {**(turn or {}), "kind": kind, "recorded": True}
        summary_input = {"user_message": user_text, "final_text": final_text, "tools": tools,
                         "label": label}
        root = self._resolve_root()
        self._submit(lambda: self._record(root, task, summary_input))

    def on_session_end(self, session_id: str = "", turn_id: str = "", completed: bool = False,
                       failed: bool = False, interrupted: bool = False, **_: Any) -> None:
        if not session_id or not turn_id:
            return
        with self._lock:
            turn = self._turns.pop((session_id, turn_id), None)
        if turn is None or turn.get("kind") is None or not (failed or interrupted):
            return
        status = "interrupted" if interrupted else "failed"
        tid = store.task_id(session_id, turn_id)
        root = self._resolve_root()
        if turn.get("recorded"):
            self._submit(lambda: store.update_task(root, tid, status=status))
            return
        source, label = turn["kind"]
        task = {
            "id": tid,
            "session_id": session_id,
            "turn_id": turn_id,
            "title": heuristic_title(turn.get("user_message", ""), label),
            "summary": "Stopped before it finished." if interrupted else "Failed before it finished.",
            "status": status,
            "source": source,
            "started_at": turn.get("started_at") or store.utcnow_iso(),
            "finished_at": store.utcnow_iso(),
            "tools": [],
        }
        self._submit(lambda: self._record(root, task, None))

    # --- worker ---------------------------------------------------------------

    def _submit(self, job: Callable[[], None]) -> None:
        self._queue.put((contextvars.copy_context(), job))
        with self._lock:
            if self._worker is None or not self._worker.is_alive():
                self._worker = threading.Thread(
                    target=self._run, name="hermuse-task-recorder", daemon=True)
                self._worker.start()

    def _run(self) -> None:
        while True:
            context, job = self._queue.get()
            try:
                context.run(job)
            except Exception as exc:
                logger.warning("hermuse tasks: recording failed: %s", exc)
            finally:
                self._queue.task_done()

    def drain(self, timeout: float = _DRAIN_TIMEOUT_S) -> bool:
        """Wait for queued writes (model summaries are skipped once exiting);
        True when the queue emptied in time."""
        self._exiting = True
        return self.flush(timeout)

    def flush(self, timeout: float = _DRAIN_TIMEOUT_S) -> bool:
        """Wait until every queued job ran; True when it finished within *timeout*."""
        done = threading.Event()

        def _join() -> None:
            self._queue.join()
            done.set()

        threading.Thread(target=_join, name="hermuse-task-flush", daemon=True).start()
        return done.wait(timeout)

    def _record(self, root: Path, task: dict[str, Any], summary_input: Optional[dict[str, Any]]) -> None:
        store.save_task(root, task)
        if summary_input is None or self._exiting:
            return
        result = self.summarize(summary_input)
        if result is not None:
            store.update_task(root, task["id"], **result)

    def summarize(self, data: dict[str, Any]) -> Optional[dict[str, str]]:
        """``{"title", "summary"}`` from the auxiliary model, None when it is
        unavailable or answers out of shape (the heuristic record then stays)."""
        if self._llm is None:
            return None
        parts = []
        if data.get("label"):
            parts.append(f"Scheduled job: {data['label']}")
        parts.append(f"Request:\n{_clip(data.get('user_message', ''), _INPUT_MAX)}")
        if data.get("tools"):
            parts.append("Tools used: " + ", ".join(data["tools"]))
        parts.append(f"Final answer:\n{_clip(data.get('final_text', ''), _INPUT_MAX)}")
        try:
            result = self._llm.complete_structured(
                instructions=SUMMARY_INSTRUCTIONS,
                input=[{"type": "text", "text": "\n\n".join(parts)}],
                json_schema=SUMMARY_SCHEMA,
                schema_name=AUX_TASK,
                task=AUX_TASK,
                purpose="Hermuse Activity task summary",
                max_tokens=300,
            )
        except Exception as exc:
            logger.info("hermuse tasks: summary model unavailable, keeping heuristic: %s", exc)
            return None
        parsed = getattr(result, "parsed", None)
        if not isinstance(parsed, dict):
            return None
        title = _plain_line(str(parsed.get("title") or "")).rstrip(".")
        summary = _plain_line(str(parsed.get("summary") or ""))
        if not title or not summary:
            return None
        return {"title": _clip(title, TITLE_MAX), "summary": _clip(summary, SUMMARY_MAX)}


def register(ctx: Any) -> TaskRecorder:
    """Register the auxiliary task and the three hooks on a PluginContext."""
    try:
        ctx.register_auxiliary_task(
            AUX_TASK, display_name=AUX_TASK_DISPLAY_NAME, description=AUX_TASK_DESCRIPTION)
    except (AttributeError, ValueError) as exc:
        logger.warning("hermuse tasks: auxiliary task not registered: %s", exc)
    try:
        llm = ctx.llm
    except Exception as exc:  # host without the plugin LLM facade
        logger.warning("hermuse tasks: no plugin LLM, summaries stay heuristic: %s", exc)
        llm = None
    recorder = TaskRecorder(llm)
    ctx.register_hook("pre_llm_call", recorder.pre_llm_call)
    ctx.register_hook("post_llm_call", recorder.post_llm_call)
    ctx.register_hook("on_session_end", recorder.on_session_end)
    return recorder
