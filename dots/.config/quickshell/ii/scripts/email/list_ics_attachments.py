#!/usr/bin/env python3
"""List bounded ICS attachments from the active Gmail account as JSON.

The script deliberately returns only attachment identity and base64 calendar
bytes. It never returns message bodies, headers, snippets, or sender data.
"""

from __future__ import annotations

import base64
import hashlib
import json
import sys
import urllib.parse
import urllib.request
from collections.abc import Iterator
from typing import Any

import gmail_config


MAX_MESSAGES = 50
MAX_CANDIDATES = 20
MAX_ATTACHMENT_BYTES = 512 * 1024
CALENDAR_MIME_TYPES = {"text/calendar", "application/ics", "text/icalendar"}


def api_get(url: str, token: str) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read())


def decode_base64url(value: str) -> bytes:
    padded = value + "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii"))


def is_ics_part(part: dict[str, Any]) -> bool:
    name = str(part.get("filename") or "").lower()
    mime_type = str(part.get("mimeType") or "").lower()
    return mime_type in CALENDAR_MIME_TYPES or name.endswith((".ics", ".ical"))


def iter_ics_parts(payload: dict[str, Any]) -> Iterator[tuple[int, dict[str, Any]]]:
    index = 0

    def walk(part: dict[str, Any]) -> Iterator[tuple[int, dict[str, Any]]]:
        nonlocal index
        current = index
        index += 1
        if is_ics_part(part):
            yield current, part
        for child in part.get("parts") or []:
            if isinstance(child, dict):
                yield from walk(child)

    yield from walk(payload)


def candidate_for_part(message_id: str, index: int, part: dict[str, Any], raw: bytes) -> dict[str, str]:
    attachment_id = str((part.get("body") or {}).get("attachmentId") or "inline:" + str(index))
    digest = hashlib.sha256(raw).hexdigest()
    return {
        "key": str(message_id) + ":" + attachment_id + ":" + digest,
        "icsBase64": base64.urlsafe_b64encode(raw).decode("ascii"),
    }


def part_bytes(token: str, message_id: str, part: dict[str, Any]) -> bytes:
    body = part.get("body") or {}
    declared_size = int(body.get("size") or 0)
    if declared_size > MAX_ATTACHMENT_BYTES:
        return b""
    inline = str(body.get("data") or "")
    if inline:
        raw = decode_base64url(inline)
    else:
        attachment_id = str(body.get("attachmentId") or "")
        if not attachment_id:
            return b""
        attachment_url = "https://gmail.googleapis.com/gmail/v1/users/me/messages/{}/attachments/{}".format(
            urllib.parse.quote(message_id, safe=""), urllib.parse.quote(attachment_id, safe="")
        )
        raw = decode_base64url(str(api_get(attachment_url, token).get("data") or ""))
    return raw if 0 < len(raw) <= MAX_ATTACHMENT_BYTES else b""


def discover(token: str, max_messages: int) -> list[dict[str, str]]:
    query = urllib.parse.urlencode({
        "q": "in:anywhere {filename:ics filename:ical}",
        "maxResults": max(1, min(MAX_MESSAGES, max_messages)),
    })
    listing = api_get("https://gmail.googleapis.com/gmail/v1/users/me/messages?" + query, token)
    candidates: list[dict[str, str]] = []
    for message in listing.get("messages") or []:
        if len(candidates) >= MAX_CANDIDATES:
            break
        message_id = str(message.get("id") or "")
        if not message_id:
            continue
        detail_url = "https://gmail.googleapis.com/gmail/v1/users/me/messages/{}?format=full".format(
            urllib.parse.quote(message_id, safe="")
        )
        payload = api_get(detail_url, token).get("payload") or {}
        for index, part in iter_ics_parts(payload):
            raw = part_bytes(token, message_id, part)
            if raw:
                candidates.append(candidate_for_part(message_id, index, part, raw))
            if len(candidates) >= MAX_CANDIDATES:
                break
    return candidates


def main() -> int:
    token_source = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        requested_max = int(sys.argv[2]) if len(sys.argv) > 2 else 25
        token = gmail_config.resolve_token(token_source)
        if not token:
            raise ValueError("missing token")
        print(json.dumps({"ok": True, "candidates": discover(token, requested_max)}))
    except Exception:
        # Do not surface API response bodies or token-adjacent details to QML.
        print(json.dumps({"ok": False, "error": "Could not check Gmail calendar attachments."}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
