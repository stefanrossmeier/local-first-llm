# Inference engineering for local coding agents

A local LLM can "fit" in memory and still be unpleasant to use. For interactive coding, the useful question is not only how many output tokens per second the model can generate. The complete request path has distinct phases with different bottlenecks.

This repository therefore measures the local serving system as an inference-engineering problem rather than treating `tok/s` as a single score.

## The request path

A simplified local coding-agent request looks like this:

```text
VS Code / Copilot Chat
        |
        | system prompt + tools + workspace/context + conversation
        v
     PREFILL
  build KV state
        |
        | first token
        v
      DECODE
  token-by-token output
        |
        v
    final response
```

**Prefill** ingests the input prompt and constructs attention/KV state. It can process many prompt tokens in parallel and is strongly affected by prompt length and implementation efficiency.

**Decode** generates output autoregressively. It is sequential and often much more sensitive to memory bandwidth and the amount of model state that has to be touched for each generated token.

For a coding agent, the input side can be unexpectedly large because VS Code may send system instructions, repository context, conversation history, and JSON schemas for dozens of tools before the model can generate one token.

## Metrics used in this repository

| Metric | Meaning | Why it matters |
|---|---|---|
| **PP tok/s** | Prompt-processing / prefill throughput | Determines how quickly a cold prompt is ingested. |
| **TG tok/s** | Token-generation / decode throughput | Determines how fast the answer streams after generation begins. |
| **TTFT** | Time to first token | The most noticeable latency for an interactive user. |
| **visible TTFT** | Time to first user-visible token | Separates hidden reasoning/tool protocol from visible response latency where the runtime exposes it. |
| **TPOT** | Approximate time per output token after the first | Another view of decode latency. |
| **E2E** | End-to-end request time | Captures the total wait, not only model decode. |
| **cached tokens** | Prompt tokens reused from a previous prefix | Shows whether prefix/KV caching is doing useful work. |
| **p50 / p95 TTFT** | Median and tail first-token latency under concurrency | Reveals whether a server still feels responsive when multiple requests are active. |
| **goodput** | Requests that meet a chosen latency/throughput SLO | Prevents high aggregate throughput from hiding bad per-user latency. |

The benchmark harness records raw JSON in addition to Markdown summaries so later documentation can be regenerated from the measurements instead of copying numbers by hand.

## Why prefix caching matters so much for Copilot

Coding-agent prompts contain large repeated prefixes: system instructions, tool schemas, repository instructions, and often the same workspace context. If a runtime can reuse the KV state for that shared prefix, a warm request can avoid most of the cold prefill work.

The Qwen3.8-35B-A3B-Distill baseline demonstrated this directly at an ~8K synthetic prompt:

| Run | Prompt | Cached | TTFT | E2E |
|---|---:|---:|---:|---:|
| Cold | 8,189 | 0 | 8.80 s | 10.39 s |
| Warm | 8,188 | 6,144 | 2.47 s | 4.05 s |

That is a **3.56x TTFT reduction** from reuse alone.

The Copilot capture is even more representative of a real developer workflow. With 55 enabled tools, the request carried about 71K characters of tool schemas and a ~23K-token prompt. The second captured request reused 20,480 tokens and reduced TTFT from 31.51 s to 4.99 s.

## Context scaling

Long context affects both phases. In the baseline run, decode remained fast even at ~32K context, but cold prefill became the dominant wait:

| Context | PP | TG | TTFT |
|---:|---:|---:|---:|
| ~1K | 894.6 tok/s | 90.6 tok/s | 1.15 s |
| ~8K | 932.2 tok/s | 83.1 tok/s | 8.79 s |
| ~16K | 828.5 tok/s | 76.0 tok/s | 19.77 s |
| ~32K | 676.2 tok/s | 66.0 tok/s | 47.94 s |

The important diagnosis is not "the model becomes slow." Decode at ~32K is still 66 tok/s. The dominant problem is **cold prompt ingestion**.

## Throughput is not goodput

A server can increase aggregate work while making every user wait longer. The concurrency experiment uses an interactive SLO of:

```text
TTFT <= 15 s
per-user TG >= 30 tok/s
```

