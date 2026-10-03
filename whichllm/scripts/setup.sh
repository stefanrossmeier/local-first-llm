#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v uvx >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "uvx is missing and Homebrew is not available." >&2
    echo "Install uv from https://docs.astral.sh/uv/ and retry." >&2
    exit 1
  fi

  echo "Installing uv with Homebrew..."
  brew install uv
fi

echo "Checking whichllm..."
"$ROOT/whichllm/scripts/run-whichllm.sh" --version

echo
echo "Ready. Try:"
echo "  ./whichllm/scripts/quick-check.sh"
