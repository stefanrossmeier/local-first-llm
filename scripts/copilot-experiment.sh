#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

STATE_FILE="$REPO_ROOT/logs/copilot-experiment-state.json"
MARKER_FILE="$REPO_ROOT/logs/copilot-experiment-marker"
ACTION="${1:-}"
LABEL="${2:-manual}"

usage() {
  cat <<USAGE
Usage:
  $0 start [label]
  $0 finish
  $0 status
USAGE
}

capture_environment() {
  local out_dir="$1"
  {
    echo "model_profile=${MODEL_PROFILE:-}"
    echo "hf_model=$HF_MODEL"
    echo "hf_model_revision=$HF_MODEL_REVISION"
    echo "model_id=$MODEL_ID"
    echo "model_max_context_window=${MODEL_MAX_CONTEXT_WINDOW:-}"
    echo "omlx_version=$(omlx --version 2>/dev/null || true)"
    echo "repo_git_commit=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
    echo "kernel=$(public_kernel_summary)"
    sw_vers 2>/dev/null || true
  } > "$out_dir/environment.txt"
  public_hardware_summary > "$out_dir/hardware.txt" 2>&1 || true
  if [[ -f "$HOME/.omlx/model_settings.json" ]]; then
    MODEL_ID="$MODEL_ID" python3 - "$HOME/.omlx/model_settings.json" <<'PY' > "$out_dir/omlx-model-settings.json"
import json, os, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
print(json.dumps(data.get("models", {}).get(os.environ["MODEL_ID"], {}), indent=2))
PY
  fi
}

case "$ACTION" in
  start)
    if [[ -f "$STATE_FILE" ]]; then
      echo "ERROR: a Copilot experiment is already active." >&2
      echo "Run '$0 status' or '$0 finish' first." >&2
      exit 1
    fi
    if ! curl -sf "http://${PROXY_HOST}:${PROXY_PORT}/v1/models" >/dev/null 2>&1; then
      echo "ERROR: Copilot proxy is not running. Start the stack first:" >&2
      echo "  $REPO_ROOT/scripts/start.sh" >&2
      exit 1
    fi

    SAFE_LABEL="$(echo "$LABEL" | tr -cs '[:alnum:]_. -' '-' | tr ' ' '-' | sed 's/^-*//;s/-*$//' | cut -c1-48)"
    [[ -n "$SAFE_LABEL" ]] || SAFE_LABEL="manual"
    TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
    PROFILE_NAME="${MODEL_PROFILE:-custom}"
    OUT_DIR="$REPO_ROOT/experiments/${PROFILE_NAME}/runs/${TIMESTAMP}-copilot-${SAFE_LABEL}"
    mkdir -p "$OUT_DIR/captures"

    # Marker comes after the output directory is prepared and immediately before
    # the interactive run begins. `find -newer` then selects only this session.
    touch "$MARKER_FILE"
    OMLX_LOG="$RUNTIME_LOG_DIR/omlx.log"
    PROXY_LOG="$RUNTIME_LOG_DIR/copilot-proxy.log"
    if [[ -f "$OMLX_LOG" ]]; then
      OMLX_OFFSET="$(wc -c < "$OMLX_LOG")"
    else
      OMLX_OFFSET=0
    fi
    if [[ -f "$PROXY_LOG" ]]; then
      PROXY_OFFSET="$(wc -c < "$PROXY_LOG")"
    else
      PROXY_OFFSET=0
    fi

    OUT_DIR="$OUT_DIR" MARKER_FILE="$MARKER_FILE" OMLX_OFFSET="$OMLX_OFFSET" PROXY_OFFSET="$PROXY_OFFSET" \
      OMLX_LOG="$OMLX_LOG" PROXY_LOG="$PROXY_LOG" python3 <<'PY' > "$STATE_FILE"
import json, os
print(json.dumps({
    "out_dir": os.environ["OUT_DIR"],
    "marker_file": os.environ["MARKER_FILE"],
    "omlx_log": os.environ["OMLX_LOG"],
    "omlx_offset": int(os.environ["OMLX_OFFSET"]),
    "proxy_log": os.environ["PROXY_LOG"],
    "proxy_offset": int(os.environ["PROXY_OFFSET"]),
}, indent=2))
PY

    capture_environment "$OUT_DIR"
    cat > "$OUT_DIR/notes.md" <<'NOTES'
# Copilot Chat experiment notes

Fill this in during/after the run. The request/response metrics are captured automatically.

## Workload

- Repository/workspace used:
- Fresh chat or continued chat:
- Prompt/task:
- Expected outcome:

## Observations

- Subjective responsiveness:
- Tool calls correct?:
- Code/result quality:
- Failures or retries:
- Other notes:
NOTES

    cat <<MSG

Copilot experiment started.

Output directory:
  $OUT_DIR

Now use VS Code Copilot Chat with:
  Qwen3.8 35B-A3B Distill MLX

Suggested sequence:
  1. Fresh chat: run one representative coding/agent task.
  2. Same chat: ask a follow-up that reuses the workspace/context.
  3. Optional fresh chat: repeat a comparable task for another cold sample.

When finished:
  $0 finish