At one request, the model met the SLO. As concurrency increased, queueing and tail latency rose sharply even though aggregate output throughput stayed around the same range. This is why the repository records p95 TTFT and goodput rather than reporting only total tok/s.

For this project the primary use case is one local developer, so single-user latency and prefix reuse matter more than multi-user serving capacity. The concurrency measurements are still valuable because they show where the serving stack saturates.

## The current result is a bare-model baseline

"Bare" here means **the model is served without the optional experimental acceleration paths enabled**. It does not mean caching or ordinary oMLX serving is disabled.

The published baseline profile sets all of these to `false`:

```text
mtp_enabled
qwen35_ane_prefill_enabled
turboquant_kv_enabled
qwen35_oq_a8_enabled
specprefill_enabled
dflash_enabled
moe_expert_offload_enabled
```

The run used the normal oMLX scheduler and prefix/KV cache. Synthetic performance requests disabled model thinking to make PP/TG comparisons stable; the VS Code profile kept thinking enabled for real use.

The recorded oMLX 0.7.0 status also showed the optional `qwen35_prefill` and `decode_fast` custom kernels as unavailable on this installation. That makes the baseline useful: later acceleration runs have a clean reference point rather than mixing several optimizations into the first measurement.

## Future performance ladder

The next phase should change **one feature at a time**, rerun the same context/cache/Copilot workloads, and keep a result only when it improves the relevant metric without breaking tool use or answer quality.

| Candidate | Primary target | What to verify |
|---|---|---|
| **Lightning MTP** (`mtp_enabled`) | Decode / TG | Whether this exact MLX conversion exposes a compatible MTP head, acceptance rate is useful, tool calling remains correct, and TG improves at 4K-32K context. |
| **Qwen ANE Prefill** (`qwen35_ane_prefill_enabled`) | Cold prefill / PP / TTFT | Whether the runtime actually engages the ANE path on this M4 Pro and whether prompt throughput improves without hurting decode. |
| **Qwen custom prefill/decode kernels** | PP and/or TG | Build/install the optional oMLX kernels, confirm they load, then rerun the baseline unchanged. |
| **TurboQuant KV** (`turboquant_kv_enabled`) | KV memory / long context / concurrency | Measure memory and long-context behavior; do not assume it increases speed. |
| **Qwen oQ A8** (`qwen35_oq_a8_enabled`) | Quantized execution path | Verify model compatibility and compare both quality and long-context decode before adopting it. |
| **SpecPrefill** (`specprefill_enabled`) | Long cold prompts | Requires a compatible draft setup; compare 16K/32K TTFT and extra memory/complexity. |
| **DFlash** (`dflash_enabled`) | Speculative acceleration | Measure independently; keep only if real workloads improve. |
| **MoE expert offload** (`moe_expert_offload_enabled`) | Memory headroom | Treat mainly as a capacity trade-off; it may reduce resident memory at the cost of latency. |

MTP and ANE prefill are the most interesting first experiments because the current baseline already has excellent decode and clearly exposes cold prefill as the remaining latency problem. MTP targets generation; ANE/custom prefill paths target the initial wait. Their effects should be measured separately before combining them.

Do not assume that a feature that improves another Qwen build or another Apple chip will improve this model on this machine. oMLX acceleration paths are model-, conversion-, runtime-, and hardware-dependent.

## Recommended experiment order

```text
bare baseline (published)
        |
        +--> MTP only --------------------> decode A/B
        |
        +--> ANE/custom prefill only -----> prefill/TTFT A/B
        |
        +--> KV optimization only --------> memory/context A/B
        |
        +--> best proven combination -----> full synthetic suite
                                             |
                                             v
                                      VS Code Copilot validation
```

Every optimized run should retain the same raw evidence as the baseline: model revision, oMLX version, model settings, context results, prefix-cache results, concurrency results, and a real Copilot capture.

## Source experiment

The baseline discussed here is documented in [`qwen38-35b-a3b-distill-experiment.md`](qwen38-35b-a3b-distill-experiment.md) and backed by the raw files under [`../experiments/qwen38-35b-a3b-distill/`](../experiments/qwen38-35b-a3b-distill/).
