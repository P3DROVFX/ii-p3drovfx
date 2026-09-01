#!/usr/bin/env python3
"""Small, isolated store for AI composer drafts.

Drafts are deliberately not part of ``config.json``, ``states.json`` or the
conversation files. A malformed draft file therefore cannot erase settings or
transcripts. Every replacement is fsynced and atomically renamed beside the
target, and stale/empty entries are pruned during a successful load/save.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
from typing import Any


SCHEMA = 1
FILE_NAME = "drafts.json"
MAX_DRAFTS = 128
MAX_AGE_MS = 45 * 24 * 60 * 60 * 1000


def now_ms() -> int:
    return int(time.time() * 1000)


def file_path(directory: str) -> str:
    return os.path.join(directory, FILE_NAME)


def read_store(directory: str) -> tuple[dict[str, Any] | None, str]:
    path = file_path(directory)
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)
    except FileNotFoundError:
        return {"schema": SCHEMA, "drafts": {}}, "missing"
    except (OSError, ValueError):
        # Do not replace a truncated file. The caller can keep the backup and
        # ask the user to retype, while config/session history remains intact.
        return None, "invalid"
    if not isinstance(raw, dict) or not isinstance(raw.get("drafts"), dict):
        return None, "invalid"
    drafts: dict[str, dict[str, Any]] = {}
    for session_id, draft in raw["drafts"].items():
        if not isinstance(session_id, str) or not session_id:
            continue
        if not isinstance(draft, dict):
            continue
        text = draft.get("text")
        if not isinstance(text, str) or not text.strip():
            continue
        updated = draft.get("updatedAt")
        updated_at = int(updated) if isinstance(updated, (int, float)) else now_ms()
        if now_ms() - updated_at > MAX_AGE_MS:
            continue
        drafts[session_id] = {"text": text, "updatedAt": updated_at}
    return {"schema": SCHEMA, "drafts": drafts}, "ok"


def prune(store: dict[str, Any]) -> dict[str, Any]:
    drafts = store.get("drafts", {})
    ordered = sorted(
        drafts.items(), key=lambda item: int(item[1].get("updatedAt", 0)), reverse=True
    )
    store["drafts"] = dict(ordered[:MAX_DRAFTS])
    store["schema"] = SCHEMA
    store["updatedAt"] = now_ms()
    return store


def write_store(directory: str, store: dict[str, Any]) -> bool:
    os.makedirs(directory, exist_ok=True)
    target = file_path(directory)
    temporary = ""
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=directory,
            prefix=".drafts.", suffix=".tmp", delete=False
        ) as handle:
            temporary = handle.name
            json.dump(prune(store), handle, ensure_ascii=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, target)
        return True
    except OSError:
        if temporary:
            try:
                os.unlink(temporary)
            except OSError:
                pass
        return False


def emit(payload: dict[str, Any]) -> int:
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def cmd_load(directory: str) -> int:
    store, status = read_store(directory)
    if store is None:
        return emit({"error": "Draft store is truncated or invalid", "recovery": "preserved"})
    # A missing file is created only after a valid load path is established.
    if status == "missing" and not write_store(directory, store):
        return emit({"error": "Could not create the draft store"})
    return emit({"schema": SCHEMA, "drafts": prune(store)["drafts"], "status": status})


def cmd_save(directory: str, session_id: str, text: str) -> int:
    if not session_id:
        return emit({"error": "Missing draft session id"})
    store, status = read_store(directory)
    if store is None:
        return emit({"error": "Draft store is truncated or invalid", "recovery": "preserved"})
    if text.strip():
        store["drafts"][session_id] = {"text": text, "updatedAt": now_ms()}
    else:
        store["drafts"].pop(session_id, None)
    if not write_store(directory, store):
        return emit({"error": "Could not write the draft store"})
    return emit({"saved": True, "sessionId": session_id})


def cmd_delete(directory: str, session_id: str) -> int:
    return cmd_save(directory, session_id, "")


COMMANDS = {"load": (1, cmd_load), "save": (2, cmd_save), "delete": (2, cmd_delete)}


def main() -> int:
    argv = sys.argv[1:]
    if not argv or argv[0] not in COMMANDS:
        return emit({"error": "Unknown draft command"})
    command = argv[0]
    arity, handler = COMMANDS[command]
    args = argv[1:]
    if len(args) < arity:
        return emit({"error": "Missing arguments"})
    if command == "load":
        return handler(args[0])
    if command == "save":
        text = args[2] if len(args) > 2 else sys.stdin.read()
        return handler(args[0], args[1], text)
    return handler(args[0], args[1])


if __name__ == "__main__":
    sys.exit(main())
