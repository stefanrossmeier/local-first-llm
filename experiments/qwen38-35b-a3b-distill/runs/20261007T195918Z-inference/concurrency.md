# Concurrency and goodput benchmark

Good request SLO: TTFT ≤ 15 s and per-user TG ≥ 30 tok/s.

| Concurrent | Aggregate output | p50 TTFT | p95 TTFT | median user TG | peak queued | SLO pass | goodput | model mem | process RSS |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 22.5 tok/s | 4.20 s | 4.20 s | 87.6 tok/s | 0 | 1/1 | 0.176 req/s | 19.08 GB | 2.48 GB |
| 2 | 21.5 tok/s | 7.31 s | 10.13 s | 54.2 tok/s | 0 | 1/2 | 0.084 req/s | 19.08 GB | 2.50 GB |
| 4 | 23.7 tok/s | 18.88 s | 18.94 s | 49.1 tok/s | 2 | 0/4 | 0.000 req/s | 19.08 GB | 2.53 GB |
| 8 | 24.9 tok/s | 35.50 s | 35.78 s | 24.0 tok/s | 6 | 1/8 | 0.024 req/s | 19.08 GB | 2.78 GB |

Aggregate throughput can rise while goodput falls. Goodput counts only requests still meeting the interactive latency SLO.
Peak queued requests and model memory come from oMLX `/api/status` polling when that endpoint is available; raw status-derived deltas are retained in `concurrency.json`.
