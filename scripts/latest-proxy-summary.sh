#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

LATEST="$(ls -1t "$PROXY_REQUEST_LOG_DIR"/*-summary.json 2>/dev/null | head -1 || true)"
if [[ -z "$LATEST" ]]; then
  echo "No proxy summary logs found in $PROXY_REQUEST_LOG_DIR"
  exit 1
fi

echo "$LATEST"
python3 -m json.tool "$LATEST"
