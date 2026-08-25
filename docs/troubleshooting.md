# Troubleshooting

## Homebrew refuses the oMLX tap

If installation prints something like:

```text
Refusing to load formula jundot/omlx/omlx from untrusted tap jundot/omlx
```

review the repository and explicitly trust the tap:

```bash
brew trust jundot/omlx
brew install omlx
```

## `/` returns `{ "detail": "Not Found" }`

The OpenAI-compatible API is under `/v1`. Depending on the oMLX build, the admin UI is under `/admin`, not `/`.

Useful checks:

```bash
curl http://127.0.0.1:8000/v1/models
curl http://127.0.0.1:8001/v1/models
```

## VS Code sends enormous prompts

Use the proxy summary:

```bash
./scripts/latest-proxy-summary.sh
```

A large number of tools can dominate the context. In our setup, 89 advertised tools produced about 124K characters of tool schemas and roughly a 30K-token model prompt.

Use the tool picker in Copilot Chat and keep only the tools you actually need. Around 8–12 tools was a useful starting point for this setup.

## A tiny question still makes two model calls

If the first response has `finish_reason=tool_calls`, the model requested a tool (often file read/search), and Copilot sends a second request with the tool result.

For small review/explanation tasks, explicitly attaching the file can avoid that extra round trip.

## Unexpected answer language or hallucinated files

The proxy can tell you what context Copilot actually sent. To capture full request bodies temporarily:

```bash
cp .env.example .env
# edit .env and set:
COPILOT_PROXY_LOG_RAW=1
COPILOT_PROXY_PREVIEW_CHARS=300
./scripts/stop.sh
./scripts/start.sh
```

**Warning:** raw requests may contain source code, workspace paths, instructions, and other private context. Never commit `logs/`.

Search locally:

```bash
grep -Rni -e 'German' -e 'Deutsch' logs/proxy/*-request.json
grep -Rni -e 'some-suspicious-file-name' logs/proxy/*-request.json
```

Set `COPILOT_PROXY_LOG_RAW=0` and `COPILOT_PROXY_PREVIEW_CHARS=0` again after debugging.

## Copilot compacts immediately or errors at small context windows

VS Code uses `maxInputTokens + maxOutputTokens` as the custom model context window. A very small advertised context can make Copilot compact aggressively or fail while trying to fit its own system/tool context.

This repo uses:

```text
28,672 input + 4,096 output = 32,768 total
```

as a practical baseline for this integration.

## Model is not shown in Agent/Copilot mode

VS Code requires tool calling for models used by agents. Ensure the custom endpoint config has:

```json
"toolCalling": true
```

Then reload VS Code.
