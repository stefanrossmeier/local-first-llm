# local-first-llm

Run a strong local coding LLM on Apple Silicon and use it from VS Code GitHub Copilot Chat through an OpenAI-compatible endpoint.

This repository documents two local Apple-Silicon paths:

- **Qwen3.8-27B 4-bit MLX** (`mlx-community/Qwen3.8-27B-4bit`) as the original dense quality baseline
- **Qwen3.8-35B-A3B-Distill 4-bit MLX** (`nvythong/Qwen3.8-35B-A3B-Distill-mlx-4Bit`) as the current fast sparse-MoE experiment
- **oMLX** for Apple-Silicon inference, continuous batching, and persistent prefix/KV caching
- **VS Code Custom Endpoint / Copilot Chat** for the coding UI
- an optional **inspection proxy** that shows how much context and how many tool schemas Copilot actually sends

The main performance lesson from this setup is simple:

> Local coding-agent performance is not one number. Prompt prefill, token generation, prefix-cache reuse, context length, and concurrency all matter. For Copilot Chat specifically, repeated system/tool prefixes can dominate the experience, so prompt size and cache reuse matter as much as raw decode speed.

## Fast MoE experiment: Qwen3.8-35B-A3B-Distill

The repository now contains a reproducible inference-engineering experiment for the community **Qwen3.8-35B-A3B-Distill** model. It distills Qwen3.8 teacher behavior into the Qwen3.6-35B-A3B sparse MoE architecture: roughly 35B total parameters with about 3B active per token. This is **not an official Alibaba/Qwen Qwen3.8 release**; the distillation is published by Empero and this repository uses a pinned community MLX 4-bit conversion.

On the validated M4 Pro / 48 GB machine with oMLX 0.7.0, the baseline run measured:

| Context | Prefill (PP) | Decode (TG) | TTFT |
|---:|---:|---:|---:|
| ~1K | 894.6 tok/s | 90.6 tok/s | 1.15 s |
| ~4K | 950.8 tok/s | 87.3 tok/s | 4.30 s |
| ~8K | 932.2 tok/s | 83.1 tok/s | 8.79 s |
| ~16K | 828.5 tok/s | 76.0 tok/s | 19.77 s |
| ~32K | 676.2 tok/s | 66.0 tok/s | 47.94 s |

Prefix reuse changed an ~8K request from **8.80 s TTFT cold** to **2.47 s TTFT warm** with 6,144 cached tokens. In a real VS Code Copilot capture with 55 enabled tools and a ~23K-token prompt, the first request took 31.51 s to first token; a highly similar second request reused 20,480 prompt tokens and reached first token in 4.99 s. The model was subjectively interactive enough for real coding work.

These numbers are deliberately a **bare-model baseline** for the current MLX artifact: MTP, Qwen ANE prefill, TurboQuant KV, Qwen oQ A8, SpecPrefill, DFlash, and MoE expert offload were all disabled. Prefix/KV caching and normal oMLX serving remain enabled. The run also reported the optional Qwen prefill/decode custom kernels as unavailable, so these results leave meaningful optimization headroom.

Read the experiment before interpreting the numbers:

- [`docs/qwen38-35b-a3b-distill-experiment.md`](docs/qwen38-35b-a3b-distill-experiment.md) — exact setup, results, Copilot capture, limitations, and conclusions
- [`docs/inference-engineering.md`](docs/inference-engineering.md) — PP/TG/TTFT/TPOT, cache behavior, goodput, and the planned MTP/prefill optimization ladder
- [`experiments/qwen38-35b-a3b-distill/`](experiments/qwen38-35b-a3b-distill/) — raw machine-readable evidence retained for reproducibility

Quick start for this profile:

```bash
./scripts/setup-qwen38-distill.sh
./scripts/start.sh
./scripts/run-inference-benchmarks.sh
```

For VS Code, merge `config/chatLanguageModels.provider.qwen38-35b-a3b-distill.json` into the Language Models custom-endpoint configuration and select **Qwen3.8 35B-A3B Distill MLX**.

## Repository layout

```text
.
├── .env.example
├── config/
│   ├── chatLanguageModels.provider.json
│   └── model_settings.json.example
├── copilot-proxy/
│   ├── proxy.py
│   └── requirements.txt
├── docs/
│   ├── benchmarking.md
│   └── troubleshooting.md
├── llmfit/
│   ├── README.md
│   ├── benchmarks/
│   ├── recommendations/
│   └── scripts/
├── whichllm/
│   ├── README.md
│   ├── recommendations/
│   └── scripts/
└── scripts/
    ├── benchmark-api.sh
    ├── common.sh
    ├── configure-omlx-model.sh
    ├── download-model.sh
    ├── latest-proxy-summary.sh
    ├── setup-all.sh
    ├── setup-omlx.sh
    ├── setup-proxy.sh
    ├── start.sh
    ├── status.sh
    └── stop.sh
```

