#!/usr/bin/env python3
import sys
import json
import google_config

def main():
    refresh_token = ""
    if len(sys.argv) > 1 and sys.argv[1].strip():
        refresh_token = sys.argv[1].strip()
    else:
        refresh_token = sys.stdin.read().strip()

    if not refresh_token:
        print(json.dumps({
            "ok": False,
            "code": "missing_refresh_token",
            "message": "No refresh token provided"
        }), flush=True)
        sys.exit(1)

    try:
        data = google_config.refresh_token_exchange(refresh_token)
        access_token = data.get("access_token") if isinstance(data, dict) else str(data)
        expires_in = data.get("expires_in", 3600) if isinstance(data, dict) else 3600
        scope = data.get("scope", "") if isinstance(data, dict) else ""
        print(json.dumps({
            "ok": True,
            "access_token": access_token,
            "expires_in": expires_in,
            "scope": scope
        }), flush=True)
        sys.exit(0)
    except ValueError as e:
        if str(e) == "invalid_grant":
            print(json.dumps({
                "ok": False,
                "code": "invalid_grant",
                "reauthorization_required": True,
                "message": "The authorization has been revoked or expired. Reauthorization required."
            }), flush=True)
            sys.exit(1)
        print(json.dumps({
            "ok": False,
            "code": "token_refresh_failed",
            "message": str(e)
        }), flush=True)
        sys.exit(1)
    except Exception as e:
        print(json.dumps({
            "ok": False,
            "code": "token_refresh_failed",
            "message": str(e)
        }), flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
