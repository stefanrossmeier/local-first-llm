# llmfit experiments

This directory records model-fit predictions and measured inference performance for the hardware used by this repository.

Validated machine:

* Apple M4 Pro
* 48 GB unified memory
* macOS
* MLX inference through oMLX

## Why there are separate clean and personalized results

`llmfit bench` stores successful benchmark runs locally.

Those measurements can influence later model-fit estimates through local measurement overrides and calibration.

For reproducibility, this repository therefore maintains two views.

### Baseline recommendations

`recommendations/*/baseline/`

These are generated with a temporary empty `LLMFIT_BENCH_STORE`.

This prevents measurements produced by this repository from being loaded from its local benchmark store. llmfit may still use benchmark data embedded in the installed release, including matching community measurements and calibration.

### Personalized recommendations

`recommendations/*/personalized/`

These use the experiment-local benchmark store:

```text
llmfit/.bench-store
```

After models have been benchmarked, these show how the measurements change llmfit's recommendations.

The store itself is intentionally gitignored. Exported JSON results are committed instead.

## Target-model analysis

`recommendations/*/targets/`

The experiment explicitly captures `info` and `plan` results for:

* `Qwen/Qwen3.8-27B`
* `Qwen/Qwen3-Coder-30B-A3B-Instruct`

This is important because `--use-case coding` is a filtered recommendation view. llmfit currently classifies Qwen3.8-27B as Multimodal rather than Coding, so it does not appear in that filtered list even though coding is one of the workloads being evaluated in this repository.

The target directory therefore provides a direct fit comparison independent of that catalog-category filter.

## MLX quantization caveat

The llmfit 1.1.15 native MLX quantization hierarchy models:

* `mlx-8bit`
* `mlx-4bit`

It does not currently treat MLX 3-bit as a first-class dynamic quantization choice.

For that reason, this repository does not treat llmfit's `best_quant` field as authoritative evidence about 3-bit MLX models.

Actual model artifacts and measured inference results take precedence.

## Capture recommendations

Stop inference servers first if you want a clean machine-state capture.

```bash
./llmfit/scripts/capture-recommendations.sh
```

This captures 32K and 64K results, broad recommendations, coding-filtered recommendations, direct Qwen3.8/Qwen3-Coder analysis, and explicit MLX 4-bit/8-bit plans.

The script fails if any file in the `clean` baseline unexpectedly contains a non-null local calibration factor.

## Benchmark a running model

Start oMLX, determine the exact model ID from `/v1/models`, then run:

```bash
./llmfit/scripts/benchmark-model.sh MODEL_ID
```

Raw benchmark output is committed under:

```text
llmfit/benchmarks/
```

## Re-run recommendations after benchmarking

```bash
./llmfit/scripts/capture-recommendations.sh
```

The new run will contain both:

* a `baseline/` result without repository-local benchmark history;
* a `personalized/` result using the measurements from this repository.

This makes the effect of local calibration directly inspectable.

## Contribute measurements upstream

Preview the pending contribution:

```bash
./llmfit/scripts/share-benchmarks.sh --dry-run
```

Submit it:

```bash
./llmfit/scripts/share-benchmarks.sh
```

After llmfit creates the GitHub pull request, record it:

```bash
./llmfit/scripts/record-contribution.sh \
  MODEL_ID \
  https://github.com/AlexsJones/llmfit/pull/PR_NUMBER
```

Commit the resulting `UPSTREAM.md`.

## Reusing this for another model

The workflow is the same:

1. capture clean recommendations;
2. install and serve the chosen model;
3. benchmark it;
4. capture recommendations again;
5. compare `baseline/` with `personalized/`;
6. contribute the measurement upstream;
7. record the pull request under the benchmark run.

