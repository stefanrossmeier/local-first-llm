#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage:"
  echo "  $0 <model-id> <github-pr-url> [status]"
  echo
  echo "Example:"
  echo "  $0 Qwen3.8-27B-4bit https://github.com/AlexsJones/llmfit/pull/1234 open"
  exit 1
fi

MODEL="$1"
PR_URL="$2"
STATUS="${3:-open}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SAFE_MODEL="$(
  printf '%s' "$MODEL" \
    | tr '/: ' '---' \
    | tr -cd '[:alnum:]._-'
)"

BASE="$ROOT/llmfit/benchmarks/$SAFE_MODEL"

if [[ ! -d "$BASE" ]]; then
  echo "No benchmark directory found:"
  echo "  $BASE"
  exit 1
fi

LATEST="$(
  for d in "$BASE"/*; do
    [[ -d "$d" ]] && printf '%s\n' "$d"
  done | sort | tail -n 1
)"

if [[ -z "$LATEST" ]]; then
  echo "No benchmark run found under:"
  echo "  $BASE"
  exit 1
fi

cat > "$LATEST/UPSTREAM.md" <<EOF2
# Upstream llmfit contribution

Model: \`${MODEL}\`

Hardware:

- Apple M4 Pro
- 48 GB unified memory

Runtime:

- oMLX / MLX

llmfit:

- version: \`$(llmfit --version)\`

Contribution:

- Repository: \`AlexsJones/llmfit\`
- Pull request: ${PR_URL}
- Status: ${STATUS}
- Recorded at UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Source measurement:

- \`llmfit-bench.json\`

Local benchmark store:

- \`llmfit/.bench-store\` (not committed)
EOF2

echo "Recorded contribution:"
echo "  $LATEST/UPSTREAM.md"
