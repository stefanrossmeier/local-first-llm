# Qwen3.8-35B-A3B-Distill experiment evidence

This directory contains the raw evidence behind [`docs/qwen38-35b-a3b-distill-experiment.md`](../../docs/qwen38-35b-a3b-distill-experiment.md).

Published baseline runs:

- `runs/20261007T195918Z-inference/` -- successful bare inference-engineering suite: context scaling, prefix cache, concurrency/goodput, runtime status, and machine metadata.
- `runs/20261007T201306Z-copilot-qwen38-distill-coding/` -- privacy-preserving VS Code Copilot request/response metrics.

The first attempted inference run failed before the benchmark started because the harness called a nonexistent `/tokenize` endpoint. That failed run is intentionally not retained as experiment evidence; the harness was fixed to use oMLX token counting and to return a failure status instead of printing a misleading success banner.

## Baseline status

The published run is intentionally the **bare model profile**. Optional acceleration paths such as MTP, ANE prefill, TurboQuant KV, oQ A8, SpecPrefill, DFlash, and MoE expert offload were disabled. This keeps the run useful as the reference point for later A/B optimization experiments.

Do not edit the JSON result files to make later charts look cleaner. Add a new timestamped run when the model, runtime, or settings change.
