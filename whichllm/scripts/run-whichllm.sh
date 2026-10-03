#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v uvx >/dev/null 2>&1; then
  cat >&2 <<'MSG'
uvx was not found.

Install uv first, for example:
  ./whichllm/scripts/setup.sh

or:
  brew install uv
MSG
  exit 1
fi

# Keep whichllm's live model/benchmark cache scoped to this repository so
# captures do not silently depend on a user's unrelated global whichllm cache.
# uv itself can keep using its normal user cache.
export XDG_CACHE_HOME="${WHICHLLM_CACHE_ROOT:-$ROOT/whichllm/.cache}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.cache/uv}"
mkdir -p "$XDG_CACHE_HOME"

SPEC="${WHICHLLM_SPEC:-whichllm@latest}"
exec uvx "$SPEC" "$@"
