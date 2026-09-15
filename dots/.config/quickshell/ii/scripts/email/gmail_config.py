import os
import sys

# Ensure scripts/google is importable
_google_dir = os.path.realpath(os.path.join(os.path.dirname(__file__), '..', 'google'))
if _google_dir not in sys.path:
    sys.path.insert(0, _google_dir)

import google_config

CLIENT_ID, CLIENT_SECRET = google_config.get_credentials()

def get_credentials():
    return google_config.get_credentials()

def has_credentials():
    return google_config.has_credentials()

def refresh_token_exchange(refresh_token):
    res = google_config.refresh_token_exchange(refresh_token)
    if isinstance(res, dict):
        return res.get("access_token", "")
    return str(res)

def resolve_token(token_or_refresh):
    return google_config.resolve_token(token_or_refresh)