## Requirements

- Apple Silicon Mac
- macOS 15 or newer for current oMLX releases
- Homebrew
- Python 3
- about **16 GB** for the dense Qwen3.8-27B profile or **20 GB** for the Qwen3.8-35B-A3B-Distill 4-bit profile, plus cache/log headroom
- VS Code with the current GitHub Copilot Chat / language-model features

This repository was developed and measured with **oMLX 0.6.3rc2**. oMLX evolves quickly, so newer versions can change CLI flags, model support, and performance.

## Supported hardware profile

| Unified memory | Support level | Practical guidance |
|---|---|---|
| Less than 48 GB | Not supported by this documented profile | It may work with a smaller context or model, but it was not validated here. |
| 48 GB | Validated baseline | M4 Pro / 48 GB was tested with the advertised 32,768-token context window and the benchmarks in `docs/benchmarking.md`. Close memory-heavy applications. |
| 64 GB or more | Recommended | Provides more room for macOS, VS Code, Metal buffers, KV cache, and other applications. |

The 4-bit weights are much smaller than the working memory required by the full server. If oMLX reports a Metal allocation or out-of-memory error, stop the stack, close memory-heavy applications, and retry with a smaller advertised context before treating the machine as supported.

## 1. Clone and configure

```bash
git clone https://github.com/stefanrossmeier/local-first-llm.git
cd local-first-llm
cp .env.example .env
```

Set `HF_MODEL_REVISION` in `.env` to the 40-character commit SHA of the tested Hugging Face model snapshot. Do not use a branch name, tag, or `main`: the revision is part of the reproducible model profile. The defaults match this layout:

```text
~/llm/Models/MLX/Qwen3.8-27B-4bit
```

Edit `.env` if you prefer another model directory or ports.

## 2. Install oMLX

Run:

```bash
./scripts/setup-omlx.sh
```

The script uses the official Homebrew tap:

```bash
brew tap jundot/omlx https://github.com/jundot/omlx
brew install omlx
```

If Homebrew refuses to load the tap because it is untrusted, review it first and then explicitly trust it:

```bash
brew trust jundot/omlx
./scripts/setup-omlx.sh
```

Upstream: https://github.com/jundot/omlx

## 3. Download the exact MLX model

Run:

```bash
./scripts/download-model.sh
```

That performs the equivalent of:

```bash
hf download \
  mlx-community/Qwen3.8-27B-4bit \
  --revision YOUR_40_CHARACTER_COMMIT_SHA \
  --local-dir ~/llm/Models/MLX/Qwen3.8-27B-4bit
```

If `hf` is not already installed, the script creates a small local Python environment and installs `huggingface_hub` for you.

Model page: https://huggingface.co/mlx-community/Qwen3.8-27B-4bit

## 4. Set up the inspection proxy

The proxy is optional for inference but extremely useful for Copilot tuning. It forwards requests unchanged to oMLX and records request summaries such as:

```json
{
  "message_count": 3,
  "tool_count": 10,
  "tools_chars": 13636,
  "reasoning_effort": "low"
}
```

Install it:

```bash
./scripts/setup-proxy.sh
```

By default the proxy stores **summaries only**, with message previews disabled. It does not save full source-containing requests unless you explicitly enable `COPILOT_PROXY_LOG_RAW=1` in `.env`. To include short message previews temporarily, set `COPILOT_PROXY_PREVIEW_CHARS=300`.

## 5. Configure oMLX model behavior

Run:

```bash
./scripts/configure-omlx-model.sh
```

This merges these safe defaults into `~/.omlx/model_settings.json`:

- thinking enabled
- historical thinking traces not preserved
- no hard thinking token budget

Reasoning effort is instead selected from VS Code as **Low / Medium / High**.

## 6. Start the local stack

```bash
./scripts/start.sh
```

This starts:

```text
oMLX                 http://127.0.0.1:8000
Copilot proxy        http://127.0.0.1:8001
Copilot endpoint     http://127.0.0.1:8001/v1/chat/completions
```

Check status:

```bash
./scripts/status.sh
```

Watch inference logs:

```bash
tail -f ~/llm/logs/omlx.log
```

Watch Copilot request summaries:

