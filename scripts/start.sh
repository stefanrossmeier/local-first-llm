#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if ! command -v omlx >/dev/null 2>&1; then
  echo "ERROR: omlx not found. Run ./scripts/setup-omlx.sh first."
  exit 1
fi

if [[ ! -d "$MODEL_DIR" ]]; then
  echo "ERROR: model directory not found: $MODEL_DIR"
  echo "Run ./scripts/download-model.sh first."
  exit 1
fi

if [[ ! -x "$PROXY_VENV/bin/uvicorn" ]]; then
  echo "ERROR: proxy environment not found. Run ./scripts/setup-proxy.sh first."
  exit 1
fi

mkdir -p "$RUNTIME_LOG_DIR" "$PID_DIR" "$PROXY_REQUEST_LOG_DIR"

"$SCRIPT_DIR/stop.sh" >/dev/null 2>&1 || true
sleep 1

echo "==> Starting oMLX on http://${OMLX_HOST}:${OMLX_PORT}"
nohup omlx serve \
  --model-dir "$MODEL_ROOT" \
  --host "$OMLX_HOST" \
  --port "$OMLX_PORT" \
  > "$RUNTIME_LOG_DIR/omlx.log" 2>&1 &
OMLX_PID=$!
echo "$OMLX_PID" > "$PID_DIR/omlx.pid"

for _ in {1..90}; do
  if curl -sf "http://${OMLX_HOST}:${OMLX_PORT}/v1/models" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$OMLX_PID" 2>/dev/null; then
    echo "ERROR: oMLX exited during startup."
    tail -80 "$RUNTIME_LOG_DIR/omlx.log"
    exit 1
  fi
  sleep 1
done

if ! curl -sf "http://${OMLX_HOST}:${OMLX_PORT}/v1/models" >/dev/null 2>&1; then
  echo "ERROR: oMLX did not become ready."
  tail -80 "$RUNTIME_LOG_DIR/omlx.log"
  exit 1
fi

echo "==> Starting Copilot inspection proxy on http://${PROXY_HOST}:${PROXY_PORT}"
cd "$PROXY_DIR"
COPILOT_PROXY_UPSTREAM="http://${OMLX_HOST}:${OMLX_PORT}" \
COPILOT_PROXY_LOG_DIR="$PROXY_REQUEST_LOG_DIR" \
COPILOT_PROXY_LOG_RAW="$COPILOT_PROXY_LOG_RAW" \
COPILOT_PROXY_PREVIEW_CHARS="$COPILOT_PROXY_PREVIEW_CHARS" \
nohup "$PROXY_VENV/bin/uvicorn" proxy:app \
  --host "$PROXY_HOST" \
  --port "$PROXY_PORT" \
  > "$RUNTIME_LOG_DIR/copilot-proxy.log" 2>&1 &
PROXY_PID=$!
echo "$PROXY_PID" > "$PID_DIR/proxy.pid"

for _ in {1..30}; do
  if curl -sf "http://${PROXY_HOST}:${PROXY_PORT}/v1/models" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$PROXY_PID" 2>/dev/null; then
    echo "ERROR: proxy exited during startup."
    tail -80 "$RUNTIME_LOG_DIR/copilot-proxy.log"
    exit 1
  fi
  sleep 1
done

if ! curl -sf "http://${PROXY_HOST}:${PROXY_PORT}/v1/models" >/dev/null 2>&1; then
  echo "ERROR: proxy did not become ready."
  tail -80 "$RUNTIME_LOG_DIR/copilot-proxy.log"
  exit 1
fi

cat <<MSG

============================================
 Local coding LLM ready
============================================
Model:        $MODEL_ID
oMLX:         http://${OMLX_HOST}:${OMLX_PORT}
Copilot URL:  http://${PROXY_HOST}:${PROXY_PORT}/v1/chat/completions

Runtime logs:
  tail -f "$RUNTIME_LOG_DIR/omlx.log"
  tail -f "$RUNTIME_LOG_DIR/copilot-proxy.log"

Request summaries:
  $PROXY_REQUEST_LOG_DIR

Stop:
  $REPO_ROOT/scripts/stop.sh
MSG
