#!/usr/bin/env python3
"""Microsoft Entra device-code and refresh-token bridge.

The desktop shell is a public client: it stores only the user-provided app id
and its refresh token in the keyring, never a client secret.  Every command
receives its sensitive input as JSON on stdin and writes one JSON reply.
"""

from __future__ import annotations

import json
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


AUTHORITY = "https://login.microsoftonline.com/common/oauth2/v2.0"
DEFAULT_SCOPES = ("offline_access", "User.Read", "Calendars.Read", "Mail.Read")
TIMEOUT_SECONDS = 20


def _message(payload: dict[str, Any], fallback: str) -> str:
    return str(payload.get("error_description") or payload.get("message") or payload.get("error") or fallback)


def form_post(endpoint: str, values: dict[str, str]) -> dict[str, Any]:
    """POST form data and normalise Microsoft OAuth errors for QML."""
    request = Request(
        endpoint,
        data=urlencode(values).encode("utf-8"),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            parsed = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        try:
            parsed = json.loads(error.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            parsed = {}
        return {
            "ok": False,
            "code": str(parsed.get("error") or "http_error"),
            "message": _message(parsed, f"Microsoft authorization returned HTTP {error.code}."),
            "httpStatus": error.code,
        }
    except (URLError, OSError) as error:
        return {"ok": False, "code": "network_error", "message": f"Microsoft authorization is unavailable: {error}."}
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        return {"ok": False, "code": "parse_error", "message": f"Microsoft authorization returned invalid JSON: {error}."}
    if "error" in parsed:
        return {"ok": False, "code": str(parsed.get("error")), "message": _message(parsed, "Microsoft authorization failed.")}
    return {"ok": True, "data": parsed}


def _client_id(payload: dict[str, Any]) -> str:
    client_id = str(payload.get("clientId") or "").strip()
    if not client_id:
        raise ValueError("Enter a Microsoft application (client) ID first.")
    if len(client_id) > 200 or any(character.isspace() for character in client_id):
        raise ValueError("Microsoft application ID is invalid.")
    return client_id


def _scopes(payload: dict[str, Any]) -> str:
    configured = payload.get("scopes")
    values = configured if isinstance(configured, list) else DEFAULT_SCOPES
    scopes = [str(value).strip() for value in values if str(value).strip()]
    required = [scope for scope in DEFAULT_SCOPES if scope not in scopes]
    return " ".join(scopes + required)


def device_code(payload: dict[str, Any]) -> dict[str, Any]:
    reply = form_post(f"{AUTHORITY}/devicecode", {"client_id": _client_id(payload), "scope": _scopes(payload)})
    if not reply["ok"]:
        return reply
    data = reply["data"]
    return {
        "ok": True,
        "deviceCode": str(data.get("device_code") or ""),
        "userCode": str(data.get("user_code") or ""),
        "verificationUri": str(data.get("verification_uri") or ""),
        "message": str(data.get("message") or ""),
        "expiresIn": int(data.get("expires_in") or 900),
        "interval": max(2, int(data.get("interval") or 5)),
    }


def token_for_device_code(payload: dict[str, Any]) -> dict[str, Any]:
    device = str(payload.get("deviceCode") or "").strip()
    if not device:
        raise ValueError("Microsoft device authorization is missing.")
    reply = form_post(f"{AUTHORITY}/token", {
        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        "client_id": _client_id(payload),
        "device_code": device,
    })
    if not reply["ok"]:
        return reply
    return token_reply(reply["data"])


def refresh(payload: dict[str, Any]) -> dict[str, Any]:
    refresh_token = str(payload.get("refreshToken") or "").strip()
    if not refresh_token:
        raise ValueError("Microsoft refresh token is missing.")
    reply = form_post(f"{AUTHORITY}/token", {
        "grant_type": "refresh_token",
        "client_id": _client_id(payload),
        "refresh_token": refresh_token,
        "scope": _scopes(payload),
    })
    if not reply["ok"]:
        return reply
    return token_reply(reply["data"])


def token_reply(data: dict[str, Any]) -> dict[str, Any]:
    access_token = str(data.get("access_token") or "")
    if not access_token:
        return {"ok": False, "code": "missing_access_token", "message": "Microsoft authorization did not return an access token."}
    return {
        "ok": True,
        "accessToken": access_token,
        "refreshToken": str(data.get("refresh_token") or ""),
        "expiresIn": max(60, int(data.get("expires_in") or 3600)),
        "scope": str(data.get("scope") or ""),
    }


def read_payload() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        raise ValueError("Expected a JSON authorization request on stdin.")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("Authorization request must be an object.")
    return payload


def main() -> int:
    try:
        command = sys.argv[1] if len(sys.argv) == 2 else ""
        payload = read_payload()
        handlers = {"device-code": device_code, "poll": token_for_device_code, "refresh": refresh}
        if command not in handlers:
            raise ValueError("Unknown Microsoft authorization command.")
        print(json.dumps(handlers[command](payload)))
        return 0
    except (ValueError, TypeError, json.JSONDecodeError) as error:
        print(json.dumps({"ok": False, "code": "invalid_request", "message": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
