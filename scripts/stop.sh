#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stop_pidfile() {
  local name="$1"
  local file="$2"
  local expected_command="$3"
  local expected_port="$4"
  if [[ -f "$file" ]]; then
    local pid
    local command
    pid="$(cat "$file")"
    if kill -0 "$pid" 2>/dev/null; then
      command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
      if [[ "$command" == *"$expected_command"* && "$command" == *"--port $expected_port"* ]]; then
        echo "Stopping $name (PID $pid)..."
        kill "$pid" 2>/dev/null || true
        for _ in {1..20}; do
          kill -0 "$pid" 2>/dev/null || break
          sleep 0.2
        done
        kill -9 "$pid" 2>/dev/null || true
      else
        echo "Not stopping PID $pid from $file: it does not match $name."
      fi
    fi
    rm -f "$file"
  fi
}

stop_pidfile "Copilot proxy" "$PID_DIR/proxy.pid" "$PROXY_VENV/bin/uvicorn" "$PROXY_PORT"
stop_pidfile "oMLX" "$PID_DIR/omlx.pid" "omlx serve" "$OMLX_PORT"
