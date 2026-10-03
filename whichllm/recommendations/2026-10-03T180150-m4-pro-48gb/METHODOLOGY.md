# whichllm recommendation capture

Run: `2026-10-03T180150`

Profile label: `m4-pro-48gb`

## Purpose

This is a point-in-time second opinion on models that may fit the local
hardware. It is not a measured oMLX benchmark.

## Capture policy

- Ranking calls reuse the repository-local whichllm cache by default.
- `WHICHLLM_REFRESH=1` forces `--refresh` on the first ranking call only.
- General and coding rankings are captured at 32K and 64K context.
- Strict files require direct benchmark evidence via `--evidence strict`.
- Safe files require `--gpu-only --speed usable --vram-headroom 1GB`.
- Target plans use `Q4_K_M` because whichllm's Apple Silicon ranking path is
  GGUF-oriented; these plans are not MLX quantization predictions.

## Interpretation

Use broad results for candidate discovery, strict results to inspect the effect
of evidence quality, and safe results to identify recommendations with more
runtime margin. Validate selected models with actual MLX/oMLX measurements
before changing the main repository model profile.
