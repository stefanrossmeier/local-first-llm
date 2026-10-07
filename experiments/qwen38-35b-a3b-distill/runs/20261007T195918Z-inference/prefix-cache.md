# Prefix-cache benchmark

Two requests share the same large system-prefix and differ only in the final user question.

| Run | Prompt | Cached | Cached % | PP tok/s | TG tok/s | TTFT | visible TTFT | E2E |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| cold | 8,189 | 0 | 0.0% | 930.9 | 81.0 | 8.80 s | 8.80 s | 10.39 s |
| warm | 8,188 | 6,144 | 75.0% | 826.4 | 82.1 | 2.47 s | 2.47 s | 4.05 s |

Cold/warm TTFT speedup: **3.56×**
