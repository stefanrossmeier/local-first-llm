#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

RUN_ID="${1:-$(date +%Y-%m-%dT%H%M%S)}"
PROFILE="${LLMFIT_PROFILE_NAME:-m4-pro-48gb}"

OUT="$ROOT/llmfit/recommendations/${RUN_ID}-${PROFILE}"

# Baseline store:
# intentionally empty, so measurements created by THIS repository do not
# influence the baseline.
#
# Note: llmfit may still use benchmark/calibration data embedded in its
# release, including community measurements for matching hardware.
BASELINE_STORE="$(mktemp -d "${TMPDIR:-/tmp}/llmfit-baseline-store.XXXXXX")"

# Benchmarks produced by this repository are stored separately here.
EXPERIMENT_STORE="$ROOT/llmfit/.bench-store"

cleanup() {
  rm -rf "$BASELINE_STORE"
}
trap cleanup EXIT

mkdir -p \
  "$OUT/baseline" \
  "$OUT/personalized" \
  "$OUT/targets" \
  "$EXPERIMENT_STORE"

baseline_llmfit() {
  LLMFIT_BENCH_STORE="$BASELINE_STORE" llmfit "$@"
}

personalized_llmfit() {
  LLMFIT_BENCH_STORE="$EXPERIMENT_STORE" llmfit "$@"
}

echo "Capturing llmfit experiment into:"
echo "  $OUT"
echo
echo "Baseline local benchmark store:"
echo "  $BASELINE_STORE"
echo
echo "Experiment benchmark store:"
echo "  $EXPERIMENT_STORE"
echo

{
  echo "captured_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo_commit=$(git -C "$ROOT" rev-parse HEAD)"
  echo "macos_version=$(sw_vers -productVersion)"
  echo "macos_build=$(sw_vers -buildVersion)"
  echo "architecture=$(uname -m)"
  echo "llmfit_version=$(llmfit --version)"
  echo "omlx_version=$(omlx --version 2>/dev/null || echo not-installed)"
  echo "profile=$PROFILE"
  echo "baseline_store=temporary-empty-local-store"
  echo "experiment_store=llmfit/.bench-store"
} > "$OUT/environment.txt"

git -C "$ROOT" status --short > "$OUT/git-status.txt"

echo "Capturing hardware..."
baseline_llmfit --json system > "$OUT/system.json"

echo "Capturing hardware diagnostics..."
baseline_llmfit doctor > "$OUT/doctor.txt"

echo "Capturing catalog searches..."
baseline_llmfit search "Qwen3.8" > "$OUT/qwen3.8-search.txt"
baseline_llmfit search "Qwen3-Coder" > "$OUT/qwen3-coder-search.txt"

QWEN38="Qwen/Qwen3.8-27B"
QWEN_CODER="Qwen/Qwen3-Coder-30B-A3B-Instruct"

for SPEC in "32k:32768" "64k:65536"; do
  LABEL="${SPEC%%:*}"
  CTX="${SPEC##*:}"

  echo
  echo "=== ${LABEL} / ${CTX} tokens ==="

  echo "Baseline: all recommendations..."
  baseline_llmfit \
    --max-context "$CTX" \
    --json \
    recommend \
    --min-fit good \
    --limit 100 \
    > "$OUT/baseline/all-${LABEL}.json"

  echo "Baseline: coding-filtered recommendations..."
  baseline_llmfit \
    --max-context "$CTX" \
    --json \
    recommend \
    --use-case coding \
    --min-fit good \
    --limit 100 \
    > "$OUT/baseline/coding-${LABEL}.json"

  echo "Baseline: full fit table..."
  baseline_llmfit \
    --max-context "$CTX" \
    --json \
    fit \
    -n 250 \
    > "$OUT/baseline/fit-${LABEL}.json"

  echo "Target: Qwen3.8 direct analysis..."
  baseline_llmfit \
    --max-context "$CTX" \
    --json \
    info "$QWEN38" \
    > "$OUT/targets/qwen3.8-27b-${LABEL}.json"

  echo "Target: Qwen3-Coder direct analysis..."
  baseline_llmfit \
    --max-context "$CTX" \
    --json \
    info "$QWEN_CODER" \
    > "$OUT/targets/qwen3-coder-30b-a3b-${LABEL}.json"

  echo "Target: Qwen3.8 MLX 4-bit plan..."
  baseline_llmfit \
    --json \
    plan "$QWEN38" \
    --context "$CTX" \
    --quant mlx-4bit \
    > "$OUT/targets/qwen3.8-27b-${LABEL}-mlx-4bit-plan.json"

  echo "Target: Qwen3.8 MLX 8-bit plan..."
  baseline_llmfit \
    --json \
    plan "$QWEN38" \
    --context "$CTX" \
    --quant mlx-8bit \
    > "$OUT/targets/qwen3.8-27b-${LABEL}-mlx-8bit-plan.json"

  echo "Target: Qwen3-Coder MLX 4-bit plan..."
  baseline_llmfit \
    --json \
    plan "$QWEN_CODER" \
    --context "$CTX" \
    --quant mlx-4bit \
    > "$OUT/targets/qwen3-coder-30b-a3b-${LABEL}-mlx-4bit-plan.json"

  echo "Target: Qwen3-Coder MLX 8-bit plan..."
  baseline_llmfit \
    --json \
    plan "$QWEN_CODER" \
    --context "$CTX" \
    --quant mlx-8bit \
    > "$OUT/targets/qwen3-coder-30b-a3b-${LABEL}-mlx-8bit-plan.json"

  echo "Personalized: all recommendations..."
  personalized_llmfit \
    --max-context "$CTX" \
    --json \
    recommend \
    --min-fit good \
    --limit 100 \
    > "$OUT/personalized/all-${LABEL}.json"

  echo "Personalized: coding-filtered recommendations..."
  personalized_llmfit \
    --max-context "$CTX" \
    --json \
    recommend \
    --use-case coding \
    --min-fit good \
    --limit 100 \
    > "$OUT/personalized/coding-${LABEL}.json"
