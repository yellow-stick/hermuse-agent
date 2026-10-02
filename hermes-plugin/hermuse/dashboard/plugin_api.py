"""Hermuse dashboard backend, mounted at /api/plugins/hermuse/.

Loaded by the dashboard plugin system (``hermes_cli/web_server_dashboard.py``)
from this file path via ``importlib`` — NOT as part of the plugin package — so
it adds its parent dir to ``sys.path`` to import the sibling ``store`` and
``subscription_bridge`` modules (stdlib-only, shared with the agent plugin),
``dashboard_restart`` and the ``computer`` package. HTTP auth (the
``/bridge/*`` and ``/dashboard/*`` routes included) is enforced by Hermes'
existing ``/api/`` gate; the computer WebSocket (which that gate does not
cover) takes a single-use ticket from ``POST /computer/ticket``, like Hermes'
own ``/api/display/ws``.
"""

from __future__ import annotations

import asyncio
import json
import logging
import sys
import urllib.parse
from pathlib import Path
from typing import Any, Callable, Optional

from fastapi import APIRouter, HTTPException, Query, WebSocket
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import dashboard_restart  # noqa: E402
import store  # noqa: E402
import subscription_bridge  # noqa: E402
from computer import runtime as computer_runtime  # noqa: E402
from computer import setup as computer_setup  # noqa: E402
from computer import state as computer_state  # noqa: E402
from hermes_cli.web_server_chat import _ws_request_is_allowed  # noqa: E402
from hermes_constants import get_hermes_home  # noqa: E402

log = logging.getLogger(__name__)
router = APIRouter()

# Take control leases only live in this process's WebSocket connections, so
# none can survive a dashboard (re)start: the agent holds control again.
try:
    computer_state.reset_control(get_hermes_home())
except OSError as exc:
    log.warning("hermuse computer: could not reset control: %s", exc)

# A bridge set up earlier comes back with the dashboard (server reboot, crash).
subscription_bridge.start_if_configured(get_hermes_home())


def _root() -> Path:
    return store.hermuse_root(get_hermes_home())


def _not_found(what: str) -> HTTPException:
    return HTTPException(status_code=404, detail=f"{what} not found")


# --- Feed ------------------------------------------------------------------


class FeedPostBody(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1, max_length=20000)
    topic: str = Field(default="", max_length=120)
    sources: list[str] = Field(default_factory=list, max_length=20)


class ReactBody(BaseModel):
    reaction: str = Field(pattern="^(love|discuss)$")


@router.get("/feed")
def list_feed(limit: int = Query(default=50, ge=1, le=200)):
    return {"posts": store.list_feed(_root(), limit)}


@router.get("/feed/{post_id}")
def get_feed_post(post_id: str):
    record = store.get_feed_post(_root(), post_id)
    if record is None:
        raise _not_found("feed post")
    return record


@router.post("/feed", status_code=201)
def create_feed_post(payload: FeedPostBody):
    return store.post_feed(
        _root(),
        title=payload.title.strip(),
        body=payload.body,
        topic=payload.topic.strip(),
        sources=[s for s in (s.strip() for s in payload.sources) if s],
    )


@router.post("/feed/{post_id}/react")
def react_feed_post(post_id: str, payload: ReactBody):
    record = store.react_feed(_root(), post_id, payload.reaction)
    if record is None:
        raise _not_found("feed post")
    return record


# --- Ideas -----------------------------------------------------------------


