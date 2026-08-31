#!/usr/bin/env python3
"""Return bounded Outlook ICS attachments without exposing message content to QML."""

from __future__ import annotations

import base64
import hashlib
import json
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


GRAPH_ROOT = "https://graph.microsoft.com/v1.0"
MAX_MESSAGES = 50
MAX_ATTACHMENTS = 20
MAX_ATTACHMENT_BYTES = 512 * 1024
TIMEOUT_SECONDS = 20


class AttachmentScanError(RuntimeError):
    """A safe error string for the sources rail."""


def graph_get(url: str, access_token: str) -> dict[str, Any]:
    request = Request(url, headers={"Authorization": "Bearer " + access_token})
    try:
        with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        try:
            payload = json.loads(error.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            payload = {}
        message = str(payload.get("error", {}).get("message") or f"Microsoft Graph returned HTTP {error.code}.")
        raise AttachmentScanError(message) from error
    except (URLError, OSError) as error:
        raise AttachmentScanError(f"Microsoft Graph is unavailable: {error}.") from error
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AttachmentScanError(f"Microsoft Graph returned invalid JSON: {error}.") from error
    if not isinstance(payload, dict):
        raise AttachmentScanError("Microsoft Graph returned an invalid response.")
    return payload


def is_ics_attachment(attachment: dict[str, Any]) -> bool:
    """Recognise ordinary non-inline iCalendar file attachments only."""
    if bool(attachment.get("isInline")):
        return False
    kind = str(attachment.get("@odata.type") or "").lower()
    if kind and not kind.endswith("fileattachment"):
        return False
    filename = str(attachment.get("name") or "").lower()
    content_type = str(attachment.get("contentType") or "").lower().split(";", 1)[0].strip()
    return filename.endswith((".ics", ".ical")) or content_type in {"text/calendar", "application/ics", "text/x-vcalendar"}


def bounded_ics_base64(value: Any) -> str:
    encoded = str(value or "").strip()
    if not encoded:
        return ""
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, TypeError):
        return ""
    if not raw or len(raw) > MAX_ATTACHMENT_BYTES:
        return ""
    return base64.b64encode(raw).decode("ascii")


def candidate_for_attachment(message_id: str, attachment: dict[str, Any]) -> dict[str, str] | None:
    if not is_ics_attachment(attachment):
        return None
    attachment_id = str(attachment.get("id") or "").strip()
    contents = bounded_ics_base64(attachment.get("contentBytes"))
    if not message_id or not attachment_id or not contents:
        return None
    digest = hashlib.sha256(base64.b64decode(contents)).hexdigest()[:24]
    return {
        "key": message_id + "|" + attachment_id + "|" + digest,
        "icsBase64": contents,
    }


def list_messages(access_token: str, maximum: int) -> list[dict[str, Any]]:
    query = urlencode({"$select": "id,hasAttachments", "$filter": "hasAttachments eq true", "$top": str(maximum)})
    response = graph_get(GRAPH_ROOT + "/me/messages?" + query, access_token)
    messages = response.get("value") or []
    if not isinstance(messages, list):
        raise AttachmentScanError("Microsoft Graph returned an invalid message list.")
    return [item for item in messages if isinstance(item, dict) and bool(item.get("hasAttachments"))]


def list_attachments(access_token: str, message_id: str) -> list[dict[str, Any]]:
    safe_message_id = quote(message_id, safe="")
    query = urlencode({"$select": "id,name,contentType,size,isInline,@odata.type"})
    response = graph_get(GRAPH_ROOT + "/me/messages/" + safe_message_id + "/attachments?" + query, access_token)
    attachments = response.get("value") or []
    if not isinstance(attachments, list):
        raise AttachmentScanError("Microsoft Graph returned an invalid attachment list.")
    return [item for item in attachments if isinstance(item, dict)]


def get_attachment(access_token: str, message_id: str, attachment_id: str) -> dict[str, Any]:
    safe_message_id = quote(message_id, safe="")
    safe_attachment_id = quote(attachment_id, safe="")
    query = urlencode({"$select": "id,name,contentType,size,isInline,@odata.type,contentBytes"})
    return graph_get(GRAPH_ROOT + "/me/messages/" + safe_message_id + "/attachments/" + safe_attachment_id + "?" + query, access_token)


def discover(access_token: str, maximum_messages: int) -> list[dict[str, str]]:
    candidates: list[dict[str, str]] = []
    for message in list_messages(access_token, maximum_messages):
        message_id = str(message.get("id") or "")
        if not message_id:
            continue
        for metadata in list_attachments(access_token, message_id):
            if len(candidates) >= MAX_ATTACHMENTS or not is_ics_attachment(metadata):
                continue
            size = int(metadata.get("size") or 0)
            if size <= 0 or size > MAX_ATTACHMENT_BYTES:
                continue
            attachment_id = str(metadata.get("id") or "")
            if not attachment_id:
                continue
            candidate = candidate_for_attachment(message_id, get_attachment(access_token, message_id, attachment_id))
            if candidate is not None:
                candidates.append(candidate)
        if len(candidates) >= MAX_ATTACHMENTS:
            break
    return candidates


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
        if not isinstance(payload, dict):
            raise AttachmentScanError("Outlook attachment request must be an object.")
        token = str(payload.get("accessToken") or "").strip()
        if not token:
            raise AttachmentScanError("Microsoft authorization is unavailable.")
        maximum = max(1, min(MAX_MESSAGES, int(payload.get("maxMessages") or 25)))
        print(json.dumps({"ok": True, "candidates": discover(token, maximum)}))
        return 0
    except (AttachmentScanError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
