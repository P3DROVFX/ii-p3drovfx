#!/usr/bin/env python3
"""Google Keep Workspace API Client (Trilha B).

Official Google Keep API integration for Google Workspace accounts.
Enforces the requirement that keep.googleapis.com only supports Google Workspace
enterprise/education accounts, not consumer @gmail.com accounts.

Usage:
  python3 keep_api.py detect-account
  python3 keep_api.py list
  python3 keep_api.py create --title "..." --text "..."
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# Try to find credentials from token file or environment
DEFAULT_TOKEN_FILE = Path(os.path.expanduser("~/.config/quickshell/ii/google_token.json"))


def emit(payload: dict) -> int:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    return 0 if payload.get("ok", True) else 1


def get_stored_token() -> str:
    """Retrieve OAuth access token if available."""
    token_from_env = os.getenv("GOOGLE_ACCESS_TOKEN", "")
    if token_from_env:
        return token_from_env

    candidates = [
        DEFAULT_TOKEN_FILE,
        Path(os.path.expanduser("~/.local/state/quickshell/user/google_token.json")),
        Path(os.path.expanduser("~/.config/google_token.json"))
    ]

    for p in candidates:
        if p.exists():
            try:
                data = json.loads(p.read_text(encoding="utf-8"))
                token = data.get("access_token") or data.get("token")
                if token:
                    return token
            except Exception:
                pass

    return ""


def detect_account_type(token: str) -> dict:
    """Check user identity and verify if the account is Google Workspace or consumer."""
    if not token:
        return {
            "ok": False,
            "error": "no_token",
            "message": "No Google access token. Connect the account in Settings, under Google accounts."
        }

    try:
        req = urllib.request.Request(
            "https://www.googleapis.com/oauth2/v2/userinfo",
            headers={"Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            info = json.loads(resp.read().decode("utf-8"))
            email = info.get("email", "").lower()
            hd = info.get("hd", "") # Hosted domain for Workspace accounts

            is_consumer = email.endswith("@gmail.com") or email.endswith("@googlemail.com") or not hd

            if is_consumer:
                return {
                    "ok": False,
                    "isWorkspace": False,
                    "email": email,
                    "error": "consumer_account_unsupported",
                    "message": "The official Google Keep API only works for Google Workspace accounts. A personal @gmail.com account cannot use it at all; import a Google Takeout archive instead, which the app can do."
                }

            return {
                "ok": True,
                "isWorkspace": True,
                "email": email,
                "domain": hd,
                "message": f"A Google Workspace account ({hd}). The official Keep API can be used."
            }

    except urllib.error.HTTPError as e:
        return {
            "ok": False,
            "error": f"http_{e.code}",
            "message": f"Google refused the request: {e.reason} (HTTP {e.code})."
        }
    except Exception as e:
        return {
            "ok": False,
            "error": "connection_error",
            "message": f"Could not reach Google: {str(e)}"
        }


def list_notes(token: str) -> dict:
    account_check = detect_account_type(token)
    if not account_check.get("ok"):
        return account_check

    try:
        req = urllib.request.Request(
            "https://keep.googleapis.com/v1/notes",
            headers={"Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return {
                "ok": True,
                "notes": data.get("notes", [])
            }
    except Exception as e:
        return {
            "ok": False,
            "error": "keep_api_error",
            "message": f"The Keep API call failed: {str(e)}"
        }


def create_note(token: str, title: str, text: str) -> dict:
    account_check = detect_account_type(token)
    if not account_check.get("ok"):
        return account_check

    payload = {
        "title": title,
        "body": {
            "text": {
                "text": text
            }
        }
    }

    try:
        req = urllib.request.Request(
            "https://keep.googleapis.com/v1/notes",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json"
            }
        )
        with urllib.request.urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return {
                "ok": True,
                "note": data
            }
    except Exception as e:
        return {
            "ok": False,
            "error": "keep_api_error",
            "message": f"The note could not be created in Google Keep: {str(e)}"
        }


def main() -> int:
    parser = argparse.ArgumentParser(description="Google Keep Workspace API")
    parser.add_argument("action", choices=["detect-account", "list", "create"], help="What to do")
    parser.add_argument("--token", type=str, default="", help="OAuth access token")
    parser.add_argument("--title", type=str, default="", help="Note title")
    parser.add_argument("--text", type=str, default="", help="Note body text")

    args = parser.parse_args()
    token = args.token or get_stored_token()

    if args.action == "detect-account":
        return emit(detect_account_type(token))
    elif args.action == "list":
        return emit(list_notes(token))
    elif args.action == "create":
        return emit(create_note(token, args.title, args.text))

    return emit({"ok": False, "error": "unknown_action"})


if __name__ == "__main__":
    sys.exit(main())
