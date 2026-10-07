#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# .env holds machine-specific settings and the selected model profile.
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

# A profile deliberately overrides model-specific values that may still be in
# an older .env. Generic settings such as ports and MODEL_ROOT remain untouched
# unless the profile explicitly defines them.
: "${MODEL_PROFILE:=}"
if [[ -n "$MODEL_PROFILE" ]]; then
  PROFILE_FILE="$REPO_ROOT/config/model-profiles/${MODEL_PROFILE}.env"
  if [[ ! -f "$PROFILE_FILE" ]]; then
    echo "ERROR: model profile not found: $PROFILE_FILE" >&2
    exit 1
  fi
  set -a
  source "$PROFILE_FILE"
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

# Inference-engineering benchmark defaults. Model profiles can override these.
: "${BENCH_CONTEXT_LENGTHS:=1024,4096,8192,16384,32768}"
: "${BENCH_CONTEXT_RUNS:=2}"
: "${BENCH_GENERATION_TOKENS:=256}"
: "${BENCH_PREFIX_TOKENS:=8192}"
: "${BENCH_PREFIX_MAX_TOKENS:=128}"
: "${BENCH_CONCURRENCY_PROMPT_TOKENS:=4096}"
: "${BENCH_CONCURRENCY_LEVELS:=1,2,4,8}"
: "${BENCH_CONCURRENCY_MAX_TOKENS:=128}"
: "${BENCH_SLO_TTFT_SECONDS:=15}"
: "${BENCH_SLO_MIN_TG_TPS:=30}"

MODEL_DIR="$MODEL_ROOT/$MODEL_ID"
PROXY_DIR="$REPO_ROOT/copilot-proxy"
PROXY_VENV="$PROXY_DIR/.venv"
PROXY_REQUEST_LOG_DIR="$REPO_ROOT/logs/proxy"
PID_DIR="$REPO_ROOT/logs/pids"

mkdir -p "$MODEL_ROOT" "$RUNTIME_LOG_DIR" "$PROXY_REQUEST_LOG_DIR" "$PID_DIR"

# Capture reproducibility metadata without publishing stable machine identifiers.
# `system_profiler SPHardwareDataType` otherwise includes the Mac serial number,
# hardware UUID, provisioning UDID, and Activation Lock status.
public_kernel_summary() {
  uname -srm
}

public_hardware_summary() {
  system_profiler SPHardwareDataType 2>/dev/null \
    | sed -E \
      -e '/Serial Number \(system\):/d' \
      -e '/Hardware UUID:/d' \
      -e '/Provisioning UDID:/d' \
      -e '/Activation Lock Status:/d'
}
