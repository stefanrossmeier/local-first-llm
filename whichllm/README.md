# whichllm experiments

This directory keeps `whichllm` model-fit experiments separate from the main
oMLX setup and from the existing `llmfit` measurements.

The intended machine for the first captures is the same machine documented by
this repository:

- Apple M4 Pro
- 48 GB unified memory
- macOS

`whichllm` is useful here as an independent model-discovery and fit-ranking
source. It detects the local hardware, fetches current Hugging Face model data,
combines benchmark evidence, estimates memory and generation speed, and ranks
models that look runnable.

It is **not** a replacement for measured oMLX benchmarks. In particular,
`whichllm` currently restricts Apple Silicon recommendations to GGUF-backed
candidates for runtime stability. The main repository runs MLX models through
oMLX, so treat `whichllm` as a second opinion about candidate families,
quantization-size classes, context pressure, and likely speed rather than as an
exact MLX memory/performance predictor.

## Requirements

The scripts use `uvx`, which is part of `uv`.

Install it once with:

```bash
./whichllm/scripts/setup.sh
```

Or install `uv` yourself:

```bash
brew install uv
```

The wrapper uses `whichllm@latest` by default. To reproduce a capture with a
specific release, override the package spec, for example:

```bash
WHICHLLM_SPEC='whichllm@0.5.19' \
  ./whichllm/scripts/quick-check.sh
```

The exact version used by a full capture is written into `environment.txt`.

## Quick check

Stop oMLX and other memory-heavy inference processes first if you want the
hardware view to reflect an otherwise idle machine.

Run:

```bash
./whichllm/scripts/quick-check.sh
```

This prints:

1. detected hardware;
2. top coding recommendations at 32K context;
3. coding recommendations estimated at at least 10 tok/s;
4. a conservative full-GPU view with 1 GB memory headroom.

The last view follows upstream's safer-pick guidance. It can be empty on a
machine where the most interesting models are estimated below 10 tok/s; that is
useful information rather than an error.

## Capture recommendations

Run:

```bash
./whichllm/scripts/capture-recommendations.sh
```

The capture creates:

```text
whichllm/recommendations/<timestamp>-m4-pro-48gb/
```

For both 32K and 64K context it stores:

- broad recommendations as JSON;
- coding recommendations as JSON and Markdown;
- coding recommendations with strict/direct benchmark evidence;
- a conservative coding view requiring full-GPU fit, at least 10 tok/s, and
  1 GB VRAM headroom;
- `plan` output for Qwen3.8-27B and Qwen3-Coder-30B-A3B-Instruct using Q4_K_M.

It also stores `hardware.txt`, `environment.txt`, and the repository Git status.

By default the capture reuses the repository-local `whichllm` cache. This is
intentional: running `quick-check.sh` and then immediately forcing another live
fetch can hit Hugging Face rate limits. The wrapper keeps the cache under
`whichllm/.cache/`, which is gitignored.

If you explicitly want to ignore that cache for the first ranking call, run:

```bash
WHICHLLM_REFRESH=1 ./whichllm/scripts/capture-recommendations.sh
```

`whichllm` retries transient Hugging Face failures and can fall back to cached or
curated benchmark data. A `429 Too Many Requests` warning is therefore not by
itself a capture failure; check the script's final exit status and generated
files.

## Inspect another model

Use:

```bash
./whichllm/scripts/plan-model.sh 'Qwen3.8-27B' 32k Q4_K_M
./whichllm/scripts/plan-model.sh 'Qwen3.8-27B' 64k Q4_K_M
```

Arguments are:

```text
plan-model.sh MODEL [CONTEXT] [QUANT]
```

Defaults are `32k` and `Q4_K_M`.

## Reading the results

The most useful fields in ranking JSON are:

- `fit_type`: `full_gpu`, `partial_offload`, or `cpu_only`;
- `vram_required_bytes` and `vram_available_bytes`;
- `estimated_tok_per_sec` plus its confidence/range metadata;
- `benchmark_source` and `benchmark_confidence`.

Use the broad coding result to discover candidates. Then compare it with the
strict-evidence result before trusting a quality ranking. Finally, use the safe
view to see which options have enough memory and estimated speed margin to be
comfortable rather than merely technically runnable.

Do not interpret `estimated_tok_per_sec` as a measured oMLX number. Validate a
promising model with the repository's actual inference/benchmark workflow.

## Upstream behavior this integration relies on

This integration was originally checked against upstream `whichllm` 0.5.19 and
was exercised with `whichllm` 0.5.20 on 2026-10-03. At that point:

- Python 3.11+ was required;
- `--context-length` accepted values such as `32k` and `64k`;
- `--profile coding`, `--speed usable`, `--gpu-only`, `--vram-headroom`,
  `--evidence strict`, `--json`, and `--markdown` were supported;
- model metadata was cached for 6 hours and benchmark data for 24 hours;
- Apple Silicon used unified memory for fit estimation and GGUF-backed
  candidates for ranking.

Because `whichllm` consumes live Hugging Face and benchmark data, recommendation
outputs are snapshots. Commit captures when they are useful to compare over
time; do not expect a later run to reproduce the same ranking from the same
hardware alone.
