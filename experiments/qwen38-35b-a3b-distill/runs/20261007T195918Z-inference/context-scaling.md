# Context scaling benchmark

Synthetic code workload, thinking disabled, unique leading nonce per run to avoid intentional prefix reuse.

| Target | Actual prompt | PP tok/s | TG tok/s | TTFT | visible TTFT | TPOT | E2E | peak process RSS |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1,024 | 1,028 | 894.6 | 90.6 | 1.15 s | 1.15 s | 11.1 ms | 3.98 s | 2.25 GB |
| 4,096 | 4,090 | 950.8 | 87.3 | 4.30 s | 4.30 s | 11.5 ms | 7.24 s | 2.37 GB |
| 8,192 | 8,199 | 932.2 | 83.1 | 8.79 s | 8.80 s | 12.1 ms | 11.89 s | 2.42 GB |
| 16,384 | 16,379 | 828.5 | 76.0 | 19.77 s | 19.77 s | 13.2 ms | 23.16 s | 2.45 GB |
| 32,768 | 32,411 | 676.2 | 66.0 | 47.94 s | 47.94 s | 15.2 ms | 51.86 s | 2.46 GB |

PP = prompt processing/prefill throughput. TG = token generation/decode throughput. TTFT = model time to first token. TPOT = approximate time per output token after the first.

Peak process RSS is a best-effort host-process measurement from `ps`; it is not the same as oMLX's MLX-active-memory metric.
