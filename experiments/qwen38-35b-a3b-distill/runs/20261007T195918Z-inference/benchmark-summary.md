# Inference engineering benchmark run

Model: `Qwen3.8-35B-A3B-Distill-mlx-4Bit`

Synthetic performance measurements run with model thinking disabled so prefill/decode measurements are comparable. The separate Copilot experiment uses the normal thinking-enabled profile.

- [Context scaling](context-scaling.md): PP, TG, TTFT, TPOT, E2E and process memory across context lengths.
- [Prefix cache](prefix-cache.md): cold vs warm prefix reuse and cached-token accounting.
- [Concurrency](concurrency.md): aggregate throughput, tail TTFT and SLO-based goodput.

Raw JSON files next to these reports retain the per-request metrics for later experiment documentation.
