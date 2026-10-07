#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE="qwen38-35b-a3b-distill"

"$SCRIPT_DIR/select-model-profile.sh" "$PROFILE"

echo
echo "==> Setting up oMLX"
"$SCRIPT_DIR/setup-omlx.sh"

echo
echo "==> Setting up Copilot inspection proxy"
"$SCRIPT_DIR/setup-proxy.sh"

echo
echo "==> Downloading pinned Qwen3.8-35B-A3B-Distill MLX model"
"$SCRIPT_DIR/download-model.sh"

echo
echo "==> Applying baseline oMLX model settings"
"$SCRIPT_DIR/configure-omlx-model.sh"

cat <<MSG

============================================
 Qwen3.8-35B-A3B-Distill setup complete
============================================
Profile: $PROFILE

Next:
  $REPO_ROOT/scripts/start.sh
  $REPO_ROOT/scripts/status.sh

VS Code Copilot Chat provider template:
  $REPO_ROOT/config/chatLanguageModels.provider.qwen38-35b-a3b-distill.json

Automated inference-engineering benchmark:
  $REPO_ROOT/scripts/run-inference-benchmarks.sh
MSG
