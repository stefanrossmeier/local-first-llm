# Benchmarking

There are two different things worth benchmarking:

1. **the model/server itself** (oMLX direct API), and
2. **the full VS Code Copilot Chat request**, which can be much larger because it includes system instructions, workspace context, conversation history, and tool schemas.

Do not confuse the two. In our tests, the Copilot prompt construction was initially a much larger bottleneck than raw model decoding.

## 1. Direct oMLX API benchmark

Start the stack:

```bash
./scripts/start.sh
```

Then run two identical requests:

```bash
./scripts/benchmark-api.sh 2
```

The script prints:

- prompt tokens
- completion tokens
- total time
- output tokens/second
- finish reason

Running the same prompt twice also gives oMLX a chance to reuse its prefix/KV cache.

You can change the defaults with environment variables or `.env`:

```bash
BENCH_REASONING_EFFORT=medium BENCH_MAX_TOKENS=2048 ./scripts/benchmark-api.sh 2
```

## 2. Copilot prompt-size benchmark

Keep the proxy enabled and point VS Code at port `8001`.

Start a fresh Copilot chat, attach a small source file, and ask a short question such as:

```text
Explain this file shortly.
```

Then inspect the latest request summary:

```bash
./scripts/latest-proxy-summary.sh
```

Important fields:

```json
{
  "message_count": 3,
  "tool_count": 10,
  "tools_chars": 13636,
  "reasoning_effort": "low"
}
```

The server-side token count is visible in:

```bash
tail -f ~/llm/logs/omlx.log
```

Look for a line similar to:

```text
Chat completion: model=Qwen3.8-27B-4bit, 238 tokens in 91.24s (14.2 tok/s), prompt: 8952, finish_reason=stop
```

## Why tool count matters

Measured on an M4 Pro with 48 GB unified memory, the same Copilot workflow changed substantially as tools were pruned:

| Copilot tool setup | Tool schema characters | Prompt tokens | Observation |
|---|---:|---:|---|
| 89 tools | ~124,469 | ~30,000 | Far too much prefill for a trivial request |
| 42 tools | ~59,055 | ~20,394 | Better, still too large |
| 10 tools | ~13,636 | ~8,952 | Practical baseline |

These are workload-specific measurements, not universal benchmarks. Tool schemas differ between VS Code versions and installed extensions.

## Prefix-cache measurements

With 10 tools and roughly a 9K-token Copilot prompt:

| Scenario | Prompt tokens | End-to-end server time |
|---|---:|---:|
| Cold request | ~8,952 | ~91 s |
| Same chat, next turn | ~9,378 | ~22 s |
| Warm server, new chat, first model call | ~8,729 | ~28 s |

The new-chat test then made a second tool-result call (~8,997 prompt tokens, ~26 s), so attaching the file directly can avoid an unnecessary read-file round trip.

The important result is that oMLX prefix/KV caching can make warm repeated use much faster than a cold benchmark suggests.

## llama.cpp comparison from the same machine

Earlier GGUF tests on the same M4 Pro/48 GB system gave approximately:

| Model | Prefill 8K | Prefill 16K | Decode |
|---|---:|---:|---:|
| Qwen3.8-27B Q4_K_M | 119.6 tok/s | 115.5 tok/s | ~11.5–12.1 tok/s |
| Qwen3.8-27B UD-Q4_K_M | 118.0 tok/s | 114.4 tok/s | ~11.6–12.0 tok/s |
| Qwen3.8-27B MLX 4-bit via oMLX | workload-dependent | workload-dependent | ~14–15 tok/s in direct tests |

The MLX/oMLX path was therefore chosen for the Copilot integration in this repository.

## Benchmarking advice

- Test **cold** and **warm** requests separately.
- Keep the tool set constant when comparing quantizations.
- Use the same attached file and prompt.
- Track prompt tokens as carefully as decode tokens/second.
- For coding use, evaluate answer correctness as well as speed.