class IdeaBody(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    pitch: str = Field(min_length=1, max_length=8000)
    group: str = Field(min_length=1, max_length=80)
    first_step: str = Field(default="", max_length=2000)


class IdeaFeedbackBody(BaseModel):
    feedback: str = Field(min_length=1, max_length=4000)


@router.get("/ideas")
def list_ideas(limit: int = Query(default=200, ge=1, le=500)):
    return {"ideas": store.list_ideas(_root(), limit)}


@router.get("/ideas/{idea_id}")
def get_idea(idea_id: str):
    record = store.get_idea(_root(), idea_id)
    if record is None:
        raise _not_found("idea")
    return record


@router.post("/ideas", status_code=201)
def create_idea(payload: IdeaBody):
    return store.propose_idea(
        _root(),
        title=payload.title.strip(),
        pitch=payload.pitch,
        group=payload.group.strip(),
        first_step=payload.first_step,
    )


@router.post("/ideas/{idea_id}/feedback")
def add_idea_feedback(idea_id: str, payload: IdeaFeedbackBody):
    record = store.feedback_idea(_root(), idea_id, payload.feedback)
    if record is None:
        raise _not_found("idea")
    return record


# --- Goals -----------------------------------------------------------------


class GoalBody(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    category: str = Field(pattern="^(health|relationships|finance|career|interests|productivity|something_else)$")
    why: str = Field(min_length=1, max_length=8000)
    target_date: str = Field(default="", max_length=40)


class GoalUpdateBody(BaseModel):
    note: str = Field(min_length=1, max_length=8000)
    progress: str = Field(default="", max_length=500)
    status: str = Field(default="", pattern="^(|tracking|done)$")


@router.get("/goals")
def list_goals(limit: int = Query(default=200, ge=1, le=500)):
    return {"goals": store.list_goals(_root(), limit)}


@router.get("/goals/{goal_id}")
def get_goal(goal_id: str):
    record = store.get_goal(_root(), goal_id)
    if record is None:
        raise _not_found("goal")
    return record


@router.post("/goals", status_code=201)
def create_goal(payload: GoalBody):
    try:
        return store.track_goal(
            _root(),
            title=payload.title.strip(),
            category=payload.category,
            why=payload.why,
            target_date=payload.target_date.strip(),
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post("/goals/{goal_id}/update")
def update_goal_route(goal_id: str, payload: GoalUpdateBody):
    record = store.update_goal(
        _root(), goal_id, payload.note, payload.progress, payload.status
    )
    if record is None:
        raise _not_found("goal")
    return record


# --- Artifacts -------------------------------------------------------------


@router.get("/artifacts")
def list_artifacts(limit: int = Query(default=200, ge=1, le=500)):
    return {"artifacts": store.list_artifacts(_root(), limit)}


@router.get("/artifacts/{artifact_id}")
def get_artifact(artifact_id: str):
    record = store.get_artifact(_root(), artifact_id)
    if record is None:
        raise _not_found("artifact")
    return record


@router.get("/artifacts/{artifact_id}/download")
def download_artifact(artifact_id: str):
    path = store.artifact_file(_root(), artifact_id)
    if path is None:
        raise _not_found("artifact file")
    record = store.get_artifact(_root(), artifact_id) or {}
    return FileResponse(path=str(path), filename=Path(path).name, media_type="application/octet-stream")


# --- Reflections -----------------------------------------------------------


@router.get("/reflections")
def list_reflections(limit: int = Query(default=90, ge=1, le=365)):
    return {"reflections": store.list_reflections(_root(), limit)}


@router.get("/reflections/{day}")
def get_reflection(day: str):
    record = store.get_reflection(_root(), day)
    if record is None:
        raise _not_found("reflection")
    return record


# --- Preferences -----------------------------------------------------------


class MarkdownBody(BaseModel):
    content: str = Field(max_length=100000)


@router.get("/preferences")
def get_preferences():
    return {"name": store.PREFERENCES_FILE, "content": store.read_managed(_root(), store.PREFERENCES_FILE)}


@router.put("/preferences")
def put_preferences(payload: MarkdownBody):
    store.write_managed(_root(), store.PREFERENCES_FILE, payload.content)
    return {"ok": True, "name": store.PREFERENCES_FILE}


# --- Managed files (allow-listed) ------------------------------------------


@router.get("/files")
def list_managed_files():
    return {"files": list(store.MANAGED_FILES)}


@router.get("/files/{name}")
def get_managed_file(name: str):
    # Exact allow-list match — no path joining of user input, so traversal
    # ("../", absolute paths, unknown names) can never resolve to a file.
    if name not in store.MANAGED_FILES:
        raise _not_found("file")
    return {"name": name, "content": store.read_managed(_root(), name)}


@router.put("/files/{name}")
def put_managed_file(name: str, payload: MarkdownBody):
    if name not in store.MANAGED_FILES:
        raise _not_found("file")
    store.write_managed(_root(), name, payload.content)
    return {"ok": True, "name": name}


# --- Cron ------------------------------------------------------------------


@router.get("/cron")
def cron_status():
    try:
        from cron import jobs as cron_jobs
        from cron_specs import SPECS, find_job  # noqa: E402 — plugin-root import, see sys.path above
    except ImportError as exc:
        raise HTTPException(status_code=500, detail=f"cron backend unavailable: {exc}") from exc
    out: list[dict[str, Any]] = []
    for spec in SPECS:
        job = find_job(cron_jobs, spec.key)
        out.append({
            "key": spec.key,
            "name": spec.name,
            "schedule": spec.schedule,
            "registered": job is not None,
            "job_id": job.get("id") if job else None,
            "enabled": bool(job.get("enabled", True)) if job else False,
            "next_run_at": job.get("next_run_at") if job else None,
        })
    return {"jobs": out}


@router.post("/cron/enable")
def cron_enable():
    try:
        from cron import jobs as cron_jobs
        from cron_specs import register_all  # noqa: E402
    except ImportError as exc:
        raise HTTPException(status_code=500, detail=f"cron backend unavailable: {exc}") from exc
    results = register_all(cron_jobs)
    return {
        "jobs": [
            {"key": key, "job_id": record.get("id"), "created": created,
             "next_run_at": record.get("next_run_at")}
            for key, (record, created) in results.items()
        ]
    }


@router.post("/cron/disable")
def cron_disable():
    try:
        from cron import jobs as cron_jobs
        from cron_specs import remove_all  # noqa: E402
    except ImportError as exc:
        raise HTTPException(status_code=500, detail=f"cron backend unavailable: {exc}") from exc
    return {"removed": remove_all(cron_jobs)}


# --- Dashboard ---------------------------------------------------------------


@router.get("/dashboard")
def dashboard_status():
    """This start of the dashboard process: ``boot`` changes once it restarted."""
    return {"boot": dashboard_restart.BOOT}


@router.post("/dashboard/restart", status_code=202)
def restart_dashboard():
    """Restarts this dashboard in place once the answer is out (see ``dashboard_restart``)."""
    try:
        argv = dashboard_restart.command_line()
    except dashboard_restart.RestartUnavailable as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    if not dashboard_restart.schedule(argv):
        raise HTTPException(status_code=409, detail="The dashboard is already restarting.")
    return {"boot": dashboard_restart.BOOT}


# --- Subscription bridge ---------------------------------------------------


class BridgeLoginBody(BaseModel):
    provider: str = Field(min_length=1, max_length=40)


class BridgeCallbackBody(BaseModel):
    redirect_url: str = Field(min_length=1, max_length=subscription_bridge.MAX_REDIRECT_URL_CHARS)


class BridgeStateBody(BaseModel):
    state: str = Field(min_length=1, max_length=200)


def _bridge_call(action: Callable[..., Any], *args: Any) -> Any:
    """Bridge failures as HTTP: bad input 400, unavailable here/now 409, broken 502."""
    try:
        return action(get_hermes_home(), *args)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except subscription_bridge.BridgeUnavailable as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except subscription_bridge.BridgeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.get("/bridge/status")
def bridge_status():
    return subscription_bridge.status(get_hermes_home())


@router.post("/bridge/ensure")
def bridge_ensure():
    return _bridge_call(subscription_bridge.ensure)


@router.post("/bridge/login")
def bridge_start_login(payload: BridgeLoginBody):
    return _bridge_call(subscription_bridge.start_login, payload.provider)


@router.get("/bridge/login/status")
def bridge_login_status(state: str = Query(min_length=1, max_length=200)):
    return _bridge_call(subscription_bridge.login_status, state)


@router.post("/bridge/login/callback")
def bridge_login_callback(payload: BridgeCallbackBody):
    return _bridge_call(subscription_bridge.submit_callback, payload.redirect_url)


@router.post("/bridge/login/cancel")
def bridge_cancel_login(payload: BridgeStateBody):
    return _bridge_call(subscription_bridge.cancel_login, payload.state)


# ``:path`` so a name with "/" (``..%2Fx.json``) reaches the validation (400)
# instead of missing the route.
@router.delete("/bridge/accounts/{name:path}")
def bridge_delete_account(name: str):
    if not _bridge_call(subscription_bridge.delete_account, name):
        raise _not_found("account")
    return {"ok": True, "name": name}


@router.get("/bridge/models")
def bridge_models():
    return _bridge_call(subscription_bridge.models)


# --- Computer --------------------------------------------------------------

_COMPUTER_TICKET_PROVIDER = "hermuse-computer"
_CLOSE_UNAVAILABLE = 4001
_CLOSE_BAD_TICKET = 4401
_CLOSE_NOT_ALLOWED = 4403
_STATE_PERIOD_S = 2.0
_UPSTREAM_ATTEMPTS = 10  # screend may still be starting right after ensure_running
_UPSTREAM_RETRY_S = 0.5
_UPSTREAM_MAX_MESSAGE = 16 * 1024 * 1024
_FPS_DEFAULT, _FPS_MIN, _FPS_MAX = 5, 1, 10
_INPUT_TYPES = frozenset({"move", "down", "up", "wheel", "key", "text"})
_TAB_ACTIONS = frozenset({"activate", "close"})


def _computer_mode(home: Path) -> str:
    mode = (computer_state.read_runtime(home) or {}).get("mode")
    return mode if mode in computer_runtime.MODES else "browser"


def _computer_status(home: Path) -> dict[str, Any]:
    status = computer_runtime.get_runtime().status(home)
    return {**status, "control": computer_state.read_control(home)["holder"],
            "mode": _computer_mode(home)}


@router.get("/computer/status")
def computer_status():
    return _computer_status(get_hermes_home())


@router.post("/computer/setup")
def computer_setup_route():
    return computer_setup.setup(get_hermes_home())


@router.post("/computer/start")
def computer_start():
    home = get_hermes_home()
    try:
        computer_runtime.get_runtime().ensure_running(home)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return _computer_status(home)


@router.post("/computer/stop")
def computer_stop():
    home = get_hermes_home()
    try:
        computer_runtime.get_runtime().stop(home)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return _computer_status(home)


@router.get("/computer/thumbnail")
def computer_thumbnail():
    rt = computer_state.read_runtime(get_hermes_home())
    try:
        if rt is None:
            raise RuntimeError("no runtime.json")
        jpeg = computer_runtime.get_runtime().thumbnail(rt)
    except Exception as exc:  # noqa: BLE001 — unreachable screend = not running
        raise HTTPException(status_code=409, detail="computer is not running") from exc
    return Response(content=jpeg, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


# ``:path`` so an id with "/" (``..%2Fx``) reaches the validation (400) instead
# of missing the route.
@router.get("/computer/snapshots/{tool_call_id:path}")
def computer_snapshot(tool_call_id: str):
    path = computer_state.snapshot_path(get_hermes_home(), tool_call_id)
    if path is None:
        raise HTTPException(status_code=400, detail="invalid tool call id")
    try:
        jpeg = path.read_bytes()
    except FileNotFoundError:
        raise _not_found("snapshot") from None
    return Response(content=jpeg, media_type="image/jpeg")


@router.post("/computer/ticket")
def computer_ticket():
    from hermes_cli.dashboard_auth.ws_tickets import mint_ticket

    return {"ticket": mint_ticket(user_id="hermuse", provider=_COMPUTER_TICKET_PROVIDER)}


def _consume_computer_ticket(ticket: str) -> bool:
    from hermes_cli.dashboard_auth.ws_tickets import TicketInvalid, consume_ticket

    if not ticket:
        return False
    try:
        info = consume_ticket(ticket)
    except TicketInvalid:
        return False
    return info.get("provider") == _COMPUTER_TICKET_PROVIDER


def _fps(raw: Optional[str]) -> int:
    try:
        fps = int(raw or _FPS_DEFAULT)
    except ValueError:
        fps = _FPS_DEFAULT
    return min(max(fps, _FPS_MIN), _FPS_MAX)


def _close_reason(text: str) -> str:
    return text.encode("utf-8")[:120].decode("utf-8", "ignore")  # a close frame holds <= 123 bytes


@router.websocket("/computer/ws")
async def computer_ws(ws: WebSocket) -> None:
    # Order of Hermes' /api/display/ws: Host/Origin/peer policy before accept;
    # ticket and computer state after it, so code + reason reach the client.
    if not _ws_request_is_allowed(ws):
        await ws.close(code=_CLOSE_NOT_ALLOWED)
        return
    await ws.accept()
    if not _consume_computer_ticket(ws.query_params.get("ticket", "")):
        await ws.close(code=_CLOSE_BAD_TICKET, reason="ticket missing, expired or used")
        return
    home = get_hermes_home()
    backend = computer_runtime.get_runtime()
    try:
        rt = await asyncio.to_thread(backend.ensure_running, home)
    except Exception as exc:  # noqa: BLE001 — any failure: the computer cannot start
        await ws.close(code=_CLOSE_UNAVAILABLE, reason=_close_reason(str(exc)))
        return
    await _ComputerViewer(ws, home, backend, rt).run(_fps(ws.query_params.get("fps")))


_viewers: set["_ComputerViewer"] = set()  # /computer/ws connections of this process


async def _broadcast_state() -> None:
    live = [viewer for viewer in _viewers if not viewer.closing]
    await asyncio.gather(*(viewer.push_state(force=True) for viewer in live),
                         return_exceptions=True)


class _ComputerViewer:
    """One ``/computer/ws`` connection bridged to screend's ``/stream``.

    Frames and geometry pass through untouched; ``state`` messages add control,
    mode and tabs. Input reaches the computer only from the viewer whose lease
    is the stored one; disconnecting releases this viewer's lease (a no-op when
    another viewer took over since).
    """

    def __init__(self, ws: WebSocket, home: Path, backend: Any, rt: dict[str, Any]) -> None:
        self.ws = ws
        self.home = home
        self.backend = backend
        self.rt = rt
        self.lease_id: Optional[str] = None
        self.sent_state: Optional[dict[str, Any]] = None
        self.closing = False
        self.send_lock = asyncio.Lock()
        self.state_lock = asyncio.Lock()

    async def _send(self, *, text: Optional[str] = None, data: Optional[bytes] = None) -> None:
        async with self.send_lock:
            if text is not None:
                await self.ws.send_text(text)
            else:
                await self.ws.send_bytes(data or b"")

    def _state(self) -> dict[str, Any]:
        """Blocking (control/runtime files + CDP tab list): run in a thread."""
        control = computer_state.read_control(self.home)
        try:
            pages = self.backend.tabs(self.rt)
        except Exception:  # noqa: BLE001 — Chromium restarting: no tabs for now
            pages = []
        return {
            "t": "state",
            "control": control["holder"],
            "mine": self.lease_id is not None and self.lease_id == control["lease_id"],
            "mode": _computer_mode(self.home),
            # /json/list is most-recently-used first: the first page is in front.
            "tabs": [{**page, "active": index == 0} for index, page in enumerate(pages)],
        }

    async def push_state(self, force: bool = False) -> None:
        async with self.state_lock:
            payload = await asyncio.to_thread(self._state)
            if force or payload != self.sent_state:
                self.sent_state = payload
                await self._send(text=json.dumps(payload))

    def _in_control(self) -> bool:
        return (self.lease_id is not None
                and self.lease_id == computer_state.read_control(self.home)["lease_id"])

    async def run(self, fps: int) -> None:
        upstream = await self._connect(fps)
        if upstream is None:
            await self.ws.close(code=_CLOSE_UNAVAILABLE, reason="the computer screen is not answering")
            return
        _viewers.add(self)
        pumps = [asyncio.create_task(self._from_upstream(upstream)),
                 asyncio.create_task(self._from_viewer(upstream)),
                 asyncio.create_task(self._state_loop())]
        upstream_ended = False
        try:
            done, pending = await asyncio.wait(pumps, return_when=asyncio.FIRST_COMPLETED)
            upstream_ended = pumps[0] in done
            for task in pending:
                task.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
            for task in done:
                if task.exception() is not None:
                    log.debug("hermuse computer ws ended: %r", task.exception())
        finally:
            self.closing = True
            try:
                await upstream.close()
                if self.lease_id is not None:
                    released = await asyncio.to_thread(
                        computer_state.release_control, self.home, self.lease_id)
                    self.lease_id = None
                    if released:
                        await _broadcast_state()
            finally:
                _viewers.discard(self)  # last: a viewer is gone once its lease is settled
        try:
            if upstream_ended:
                await self.ws.close(code=_CLOSE_UNAVAILABLE, reason="the computer screen stream ended")
            else:
                await self.ws.close()
        except Exception:  # noqa: BLE001 — the viewer already went away
            pass

    async def _connect(self, fps: int) -> Any:
        from websockets.asyncio.client import connect

        token = urllib.parse.quote(str(self.rt["token"]), safe="")
        url = f"ws://127.0.0.1:{int(self.rt['screen_port'])}/stream?token={token}&fps={fps}"
        error: Optional[Exception] = None
        for _ in range(_UPSTREAM_ATTEMPTS):
            try:
                return await connect(url, max_size=_UPSTREAM_MAX_MESSAGE, compression=None,
                                     proxy=None, open_timeout=5)
            except Exception as exc:  # noqa: BLE001 — refused/handshake/timeout: retry
                error = exc
                await asyncio.sleep(_UPSTREAM_RETRY_S)
        log.warning("hermuse computer: screen stream unreachable: %s", error)
        return None

    async def _from_upstream(self, upstream: Any) -> None:
        from websockets.exceptions import ConnectionClosed

        try:
            async for message in upstream:
                if isinstance(message, bytes):
                    await self._send(data=message)
                else:
                    await self._send(text=message)
        except ConnectionClosed:
            pass

    async def _from_viewer(self, upstream: Any) -> None:
        from websockets.exceptions import ConnectionClosed

        while True:
            message = await self.ws.receive()
            if message.get("type") == "websocket.disconnect":
                return
            text = message.get("text")
            if text is None:
                continue
            try:
                data = json.loads(text)
            except ValueError:
                continue
            if not isinstance(data, dict):
                continue
            try:
                await self._handle(data, text, upstream)
            except ConnectionClosed:
                return

    async def _handle(self, message: dict[str, Any], raw: str, upstream: Any) -> None:
        kind = message.get("t")
        if kind in _INPUT_TYPES:
            if self._in_control():
                await upstream.send(raw)
        elif kind == "take":
            self.lease_id = await asyncio.to_thread(computer_state.take_control, self.home)
            await _broadcast_state()
        elif kind == "release":
            await asyncio.to_thread(computer_state.release_control, self.home, self.lease_id)
            self.lease_id = None
            await _broadcast_state()
        elif kind == "mode":
            mode = message.get("mode")
            if mode in computer_runtime.MODES:
                await self._backend_call(self.backend.set_mode, mode)
        elif kind == "tab":
            action, tab_id = message.get("action"), message.get("id")
            if action in _TAB_ACTIONS and isinstance(tab_id, str) and tab_id:
                call = self.backend.activate if action == "activate" else self.backend.close_tab
                await self._backend_call(call, tab_id)

    async def _backend_call(self, call: Any, argument: str) -> None:
        try:
            await asyncio.to_thread(call, self.rt, argument)
        except Exception as exc:  # noqa: BLE001 — report in logs, keep the stream
            log.warning("hermuse computer: %s(%s) failed: %s", call.__name__, argument, exc)
            return
        await _broadcast_state()

    async def _state_loop(self) -> None:
        while True:
            await self.push_state()
            await asyncio.sleep(_STATE_PERIOD_S)
