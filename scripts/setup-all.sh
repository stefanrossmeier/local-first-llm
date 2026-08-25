#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/setup-omlx.sh"
"$SCRIPT_DIR/setup-proxy.sh"
"$SCRIPT_DIR/download-model.sh"
"$SCRIPT_DIR/configure-omlx-model.sh"

echo
echo "Setup complete. Start with:"
echo "  $SCRIPT_DIR/start.sh"
