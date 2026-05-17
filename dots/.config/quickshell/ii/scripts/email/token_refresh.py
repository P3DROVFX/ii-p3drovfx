#!/usr/bin/env python3
import sys, json, urllib.request, urllib.parse
import gmail_config

refresh_token = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read().strip()

try:
    access_token = gmail_config.refresh_token_exchange(refresh_token)
    print(json.dumps({
        "access_token": access_token,
        "expires_in":   3600
    }))
except Exception as e:
    sys.exit(1)