done

echo
echo "Summarizing estimate confidence and calibration..."

python3 - "$OUT" <<'PY'
import collections
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

def collect(directory, patterns):
    confidence = collections.Counter()
    calibrations = collections.Counter()
    model_count = 0
    files = []

    for pattern in patterns:
        files.extend(directory.glob(pattern))

    for filename in sorted(set(files)):
        try:
            data = json.loads(filename.read_text())
        except Exception:
            continue

        models = data.get("models", [])
        if not isinstance(models, list):
            continue

        for model in models:
            model_count += 1

            conf = model.get("estimate_confidence")
            if conf is not None:
                confidence[str(conf)] += 1

            basis = model.get("estimate_basis") or {}
            cal = basis.get("local_calibration")
            if cal is not None:
                calibrations[f"{float(cal):.6f}"] += 1

    return model_count, confidence, calibrations

def append_summary(lines, title, directory, patterns):
    count, confidence, calibrations = collect(directory, patterns)

    lines.append(f"{title}:")
    lines.append(f"  model rows: {count}")

    lines.append("  estimate confidence:")
    if confidence:
        for key, value in sorted(confidence.items()):
            lines.append(f"    {key}: {value}")
    else:
        lines.append("    none reported")

    lines.append("  calibration factors:")
    if calibrations:
        for key, value in sorted(calibrations.items()):
            lines.append(f"    {key}: {value} rows")
    else:
        lines.append("    none")

    lines.append("")

lines = []

# Compare like-for-like recommendation files.
patterns = ("all-*.json", "coding-*.json")

append_summary(
    lines,
    "baseline recommendations",
    root / "baseline",
    patterns,
)

append_summary(
    lines,
    "personalized recommendations",
    root / "personalized",
    patterns,
)

# The broader fit table exists only in baseline, so report it separately.
append_summary(
    lines,
    "baseline full fit tables",
    root / "baseline",
    ("fit-*.json",),
)

summary = "\n".join(lines)
print(summary)
(root / "CALIBRATION-SUMMARY.txt").write_text(summary + "\n")
PY

cat > "$OUT/METHODOLOGY.md" <<EOF2
# llmfit recommendation capture

Run: \`${RUN_ID}\`

Hardware profile: \`${PROFILE}\`

## baseline/

Generated with a temporary empty \`LLMFIT_BENCH_STORE\`.

This prevents benchmark measurements produced by this repository from being
loaded from the experiment-local benchmark store.

It does NOT mean that the output is formula-only.

llmfit releases can contain embedded community benchmark measurements for
matching hardware. Those measurements may appear directly or may be used to
calibrate estimates.

Therefore a non-null \`estimate_basis.local_calibration\` is recorded rather
than treated as a validation failure.

## personalized/

Generated with:

\`llmfit/.bench-store\`

After this repository benchmarks models, these files can show how local
measurements change the recommendation output.

Before any repository-local benchmark exists, baseline and personalized
results may be identical.

## targets/

Direct \`info\` and explicit \`plan\` output for:

- Qwen/Qwen3.8-27B
- Qwen/Qwen3-Coder-30B-A3B-Instruct

Both 32K and 64K contexts are captured.

Explicit MLX 4-bit and MLX 8-bit plans are captured.

## Coding filter caveat

\`--use-case coding\` is a filtered catalog view.

Qwen3.8-27B is currently categorized by llmfit as Multimodal, while
Qwen3-Coder is categorized as Coding.

The coding-filtered recommendation output therefore must not be interpreted
as a direct Qwen3.8 versus Qwen3-Coder comparison.

Use the broad recommendation output, direct target analysis, and measured
benchmarks for that comparison.

## Calibration summary

See:

\`CALIBRATION-SUMMARY.txt\`

This records which confidence levels and calibration factors llmfit actually
used instead of assuming that a baseline must be uncalibrated.
EOF2

echo
echo "Done."
echo
echo "Results:"
echo "  $OUT"
echo
echo "Calibration summary:"
cat "$OUT/CALIBRATION-SUMMARY.txt"
