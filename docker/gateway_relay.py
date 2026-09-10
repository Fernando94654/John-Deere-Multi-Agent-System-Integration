#!/usr/bin/env python3
"""Forward TCP connections from one host:port to another.

The OpenClaw gateway only binds loopback (by design — see agent/openclaw.example.json5).
Started by docker/openclaw.sh, this lets the server container reach it without
widening the gateway's own bind mode: it listens on the Docker bridge gateway
IP (reachable only from containers on that network, never the LAN) and relays
to the gateway's real loopback address.
"""
from __future__ import annotations

import asyncio
import sys


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while chunk := await reader.read(65536):
            writer.write(chunk)
            await writer.drain()
    except (ConnectionResetError, BrokenPipeError):
        pass
    finally:
        writer.close()


async def handle(client_reader, client_writer, target_host: str, target_port: int) -> None:
    try:
        upstream_reader, upstream_writer = await asyncio.open_connection(target_host, target_port)
    except OSError:
        client_writer.close()
        return
    await asyncio.gather(
        pipe(client_reader, upstream_writer),
        pipe(upstream_reader, client_writer),
    )


async def main(bind_host: str, bind_port: int, target_host: str, target_port: int) -> None:
    server = await asyncio.start_server(
        lambda r, w: handle(r, w, target_host, target_port), bind_host, bind_port
    )
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    bind_host, bind_port, target_host, target_port = sys.argv[1:5]
    try:
        asyncio.run(main(bind_host, int(bind_port), target_host, int(target_port)))
    except KeyboardInterrupt:
        pass
