# Invalid benchmark result

This llmfit benchmark result is retained for investigation and must not be
submitted as a community benchmark.

Environment:

- llmfit 1.1.15
- oMLX 0.6.4
- Apple M4 Pro
- 48 GB unified memory
- Qwen3.8-27B-4bit

Observed llmfit result:

- run 1: 70.91 tok/s
- run 2: 141.81 tok/s
- run 3: 121.83 tok/s
- average: 111.52 tok/s
- each run lasted approximately 2.003 seconds
- TTFT was null for every run

These values are inconsistent with known real-world performance of this model
on this hardware and are considered a benchmark/protocol artifact until the
cause is understood.

Do not contribute this result upstream as performance data.

## Root cause

The discrepancy was reproduced independently against the same oMLX endpoint.

A direct non-streaming OpenAI-compatible request generated 256 completion
tokens in approximately 17.5 seconds across three measured runs:

| Run | Wall time | Throughput |
| --- | ---: | ---: |
| 1 | 17.491 s | 14.64 tok/s |
| 2 | 17.505 s | 14.62 tok/s |
| 3 | 17.472 s | 14.65 tok/s |

The oMLX `usage.total_time` values closely matched the independently measured
wall-clock times.

Inspection of llmfit 1.1.15 shows that its OpenAI-compatible benchmark stops
the wall-clock timer immediately after `send_json()` returns, before
`read_json()` consumes the generated response body.

The resulting completion token count is therefore divided by a duration that
does not include the full generation time.

Until this is fixed upstream, llmfit 1.1.15 OpenAI-compatible MLX/oMLX
benchmark results from this setup are considered invalid and must not be
submitted as community performance measurements.
