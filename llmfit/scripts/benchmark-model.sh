#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage:"
  echo "  $0 <model-id>"
  echo
  echo "Example:"
  echo "  $0 Qwen3.8-27B-4bit"
  exit 1
fi

MODEL="$1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_ID="$(date +%Y-%m-%dT%H%M%S)"

SAFE_MODEL="$(
  printf '%s' "$MODEL" \
    | tr '/: ' '---' \
    | tr -cd '[:alnum:]._-'
)"

OUT="$ROOT/llmfit/benchmarks/${SAFE_MODEL}/${RUN_ID}"
STORE="$ROOT/llmfit/.bench-store"

URL="${LLMFIT_MLX_URL:-http://127.0.0.1:8000}"
PROVIDER="${LLMFIT_PROVIDER:-mlx}"

mkdir -p "$OUT" "$STORE"

export LLMFIT_BENCH_STORE="$STORE"

echo "Benchmark store:"
echo "  $LLMFIT_BENCH_STORE"
echo

echo "Checking provider..."
curl -fsS "$URL/v1/models" > "$OUT/provider-models.json"

{
  echo "captured_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo_commit=$(git -C "$ROOT" rev-parse HEAD)"
  echo "model=$MODEL"
  echo "provider=$PROVIDER"
  echo "provider_url=$URL"
  echo "macos_version=$(sw_vers -productVersion)"
  echo "macos_build=$(sw_vers -buildVersion)"
  echo "architecture=$(uname -m)"
  echo "llmfit_version=$(llmfit --version)"
  echo "omlx_version=$(omlx --version 2>/dev/null || echo unknown)"
  echo "llmfit_bench_store=llmfit/.bench-store"
} > "$OUT/environment.txt"

llmfit --json system > "$OUT/system-before.json"
vm_stat > "$OUT/vm-stat-before.txt"

echo
echo "Benchmarking:"
echo "  model:    $MODEL"
echo "  provider: $PROVIDER"
echo "  endpoint: $URL"
echo

llmfit \
  --json \
  bench \
  --provider "$PROVIDER" \
  --url "$URL" \
  "$MODEL" \
  | tee "$OUT/llmfit-bench.json"

llmfit --json system > "$OUT/system-after.json"
vm_stat > "$OUT/vm-stat-after.txt"

find "$STORE" -type f -print \
  | sed "s#^$ROOT/##" \
  | sort \
  > "$OUT/bench-store-files.txt"

echo
echo "Results saved to:"
echo "  $OUT"
