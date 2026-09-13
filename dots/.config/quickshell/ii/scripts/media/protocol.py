#!/usr/bin/env python3
"""Versioned JSON-lines protocol shared by QML and the local-media helper."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Mapping


PROTOCOL_VERSION = 1
# The protocol remains at version one because Phase 2 extends the same
# session-oriented contract introduced in Phase 0.  The helper rejects every
# operation outside this allow-list; a UI from a newer shell can therefore
# fail safely against an older helper instead of silently driving mpv with an
# ambiguous payload.
LOCAL_PLAYER_OPERATIONS = frozenset({
    "ping",
    "snapshot",
    "open",
    "play",
    "pause",
    "playPause",
    "stop",
    "next",
    "previous",
    "seek",
    "seekRelative",
    "setPosition",
    "setVolume",
    "setLoopStatus",
    "setRate",
    "setShuffle",
    "append",
    "playEntry",
    "moveEntry",
    "removeEntries",
    "clearFuture",
    "openUri",
    "sort",
    "sortQueue",
    "setCrossfade",
    "shutdown",
})

# Kept as an alias for the Phase-0 tests and any local tooling that imported
# the old name.  It no longer describes the complete helper capability.
PHASE0_OPERATIONS = LOCAL_PLAYER_OPERATIONS


class ProtocolError(ValueError):
    """A client-visible protocol failure with a stable machine-readable code."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class Request:
    request_id: str
    operation: str
    payload: dict[str, Any]
    session_id: str | None = None


def _string_field(payload: Mapping[str, Any], name: str, *, required: bool = True) -> str | None:
    value = payload.get(name)
    if value is None and not required:
        return None
    if not isinstance(value, str) or not value.strip():
        raise ProtocolError("invalidRequest", f"{name} must be a non-empty string")
    return value


def decode_request(line: str) -> Request:
    """Decode exactly one JSONL request without accepting ambiguous shapes."""

    try:
        raw = json.loads(line)
    except json.JSONDecodeError as error:
        raise ProtocolError("malformedJson", "request must be valid JSON") from error

    if not isinstance(raw, dict):
        raise ProtocolError("invalidRequest", "request must be a JSON object")
    if raw.get("protocolVersion") != PROTOCOL_VERSION:
        raise ProtocolError("unsupportedProtocol", f"expected protocolVersion {PROTOCOL_VERSION}")

    request_id = _string_field(raw, "requestId")
    operation = _string_field(raw, "op")
    session_id = _string_field(raw, "sessionId", required=False)
    payload = raw.get("payload", {})
    if not isinstance(payload, dict):
        raise ProtocolError("invalidRequest", "payload must be a JSON object")

    return Request(
        request_id=request_id,
        operation=operation,
        payload=dict(payload),
        session_id=session_id,
    )


def response(request: Request, payload: Mapping[str, Any] | None = None) -> dict[str, Any]:
    return {
        "protocolVersion": PROTOCOL_VERSION,
        "requestId": request.request_id,
        "ok": True,
        "payload": dict(payload or {}),
    }


def error_response(
    request_id: str | None,
    code: str,
    message: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "protocolVersion": PROTOCOL_VERSION,
        "ok": False,
        "error": {"code": code, "message": message},
    }
    if request_id:
        result["requestId"] = request_id
    return result


def event(name: str, payload: Mapping[str, Any] | None = None) -> dict[str, Any]:
    if not isinstance(name, str) or not name:
        raise ValueError("event name must be a non-empty string")
    return {
        "protocolVersion": PROTOCOL_VERSION,
        "event": name,
        "payload": dict(payload or {}),
    }


def encode(message: Mapping[str, Any]) -> str:
    """Produce one compact, UTF-8-safe JSONL record for stdout or a socket."""

    return json.dumps(dict(message), ensure_ascii=False, separators=(",", ":"))
