# VS Code Copilot Chat experiment capture

This is measurement output, not the final experiment documentation.

| Request | Messages | Tools | Prompt tokens | Cached | PP tok/s | TG tok/s | TTFT | visible TTFT | wall |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 3 | 55 | 23,465 | 0 | 744.8 | 67.7 | 31.51 s | 31.51 s | 33.08 s |
| 2 | 3 | 55 | 23,365 | 20,480 | 577.9 | 67.9 | 4.99 s | 4.99 s | 6.16 s |

The request summaries intentionally omit message bodies by default. `tools_chars` and message character counts remain in the JSON for context-overhead analysis.
