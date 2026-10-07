# Copilot Chat experiment notes

## Scope

This run validates the local VS Code Copilot endpoint, streaming, large tool-schema handling, and warm-prefix behavior for `Qwen3.8-35B-A3B-Distill-mlx-4Bit`.

The inspection proxy was configured in privacy-preserving summary mode. Full message bodies and source content were intentionally not retained, so this capture must not be treated as a controlled task-quality benchmark.

## Observations

- Two successful requests were captured with 55 enabled tools.
- The first request was cold; the second reused 20,480 prompt tokens.
- Tool calling worked in the interactive VS Code smoke/use test.
- Subjectively, the model was responsive enough for real coding work.
- A later controlled quality comparison should use a recorded public/reproducible task and run the same task against the dense Qwen3.8-27B baseline.
