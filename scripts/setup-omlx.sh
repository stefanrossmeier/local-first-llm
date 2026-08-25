#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: oMLX requires macOS on Apple Silicon."
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  cat <<'MSG'
ERROR: Homebrew is required for this setup.
Install Homebrew from https://brew.sh/ and rerun this script.
MSG
  exit 1
fi

echo "==> Tapping oMLX"
brew tap jundot/omlx https://github.com/jundot/omlx

echo "==> Installing/upgrading oMLX"
if ! brew install omlx; then
  cat <<'MSG'

oMLX installation failed.

If Homebrew printed:
  Refusing to load formula ... from untrusted tap

review the tap and explicitly trust it, then rerun this script:
  brew trust jundot/omlx

MSG
  exit 1
fi

if command -v omlx >/dev/null 2>&1; then
  echo
  echo "Installed: $(omlx --version 2>/dev/null || true)"
  echo "oMLX setup complete."
else
  echo "ERROR: omlx is not on PATH after installation."
  exit 1
fi