MSG
    ;;

  finish)
    if [[ ! -f "$STATE_FILE" ]]; then
      echo "ERROR: no active Copilot experiment." >&2
      exit 1
    fi

    eval "$(STATE_FILE="$STATE_FILE" python3 <<'PY'
import json, os, shlex
from pathlib import Path
s = json.loads(Path(os.environ["STATE_FILE"]).read_text())
for key in ("out_dir", "marker_file", "omlx_log", "proxy_log"):
    print(f"{key.upper()}={shlex.quote(str(s[key]))}")
for key in ("omlx_offset", "proxy_offset"):
    print(f"{key.upper()}={int(s[key])}")
PY
)"

    mkdir -p "$OUT_DIR/captures"
    find "$PROXY_REQUEST_LOG_DIR" -type f -newer "$MARKER_FILE" \
      \( -name '*-summary.json' -o -name '*-response.json' \) \
      -exec cp {} "$OUT_DIR/captures/" \;

    if [[ -f "$OMLX_LOG" ]]; then
      tail -c +$((OMLX_OFFSET + 1)) "$OMLX_LOG" > "$OUT_DIR/omlx-session.log" 2>/dev/null || cp "$OMLX_LOG" "$OUT_DIR/omlx-session.log"
    fi
    if [[ -f "$PROXY_LOG" ]]; then
      tail -c +$((PROXY_OFFSET + 1)) "$PROXY_LOG" > "$OUT_DIR/copilot-proxy-session.log" 2>/dev/null || cp "$PROXY_LOG" "$OUT_DIR/copilot-proxy-session.log"
    fi

    OUT_DIR="$OUT_DIR" python3 <<'PY'
import json
import os
from pathlib import Path

out = Path(os.environ["OUT_DIR"])
cap = out / "captures"
rows = []
for req_path in sorted(cap.glob("*-summary.json")):
    stem = req_path.name[:-len("-summary.json")]
    res_path = cap / f"{stem}-response.json"
    req = json.loads(req_path.read_text())
    res = json.loads(res_path.read_text()) if res_path.exists() else {}
    usage = res.get("usage") or {}
    details = usage.get("prompt_tokens_details") or {}
    messages_chars = sum(int(m.get("chars") or 0) for m in req.get("messages", []))
    row = {
        "stem": stem,
        "model": req.get("model"),
        "message_count": req.get("message_count"),
        "messages_chars": messages_chars,
        "tool_count": req.get("tool_count", 0),
        "tools_chars": req.get("tools_chars", 0),
        "status_code": res.get("status_code"),
        "wall_s": res.get("wall_s"),
        "proxy_first_visible_s": res.get("first_visible_s"),
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "cached_tokens": details.get("cached_tokens"),
        "ttft_s": usage.get("time_to_first_token"),
        "visible_ttft_s": usage.get("time_to_first_visible_token"),
        "pp_tps": usage.get("prompt_tokens_per_second"),
        "tg_tps": usage.get("generation_tokens_per_second"),
        "finish_reason": res.get("finish_reason"),
    }
    rows.append(row)

summary = {"requests": rows, "request_count": len(rows)}
(out / "copilot-summary.json").write_text(json.dumps(summary, indent=2) + "\n")

def f(v, digits=1):
    if v is None:
        return "—"
    if isinstance(v, int):
        return f"{v:,}"
    if isinstance(v, float):
        return f"{v:.{digits}f}"
    return str(v)

lines = [
    "# VS Code Copilot Chat experiment capture",
    "",
    "This is measurement output, not the final experiment documentation.",
    "",
    "| Request | Messages | Tools | Prompt tokens | Cached | PP tok/s | TG tok/s | TTFT | visible TTFT | wall |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
]
for i, r in enumerate(rows, 1):
    lines.append(
        f"| {i} | {f(r['message_count'])} | {f(r['tool_count'])} | {f(r['prompt_tokens'])} | "
        f"{f(r['cached_tokens'])} | {f(r['pp_tps'])} | {f(r['tg_tps'])} | "
        f"{f(r['ttft_s'],2)} s | {f(r['visible_ttft_s'],2)} s | {f(r['wall_s'],2)} s |"
    )
if not rows:
    lines += ["", "No chat-completion request summaries were captured. Check `copilot-proxy-session.log`."]
else:
    lines += [
        "",
        "The request summaries intentionally omit message bodies by default. `tools_chars` and message character counts remain in the JSON for context-overhead analysis.",
    ]
(out / "copilot-summary.md").write_text("\n".join(lines) + "\n")
PY

    rm -f "$STATE_FILE" "$MARKER_FILE"
    cat <<MSG

Copilot experiment finished.

Results:
  $OUT_DIR

Read first:
  $OUT_DIR/copilot-summary.md
  $OUT_DIR/notes.md

Keep this run directory; it is the source material for the later experiment write-up.
MSG
    ;;

  status)
    if [[ -f "$STATE_FILE" ]]; then
      echo "Active Copilot experiment:"
      cat "$STATE_FILE"
    else
      echo "No active Copilot experiment."
    fi
    ;;

  *)
    usage
    exit 2
    ;;
esac
