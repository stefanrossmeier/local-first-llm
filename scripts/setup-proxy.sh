#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "==> Creating proxy virtual environment"
python3 -m venv "$PROXY_VENV"
source "$PROXY_VENV/bin/activate"
python3 -m pip install --upgrade pip
python3 -m pip install -r "$PROXY_DIR/requirements.txt"

echo
echo "Proxy setup complete: $PROXY_VENV"
