#!/usr/bin/env python3

import argparse
import json
import statistics
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_URL = "http://127.0.0.1:8000"
DEFAULT_MAX_TOKENS = 256
DEFAULT_RUNS = 3

PROMPT = (
    "Write a very detailed technical essay explaining how virtual memory "
    "works in a modern operating system. Continue with substantial detail "
    "and do not finish early."
)


def get_models(base_url):
    with urllib.request.urlopen(
        f"{base_url.rstrip('/')}/v1/models",
        timeout=30,
    ) as response:
        return json.load(response)


def benchmark_once(base_url, model, max_tokens):
    url = f"{base_url.rstrip('/')}/v1/chat/completions"

    payload = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": PROMPT,
            }
        ],
        "temperature": 0.0,
        "max_tokens": max_tokens,
        "stream": False,
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    start = time.perf_counter()

    with urllib.request.urlopen(req, timeout=600) as response:
        result = json.load(response)

    wall_seconds = time.perf_counter() - start

    usage = result.get("usage", {})
    completion_tokens = int(usage.get("completion_tokens", 0) or 0)
    prompt_tokens = int(usage.get("prompt_tokens", 0) or 0)

    wall_tps = (
        completion_tokens / wall_seconds
        if completion_tokens > 0 and wall_seconds > 0
        else None
    )

    return {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "wall_seconds": wall_seconds,
        "wall_tps": wall_tps,
        "provider_total_time": usage.get("total_time"),
        "provider_generation_duration": usage.get("generation_duration"),
        "provider_generation_tps": usage.get(
            "generation_tokens_per_second"
        ),
        "provider_ttft": usage.get("time_to_first_token"),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--model")
    parser.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=DEFAULT_MAX_TOKENS,
    )
    parser.add_argument("--output")
    args = parser.parse_args()

    models_response = get_models(args.url)
    models = models_response.get("data", [])

    if not models:
        raise SystemExit("No models returned by oMLX.")

    model = args.model or models[0]["id"]

    print(f"Model:      {model}")
    print(f"Endpoint:   {args.url}")
    print(f"Max tokens: {args.max_tokens}")
    print()

    print("Warm-up...")
    warmup = benchmark_once(args.url, model, args.max_tokens)

    print(
        f"  {warmup['completion_tokens']} tokens, "
        f"{warmup['wall_seconds']:.3f}s, "
        f"{warmup['wall_tps']:.2f} tok/s"
    )

    measured = []

    print()
    print("Measured runs:")

    for index in range(1, args.runs + 1):
        run = benchmark_once(args.url, model, args.max_tokens)
        measured.append(run)

        print(
            f"  Run {index}: "
            f"{run['completion_tokens']} tokens, "
            f"{run['wall_seconds']:.3f}s, "
            f"{run['wall_tps']:.2f} tok/s"
        )

    tps_values = [
        run["wall_tps"]
        for run in measured
        if run["wall_tps"] is not None
    ]

    summary = {
        "num_runs": len(measured),
        "mean_wall_tps": statistics.mean(tps_values),
        "median_wall_tps": statistics.median(tps_values),
        "min_wall_tps": min(tps_values),
        "max_wall_tps": max(tps_values),
    }

    output = {
        "schema": "local-first-llm/omlx-benchmark-v1",
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "model": model,
        "provider": "omlx",
        "endpoint": args.url,
        "max_tokens": args.max_tokens,
        "stream": False,
        "prompt": PROMPT,
        "warmup": warmup,
        "runs": measured,
        "summary": summary,
        "provider_models": models_response,
    }

    print()
    print("Summary:")
    print(f"  mean:   {summary['mean_wall_tps']:.2f} tok/s")
    print(f"  median: {summary['median_wall_tps']:.2f} tok/s")
    print(f"  min:    {summary['min_wall_tps']:.2f} tok/s")
    print(f"  max:    {summary['max_wall_tps']:.2f} tok/s")

    if args.output:
        path = Path(args.output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(output, indent=2) + "\n")
        print()
        print(f"Saved: {path}")


if __name__ == "__main__":
    main()
