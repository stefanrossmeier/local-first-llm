#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

URL="http://${OMLX_HOST}:${OMLX_PORT}/v1/chat/completions"
REPEAT="${1:-2}"
PROMPT='Review this TypeScript function for correctness. Identify important bugs or race conditions and propose a concise fix. Keep the final answer focused and under 400 words.\n\nasync function getUser(id: string) {\n  if (!cache.has(id)) {\n    const user = await db.findUser(id);\n    cache.set(id, user);\n  }\n  return cache.get(id);\n}'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

for i in $(seq 1 "$REPEAT"); do
  OUT="$TMP_DIR/response-$i.json"
  echo "==> Run $i/$REPEAT: reasoning=$BENCH_REASONING_EFFORT max_tokens=$BENCH_MAX_TOKENS"

  python3 - "$MODEL_ID" "$BENCH_REASONING_EFFORT" "$BENCH_MAX_TOKENS" "$PROMPT" > "$TMP_DIR/request.json" <<'PY'
import json, sys
model, effort, max_tokens, prompt = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
print(json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "chat_template_kwargs": {
        "enable_thinking": True,
        "reasoning_effort": effort,
        "preserve_thinking": False,
    },
    "max_tokens": max_tokens,
    "temperature": 0.2,
}))
PY

  curl -sf "$URL" \
    -H 'Content-Type: application/json' \
    --data-binary @"$TMP_DIR/request.json" \
    > "$OUT"

  python3 - "$OUT" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
usage = data.get("usage", {})
choice = (data.get("choices") or [{}])[0]
pt = usage.get("prompt_tokens") or usage.get("input_tokens")
ct = usage.get("completion_tokens") or usage.get("output_tokens")
total_time = usage.get("total_time")
finish = choice.get("finish_reason")
rate = (ct / total_time) if ct and total_time else None
print(f"prompt_tokens     : {pt}")
print(f"completion_tokens : {ct}")
print(f"total_time_s      : {total_time}")
print(f"effective_output_tok_s: {rate:.2f}" if rate else "effective_output_tok_s: n/a")
print(f"finish_reason     : {finish}")
PY
  echo
done
