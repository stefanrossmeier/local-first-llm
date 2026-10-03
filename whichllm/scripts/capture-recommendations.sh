#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$ROOT/whichllm/scripts/run-whichllm.sh"

RUN_ID="${1:-$(date +%Y-%m-%dT%H%M%S)}"
PROFILE="${WHICHLLM_PROFILE_NAME:-m4-pro-48gb}"
TOP="${WHICHLLM_CAPTURE_TOP:-100}"
OUT="$ROOT/whichllm/recommendations/${RUN_ID}-${PROFILE}"

mkdir -p "$OUT/targets"

repo_commit="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
macos_version="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
macos_build="$(sw_vers -buildVersion 2>/dev/null || echo unknown)"
requested_spec="${WHICHLLM_SPEC:-whichllm@latest}"
whichllm_version="$($RUN --version 2>&1 | tail -n 1)"
resolved_version="$(printf '%s\n' "$whichllm_version" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1 || true)"

# If the caller requested latest, pin the remaining commands in this capture to
# the exact version resolved above. That avoids a release change mid-capture.
if [[ "$requested_spec" == "whichllm@latest" && -n "$resolved_version" ]]; then
  export WHICHLLM_SPEC="whichllm@$resolved_version"
fi
resolved_spec="${WHICHLLM_SPEC:-$requested_spec}"

cat > "$OUT/environment.txt" <<EOF2
captured_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
repo_commit=$repo_commit
macos_version=$macos_version
macos_build=$macos_build
architecture=$(uname -m)
whichllm_version=$whichllm_version
whichllm_requested_spec=$requested_spec
whichllm_resolved_spec=$resolved_spec
profile=$PROFILE
capture_top=$TOP
cache_root=${WHICHLLM_CACHE_ROOT:-$ROOT/whichllm/.cache}
EOF2

git -C "$ROOT" status --short > "$OUT/git-status.txt" 2>/dev/null || true

printf 'Capturing whichllm experiment into:\n  %s\n\n' "$OUT"

echo "Capturing detected hardware..."
"$RUN" hardware > "$OUT/hardware.txt"

refresh_next="${WHICHLLM_REFRESH:-0}"

case "$refresh_next" in
  0|1) ;;
  *)
    echo "WHICHLLM_REFRESH must be 0 or 1 (got: $refresh_next)" >&2
    exit 2
    ;;
esac

capture_rank() {
  local name="$1"
  shift

  echo "Capturing $name..."

  # macOS still ships Bash 3.2. Avoid expanding an empty local array under
  # `set -u`: `${array[@]}` can be reported as an unbound variable there.
  if [[ "$refresh_next" == "1" ]]; then
    refresh_next=0
    "$RUN" --refresh "$@" --top "$TOP" --json > "$OUT/${name}.json"
  else
    "$RUN" "$@" --top "$TOP" --json > "$OUT/${name}.json"
  fi
}

capture_markdown() {
  local name="$1"
  shift

  echo "Capturing $name markdown..."
  "$RUN" "$@" --top "$TOP" --markdown > "$OUT/${name}.md"
}

for CONTEXT in 32k 64k; do
  capture_rank \
    "general-${CONTEXT}" \
    --context-length "$CONTEXT"

  capture_rank \
    "coding-${CONTEXT}" \
    --profile coding \
    --context-length "$CONTEXT"

  capture_markdown \
    "coding-${CONTEXT}" \
    --profile coding \
    --context-length "$CONTEXT"

  capture_rank \
    "coding-${CONTEXT}-strict" \
    --profile coding \
    --context-length "$CONTEXT" \
    --evidence strict

  capture_rank \
    "coding-${CONTEXT}-safe" \
    --profile coding \
    --context-length "$CONTEXT" \
    --gpu-only \
    --speed usable \
    --vram-headroom 1GB

  capture_markdown \
    "coding-${CONTEXT}-safe" \
    --profile coding \
    --context-length "$CONTEXT" \
    --gpu-only \
    --speed usable \
    --vram-headroom 1GB

done

QWEN38="Qwen3.8-27B"
QWEN_CODER="Qwen3-Coder-30B-A3B-Instruct"

for CONTEXT in 32k 64k; do
  echo "Planning Qwen3.8-27B / ${CONTEXT}..."
  "$RUN" plan "$QWEN38" \
    --context-length "$CONTEXT" \
    --quant Q4_K_M \
    --json \
    > "$OUT/targets/qwen3.8-27b-${CONTEXT}-q4_k_m.json"

  echo "Planning Qwen3-Coder-30B-A3B-Instruct / ${CONTEXT}..."
  "$RUN" plan "$QWEN_CODER" \
    --context-length "$CONTEXT" \
    --quant Q4_K_M \
    --json \
    > "$OUT/targets/qwen3-coder-30b-a3b-${CONTEXT}-q4_k_m.json"
done

cat > "$OUT/METHODOLOGY.md" <<EOF2
# whichllm recommendation capture

Run: \`${RUN_ID}\`

Profile label: \`${PROFILE}\`

## Purpose

This is a point-in-time second opinion on models that may fit the local
hardware. It is not a measured oMLX benchmark.

## Capture policy

- Ranking calls reuse the repository-local whichllm cache by default.
- \`WHICHLLM_REFRESH=1\` forces \`--refresh\` on the first ranking call only.
- General and coding rankings are captured at 32K and 64K context.
- Strict files require direct benchmark evidence via \`--evidence strict\`.
- Safe files require \`--gpu-only --speed usable --vram-headroom 1GB\`.
- Target plans use \`Q4_K_M\` because whichllm's Apple Silicon ranking path is
  GGUF-oriented; these plans are not MLX quantization predictions.

## Interpretation

Use broad results for candidate discovery, strict results to inspect the effect
of evidence quality, and safe results to identify recommendations with more
runtime margin. Validate selected models with actual MLX/oMLX measurements
before changing the main repository model profile.
EOF2

echo
echo "Capture complete:"
echo "  $OUT"
