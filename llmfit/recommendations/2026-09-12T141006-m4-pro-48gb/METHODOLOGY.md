# llmfit recommendation capture

Run: `2026-09-12T141006`

Hardware profile: `m4-pro-48gb`

## baseline/

Generated with a temporary empty `LLMFIT_BENCH_STORE`.

This prevents benchmark measurements produced by this repository from being
loaded from the experiment-local benchmark store.

It does NOT mean that the output is formula-only.

llmfit releases can contain embedded community benchmark measurements for
matching hardware. Those measurements may appear directly or may be used to
calibrate estimates.

Therefore a non-null `estimate_basis.local_calibration` is recorded rather
than treated as a validation failure.

## personalized/

Generated with:

`llmfit/.bench-store`

After this repository benchmarks models, these files can show how local
measurements change the recommendation output.

Before any repository-local benchmark exists, baseline and personalized
results may be identical.

## targets/

Direct `info` and explicit `plan` output for:

- Qwen/Qwen3.8-27B
- Qwen/Qwen3-Coder-30B-A3B-Instruct

Both 32K and 64K contexts are captured.

Explicit MLX 4-bit and MLX 8-bit plans are captured.

## Coding filter caveat

`--use-case coding` is a filtered catalog view.

Qwen3.8-27B is currently categorized by llmfit as Multimodal, while
Qwen3-Coder is categorized as Coding.

The coding-filtered recommendation output therefore must not be interpreted
as a direct Qwen3.8 versus Qwen3-Coder comparison.

Use the broad recommendation output, direct target analysis, and measured
benchmarks for that comparison.

## Calibration summary

See:

`CALIBRATION-SUMMARY.txt`

This records which confidence levels and calibration factors llmfit actually
used instead of assuming that a baseline must be uncalibrated.
