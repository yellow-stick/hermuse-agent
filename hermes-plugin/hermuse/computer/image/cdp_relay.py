#!/usr/bin/env python3
"""cdp_relay: publish Chromium's DevTools endpoint out of the container.

Chromium ignores ``--remote-debugging-address`` and only listens on the
container's loopback (port 9222), which Docker cannot publish. This relays port
9223 on all container interfaces to it, byte for byte, so both the HTTP
discovery routes (``/json/*``) and the DevTools WebSocket pass through
untouched. The Hermuse runtime publishes 9223 on the host's loopback only.

Separate from screend so a screen-service failure never takes CDP down.
Standard library only.
"""

from __future__ import annotations

import asyncio
import contextlib

LISTEN_HOST, LISTEN_PORT = "0.0.0.0", 9223
CHROMIUM_HOST, CHROMIUM_PORT = "127.0.0.1", 9222
CHUNK = 65536
HALF_CLOSE_GRACE_S = 2.0  # after one side ends, how long the other may finish


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    """Copy until EOF, then half-close the other side so its reply can still drain."""
    try:
        while data := await reader.read(CHUNK):
            writer.write(data)
            await writer.drain()
        if writer.can_write_eof():
            writer.write_eof()
    except OSError:  # reset by either peer: the caller tears both sides down
        pass


async def handle(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter) -> None:
    try:
        chromium_reader, chromium_writer = await asyncio.open_connection(CHROMIUM_HOST, CHROMIUM_PORT)
    except OSError:  # Chromium (re)starting: refuse like a closed port would
        client_writer.close()
        return
    pumps = [asyncio.create_task(pipe(client_reader, chromium_writer)),
             asyncio.create_task(pipe(chromium_reader, client_writer))]
    _, pending = await asyncio.wait(pumps, return_when=asyncio.FIRST_COMPLETED)
    if pending:
        _, pending = await asyncio.wait(pending, timeout=HALF_CLOSE_GRACE_S)
    for pump in pending:
        pump.cancel()
    await asyncio.gather(*pumps, return_exceptions=True)
    for writer in (client_writer, chromium_writer):
        writer.close()
        with contextlib.suppress(OSError):
            await writer.wait_closed()


async def main() -> None:
    server = await asyncio.start_server(handle, LISTEN_HOST, LISTEN_PORT, reuse_address=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
