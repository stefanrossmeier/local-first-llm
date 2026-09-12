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
DATE="$(date +%Y-%m-%d)"

SAFE_MODEL="$(
  printf '%s' "$MODEL" |
    tr '/: ' '---' |
    tr -cd '[:alnum:]._-'
)"

OUT="$ROOT/llmfit/benchmarks/${SAFE_MODEL}/${DATE}"

mkdir -p "$OUT"

URL="${LLMFIT_MLX_URL:-http://127.0.0.1:8000}"

echo "Checking oMLX..."
curl -fsS "$URL/v1/models" > "$OUT/provider-models.json"

{
  echo "captured_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo_commit=$(git -C "$ROOT" rev-parse HEAD)"
  echo "model=$MODEL"
  echo "provider=mlx"
  echo "provider_url=$URL"
  echo "macos_version=$(sw_vers -productVersion)"
  echo "macos_build=$(sw_vers -buildVersion)"
  echo "llmfit_version=$(llmfit --version)"
  echo "omlx_version=$(omlx --version 2>/dev/null || echo unknown)"
} > "$OUT/environment.txt"

echo
echo "Benchmarking:"
echo "  model:    $MODEL"
echo "  provider: MLX/oMLX"
echo "  endpoint: $URL"
echo

llmfit bench \
  --provider mlx \
  --url "$URL" \
  "$MODEL" \
  --json \
  | tee "$OUT/llmfit-bench.json"

echo
echo "Results saved to:"
echo "  $OUT"
