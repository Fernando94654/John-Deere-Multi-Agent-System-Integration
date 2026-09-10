#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

with_openclaw=false
if [[ "${1:-}" == --with-openclaw ]]; then
  with_openclaw=true
  shift
fi
usage() { echo "Usage: $0 [--with-openclaw] [up|down|logs|status]" >&2; }
case "${1:-up}" in
  up|down|logs|status) action="${1:-up}" ;;
  *) usage; exit 2 ;;
esac
if (( $# > 1 )); then
  usage
  exit 2
fi
command -v docker >/dev/null && docker compose version >/dev/null || {
  echo "Install Docker with the Docker Compose plugin first." >&2; exit 1;
}

compose=(docker compose)
if "$with_openclaw"; then
  compose+=(-f compose.yaml -f docker/compose.openclaw.yaml)
fi

case "$action" in
  up)
    if "$with_openclaw"; then
      export PATH="$HOME/.local/node/bin:$HOME/.local/bin:$PATH"
      export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.openclaw/claude-home}"
      command -v openclaw >/dev/null || {
        echo "OpenClaw is not installed. See the server README for setup." >&2; exit 1;
      }
      config_path="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
      [[ -f "$config_path" ]] || {
        echo "Configure OpenClaw first. See agent/openclaw.example.json5." >&2; exit 1;
      }
      # The server container has no OpenClaw config of its own; hand its browser
      # chat bridge the gateway's port and credential directly (see docker/openclaw.sh
      # for the loopback relay that makes the gateway reachable from the container).
      mapfile -t gateway_env < <(python3 - "$config_path" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
gateway = config.get("gateway", {})
auth = gateway.get("auth", {})
print(gateway.get("port", 18789))
print(auth.get("token") or auth.get("password") or "")
PY
)
      export OPENCLAW_GATEWAY_PORT="${gateway_env[0]:-}"
      export OPENCLAW_GATEWAY_TOKEN="${gateway_env[1]:-}"
      [[ -n "$OPENCLAW_GATEWAY_PORT" && -n "$OPENCLAW_GATEWAY_TOKEN" ]] || {
        echo "Could not read gateway.port and gateway.auth.token/password from $config_path." >&2; exit 1;
      }
    fi
    for path in John-Deere-Multi-Agent-System/Servidor/server.py John-Deere-MultiAgents-Website/package.json; do
      [[ -f "$path" ]] || {
        echo "Missing submodules. Run: git submodule update --init --recursive" >&2
        exit 1
      }
    done
    for asset in unity-build/Build/*.data unity-build/Build/*.wasm; do
      if [[ -f "$asset" ]] && [[ "$(head -c 42 "$asset")" == 'version https://git-lfs.github.com/spec/v1'* ]]; then
        echo "Unity assets are Git LFS pointers. Install Git LFS and run: git lfs pull" >&2
        exit 1
      fi
    done
    # Compose resolves both shell overrides and .env before choosing host ports.
    # Only native project servers are stopped; other applications are left alone.
    if [[ -d /proc ]] && command -v python3 >/dev/null && command -v ss >/dev/null; then
      "${compose[@]}" config --format json | python3 docker/stop-local-server.py
    else
      echo "Automatic local-server cleanup requires Linux/WSL, python3 and ss; skipping."
    fi
    "${compose[@]}" up --build --detach --wait
    "${compose[@]}" port web 80
    echo "Web is ready at the address above (HTTP). Unity WebSocket address:"
    "${compose[@]}" port server 8765
    if [[ ! -f unity-build/Build/WebDevelopmentTest3.loader.js ]]; then
      echo "Local Unity WebGL build is absent. See README.md to enable the embedded 3D view."
    fi
    if "$with_openclaw"; then
      echo "MCP endpoint (use http://ADDRESS/mcp in OpenClaw's johndeere registration):"
      "${compose[@]}" port server 8766
      # This helper keeps the native gateway in the foreground and owns its cleanup.
      exec bash docker/openclaw.sh
    fi
    ;;
  down)
    relay_pidfile=.runtime/gateway-relay.pid
    if [[ -f "$relay_pidfile" ]]; then
      kill "$(cat "$relay_pidfile")" 2>/dev/null || true
      rm -f "$relay_pidfile"
    fi
    "${compose[@]}" down
    ;;
  logs) "${compose[@]}" logs --follow ;;
  status) "${compose[@]}" ps ;;
esac
