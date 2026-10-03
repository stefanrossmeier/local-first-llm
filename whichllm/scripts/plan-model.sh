#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  cat >&2 <<'MSG'
Usage:
  ./whichllm/scripts/plan-model.sh MODEL [CONTEXT] [QUANT]

Examples:
  ./whichllm/scripts/plan-model.sh 'Qwen3.8-27B'
  ./whichllm/scripts/plan-model.sh 'Qwen3.8-27B' 64k Q4_K_M
MSG
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$ROOT/whichllm/scripts/run-whichllm.sh"

MODEL="$1"
CONTEXT="${2:-32k}"
QUANT="${3:-Q4_K_M}"

"$RUN" plan "$MODEL" \
  --context-length "$CONTEXT" \
  --quant "$QUANT"
