#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BASE_URL="http://${OMLX_HOST}:${OMLX_PORT}"
if ! curl -sf "$BASE_URL/v1/models" >/dev/null 2>&1; then
  echo "ERROR: oMLX is not reachable at $BASE_URL" >&2
  echo "Start it first with: $REPO_ROOT/scripts/start.sh" >&2
  exit 1
fi

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PROFILE_NAME="${MODEL_PROFILE:-custom}"
RUN_ROOT="$REPO_ROOT/experiments/${PROFILE_NAME}/runs"
OUT_DIR="${1:-$RUN_ROOT/$TIMESTAMP-inference}"
mkdir -p "$OUT_DIR"

OMLX_PID=""
if [[ -f "$PID_DIR/omlx.pid" ]]; then
  OMLX_PID="$(cat "$PID_DIR/omlx.pid" 2>/dev/null || true)"
fi

export OMLX_BASE_URL="$BASE_URL"
export MODEL_ID MODEL_MAX_CONTEXT_WINDOW
export BENCH_CONTEXT_LENGTHS BENCH_CONTEXT_RUNS BENCH_GENERATION_TOKENS
export BENCH_PREFIX_TOKENS BENCH_PREFIX_MAX_TOKENS
export BENCH_CONCURRENCY_PROMPT_TOKENS BENCH_CONCURRENCY_LEVELS BENCH_CONCURRENCY_MAX_TOKENS
export BENCH_SLO_TTFT_SECONDS BENCH_SLO_MIN_TG_TPS

{
  echo "timestamp_utc=$TIMESTAMP"
  echo "model_profile=${MODEL_PROFILE:-}"
  echo "hf_model=$HF_MODEL"
  echo "hf_model_revision=$HF_MODEL_REVISION"
  echo "model_id=$MODEL_ID"
  echo "model_dir=$MODEL_DIR"
  echo "model_max_context_window=${MODEL_MAX_CONTEXT_WINDOW:-}"
  echo "omlx_url=$BASE_URL"
  echo "omlx_version=$(omlx --version 2>/dev/null || true)"
  echo "repo_git_commit=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
  echo "model_disk_bytes=$(du -sk "$MODEL_DIR" 2>/dev/null | awk '{print $1 * 1024}' || true)"
  echo "kernel=$(public_kernel_summary)"
  sw_vers 2>/dev/null || true
} > "$OUT_DIR/environment.txt"

public_hardware_summary > "$OUT_DIR/hardware.txt" 2>&1 || true
vm_stat > "$OUT_DIR/vm-stat-before.txt" 2>&1 || true
curl -s "$BASE_URL/v1/models" > "$OUT_DIR/models.json" || true
curl -s "$BASE_URL/api/status" > "$OUT_DIR/api-status-before.json" || true

SETTINGS="$HOME/.omlx/model_settings.json"
if [[ -f "$SETTINGS" ]]; then
  MODEL_ID="$MODEL_ID" SETTINGS="$SETTINGS" python3 <<'PY' > "$OUT_DIR/omlx-model-settings.json"
import json, os
from pathlib import Path
p = Path(os.environ["SETTINGS"])
data = json.loads(p.read_text())
model_id = os.environ["MODEL_ID"]
print(json.dumps(data.get("models", {}).get(model_id, {}), indent=2))
PY
fi

ARGS=(
  --base-url "$BASE_URL"
  --model "$MODEL_ID"
  --out "$OUT_DIR"
  --suite all
  --max-context "${MODEL_MAX_CONTEXT_WINDOW:-32768}"
)
if [[ -n "$OMLX_PID" ]] && kill -0 "$OMLX_PID" 2>/dev/null; then
  ARGS+=(--pid "$OMLX_PID")
fi

set +e
"$SCRIPT_DIR/benchmark-inference.py" "${ARGS[@]}"
STATUS=$?
set -e
vm_stat > "$OUT_DIR/vm-stat-after.txt" 2>&1 || true
curl -s "$BASE_URL/api/status" > "$OUT_DIR/api-status-after.json" || true

if [[ "$STATUS" -ne 0 ]]; then
  cat <<MSG >&2

============================================
 Inference benchmark FAILED
============================================
The benchmark process exited with status $STATUS.
Partial diagnostics, if any, are in:
  $OUT_DIR

Fix the reported error and rerun the command. A failed run is not valid
experiment evidence and should not be used for the later documentation.
MSG
  exit "$STATUS"
fi

cat <<MSG

============================================
 Inference benchmark complete
============================================
Results:
  $OUT_DIR

Read first:
  $OUT_DIR/benchmark-summary.md

The JSON files are the source data for the later experiment documentation.
MSG

exit 0
