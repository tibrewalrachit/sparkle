"""LLM client for the agentic layer.

Uses OpenRouter's OpenAI-compatible chat API. Model defaults to GLM 5.2 and
is overridable via SPARKLE_FV_MODEL. The API key is read from
OPENROUTER_API_KEY (never stored in the repository).

Every caller must tolerate `LLMUnavailable`: the harness degrades to its
deterministic template synthesizers so proofs and benchmarks remain
reproducible without network access.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request

DEFAULT_MODEL = os.environ.get("SPARKLE_FV_MODEL", "z-ai/glm-5.2")
API_URL = os.environ.get("SPARKLE_FV_LLM_URL",
                         "https://openrouter.ai/api/v1/chat/completions")


class LLMUnavailable(Exception):
    pass


def llm_enabled() -> bool:
    return bool(os.environ.get("OPENROUTER_API_KEY")) and \
        os.environ.get("SPARKLE_FV_NO_LLM", "") != "1"


def chat(system: str, user: str, model: str | None = None,
         max_tokens: int = 4096, temperature: float = 0.2,
         retries: int = 2, timeout_s: float = 120.0) -> str:
    """One-shot chat completion. Raises LLMUnavailable on any failure."""
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        raise LLMUnavailable("OPENROUTER_API_KEY not set")
    body = json.dumps({
        "model": model or DEFAULT_MODEL,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }).encode()
    last_err: Exception | None = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(
                API_URL, data=body, method="POST",
                headers={
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                    "HTTP-Referer": "https://github.com/tibrewalrachit/sparkle",
                    "X-Title": "sparkle-fv",
                })
            with urllib.request.urlopen(req, timeout=timeout_s) as resp:
                data = json.loads(resp.read().decode())
            return data["choices"][0]["message"]["content"]
        except (urllib.error.URLError, urllib.error.HTTPError, OSError,
                KeyError, json.JSONDecodeError, TimeoutError) as e:
            last_err = e
            if attempt < retries:
                time.sleep(2 ** attempt)
    raise LLMUnavailable(f"LLM call failed after {retries + 1} attempts: {last_err}")


def extract_json_block(text: str):
    """Best-effort extraction of the first JSON array/object in a response."""
    depth = 0
    start = None
    for i, ch in enumerate(text):
        if ch in "[{":
            if depth == 0:
                start = i
            depth += 1
        elif ch in "]}":
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    return json.loads(text[start:i + 1])
                except json.JSONDecodeError:
                    start = None
    raise ValueError("no JSON block found in LLM response")
