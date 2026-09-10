#!/usr/bin/env bash
# Called by run.sh after Docker is healthy. No second simulation is started.
set -euo pipefail

gateway_pid=""
cleanup() {
  if [[ -n "$gateway_pid" ]]; then
    echo "Stopping the native OpenClaw gateway started by this launcher..."
    kill "$gateway_pid" 2>/dev/null || true
    wait "$gateway_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

health() { openclaw gateway health --timeout 2000 >/dev/null 2>&1; }

if health; then
  echo "Reusing the active OpenClaw gateway. It will remain running."
else
  mkdir -p .runtime
  chmod 700 .runtime
  echo "Starting native OpenClaw; log: .runtime/openclaw.log"
  (umask 077; exec openclaw gateway run) > .runtime/openclaw.log 2>&1 &
  gateway_pid=$!
  ready=false
  for ((attempt=0; attempt<20; attempt++)); do
    kill -0 "$gateway_pid" 2>/dev/null || break
    if health; then
      ready=true
      break
    fi
    sleep 1
  done
  if ! "$ready" || ! kill -0 "$gateway_pid" 2>/dev/null; then
    echo "OpenClaw failed to start. See .runtime/openclaw.log; Docker is still running." >&2
    exit 1
  fi
fi

if ! openclaw mcp probe johndeere; then
  echo "MCP probe failed. Check OpenClaw's johndeere URL against the endpoint printed above." >&2
  exit 1
fi
echo "OpenClaw is connected. No automatic model turns are enabled."
echo 'Example: openclaw agent --agent farm-manager --session-key harvest -m "How is the harvest going?"'

# The gateway only binds loopback; the browser chat bridge in Servidor/chat.py
# runs inside the "server" container and needs a way in. This relay listens on
# the Docker bridge gateway IP (reachable only from containers on that network,
# never the LAN) and forwards to the gateway's real loopback address. It is
# detached from this script's process group so it outlives a reused-gateway
# session that returns immediately; `./run.sh down` stops it.
mkdir -p .runtime
chmod 700 .runtime
relay_pidfile=.runtime/gateway-relay.pid
if [[ -f "$relay_pidfile" ]] && kill -0 "$(cat "$relay_pidfile")" 2>/dev/null; then
  echo "Reusing the active gateway relay."
else
  setsid nohup python3 docker/gateway_relay.py 172.28.0.1 "$OPENCLAW_GATEWAY_PORT" 127.0.0.1 "$OPENCLAW_GATEWAY_PORT" \
    > .runtime/gateway-relay.log 2>&1 < /dev/null &
  disown
  echo $! > "$relay_pidfile"
  sleep 0.2
  if ! kill -0 "$(cat "$relay_pidfile")" 2>/dev/null; then
    echo "Gateway relay failed to start; see .runtime/gateway-relay.log. Browser chat will be unavailable." >&2
    rm -f "$relay_pidfile"
  fi
fi

if [[ -n "$gateway_pid" ]]; then
  echo "Ctrl-C stops this gateway. Docker stays running; stop it with ./run.sh down."
  wait "$gateway_pid"
fi
