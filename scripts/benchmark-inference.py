#!/usr/bin/env python3
"""Reproducible local inference-engineering benchmarks for oMLX.

The suite intentionally uses only the OpenAI-compatible API and Python stdlib.
It does not use oMLX's public benchmark uploader.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    return int(value) if value else default


def env_float(name: str, default: float) -> float:
    value = os.environ.get(name)
    return float(value) if value else default


def env_csv_ints(name: str, default: str) -> list[int]:
    value = os.environ.get(name, default)
    return [int(part.strip()) for part in value.split(",") if part.strip()]


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    xs = sorted(values)
    if len(xs) == 1:
        return xs[0]
    pos = (len(xs) - 1) * p
    lo = math.floor(pos)
    hi = math.ceil(pos)
    if lo == hi:
        return xs[lo]
    return xs[lo] * (hi - pos) + xs[hi] * (pos - lo)


def median(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def fmt(value: Any, digits: int = 1) -> str:
    if value is None:
        return "—"
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, int):
        return f"{value:,}"
    if isinstance(value, float):
        return f"{value:,.{digits}f}"
    return str(value)


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def post_json(url: str, payload: dict[str, Any], timeout: float = 120.0) -> dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from {url}: {detail}") from exc


def get_json(url: str, timeout: float = 5.0) -> dict[str, Any]:
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


class StatusSampler:
    """Poll lightweight oMLX server status while a workload is running."""

    def __init__(self, base_url: str, interval: float = 0.10):
        self.url = f"{base_url.rstrip('/')}/api/status"
        self.interval = interval
        self.samples: list[dict[str, Any]] = []
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def _sample_once(self) -> None:
        try:
            data = get_json(self.url, timeout=2.0)
            if isinstance(data, dict):
                self.samples.append(data)
        except Exception:
            # Older oMLX builds may not expose this endpoint. The request-level
            # benchmark metrics remain valid, so status telemetry is optional.
            pass

    def _run(self) -> None:
        while not self._stop.is_set():
            self._sample_once()
            self._stop.wait(self.interval)
        self._sample_once()

    def __enter__(self):
        self._sample_once()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        return self

    def __exit__(self, exc_type, exc, tb):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)

    @property
    def summary(self) -> dict[str, Any]:
        if not self.samples:
            return {}

        def numeric(name: str) -> list[float]:
            out = []
            for sample in self.samples:
                value = sample.get(name)
                if isinstance(value, (int, float)):
                    out.append(float(value))
            return out

        first, last = self.samples[0], self.samples[-1]
        result: dict[str, Any] = {
            "sample_count": len(self.samples),
            "peak_active_requests": int(max(numeric("active_requests"), default=0)),
            "peak_waiting_requests": int(max(numeric("waiting_requests"), default=0)),
        }
        memory = numeric("model_memory_used")
        if memory:
            result["peak_model_memory_gb"] = max(memory) / (1024 ** 3)

        for name in ("total_prompt_tokens", "total_completion_tokens", "total_cached_tokens"):
            a, b = first.get(name), last.get(name)
            if isinstance(a, (int, float)) and isinstance(b, (int, float)):
                result[f"{name}_delta"] = b - a

        prompt_delta = result.get("total_prompt_tokens_delta")
        cached_delta = result.get("total_cached_tokens_delta")
        if isinstance(prompt_delta, (int, float)) and prompt_delta > 0 and isinstance(cached_delta, (int, float)):
            result["cache_efficiency_delta"] = cached_delta / prompt_delta
        return result


class MemorySampler:
    """Best-effort process RSS sampler (portable enough for macOS/Linux)."""

    def __init__(self, pid: int | None, interval: float = 0.25):
        self.pid = pid
        self.interval = interval
        self.peak_rss_kb: int | None = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def _sample_once(self) -> None:
        if not self.pid:
            return
        try:
            out = subprocess.check_output(
                ["ps", "-o", "rss=", "-p", str(self.pid)],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
            if out:
                rss = int(out.split()[0])
                self.peak_rss_kb = max(self.peak_rss_kb or 0, rss)
        except Exception:
            pass

    def _run(self) -> None:
        while not self._stop.is_set():
            self._sample_once()
            self._stop.wait(self.interval)
        self._sample_once()

    def __enter__(self):
        if self.pid:
            self._thread = threading.Thread(target=self._run, daemon=True)
            self._thread.start()
        return self

    def __exit__(self, exc_type, exc, tb):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)

    @property
    def peak_rss_gb(self) -> float | None:
        if self.peak_rss_kb is None:
            return None
        return self.peak_rss_kb / (1024 * 1024)


@dataclass
class Client:
    base_url: str
    model: str

    def tokenize(self, messages: list[dict[str, Any]]) -> int:
        """Count chat prompt tokens with oMLX's supported token-count API.

        oMLX does not expose a ``/tokenize`` route. It does expose the
        Anthropic-compatible ``/v1/messages/count_tokens`` endpoint, which uses
        the loaded model's tokenizer and chat template on the server. Synthetic
        benchmark requests use only system/user text messages, so conversion to
        Anthropic's request shape is lossless here.

        The performance request itself still reports the authoritative prompt
        token count in OpenAI ``usage``. The count returned here is only used to
        size synthetic prompts before they are sent.
        """
        system_parts: list[str] = []
        anthropic_messages: list[dict[str, Any]] = []
        for message in messages:
            role = str(message.get("role", "user"))
            content = message.get("content", "")
            if role == "system":
                if isinstance(content, str):
                    system_parts.append(content)
                else:
                    system_parts.append(json.dumps(content, ensure_ascii=False))
                continue
            if role not in {"user", "assistant"}:
                raise ValueError(
                    f"Token counter only supports system/user/assistant benchmark messages, got {role!r}"
                )
            anthropic_messages.append({"role": role, "content": content})

        payload: dict[str, Any] = {
            "model": self.model,
            "messages": anthropic_messages,
            "thinking": {"type": "disabled"},
        }
        if system_parts:
            payload["system"] = "\n\n".join(system_parts)

        data = post_json(
            f"{self.base_url}/v1/messages/count_tokens",
            payload,
        )
        return int(data["input_tokens"])

    def stream_chat(
        self,
        messages: list[dict[str, Any]],
        max_tokens: int,
        temperature: float = 0.0,
    ) -> dict[str, Any]:
        payload = {
            "model": self.model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": True,
            "stream_options": {"include_usage": True},
            "chat_template_kwargs": {"enable_thinking": False},
        }
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{self.base_url}/v1/chat/completions",
            data=body,
            method="POST",
            headers={"Content-Type": "application/json"},
        )

        start = time.perf_counter()
        first_visible: float | None = None
        usage: dict[str, Any] | None = None
        finish_reason: str | None = None
        output_chars = 0
        error_payload: dict[str, Any] | None = None

        try:
            with urllib.request.urlopen(req, timeout=3600) as resp:
                for raw_line in resp:
                    line = raw_line.decode("utf-8", errors="replace").strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if not data or data == "[DONE]":
                        continue
                    try:
                        chunk = json.loads(data)
                    except json.JSONDecodeError:
                        continue
                    if "error" in chunk:
                        error_payload = chunk
                    if chunk.get("usage"):
                        usage = chunk["usage"]
                    for choice in chunk.get("choices", []) or []:
                        if choice.get("finish_reason"):
                            finish_reason = choice["finish_reason"]
                        delta = choice.get("delta", {}) or {}
                        visible = delta.get("content") or delta.get("reasoning_content")
                        tool_calls = delta.get("tool_calls")
                        if visible:
                            output_chars += len(str(visible))
                            if first_visible is None:
                                first_visible = time.perf_counter() - start
                        elif tool_calls:
                            if first_visible is None:
                                first_visible = time.perf_counter() - start
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"HTTP {exc.code} from /v1/chat/completions: {detail}"
            ) from exc

        wall = time.perf_counter() - start
        if error_payload:
            raise RuntimeError(f"Streaming error: {json.dumps(error_payload)}")
        if usage is None:
            raise RuntimeError(
                "oMLX did not return a usage chunk. Ensure stream_options.include_usage "
                "is supported by the installed oMLX version."
            )

        details = usage.get("prompt_tokens_details") or {}
        completion_tokens = int(usage.get("completion_tokens") or 0)
        generation_duration = usage.get("generation_duration")
        tpot_ms = None
        if generation_duration is not None and completion_tokens > 1:
            tpot_ms = float(generation_duration) * 1000.0 / (completion_tokens - 1)

        return {
            "prompt_tokens": usage.get("prompt_tokens"),
            "completion_tokens": completion_tokens,
            "total_tokens": usage.get("total_tokens"),
            "cached_tokens": details.get("cached_tokens", 0),
            "ttft_s": usage.get("time_to_first_token"),
            "visible_ttft_s": usage.get("time_to_first_visible_token", first_visible),
            "client_first_visible_s": first_visible,
            "prompt_eval_s": usage.get("prompt_eval_duration"),
            "generation_s": generation_duration,
            "pp_tps": usage.get("prompt_tokens_per_second"),
            "tg_tps": usage.get("generation_tokens_per_second"),
            "tpot_ms": tpot_ms,
            "provider_total_s": usage.get("total_time"),
            "wall_s": wall,
            "finish_reason": finish_reason,
            "output_chars": output_chars,
        }


def make_corpus(min_chars: int = 220_000) -> str:
    chunks: list[str] = []
    i = 0
    size = 0
    while size < min_chars:
        chunk = (
            f"def transform_record_{i}(record, cache):\n"
            f"    key = record.get('id', {i})\n"
            "    values = [v for v in record.get('values', []) if v is not None]\n"
            "    subtotal = sum((idx + 1) * value for idx, value in enumerate(values))\n"
            "    if key in cache:\n"
            "        subtotal += cache[key]\n"
            "    return {'key': key, 'subtotal': subtotal, 'count': len(values)}\n\n"
        )
        chunks.append(chunk)
        size += len(chunk)
        i += 1
    return "".join(chunks)


CORPUS = make_corpus()


def context_messages(nonce: str, body: str) -> list[dict[str, str]]:
    return [
        {
            "role": "system",
            "content": (
                f"benchmark-nonce:{nonce}\n"
                "You are reviewing a synthetic Python repository. Thinking is disabled. "
                "Read the supplied code carefully and answer only after considering all of it."
            ),
        },
        {
            "role": "user",
            "content": (
                body
                + "\nReview the code above. Produce a long numbered list of concrete observations "
                "about correctness, performance, maintainability, and testing. Continue until the output limit."
            ),
        },
    ]


def fit_context_prompt(
    client: Client,
    target: int,
    nonce: str,
    max_context: int,
    reserve_output_tokens: int = 0,
) -> tuple[list[dict[str, str]], int]:
    # Leave room for requested output plus a template/counting safety margin.
    # The OpenAI usage object returned by the real benchmark request remains
    # authoritative for the actual prompt size.
    prompt_ceiling = max(256, max_context - reserve_output_tokens - 128)
    effective_target = min(target, prompt_ceiling)
    lo, hi = 0, len(CORPUS)
    best_messages = context_messages(nonce, "")
    best_count = client.tokenize(best_messages)
    best_distance = abs(best_count - effective_target)

    for _ in range(20):
        mid = (lo + hi) // 2
        messages = context_messages(nonce, CORPUS[:mid])
        count = client.tokenize(messages)
        distance = abs(count - effective_target)
        if distance < best_distance:
            best_messages, best_count, best_distance = messages, count, distance
        if count < effective_target:
            lo = mid + 1
        else:
            hi = mid - 1
        if distance <= max(8, effective_target // 500):
            break
    return best_messages, best_count


def run_one(client: Client, messages, max_tokens: int, pid: int | None) -> dict[str, Any]:
    with MemorySampler(pid) as sampler:
        result = client.stream_chat(messages, max_tokens=max_tokens)
    result["peak_process_rss_gb"] = sampler.peak_rss_gb
    return result


def context_suite(
    client: Client,
    out: Path,
    lengths: list[int],
    runs: int,
    max_tokens: int,
    max_context: int,
    pid: int | None,
) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    print("\n== Context scaling / prefill vs decode ==", flush=True)
    for target in lengths:
        for run_no in range(1, runs + 1):
            nonce = f"context-{target}-{run_no}-{uuid.uuid4().hex}"
            messages, tokenized = fit_context_prompt(
                client, target, nonce, max_context, reserve_output_tokens=max_tokens
            )
            print(f"  target {target:>5} run {run_no}: {tokenized} prompt tokens ...", end="", flush=True)
            result = run_one(client, messages, max_tokens, pid)
            result.update({"target_prompt_tokens": target, "run": run_no, "tokenized_prompt_tokens": tokenized})
            rows.append(result)
            print(f" PP={fmt(result['pp_tps'])} TG={fmt(result['tg_tps'])} TTFT={fmt(result['ttft_s'], 2)}s", flush=True)

    grouped: list[dict[str, Any]] = []
    for target in lengths:
        sample = [r for r in rows if r["target_prompt_tokens"] == target]
        def vals(key):
            return [float(r[key]) for r in sample if r.get(key) is not None]
        grouped.append(
            {
                "target_prompt_tokens": target,
                "actual_prompt_tokens_median": int(median(vals("prompt_tokens")) or 0),
                "pp_tps_median": median(vals("pp_tps")),
                "tg_tps_median": median(vals("tg_tps")),
                "ttft_s_median": median(vals("ttft_s")),
                "visible_ttft_s_median": median(vals("visible_ttft_s")),
                "tpot_ms_median": median(vals("tpot_ms")),
                "e2e_s_median": median(vals("wall_s")),
                "cached_tokens_median": median(vals("cached_tokens")),
                "peak_process_rss_gb_max": max(vals("peak_process_rss_gb"), default=None),
            }
        )

    data = {"suite": "context-scaling", "runs": rows, "summary": grouped}
    write_json(out / "context-scaling.json", data)

    lines = [
        "# Context scaling benchmark",
        "",
        "Synthetic code workload, thinking disabled, unique leading nonce per run to avoid intentional prefix reuse.",
        "",
        "| Target | Actual prompt | PP tok/s | TG tok/s | TTFT | visible TTFT | TPOT | E2E | peak process RSS |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in grouped:
        lines.append(
            f"| {fmt(r['target_prompt_tokens'])} | {fmt(r['actual_prompt_tokens_median'])} | "
            f"{fmt(r['pp_tps_median'])} | {fmt(r['tg_tps_median'])} | {fmt(r['ttft_s_median'],2)} s | "
            f"{fmt(r['visible_ttft_s_median'],2)} s | {fmt(r['tpot_ms_median'])} ms | "
            f"{fmt(r['e2e_s_median'],2)} s | {fmt(r['peak_process_rss_gb_max'],2)} GB |"
        )
    lines += [
        "",
        "PP = prompt processing/prefill throughput. TG = token generation/decode throughput. "
        "TTFT = model time to first token. TPOT = approximate time per output token after the first.",
        "",
        "Peak process RSS is a best-effort host-process measurement from `ps`; it is not the same as oMLX's MLX-active-memory metric.",
    ]
    (out / "context-scaling.md").write_text("\n".join(lines) + "\n")
    return data


def build_prefix_messages(
    client: Client,
    target: int,
    nonce: str,
    question: str,
    max_context: int,
    reserve_output_tokens: int = 128,
):
    effective_target = min(target, max(256, max_context - reserve_output_tokens - 128))
    lo, hi = 0, len(CORPUS)
    best = None
    best_count = 0
    best_distance = 10**9
    while lo <= hi:
        mid = (lo + hi) // 2
        messages = [
            {
                "role": "system",
                "content": (
                    f"prefix-experiment:{nonce}\n"
                    "This synthetic repository snapshot is shared verbatim between turns.\n"
                    + CORPUS[:mid]
                ),
            },
            {"role": "user", "content": question},
        ]
        count = client.tokenize(messages)
        distance = abs(count - effective_target)
        if distance < best_distance:
            best, best_count, best_distance = messages, count, distance
        if count < effective_target:
            lo = mid + 1
        else:
            hi = mid - 1
        if distance <= max(8, effective_target // 500):
            break
    assert best is not None
    return best, best_count


def prefix_suite(client: Client, out: Path, target: int, max_tokens: int, max_context: int, pid: int | None):
    print("\n== Prefix cache: cold vs warm ==", flush=True)
    nonce = uuid.uuid4().hex
    cold_messages, cold_tokenized = build_prefix_messages(
        client,
        target,
        nonce,
        "Find five maintainability issues. Continue with detail until the output limit.",
        max_context,
        reserve_output_tokens=max_tokens,
    )
    # Reuse the exact same large system message for the warm request. Only the
    # final user message changes, so cached-token accounting really measures
    # prefix reuse rather than small prompt-construction differences.
    warm_messages = [
        cold_messages[0],
        {"role": "user", "content": "Find five performance issues. Continue with detail until the output limit."},
    ]
    warm_tokenized = client.tokenize(warm_messages)

    print(f"  cold ({cold_tokenized} prompt tokens) ...", end="", flush=True)
    cold = run_one(client, cold_messages, max_tokens, pid)
    print(f" cached={cold.get('cached_tokens', 0)} TTFT={fmt(cold.get('ttft_s'),2)}s", flush=True)
    print(f"  warm ({warm_tokenized} prompt tokens) ...", end="", flush=True)
    warm = run_one(client, warm_messages, max_tokens, pid)
    print(f" cached={warm.get('cached_tokens', 0)} TTFT={fmt(warm.get('ttft_s'),2)}s", flush=True)

    speedup = None
    if cold.get("ttft_s") and warm.get("ttft_s"):
        speedup = float(cold["ttft_s"]) / float(warm["ttft_s"])
    cached_fraction = None
    if warm.get("prompt_tokens"):
        cached_fraction = float(warm.get("cached_tokens") or 0) / float(warm["prompt_tokens"])

    data = {
        "suite": "prefix-cache",
        "target_prompt_tokens": target,
        "cold_tokenized_prompt_tokens": cold_tokenized,
        "warm_tokenized_prompt_tokens": warm_tokenized,
        "cold": cold,
        "warm": warm,
        "ttft_speedup_cold_over_warm": speedup,
        "warm_cached_fraction": cached_fraction,
    }
    write_json(out / "prefix-cache.json", data)

    lines = [
        "# Prefix-cache benchmark",
        "",
        "Two requests share the same large system-prefix and differ only in the final user question.",
        "",
        "| Run | Prompt | Cached | Cached % | PP tok/s | TG tok/s | TTFT | visible TTFT | E2E |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for label, row in (("cold", cold), ("warm", warm)):
        fraction = (float(row.get("cached_tokens") or 0) / float(row.get("prompt_tokens") or 1)) * 100
        lines.append(
            f"| {label} | {fmt(row.get('prompt_tokens'))} | {fmt(row.get('cached_tokens'))} | {fraction:.1f}% | "
            f"{fmt(row.get('pp_tps'))} | {fmt(row.get('tg_tps'))} | {fmt(row.get('ttft_s'),2)} s | "
            f"{fmt(row.get('visible_ttft_s'),2)} s | {fmt(row.get('wall_s'),2)} s |"
        )
    lines += ["", f"Cold/warm TTFT speedup: **{fmt(speedup, 2)}×**"]
    (out / "prefix-cache.md").write_text("\n".join(lines) + "\n")
    return data


def concurrency_suite(
    client: Client,
    out: Path,
    prompt_target: int,
    levels: list[int],
    max_tokens: int,
    max_context: int,
    pid: int | None,
    slo_ttft: float,
    slo_tg: float,
):
    print("\n== Concurrency / throughput / goodput ==", flush=True)
    groups = []
    for concurrency in levels:
        messages_list = []
        for idx in range(concurrency):
            nonce = f"conc-{concurrency}-{idx}-{uuid.uuid4().hex}"
            messages, _ = fit_context_prompt(
                client,
                prompt_target,
                nonce,
                max_context,
                reserve_output_tokens=max_tokens,
            )
            messages_list.append(messages)

        group_start = time.perf_counter()
        with StatusSampler(client.base_url) as status_sampler, MemorySampler(pid) as sampler:
            with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
                futures = [pool.submit(client.stream_chat, messages, max_tokens) for messages in messages_list]
                results = []
                for future in futures:
                    try:
                        row = future.result()
                        row["ok"] = True
                    except Exception as exc:
                        row = {"ok": False, "error": str(exc)}
                    results.append(row)
        group_wall = time.perf_counter() - group_start
        status = status_sampler.summary

        successful = [r for r in results if r.get("ok")]
        completion_tokens = sum(int(r.get("completion_tokens") or 0) for r in successful)
        aggregate_tps = completion_tokens / group_wall if group_wall else None
        ttfts = [float(r["ttft_s"]) for r in successful if r.get("ttft_s") is not None]
        tgs = [float(r["tg_tps"]) for r in successful if r.get("tg_tps") is not None]
        good = [
            r for r in successful
            if r.get("ttft_s") is not None
            and r.get("tg_tps") is not None
            and float(r["ttft_s"]) <= slo_ttft
            and float(r["tg_tps"]) >= slo_tg
        ]
        group = {
            "concurrency": concurrency,
            "group_wall_s": group_wall,
            "requests": results,
            "successful_requests": len(successful),
            "slo_successes": len(good),
            "aggregate_output_tps": aggregate_tps,
            "p50_ttft_s": percentile(ttfts, 0.50),
            "p95_ttft_s": percentile(ttfts, 0.95),
            "median_user_tg_tps": median(tgs),
            "request_throughput_rps": len(successful) / group_wall if group_wall else None,
            "goodput_rps": len(good) / group_wall if group_wall else None,
            "slo_success_fraction": len(good) / concurrency if concurrency else None,
            "peak_process_rss_gb": sampler.peak_rss_gb,
            "server_status": status,
        }
        groups.append(group)
        print(
            f"  {concurrency}x: aggregate={fmt(aggregate_tps)} tok/s, "
            f"p95 TTFT={fmt(group['p95_ttft_s'],2)}s, "
            f"waiting_peak={fmt(status.get('peak_waiting_requests'))}, "
            f"good={len(good)}/{concurrency}",
            flush=True,
        )

    data = {
        "suite": "concurrency-goodput",
        "slo": {"max_ttft_s": slo_ttft, "min_user_tg_tps": slo_tg},
        "groups": groups,
    }
    write_json(out / "concurrency.json", data)

    lines = [
        "# Concurrency and goodput benchmark",
        "",
        f"Good request SLO: TTFT ≤ {slo_ttft:g} s and per-user TG ≥ {slo_tg:g} tok/s.",
        "",
        "| Concurrent | Aggregate output | p50 TTFT | p95 TTFT | median user TG | peak queued | SLO pass | goodput | model mem | process RSS |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for g in groups:
        lines.append(
            f"| {g['concurrency']} | {fmt(g['aggregate_output_tps'])} tok/s | "
            f"{fmt(g['p50_ttft_s'],2)} s | {fmt(g['p95_ttft_s'],2)} s | "
            f"{fmt(g['median_user_tg_tps'])} tok/s | {fmt(g['server_status'].get('peak_waiting_requests'))} | "
            f"{g['slo_successes']}/{g['concurrency']} | {fmt(g['goodput_rps'],3)} req/s | "
            f"{fmt(g['server_status'].get('peak_model_memory_gb'),2)} GB | {fmt(g['peak_process_rss_gb'],2)} GB |"
        )
    lines += [
        "",
        "Aggregate throughput can rise while goodput falls. Goodput counts only requests still meeting the interactive latency SLO.",
        "Peak queued requests and model memory come from oMLX `/api/status` polling when that endpoint is available; raw status-derived deltas are retained in `concurrency.json`.",
    ]
    (out / "concurrency.md").write_text("\n".join(lines) + "\n")
    return data


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.environ.get("OMLX_BASE_URL", "http://127.0.0.1:8000"))
    parser.add_argument("--model", default=os.environ.get("MODEL_ID"))
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--suite", choices=["all", "context", "prefix", "concurrency"], default="all")
    parser.add_argument("--pid", type=int, default=None)
    parser.add_argument("--max-context", type=int, default=env_int("MODEL_MAX_CONTEXT_WINDOW", 32768))
    args = parser.parse_args()
    if not args.model:
        parser.error("--model or MODEL_ID is required")

    args.out.mkdir(parents=True, exist_ok=True)
    client = Client(args.base_url.rstrip("/"), args.model)

    # Fail early if the model/tokenizer cannot be addressed and warm model load.
    # Token sizing uses oMLX's supported Anthropic-compatible count_tokens API.
    print(f"Model: {args.model}")
    print(f"API:   {client.base_url}")
    warmup = [
        {"role": "system", "content": f"warmup:{uuid.uuid4().hex}"},
        {"role": "user", "content": "Reply with the word ready."},
    ]
    count = client.tokenize(warmup)
    print(f"Warm-up prompt tokens: {count}")
    client.stream_chat(warmup, max_tokens=16)

    summary: dict[str, Any] = {
        "model": args.model,
        "base_url": client.base_url,
        "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "thinking": "disabled for synthetic performance suites",
    }

    if args.suite in {"all", "context"}:
        summary["context"] = context_suite(
            client,
            args.out,
            env_csv_ints("BENCH_CONTEXT_LENGTHS", "1024,4096,8192,16384,32768"),
            env_int("BENCH_CONTEXT_RUNS", 2),
            env_int("BENCH_GENERATION_TOKENS", 256),
            args.max_context,
            args.pid,
        )["summary"]

    if args.suite in {"all", "prefix"}:
        prefix = prefix_suite(
            client,
            args.out,
            env_int("BENCH_PREFIX_TOKENS", 8192),
            env_int("BENCH_PREFIX_MAX_TOKENS", 128),
            args.max_context,
            args.pid,
        )
        summary["prefix"] = {
            "ttft_speedup_cold_over_warm": prefix["ttft_speedup_cold_over_warm"],
            "warm_cached_fraction": prefix["warm_cached_fraction"],
        }

    if args.suite in {"all", "concurrency"}:
        concurrency = concurrency_suite(
            client,
            args.out,
            env_int("BENCH_CONCURRENCY_PROMPT_TOKENS", 4096),
            env_csv_ints("BENCH_CONCURRENCY_LEVELS", "1,2,4,8"),
            env_int("BENCH_CONCURRENCY_MAX_TOKENS", 128),
            args.max_context,
            args.pid,
            env_float("BENCH_SLO_TTFT_SECONDS", 15.0),
            env_float("BENCH_SLO_MIN_TG_TPS", 30.0),
        )
        summary["concurrency"] = concurrency["groups"]

    write_json(args.out / "benchmark-summary.json", summary)
    index = [
        "# Inference engineering benchmark run",
        "",
        f"Model: `{args.model}`",
        "",
        "Synthetic performance measurements run with model thinking disabled so prefill/decode measurements are comparable. "
        "The separate Copilot experiment uses the normal thinking-enabled profile.",
        "",
    ]
    if (args.out / "context-scaling.md").exists():
        index.append("- [Context scaling](context-scaling.md): PP, TG, TTFT, TPOT, E2E and process memory across context lengths.")
    if (args.out / "prefix-cache.md").exists():
        index.append("- [Prefix cache](prefix-cache.md): cold vs warm prefix reuse and cached-token accounting.")
    if (args.out / "concurrency.md").exists():
        index.append("- [Concurrency](concurrency.md): aggregate throughput, tail TTFT and SLO-based goodput.")
    index += [
        "",
        "Raw JSON files next to these reports retain the per-request metrics for later experiment documentation.",
    ]
    (args.out / "benchmark-summary.md").write_text("\n".join(index) + "\n")
    print(f"\nResults written to: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
