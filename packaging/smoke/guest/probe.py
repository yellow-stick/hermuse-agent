#!/usr/bin/env python3
"""Protocol probes of the release smoke guest (stdlib only, run as root).

They talk to the stack the installed app prepared exactly like the app does:
the loopback backend it supervises (dashboard REST with the
``X-Hermes-Session-Token`` header, ``/api/ws`` JSON-RPC), the plugin's
``/computer/ws`` viewer protocol, and the CLIProxy management API. The
backend is found through /proc (the ``hermes serve`` child whose environment
carries ``HERMES_DESKTOP=1`` and the session token the app minted); secrets
are read from /proc or files and never printed. Every subcommand prints one
JSON object and exits 0 when its check passed, 1 when it failed, 2 on usage.

  probe.py backend
  probe.py connection --app-pid PID
  probe.py rest METHOD PATH [--body JSON | --body-file FILE]
  probe.py converse --nonce TEXT [--timeout S]
  probe.py computer --out DIR [--timeout S]
  probe.py cliproxy --config PATH --expect-exe PATH
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import http.client
import json
import os
import pwd
import re
import socket
import struct
import sys
import time
import urllib.parse
from typing import Any, Optional

USER = "tester"
# Variables the AppImage runtime exports; none may reach a supervised child.
APPIMAGE_RUNTIME_VARS = ("APPDIR", "APPIMAGE", "APPOFFSET", "ARGV0", "OWD", "URUNTIME", "URUNTIME_DIR")
_WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def emit(payload: dict[str, Any], ok: bool) -> None:
    payload["ok"] = ok
    print(json.dumps(payload, indent=2, sort_keys=True))
    sys.exit(0 if ok else 1)


# --- /proc ------------------------------------------------------------------


def _environ(pid: str) -> dict[str, str]:
    with open(f"/proc/{pid}/environ", "rb") as handle:
        raw = handle.read()
    env = {}
    for item in raw.split(b"\0"):
        if b"=" in item:
            key, _, value = item.partition(b"=")
            env[key.decode(errors="replace")] = value.decode(errors="replace")
    return env


def _cmdline(pid: str) -> list[str]:
    with open(f"/proc/{pid}/cmdline", "rb") as handle:
        return [part.decode(errors="replace") for part in handle.read().split(b"\0") if part]


def _ppid(pid: str) -> int:
    with open(f"/proc/{pid}/stat") as handle:
        return int(handle.read().rsplit(")", 1)[1].split()[1])


def listening_ports(pid: str) -> list[int]:
    inodes = set()
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            link = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if link.startswith("socket:["):
            inodes.add(link[8:-1])
    ports = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                rows = handle.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) > 9 and fields[3] == "0A" and fields[9] in inodes:
                ports.add(int(fields[1].rsplit(":", 1)[1], 16))
    return sorted(ports)


def user_processes() -> list[str]:
    uid = pwd.getpwnam(USER).pw_uid
    pids = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            if os.stat(f"/proc/{pid}").st_uid == uid:
                pids.append(pid)
        except OSError:
            continue
    return pids


class Backend:
    def __init__(self, pid: str, port: int, token: str, env: dict[str, str], cmdline: list[str]):
        self.pid, self.port, self.token, self.env, self.cmdline = pid, port, token, env, cmdline

    def describe(self) -> dict[str, Any]:
        return {
            "pid": int(self.pid),
            "ppid": _ppid(self.pid),
            "port": self.port,
            "cmdline": self.cmdline,
            "hermes_home": self.env.get("HERMES_HOME", ""),
            "home": self.env.get("HOME", ""),
            "path": self.env.get("PATH", ""),
            "ld_library_path": self.env.get("LD_LIBRARY_PATH"),
            "appimage_vars": sorted(k for k in self.env if k in APPIMAGE_RUNTIME_VARS
                                    or k.startswith("HERMUSE_ORIG_") or k == "HERMUSE_APPIMAGE_ENV_SAVED"),
        }


def find_backend() -> Optional[Backend]:
    """The app-supervised ``hermes serve``: HERMES_DESKTOP=1 + a session token."""
    found = []
    for pid in user_processes():
        try:
            env = _environ(pid)
            if env.get("HERMES_DESKTOP") != "1" or not env.get("HERMES_DASHBOARD_SESSION_TOKEN"):
                continue
            cmdline = _cmdline(pid)
            if "serve" not in cmdline:
                continue
            ports = listening_ports(pid)
        except OSError:
            continue
        for port in ports:
            found.append(Backend(pid, port, env["HERMES_DASHBOARD_SESSION_TOKEN"], env, cmdline))
    for backend in found:
        status, body = http_call(backend.port, "GET", "/api/status")
        if status == 200 and isinstance(body, dict):
            return backend
    return None


def require_backend() -> Backend:
    backend = find_backend()
    if backend is None:
        emit({"error": "no app-supervised hermes serve (HERMES_DESKTOP=1 + session token) is listening"}, False)
    assert backend is not None
    return backend


# --- HTTP -------------------------------------------------------------------


def http_call(port: int, method: str, path: str, *, token: Optional[str] = None,
              body: Any = None, headers: Optional[dict[str, str]] = None,
              timeout: float = 30.0) -> tuple[int, Any]:
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    all_headers = {"Accept": "application/json"}
    if token:
        all_headers["X-Hermes-Session-Token"] = token
    all_headers.update(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        all_headers["Content-Type"] = "application/json"
    try:
        conn.request(method, path, body=data, headers=all_headers)
        response = conn.getresponse()
        raw = response.read()
    except OSError as exc:
        return 0, f"{type(exc).__name__}: {exc}"
    finally:
        conn.close()
    try:
        return response.status, json.loads(raw)
    except ValueError:
        return response.status, raw.decode(errors="replace")[:2000]


# --- WebSocket (RFC 6455 client) --------------------------------------------


class WsClosed(Exception):
    pass


class WebSocket:
    def __init__(self, sock: socket.socket, buffered: bytes):
        self.sock = sock
        self.buffer = buffered
        self.partial = b""
        self.partial_kind = ""

    @classmethod
    def connect(cls, port: int, path: str, timeout: float = 15.0) -> "WebSocket":
        sock = socket.create_connection(("127.0.0.1", port), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\n"
                   f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        sock.sendall(request.encode())
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = sock.recv(4096)
            if not chunk:
                raise WsClosed("connection closed during the handshake")
            data += chunk
        head, _, rest = data.partition(b"\r\n\r\n")
        lines = head.decode(errors="replace").split("\r\n")
        if " 101 " not in lines[0]:
            raise WsClosed(f"handshake refused: {lines[0]}")
        expected = base64.b64encode(hashlib.sha1((key + _WS_GUID).encode()).digest()).decode()
        accept = [line.split(":", 1)[1].strip() for line in lines[1:]
                  if line.lower().startswith("sec-websocket-accept:")]
        if accept != [expected]:
            raise WsClosed("bad Sec-WebSocket-Accept")
        return cls(sock, rest)

    @staticmethod
    def _parse(buffer: bytes) -> Optional[tuple[int, int, bytes, int]]:
        """(fin, opcode, payload, bytes used) of the first complete frame, or None."""
        if len(buffer) < 2:
            return None
        first, second = buffer[0], buffer[1]
        length, offset = second & 0x7F, 2
        if length == 126:
            if len(buffer) < 4:
                return None
            length, offset = struct.unpack("!H", buffer[2:4])[0], 4
        elif length == 127:
            if len(buffer) < 10:
                return None
            length, offset = struct.unpack("!Q", buffer[2:10])[0], 10
        mask = b""
        if second & 0x80:
            if len(buffer) < offset + 4:
                return None
            mask, offset = buffer[offset:offset + 4], offset + 4
        if len(buffer) < offset + length:
            return None
        payload = buffer[offset:offset + length]
        if mask:
            payload = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))
        return first & 0x80, first & 0x0F, payload, offset + length

    def _frame(self) -> tuple[int, int, bytes]:
        """Consumes one whole frame; a timeout leaves the buffer intact."""
        while True:
            parsed = self._parse(self.buffer)
            if parsed is not None:
                fin, opcode, payload, used = parsed
                self.buffer = self.buffer[used:]
                return fin, opcode, payload
            chunk = self.sock.recv(65536)
            if not chunk:
                raise WsClosed("connection closed")
            self.buffer += chunk

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        header = bytearray([0x80 | opcode])
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        elif length < 1 << 16:
            header.append(0x80 | 126)
            header += struct.pack("!H", length)
        else:
            header.append(0x80 | 127)
            header += struct.pack("!Q", length)
        mask = os.urandom(4)
        masked = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))
        self.sock.sendall(bytes(header) + mask + masked)

    def send_json(self, value: Any) -> None:
        self._send_frame(0x1, json.dumps(value).encode())

    def recv(self, timeout: float) -> tuple[str, Any]:
        """Next data message: ("text", str) or ("binary", bytes)."""
        self.sock.settimeout(timeout)
        while True:
            fin, opcode, payload = self._frame()
            if opcode == 0x8:
                code = struct.unpack("!H", payload[:2])[0] if len(payload) >= 2 else 1005
                raise WsClosed(f"closed by server: {code} {payload[2:].decode(errors='replace')}")
            if opcode == 0x9:
                self._send_frame(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            if opcode in (0x1, 0x2):
                self.partial_kind = "text" if opcode == 0x1 else "binary"
                self.partial = b""
            self.partial += payload
            if fin:
                kind, message = self.partial_kind, self.partial
                self.partial = b""
                return kind, message.decode() if kind == "text" else message

    def close(self) -> None:
        try:
            self._send_frame(0x8, struct.pack("!H", 1000))
        except OSError:
            pass
        self.sock.close()


# --- subcommands ------------------------------------------------------------


def cmd_backend(_: argparse.Namespace) -> None:
    backend = require_backend()
    status, body = http_call(backend.port, "GET", "/api/status")
    emit({"backend": backend.describe(), "status": status, "api_status": body}, status == 200)


def established_remote_ports(pid: str) -> list[int]:
    """Remote ports of the ESTABLISHED loopback TCP connections of *pid*."""
    inodes = set()
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            link = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if link.startswith("socket:["):
            inodes.add(link[8:-1])
    ports = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                rows = handle.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) > 9 and fields[3] == "01" and fields[9] in inodes:
                ports.add(int(fields[2].rsplit(":", 1)[1], 16))
    return sorted(ports)


def cmd_connection(args: argparse.Namespace) -> None:
    """Whether the app process holds a connection to its supervised backend."""
    backend = find_backend()
    report: dict[str, Any] = {"app_pid": args.app_pid, "backend": backend.describe() if backend else None}
    try:
        remote = established_remote_ports(str(args.app_pid))
    except OSError as exc:
        emit({**report, "connected": False, "error": f"{type(exc).__name__}: {exc}"}, False)
    report["connected"] = backend is not None and backend.port in remote
    emit(report, report["connected"])


def cmd_rest(args: argparse.Namespace) -> None:
    backend = require_backend()
    body = None
    if args.body_file:
        with open(args.body_file) as handle:
            body = json.load(handle)
    elif args.body:
        body = json.loads(args.body)
    status, response = http_call(backend.port, args.method.upper(), args.path, token=backend.token,
                                 body=body, timeout=args.timeout)
    emit({"method": args.method.upper(), "path": args.path, "status": status, "body": response},
         200 <= status < 300)


def _rpc_loop(ws: WebSocket, deadline: float, want: Any) -> Any:
    """Receives until ``want(frame)`` returns non-None; refuses server requests."""
    seen: list[str] = []
    while True:
        left = deadline - time.monotonic()
        if left <= 0:
            raise TimeoutError(f"timed out; events seen: {seen[-20:]}")
        kind, text = ws.recv(left)
        if kind != "text":
            continue
        try:
            frame = json.loads(text)
        except ValueError:
            continue
        if frame.get("method") == "event":
            seen.append(str((frame.get("params") or {}).get("type")))
        elif "method" in frame and "id" in frame:
            ws.send_json({"jsonrpc": "2.0", "id": frame["id"],
                          "error": {"code": -32601, "message": "not handled by the smoke probe"}})
            continue
        result = want(frame)
        if result is not None:
            return result


def cmd_converse(args: argparse.Namespace) -> None:
    backend = require_backend()
    deadline = time.monotonic() + args.timeout
    report: dict[str, Any] = {"nonce": args.nonce}
    ws = WebSocket.connect(backend.port, "/api/ws?" + urllib.parse.urlencode({"token": backend.token}))
    try:
        _rpc_loop(ws, deadline, lambda f: True if (f.get("params") or {}).get("type") == "gateway.ready" else None)
        ws.send_json({"jsonrpc": "2.0", "id": 1, "method": "session.create", "params": {}})
        created = _rpc_loop(ws, deadline, lambda f: f if f.get("id") == 1 else None)
        if "error" in created:
            emit({**report, "error": created["error"]}, False)
        session_id = created["result"]["session_id"]
        report["session_id"] = session_id
        prompt = f"Reply with exactly this token and nothing else: {args.nonce}"
        ws.send_json({"jsonrpc": "2.0", "id": 2, "method": "prompt.submit",
                      "params": {"session_id": session_id, "text": prompt}})

        def complete(frame: dict[str, Any]) -> Any:
            if frame.get("id") == 2 and "error" in frame:
                return {"error": frame["error"]}
            params = frame.get("params") or {}
            if (frame.get("method") == "event" and params.get("type") == "message.complete"
                    and params.get("session_id") == session_id):
                return params.get("payload") or {}
            return None

        payload = _rpc_loop(ws, deadline, complete)
    finally:
        ws.close()
    text = payload.get("text") if isinstance(payload, dict) else None
    report["reply"] = text if isinstance(text, str) else None
    report["status"] = payload.get("status") if isinstance(payload, dict) else None
    report["error"] = payload.get("error") if isinstance(payload, dict) else None
    emit(report, isinstance(text, str) and args.nonce in text)


# Typed into the computer's address bar by the "human" viewer: every input the
# viewer sends shows up in the tab title the state messages carry. No "%" or
# "#" (URL syntax), no network.
_FIXTURE = ("data:text/html,<title>hs:ready</title><body style=\"margin:0;height:6000px\">"
            "<input id=\"i\" autofocus style=\"font-size:32px;width:640px\"><script>var c=0;"
            "function u(){document.title='hs:k='+i.value+'|c='+c+'|s='+Math.round(scrollY)}"
            "i.oninput=u;onclick=function(){c++;u()};onscroll=u;u()</script>")


def cmd_computer(args: argparse.Namespace) -> None:
    backend = require_backend()
    os.makedirs(args.out, exist_ok=True)
    steps: list[dict[str, Any]] = []
    report: dict[str, Any] = {"steps": steps}
    status, body = http_call(backend.port, "POST", "/api/plugins/hermuse/computer/ticket",
                             token=backend.token, body={})
    if status != 200 or not isinstance(body, dict) or not body.get("ticket"):
        emit({**report, "error": f"ticket: HTTP {status} {body}"}, False)
    query = urllib.parse.urlencode({"ticket": body["ticket"], "fps": 5})
    ws = WebSocket.connect(backend.port, f"/api/plugins/hermuse/computer/ws?{query}", timeout=60)
    state: dict[str, Any] = {}
    geometry: dict[str, Any] = {}
    frames = {"count": 0}

    def pump(until: Any, timeout: float, save_frame: Optional[str] = None) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                kind, data = ws.recv(max(0.1, deadline - time.monotonic()))
            except socket.timeout:
                break
            if kind == "binary":
                frames["count"] += 1
                if save_frame and data[:2] == b"\xff\xd8":
                    with open(os.path.join(args.out, save_frame), "wb") as handle:
                        handle.write(data)
                    save_frame = None
            else:
                message = json.loads(data)
                if message.get("t") == "geometry":
                    geometry.update(message)
                elif message.get("t") == "state":
                    state.clear()
                    state.update(message)
            if until() and save_frame is None:
                return True
        return bool(until()) and save_frame is None

    def title() -> str:
        for tab in state.get("tabs") or []:
            if tab.get("active"):
                return str(tab.get("title") or "")
        return ""

    def step(name: str, ok: bool, detail: Any = None) -> bool:
        steps.append({"name": name, "ok": ok, "detail": detail})
        return ok

    def key(name: str) -> None:
        ws.send_json({"t": "key", "k": name, "a": "down"})
        ws.send_json({"t": "key", "k": name, "a": "up"})

    try:
        ok = step("frames", pump(lambda: bool(geometry) and frames["count"] > 0, args.timeout,
                                 save_frame="frame-first.jpg"),
                  {"geometry": dict(geometry), "frames": frames["count"]})
        width, height = int(geometry.get("w", 0)), int(geometry.get("h", 0))
        if ok:
            ws.send_json({"t": "take"})
            ok = step("take-control", pump(lambda: state.get("mine") is True, 20),
                      {"control": state.get("control")})
        if ok:
            ws.send_json({"t": "key", "k": "Control_L", "a": "down"})
            key("l")
            ws.send_json({"t": "key", "k": "Control_L", "a": "up"})
            ws.send_json({"t": "text", "s": _FIXTURE})
            key("Return")
            ok = step("open-fixture-page", pump(lambda: title().startswith("hs:"), 60), title())
        if ok:
            ws.send_json({"t": "text", "s": "hermuse"})
            ok = step("type", pump(lambda: "k=hermuse|" in title(), 30), title())
        if ok:
            x, y = width // 2, (height * 3) // 4
            ws.send_json({"t": "move", "x": x, "y": y})
            ws.send_json({"t": "down", "x": x, "y": y, "b": 1})
            ws.send_json({"t": "up", "x": x, "y": y, "b": 1})
            ok = step("click", pump(lambda: "|c=1|" in title(), 30), title())
        if ok:
            ws.send_json({"t": "wheel", "x": width // 2, "y": height // 2, "dy": 5})
            ok = step("scroll", pump(lambda: re.search(r"\|s=[1-9]", title()) is not None, 30), title())
        if ok:
            ok = step("frame-after-input", pump(lambda: True, 15, save_frame="frame-after-input.jpg"))
        if ok:
            ws.send_json({"t": "release"})
            ok = step("release-control", pump(lambda: state.get("mine") is False, 20),
                      {"control": state.get("control")})
        if ok:
            before = title()
            ws.send_json({"t": "text", "s": "x"})
            pump(lambda: False, 6)
            ok = step("input-ignored-after-release", title() == before, {"before": before, "after": title()})
    except (WsClosed, OSError, ValueError) as exc:
        step("stream", False, f"{type(exc).__name__}: {exc}")
    finally:
        ws.close()
    report["frames"] = frames["count"]
    emit(report, all(entry["ok"] for entry in steps) and len(steps) >= 9)


def _yaml_scalar(text: str, key: str, section: Optional[str] = None) -> Optional[str]:
    """Scalar of the flat YAML the app generates (JSON-quoted strings)."""
    current = None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            current = line.split(":", 1)[0].strip()
            if section is None and current == key:
                value = line.split(":", 1)[1].strip()
                return json.loads(value) if value.startswith('"') else value
        elif section is not None and current == section:
            name, _, value = line.strip().partition(":")
            if name == key:
                value = value.strip()
                return json.loads(value) if value.startswith('"') else value
    return None


def cmd_cliproxy(args: argparse.Namespace) -> None:
    with open(args.config) as handle:
        config = handle.read()
    port = int(_yaml_scalar(config, "port") or 0)
    key = _yaml_scalar(config, "secret-key", section="remote-management") or ""
    report: dict[str, Any] = {"config": args.config, "port": port}
    processes = []
    for pid in user_processes():
        try:
            exe = os.readlink(f"/proc/{pid}/exe")
            cmdline = _cmdline(pid)
        except OSError:
            continue
        if args.config in cmdline:
            processes.append({"pid": int(pid), "exe": exe, "cmdline": cmdline})
    report["processes"] = processes
    report["exe_is_bundle_slot"] = bool(processes) and all(
        os.path.realpath(p["exe"]) == os.path.realpath(args.expect_exe) for p in processes)
    unauthenticated, _ = http_call(port, "GET", "/v0/management/config", timeout=10)
    authenticated, body = http_call(port, "GET", "/v0/management/config", timeout=10,
                                    headers={"Authorization": f"Bearer {key}"})
    report["unauthenticated_status"] = unauthenticated
    report["authenticated_status"] = authenticated
    report["authenticated_is_json"] = isinstance(body, dict)
    emit(report, bool(key) and report["exe_is_bundle_slot"] and unauthenticated in (401, 403)
         and authenticated == 200 and isinstance(body, dict))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("backend").set_defaults(run=cmd_backend)
    connection = sub.add_parser("connection")
    connection.add_argument("--app-pid", type=int, required=True)
    connection.set_defaults(run=cmd_connection)
    rest = sub.add_parser("rest")
    rest.add_argument("method")
    rest.add_argument("path")
    rest.add_argument("--body")
    rest.add_argument("--body-file")
    rest.add_argument("--timeout", type=float, default=60.0)
    rest.set_defaults(run=cmd_rest)
    converse = sub.add_parser("converse")
    converse.add_argument("--nonce", required=True)
    converse.add_argument("--timeout", type=float, default=300.0)
    converse.set_defaults(run=cmd_converse)
    computer = sub.add_parser("computer")
    computer.add_argument("--out", required=True)
    computer.add_argument("--timeout", type=float, default=120.0)
    computer.set_defaults(run=cmd_computer)
    cliproxy = sub.add_parser("cliproxy")
    cliproxy.add_argument("--config", required=True)
    cliproxy.add_argument("--expect-exe", required=True)
    cliproxy.set_defaults(run=cmd_cliproxy)
    args = parser.parse_args()
    try:
        args.run(args)
    except (WsClosed, OSError, TimeoutError, KeyError, ValueError) as exc:
        emit({"command": args.command, "error": f"{type(exc).__name__}: {exc}"}, False)


if __name__ == "__main__":
    main()