```bash
tail -f ~/llm/logs/copilot-proxy.log
```

Stop everything:

```bash
./scripts/stop.sh
```

The startup script intentionally **does not clear the oMLX cache**. Persistent prefix/KV caching was one of the largest improvements for repeated coding-chat requests.

## 7. Copilot prerequisites

Before adding the endpoint, verify that:

- you are signed in to VS Code with the GitHub account that has access to Copilot Chat;
- GitHub Copilot Chat is installed and enabled, or is included in your VS Code build;
- your VS Code build exposes **Chat: Manage Language Models** and **Add Models** -> **Custom Endpoint**;
- local HTTP endpoints are permitted by your VS Code/Copilot policy.

Custom Endpoint availability, Copilot entitlement, and the configuration schema can vary by VS Code release and organization policy. Update VS Code and confirm those prerequisites before debugging the local server.

## 8. Add the model to VS Code Copilot Chat

Current VS Code versions expose custom language models through the **Language Models editor**.

1. Open the Chat model picker.
2. Select **Manage Language Models** (gear icon), or run:

   ```text
   Chat: Manage Language Models
   ```

3. Choose **Add Models** → **Custom Endpoint**.
4. Give the provider a name such as `Local MLX`.
5. Choose **Chat Completions** as the API type.
6. VS Code opens `chatLanguageModels.json` for advanced model configuration.
7. Merge the provider object from:

   ```text
   config/chatLanguageModels.provider.json
   ```

   into the top-level JSON array.

The provider looks like this:

```json
{
  "name": "Local MLX",
  "vendor": "customendpoint",
  "apiType": "chat-completions",
  "models": [
    {
      "id": "Qwen3.8-27B-4bit",
      "name": "Qwen3.8 27B MLX",
      "url": "http://127.0.0.1:8001/v1/chat/completions",
      "toolCalling": true,
      "vision": false,
      "thinking": true,
      "supportsReasoningEffort": ["low", "medium", "high"],
      "reasoningEffortFormat": "chat-completions",
      "maxInputTokens": 28672,
      "maxOutputTokens": 4096,
      "modelOptions": {
        "temperature": 0.2
      }
    }
  ]
}
```

VS Code treats `maxInputTokens + maxOutputTokens` as the model's advertised context window. The values above advertise a **32,768-token** context.

Official VS Code documentation: https://code.visualstudio.com/docs/agent-customization/language-models

After saving the configuration, reload VS Code if the model does not appear immediately:

```text
Developer: Reload Window
```

Then select **Qwen3.8 27B MLX** in the Copilot Chat model picker.

## 9. Verify the first Copilot chat

After reloading VS Code and selecting **Qwen3.8 27B MLX**, start a new Agent chat and send:

```text
Use a workspace tool to read the first line of README.md. Reply with that line and state that the local endpoint is working.
```

The chat should complete and the proxy should record at least the initial request. Confirm that the summary names `Qwen3.8-27B-4bit`, includes the expected `reasoning_effort`, and advertises the enabled tools:

```bash
./scripts/latest-proxy-summary.sh
tail -f ~/llm/logs/omlx.log
```

For a successful tool round trip, the oMLX log should show a tool-call completion followed by Copilot's tool-result request. If the model is unavailable, return to the prerequisite list and then check `docs/troubleshooting.md`.

## 10. Set reasoning effort

The model configuration declares:

```json
"supportsReasoningEffort": ["low", "medium", "high"]
```

Open the model picker and choose the model's **Thinking Effort** submenu.

Recommended starting points:

- **Low** — explanations, small edits, normal interactive work
- **Medium** — code review, debugging, multi-step coding tasks
- **High** — only when the extra latency is justified

For this model/runtime, Low was a good default for interactive Copilot usage.

## 11. Reduce Copilot tools — this matters a lot

This step made a larger practical difference than changing 4-bit quantization formats.

Copilot sends JSON schemas for every enabled tool to the model. With many installed tools/extensions, the tool definitions can consume most of the prompt.

Use the **tool picker in Copilot Chat** and disable tools that you do not need for local coding. A useful small set is roughly:

- file read/search
- text/code search
- edit/apply patch
- diagnostics/problems
- terminal/run command
- Git status/diff if you actively use it

Exact names vary by VS Code version and extensions.

In the measured setup:

```text
89 tools -> ~124K schema chars -> ~30K-token prompt
42 tools ->  ~59K schema chars -> ~20K-token prompt
10 tools ->  ~14K schema chars ->  ~9K-token prompt
```

Inspect your current request:

```bash
./scripts/latest-proxy-summary.sh
```

