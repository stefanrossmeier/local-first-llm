#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DATE="${1:-$(date +%Y-%m-%d)}"
PROFILE="${LLMFIT_PROFILE_NAME:-m4-pro-48gb}"

OUT="$ROOT/llmfit/recommendations/${DATE}-${PROFILE}"

mkdir -p "$OUT"

echo "Capturing llmfit environment into:"
echo "  $OUT"
echo

{
  echo "captured_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo_commit=$(git -C "$ROOT" rev-parse HEAD)"
  echo "macos_version=$(sw_vers -productVersion)"
  echo "macos_build=$(sw_vers -buildVersion)"
  echo "architecture=$(uname -m)"
  echo "llmfit_version=$(llmfit --version)"
  echo "omlx_version=$(omlx --version 2>/dev/null || echo not-installed)"
} > "$OUT/environment.txt"

echo "Capturing hardware..."
llmfit system --json > "$OUT/system.json"

echo "Capturing hardware diagnostics..."
llmfit doctor > "$OUT/doctor.txt"

echo "Capturing default coding recommendations..."
llmfit recommend \
  --json \
  --use-case coding \
  --limit 20 \
  > "$OUT/coding-default.json"

echo "Capturing coding recommendations at 32K context..."
llmfit \
  --max-context 32768 \
  recommend \
  --json \
  --use-case coding \
  --limit 20 \
  > "$OUT/coding-32k.json"

echo "Capturing coding recommendations at 64K context..."
llmfit \
  --max-context 65536 \
  recommend \
  --json \
  --use-case coding \
  --limit 20 \
  > "$OUT/coding-64k.json"

echo "Capturing Qwen3.8 catalog entries..."
llmfit search "Qwen3.8" > "$OUT/qwen3.8-search.txt"

echo
echo "Done:"
echo "  $OUT"
