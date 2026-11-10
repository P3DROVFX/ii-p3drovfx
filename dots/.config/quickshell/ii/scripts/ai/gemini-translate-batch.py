#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Translate the missing keys of a shell locale file in batches with an LLM.

Providers:
  gemini  Google Gemini API (key from GEMINI_API_KEY or the shell keyring)
  claude  Claude through the local `claude` CLI, billed to the signed-in
          Claude plan (Pro/Max) instead of an API key

Machine-readable lines on stdout (the Settings page parses them):
  @@TOTAL <keys_needing_translation> <batches>
  @@PROGRESS <keys_done> <keys_total> <batch> <batches>
  @@ERROR <message>
  @@DONE <keys_translated> <keys_failed>
  @@USAGE <input_tokens> <output_tokens> <api_equivalent_usd>   (claude provider, per batch)

Exit codes: 0 everything translated, 1 nothing could run, 2 some batches failed.
"""

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


def emit(tag: str, *values) -> None:
    print(" ".join([f"@@{tag}", *[str(v) for v in values]]), flush=True)


def log(message: str) -> None:
    print(message, flush=True)


def instruction_for(target_locale: str) -> str:
    return (
        "You are to translate the user interface of a **desktop shell**. "
        "Given a JSON object of key-value pairs, return a JSON with the exact same structure, "
        f"with keys unchanged and values translated to {target_locale}. "
        "Keep placeholders such as %1, %2 and \\n exactly as they are. "
        "Leave product names, commands, file names, keys and proper nouns unchanged. "
        "Be as **concise** as possible to save screen space, and make sure terminology is relevant "
        '(e.g. "discharging" refers to the battery status). '
        "Reply with the JSON object only."
    )


def get_gemini_key() -> str:
    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if api_key:
        return api_key
    try:
        result = subprocess.run(
            ["secret-tool", "lookup", "application", "illogical-impulse"],
            capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout.strip()).get("apiKeys", {}).get("gemini", "") or ""
    except Exception:
        return ""


def parse_json_object(text: str) -> dict:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else ""
        text = text.rsplit("```", 1)[0]
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end < start:
        raise ValueError("response has no JSON object")
    data = json.loads(text[start:end + 1])
    if not isinstance(data, dict):
        raise ValueError("response is not a JSON object")
    return data


def translate_gemini(batch: dict, locale: str, model: str, api_key: str) -> dict:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    prompt = f"{instruction_for(locale)}\n```json\n{json.dumps(batch, ensure_ascii=False, indent=2)}\n```\n"
    generation = {"temperature": 0.0, "responseMimeType": "application/json"}
    # Translation needs no reasoning; thinking tokens are billed as output.
    if model.startswith("gemini-3"):
        generation["thinkingConfig"] = {"thinkingLevel": "low"}
    elif model.startswith("gemini-2.5-flash"):
        generation["thinkingConfig"] = {"thinkingBudget": 0}
    payload = {"contents": [{"parts": [{"text": prompt}]}], "generationConfig": generation}
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = json.loads(e.read().decode("utf-8")).get("error", {}).get("message", "")
        except Exception:
            pass
        raise RuntimeError(f"Gemini API {e.code}: {detail or e.reason}") from None
    return parse_json_object(data["candidates"][0]["content"]["parts"][0]["text"])


def translate_claude(batch: dict, locale: str, model: str, claude_bin: str) -> dict:
    prompt = f"```json\n{json.dumps(batch, ensure_ascii=False, indent=2)}\n```\n"
    # An empty working directory keeps project CLAUDE.md files out of the prompt;
    # no tools, MCP or settings keeps the request a plain completion.
    with tempfile.TemporaryDirectory(prefix="ii-translate-") as cwd:
        result = subprocess.run(
            [
                claude_bin, "-p",
                "--model", model,
                "--output-format", "json",
                "--tools", "",
                "--strict-mcp-config",
                "--setting-sources", "",
                "--no-session-persistence",
                "--system-prompt", instruction_for(locale),
            ],
            input=prompt, capture_output=True, text=True, cwd=cwd, timeout=600,
        )
    try:
        envelope = json.loads(result.stdout)
    except Exception:
        tail = (result.stderr or result.stdout).strip().splitlines()[-1:] or ["no output"]
        raise RuntimeError(f"claude CLI failed: {tail[0]}") from None
    if envelope.get("is_error") or result.returncode != 0:
        raise RuntimeError(f"claude CLI: {str(envelope.get('result', 'error')).strip()[:200]}")
    usage = envelope.get("usage") or {}
    emit("USAGE",
         usage.get("input_tokens", 0) + usage.get("cache_creation_input_tokens", 0) + usage.get("cache_read_input_tokens", 0),
         usage.get("output_tokens", 0),
         f"{float(envelope.get('total_cost_usd') or 0):.5f}")
    return parse_json_object(envelope.get("result", ""))


def main() -> None:
    # SystemExit unwinds subprocess.run, which kills a claude CLI still running.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(130))
    parser = argparse.ArgumentParser(description="Translate missing locale keys in batches with an LLM")
    parser.add_argument("source_file", help="Path to the source en_US.json")
    parser.add_argument("target_file", help="Path to the target locale JSON (e.g. pt_BR.json)")
    parser.add_argument("target_locale", help="Target locale code (e.g. pt_BR)")
    parser.add_argument("--model", default="gemini-3.8-flash", help="Model id")
    parser.add_argument("--provider", default="auto", choices=["auto", "gemini", "claude"])
    parser.add_argument("--batch-size", type=int, default=300, help="Keys per batch")
    parser.add_argument("--include-identical", action="store_true",
                        help="Also translate values still identical to the English source (copied, never translated)")
    args = parser.parse_args()

    provider = args.provider
    if provider == "auto":
        provider = "claude" if args.model.startswith("claude-") else "gemini"

    if provider == "gemini":
        api_key = get_gemini_key()
        if not api_key:
            emit("ERROR", "No Gemini API key. Add one in Settings → AI Assistant.")
            sys.exit(1)
        translate = lambda batch: translate_gemini(batch, args.target_locale, args.model, api_key)
    else:
        claude_bin = shutil.which("claude") or str(Path.home() / ".local/bin/claude")
        if not os.access(claude_bin, os.X_OK):
            emit("ERROR", "The claude CLI is not installed or not in PATH.")
            sys.exit(1)
        translate = lambda batch: translate_claude(batch, args.target_locale, args.model, claude_bin)

    source_path, target_path = Path(args.source_file), Path(args.target_file)
    if not source_path.exists():
        emit("ERROR", f"Source file {source_path.name} does not exist.")
        sys.exit(1)
    source_data = json.loads(source_path.read_text(encoding="utf-8"))

    target_data = {}
    if target_path.exists():
        try:
            target_data = json.loads(target_path.read_text(encoding="utf-8"))
        except Exception as e:
            log(f"Warning: could not parse the existing target file: {e}")

    keep_suffix = "/*keep*/"
    def needs(key, value):
        current = target_data.get(key)
        if not current:
            return True
        return args.include_identical and current == value and not current.endswith(keep_suffix)
    missing = [(k, v) for k, v in source_data.items() if needs(k, v)]
    total = len(missing)
    batch_size = max(1, args.batch_size)
    batches = (total + batch_size - 1) // batch_size
    log(f"{len(source_data)} source keys, {total} need translation, {provider}:{args.model}")
    emit("TOTAL", total, batches)
    if total == 0:
        emit("DONE", 0, 0)
        sys.exit(0)

    done = failed = 0
    last_error = ""
    for b in range(batches):
        batch = dict(missing[b * batch_size:(b + 1) * batch_size])
        translated = None
        for attempt in range(2):
            try:
                translated = translate(batch)
                break
            except Exception as e:
                last_error = str(e)
                log(f"Batch {b + 1}/{batches} attempt {attempt + 1} failed: {e}")
                time.sleep(2)
        if translated is None:
            failed += len(batch)
            # A bad key or an exhausted plan fails every batch the same way.
            if b == 0:
                emit("ERROR", last_error)
                sys.exit(1)
        else:
            accepted = {k: v for k, v in translated.items() if k in batch and isinstance(v, str) and v}
            target_data.update(accepted)
            failed += len(batch) - len(accepted)
            target_path.parent.mkdir(parents=True, exist_ok=True)
            # Rewrite in place: a new inode would detach the shell's file watcher.
            with open(target_path, "w", encoding="utf-8") as f:
                f.write(json.dumps(target_data, ensure_ascii=False, indent=4) + "\n")
        done += len(batch)
        emit("PROGRESS", done, total, b + 1, batches)

    emit("DONE", total - failed, failed)
    if failed:
        emit("ERROR", f"{failed} strings were not translated. {last_error}".strip())
        sys.exit(2)


if __name__ == "__main__":
    main()
