#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

check() {
  local label="$1"
  local url="$2"
  if curl -sf "$url" >/dev/null 2>&1; then
    echo "OK   $label  $url"
  else
    echo "DOWN $label  $url"
  fi
}

check "oMLX  " "http://${OMLX_HOST}:${OMLX_PORT}/v1/models"
check "Proxy " "http://${PROXY_HOST}:${PROXY_PORT}/v1/models"

echo
curl -s "http://${PROXY_HOST}:${PROXY_PORT}/v1/models" | python3 -m json.tool 2>/dev/null || true
