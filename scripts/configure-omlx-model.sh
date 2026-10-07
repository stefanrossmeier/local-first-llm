#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

TARGET="$HOME/.omlx/model_settings.json"
mkdir -p "$HOME/.omlx"

export MODEL_ID TARGET
export MODEL_MAX_CONTEXT_WINDOW="${MODEL_MAX_CONTEXT_WINDOW:-}"
export MODEL_ENABLE_THINKING="${MODEL_ENABLE_THINKING:-}"
export MODEL_PRESERVE_THINKING="${MODEL_PRESERVE_THINKING:-}"
export MODEL_THINKING_BUDGET_ENABLED="${MODEL_THINKING_BUDGET_ENABLED:-}"
export MODEL_MTP_ENABLED="${MODEL_MTP_ENABLED:-}"
export MODEL_QWEN35_ANE_PREFILL_ENABLED="${MODEL_QWEN35_ANE_PREFILL_ENABLED:-}"
export MODEL_TURBOQUANT_KV_ENABLED="${MODEL_TURBOQUANT_KV_ENABLED:-}"
export MODEL_QWEN35_OQ_A8_ENABLED="${MODEL_QWEN35_OQ_A8_ENABLED:-}"
export MODEL_SPEC_PREFILL_ENABLED="${MODEL_SPEC_PREFILL_ENABLED:-}"
export MODEL_DFLASH_ENABLED="${MODEL_DFLASH_ENABLED:-}"
export MODEL_MOE_EXPERT_OFFLOAD_ENABLED="${MODEL_MOE_EXPERT_OFFLOAD_ENABLED:-}"

python3 <<'PY'
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


def parse_bool(value: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise SystemExit(f"Invalid boolean value: {value!r}")


def set_if_env(env_name: str, setting_name: str, converter):
    value = os.environ.get(env_name)
    if value is not None and value != "":
        settings[setting_name] = converter(value)


set_if_env("MODEL_MAX_CONTEXT_WINDOW", "max_context_window", int)
set_if_env("MODEL_ENABLE_THINKING", "enable_thinking", parse_bool)
set_if_env("MODEL_PRESERVE_THINKING", "preserve_thinking", parse_bool)
set_if_env("MODEL_THINKING_BUDGET_ENABLED", "thinking_budget_enabled", parse_bool)
set_if_env("MODEL_MTP_ENABLED", "mtp_enabled", parse_bool)
set_if_env("MODEL_QWEN35_ANE_PREFILL_ENABLED", "qwen35_ane_prefill_enabled", parse_bool)
set_if_env("MODEL_TURBOQUANT_KV_ENABLED", "turboquant_kv_enabled", parse_bool)
set_if_env("MODEL_QWEN35_OQ_A8_ENABLED", "qwen35_oq_a8_enabled", parse_bool)
set_if_env("MODEL_SPEC_PREFILL_ENABLED", "specprefill_enabled", parse_bool)
set_if_env("MODEL_DFLASH_ENABLED", "dflash_enabled", parse_bool)
set_if_env("MODEL_MOE_EXPERT_OFFLOAD_ENABLED", "moe_expert_offload_enabled", parse_bool)

path.write_text(json.dumps(data, indent=2) + "\n")
print(f"Updated {path} for {model_id}")
PY

cat "$TARGET"
