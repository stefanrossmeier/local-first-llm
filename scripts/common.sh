#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

: "${HF_MODEL:=mlx-community/Qwen3.8-27B-4bit}"
: "${HF_MODEL_REVISION:=}"
: "${MODEL_ID:=Qwen3.8-27B-4bit}"
: "${MODEL_ROOT:=$HOME/llm/Models/MLX}"
: "${OMLX_HOST:=127.0.0.1}"
: "${OMLX_PORT:=8000}"
: "${PROXY_HOST:=127.0.0.1}"
: "${PROXY_PORT:=8001}"
: "${RUNTIME_LOG_DIR:=$HOME/llm/logs}"
: "${COPILOT_PROXY_LOG_RAW:=0}"
: "${COPILOT_PROXY_PREVIEW_CHARS:=0}"
: "${BENCH_REASONING_EFFORT:=low}"
: "${BENCH_MAX_TOKENS:=1024}"

MODEL_DIR="$MODEL_ROOT/$MODEL_ID"
PROXY_DIR="$REPO_ROOT/copilot-proxy"
PROXY_VENV="$PROXY_DIR/.venv"
PROXY_REQUEST_LOG_DIR="$REPO_ROOT/logs/proxy"
PID_DIR="$REPO_ROOT/logs/pids"

mkdir -p "$MODEL_ROOT" "$RUNTIME_LOG_DIR" "$PROXY_REQUEST_LOG_DIR" "$PID_DIR"
