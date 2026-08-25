import json
import os
import time
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import Response, StreamingResponse

UPSTREAM = os.environ.get("COPILOT_PROXY_UPSTREAM", "http://127.0.0.1:8000").rstrip("/")
LOG_DIR = Path(os.environ.get("COPILOT_PROXY_LOG_DIR", str(Path(__file__).resolve().parents[1] / "logs" / "proxy")))
LOG_RAW = os.environ.get("COPILOT_PROXY_LOG_RAW", "0").lower() in {"1", "true", "yes", "on"}
PREVIEW_CHARS = max(0, int(os.environ.get("COPILOT_PROXY_PREVIEW_CHARS", "0")))
LOG_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI()


def _content_stats(content):
    if isinstance(content, str):
        serialized = content
    else:
        serialized = json.dumps(content, ensure_ascii=False)
    preview = serialized[:PREVIEW_CHARS] if PREVIEW_CHARS else None
    return len(serialized), preview


def summarize_json(data):
    messages = data.get("messages", []) or []
    tools = data.get("tools", []) or []

    summary = {
        "model": data.get("model"),
        "stream": data.get("stream"),
        "max_tokens": data.get("max_tokens"),
        "temperature": data.get("temperature"),
        "message_count": len(messages),
        "tool_count": len(tools),
        "messages": [],
    }

    for i, msg in enumerate(messages):
        chars, preview = _content_stats(msg.get("content"))
        item = {
            "index": i,
            "role": msg.get("role"),
            "chars": chars,
        }
        if preview is not None:
            item["preview"] = preview
        summary["messages"].append(item)

    if tools:
        summary["tools_chars"] = len(json.dumps(tools, ensure_ascii=False))

    if "chat_template_kwargs" in data:
        summary["chat_template_kwargs"] = data["chat_template_kwargs"]

    if "reasoning_effort" in data:
        summary["reasoning_effort"] = data["reasoning_effort"]

    return summary


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
async def proxy(path: str, request: Request):
    body = await request.body()
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    millis = int((time.time() % 1) * 1000)
    stem = f"{timestamp}-{millis:03d}"

    headers = dict(request.headers)
    headers.pop("host", None)
    headers.pop("content-length", None)

    url = f"{UPSTREAM}/{path}"

    if body:
        try:
            data = json.loads(body)
            summary = summarize_json(data)
            summary_path = LOG_DIR / f"{stem}-summary.json"
            summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")

            print("\n=== COPILOT REQUEST ===", flush=True)
            print(json.dumps(summary, indent=2, ensure_ascii=False), flush=True)

            if LOG_RAW:
                raw_path = LOG_DIR / f"{stem}-request.json"
                raw_path.write_bytes(body)
                print(f"Raw request saved: {raw_path}", flush=True)
        except Exception as exc:
            print(f"Could not parse JSON body: {exc}", flush=True)

    client = httpx.AsyncClient(timeout=None)
    upstream = await client.send(
        client.build_request(
            request.method,
            url,
            headers=headers,
            content=body,
            params=request.query_params,
        ),
        stream=True,
    )

    response_headers = dict(upstream.headers)
    for header in ("content-length", "transfer-encoding", "connection"):
        response_headers.pop(header, None)

    content_type = upstream.headers.get("content-type", "")

    if "text/event-stream" in content_type:
        async def iterator():
            try:
                async for chunk in upstream.aiter_bytes():
                    yield chunk
            finally:
                await upstream.aclose()
                await client.aclose()

        return StreamingResponse(
            iterator(),
            status_code=upstream.status_code,
            headers=response_headers,
            media_type="text/event-stream",
        )

    content = await upstream.aread()
    await upstream.aclose()
    await client.aclose()

    return Response(
        content=content,
        status_code=upstream.status_code,
        headers=response_headers,
        media_type=content_type or None,
    )
