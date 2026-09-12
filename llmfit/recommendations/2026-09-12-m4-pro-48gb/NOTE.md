# Legacy recommendation run

This was the first llmfit capture.

Do not use the reported throughput estimates as an uncontaminated baseline.

The generated JSON contains a local calibration factor of approximately
2.504x, meaning an earlier local llmfit benchmark had already influenced
later speed estimates.

The revised experiment uses an isolated empty `LLMFIT_BENCH_STORE` for
clean recommendations and a separate repository-local benchmark store for
measured/personalized results.

Also note that `llmfit search` is catalog lookup, not fit analysis, and
`--use-case coding` does not include Qwen3.8-27B because llmfit currently
classifies that model as Multimodal rather than Coding.
