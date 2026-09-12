#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STORE="$ROOT/llmfit/.bench-store"

export LLMFIT_BENCH_STORE="$STORE"

echo "llmfit benchmark store:"
echo "  $LLMFIT_BENCH_STORE"
echo

case "${1:-}" in
  "")
    llmfit bench --share
    ;;
  --dry-run)
    llmfit bench --share --dry-run
    ;;
  --yes)
    llmfit bench --share --yes
    ;;
  *)
    echo "Usage:"
    echo "  $0"
    echo "  $0 --dry-run"
    echo "  $0 --yes"
    exit 1
    ;;
esac
