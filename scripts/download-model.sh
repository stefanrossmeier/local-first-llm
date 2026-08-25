#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

TOOLS_VENV="$REPO_ROOT/.venv-hf"

if [[ ! "$HF_MODEL_REVISION" =~ '^[0-9a-fA-F]{40}$' ]]; then
  cat <<'MSG'
ERROR: HF_MODEL_REVISION must be a 40-character Hugging Face commit SHA.
Copy .env.example to .env, then set HF_MODEL_REVISION to the tested model
snapshot commit from the model's Files and versions page.
MSG
  exit 1
fi

if command -v hf >/dev/null 2>&1; then
  HF_CMD=(hf)
else
  echo "==> Creating local Hugging Face CLI environment"
  python3 -m venv "$TOOLS_VENV"
  source "$TOOLS_VENV/bin/activate"
  python3 -m pip install --upgrade pip huggingface_hub
  HF_CMD=(hf)
fi

echo "==> Downloading"
echo "    source: $HF_MODEL"
echo "    revision: $HF_MODEL_REVISION"
echo "    target: $MODEL_DIR"
mkdir -p "$MODEL_DIR"

"${HF_CMD[@]}" download "$HF_MODEL" \
  --revision "$HF_MODEL_REVISION" \
  --local-dir "$MODEL_DIR"

echo
echo "Model download complete."
echo "Size:"
du -sh "$MODEL_DIR"
