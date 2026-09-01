#!/usr/bin/env python3
"""Consolidated boot-time index for the Ai service.

Returns a single JSON document combining:

  - installed local Ollama models (if `ollama` is reachable)
  - default prompt file names (.md/.txt) under the repo's defaults/ai/prompts
  - user prompt file names (.md/.txt) under the user's ai/prompts

Chats are not listed here any more: they live in the session store, which
`ai_sessions.py` owns.

Usage:
    ai_index.py DEFAULT_PROMPTS_DIR USER_PROMPTS_DIR

Output (one JSON object on stdout):
    {
        "ollama_models": ["llama3.1:8b", "qwen:7b", ...],
        "default_prompts": ["/abs/path/p1.md", ...],
        "user_prompts":    ["/abs/path/u1.md", ...]
    }
"""

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path


def list_files(directory: str, suffixes: tuple[str, ...]) -> list[str]:
    if not directory or not os.path.isdir(directory):
        return []
    out: list[str] = []
    try:
        for name in sorted(os.listdir(directory)):
            if any(name.endswith(suf) for suf in suffixes):
                out.append(os.path.join(directory, name))
    except OSError:
        pass
    return out


def list_ollama_models() -> list[dict]:
    # Heuristic: only try to invoke ollama if the binary exists AND ollama
    # is reachable. The CLI blocks for several seconds when the daemon is
    # down (no — it errors immediately), but the spawn-test keeps the
    # logic cheap and avoids polluting stderr.
    try:
        # /api/tags is the capability source of truth. Unlike `ollama list`,
        # it tells the UI which local models actually support tools, vision,
        # thinking and their real context window.
        with urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=2) as response:
            payload = json.loads(response.read().decode("utf-8"))
        models = []
        for model in payload.get("models", []):
            if not isinstance(model, dict) or not model.get("name"):
                continue
            details = model.get("details") if isinstance(model.get("details"), dict) else {}
            models.append({
                "name": str(model["name"]),
                "capabilities": [str(capability) for capability in model.get("capabilities", [])],
                "context_length": int(details.get("context_length") or 0),
                "digest": str(model.get("digest") or ""),
            })
        return models
    except (urllib.error.URLError, ValueError, OSError):
        pass
    try:
        probe = subprocess.run(
            ["pgrep", "-x", "ollama"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        # If no running daemon, the CLI would just print "couldn't connect"
        # and exit. Skip the call entirely to save one fork.
        if probe.returncode != 0:
            # Fall back to `ollama list` anyway in case the daemon is
            # running under a non-default name (e.g. user systemd unit).
            pass
        res = subprocess.run(
            ["ollama", "list"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=4,
        )
        if res.returncode != 0:
            return []
        lines = res.stdout.decode("utf-8", errors="replace").splitlines()
        # Drop the header row.
        if lines and lines[0].lower().startswith("name"):
            lines = lines[1:]
        models: list[dict] = []
        for line in lines:
            line = line.strip()
            if not line:
                continue
            # `ollama list` columns are whitespace-separated; first column
            # is the model name (tag included).
            name = line.split()[0]
            if name:
                # Old Ollama has no capabilities in /api/tags. Preserve the
                # model but mark the absence, so the manual override is only
                # offered for this case rather than pretending every model can
                # use tools.
                models.append({"name": name, "capabilities": [], "context_length": 0, "digest": ""})
        return models
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return []


def main() -> int:
    argv = sys.argv[1:]

    if len(argv) < 2:
        print(
            json.dumps(
                {
                    "ollama_models": [],
                    "default_prompts": [],
                    "user_prompts": [],
                }
            )
        )
        return 0

    default_dir, user_dir = argv[0], argv[1]
    payload = {
        "ollama_models": list_ollama_models(),
        "default_prompts": list_files(default_dir, (".md", ".txt")),
        "user_prompts": list_files(user_dir, (".md", ".txt")),
    }
    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