If a simple request is still near 30K tokens, reduce the tool set before trying a smaller model or buying faster hardware.

## 12. Attach small files explicitly when appropriate

A new Copilot chat may initially tell the model which file is active without sending the file contents. The model can then request the file through a tool, causing a second full model call.

For a small review/explanation task, explicitly attaching the file can avoid that extra round trip.

## 13. Benchmark the server

Direct API benchmark:

```bash
./scripts/benchmark-api.sh 2
```

The first run is useful as a cold/warm baseline; the second identical request can show prefix-cache effects.

For Copilot-specific benchmarking, keep the proxy enabled and inspect:

```bash
./scripts/latest-proxy-summary.sh
tail -f ~/llm/logs/omlx.log
```

See [`docs/benchmarking.md`](docs/benchmarking.md) for the measured numbers and methodology.

## Observed performance: dense Qwen3.8-27B baseline

The newer sparse-MoE result is documented in [`docs/qwen38-35b-a3b-distill-experiment.md`](docs/qwen38-35b-a3b-distill-experiment.md). The measurements below are the earlier dense Qwen3.8-27B baseline.

On the M4 Pro / 48 GB machine used while building this setup:

- direct Qwen3.8-27B MLX 4-bit generation was typically around **14–15 output tok/s**
- a cold ~9K-token Copilot request took roughly **91 s**
- the next turn with a warm shared prefix took roughly **22 s**
- a brand-new chat with a warm server reused enough prefix state that its first ~8.7K-token model call took roughly **28 s**

These are local measurements, not guarantees. macOS load, prompt composition, enabled tools, context length, cache state, oMLX version, and model conversion all affect the result.

## Why oMLX instead of the GGUF setup?

The earlier llama.cpp tests were functional, including Unsloth Dynamic GGUFs, but decode speed on the same machine stayed around 12 tok/s. The MLX/oMLX path reached roughly 14–15 tok/s and, more importantly, oMLX's persistent paged/prefix KV cache made repeated Copilot interactions much more practical.

oMLX explicitly supports persistent hot/SSD KV caching and prefix sharing, which is a strong fit for coding agents whose system/tool prefixes repeat across requests.

## Privacy and security

Everything here can run on localhost, but the inspection proxy deserves special attention:

- summary logs include message sizes and tool metadata; previews are disabled by default
- raw logs can include complete source files and instructions
- `logs/` is gitignored
- raw capture is **off by default**

Do not publish request logs from private repositories.

The oMLX server and proxy are intentionally bound to `127.0.0.1` by default. Do not expose them to a network unless you also configure authentication and understand the implications.

## One-command setup

After reviewing the scripts, you can run:

```bash
./scripts/setup-all.sh
./scripts/start.sh
```

The Homebrew trust step may require explicit manual approval on some Homebrew versions.

## Updating

Update oMLX:

```bash
brew update
brew upgrade omlx
```

Update/re-download the model files:

```bash
./scripts/download-model.sh
```

## References

- oMLX: https://github.com/jundot/omlx
- Qwen3.8-27B 4-bit MLX: https://huggingface.co/mlx-community/Qwen3.8-27B-4bit
- Qwen3.8-35B-A3B-Distill base/distill: https://huggingface.co/empero-ai/Qwen3.8-35B-A3B-Distill
- Qwen3.8-35B-A3B-Distill MLX conversion used here: https://huggingface.co/nvythong/Qwen3.8-35B-A3B-Distill-mlx-4Bit
- VS Code language model / Custom Endpoint docs: https://code.visualstudio.com/docs/agent-customization/language-models

## License

MIT. See [`LICENSE`](LICENSE).

## Model selection with llmfit

This repository also records model-fit recommendations and standardized
inference measurements using `llmfit`.

See [`llmfit/`](llmfit/) for:

- coding-model recommendations for the M4 Pro / 48 GB profile;
- 32K and 64K context comparisons;
- measured local benchmarks;
- reproducible benchmark scripts;
- upstream benchmark contributions to the llmfit community dataset.

## Model selection with whichllm

The repository also contains a lightweight `whichllm` experiment harness. It
uses current Hugging Face and benchmark data to rank models that appear to fit
the local machine and captures 32K/64K general, coding, strict-evidence, and
conservative recommendations.

See [`whichllm/`](whichllm/) for the scripts and interpretation notes. On Apple
Silicon, `whichllm` currently ranks GGUF-backed candidates, so use it as a
candidate-discovery and fit cross-check. Validate promising models with the
repository's actual MLX/oMLX benchmark workflow before adopting them.
