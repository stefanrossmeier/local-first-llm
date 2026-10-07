#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
  echo "Usage: $0 <profile-name>" >&2
  echo "Available profiles:" >&2
  for f in "$REPO_ROOT"/config/model-profiles/*.env; do
    [[ -e "$f" ]] || continue
    basename "$f" .env >&2
  done
  exit 2
fi

PROFILE_FILE="$REPO_ROOT/config/model-profiles/${PROFILE}.env"
if [[ ! -f "$PROFILE_FILE" ]]; then
  echo "ERROR: model profile not found: $PROFILE_FILE" >&2
  exit 1
fi

ENV_FILE="$REPO_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$REPO_ROOT/.env.example" "$ENV_FILE"
fi

PROFILE="$PROFILE" ENV_FILE="$ENV_FILE" python3 <<'PY'
import os
from pathlib import Path

path = Path(os.environ["ENV_FILE"])
profile = os.environ["PROFILE"]
lines = path.read_text().splitlines()
out = []
replaced = False
for line in lines:
    if line.startswith("MODEL_PROFILE="):
        if not replaced:
            out.append(f"MODEL_PROFILE={profile}")
            replaced = True
        continue
    out.append(line)
if not replaced:
    insert_at = 0
    while insert_at < len(out) and (not out[insert_at].strip() or out[insert_at].lstrip().startswith("#")):
        insert_at += 1
    out.insert(insert_at, f"MODEL_PROFILE={profile}")
path.write_text("\n".join(out) + "\n")
PY

echo "Selected model profile: $PROFILE"
echo "Persisted in: $ENV_FILE"
