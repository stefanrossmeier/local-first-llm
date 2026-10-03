#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$ROOT/whichllm/scripts/run-whichllm.sh"
CONTEXT="${WHICHLLM_CONTEXT:-32k}"
TOP="${WHICHLLM_TOP:-15}"

section() {
  echo
  echo "================================================================"
  echo "$1"
  echo "================================================================"
}

section "whichllm version"
"$RUN" --version

section "Detected hardware"
"$RUN" hardware

section "Coding candidates / ${CONTEXT}"
"$RUN" \
  --profile coding \
  --context-length "$CONTEXT" \
  --top "$TOP"

section "Coding candidates / ${CONTEXT} / estimated >= 10 tok/s"
"$RUN" \
  --profile coding \
  --context-length "$CONTEXT" \
  --speed usable \
  --top "$TOP"

section "Conservative coding candidates / ${CONTEXT}"
"$RUN" \
  --profile coding \
  --context-length "$CONTEXT" \
  --gpu-only \
  --speed usable \
  --vram-headroom 1GB \
  --top "$TOP"
