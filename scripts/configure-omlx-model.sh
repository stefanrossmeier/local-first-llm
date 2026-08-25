#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

TARGET="$HOME/.omlx/model_settings.json"
mkdir -p "$HOME/.omlx"

MODEL_ID="$MODEL_ID" TARGET="$TARGET" python3 <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["TARGET"])
model_id = os.environ["MODEL_ID"]

if path.exists():
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        raise SystemExit(f"Cannot parse {path}: {exc}")
else:
    data = {"version": 1, "models": {}}

data.setdefault("version", 1)
models = data.setdefault("models", {})
settings = models.setdefault(model_id, {})

# Keep reasoning enabled, but let the client choose low/medium/high effort.
# Do not preserve old thinking traces in subsequent turns.
settings["enable_thinking"] = True
settings["preserve_thinking"] = False
settings["thinking_budget_enabled"] = False

path.write_text(json.dumps(data, indent=2) + "\n")
print(f"Updated {path} for {model_id}")
PY

cat "$TARGET"
