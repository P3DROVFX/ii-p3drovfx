import os
import json
import socket
import urllib.request
import urllib.parse
import urllib.error

# Force IPv4 preference to avoid hanging on networks where IPv6 is configured
# locally but has no route to Google endpoints (causing SYN_SENT hangs).
_orig_getaddrinfo = socket.getaddrinfo
def _ipv4_first_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    if family == 0 or family == socket.AF_UNSPEC:
        try:
            return _orig_getaddrinfo(host, port, socket.AF_INET, type, proto, flags)
        except Exception:
            pass
    return _orig_getaddrinfo(host, port, family, type, proto, flags)
socket.getaddrinfo = _ipv4_first_getaddrinfo

def _load_env():
    # .env is located in the shell root (two levels up from scripts/google)
    env_path = os.path.join(os.path.dirname(__file__), '..', '..', '.env')
    env = {}
    try:
        with open(os.path.realpath(env_path), 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    env[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    except Exception:
        pass
    return env

_env = _load_env()
CLIENT_ID = _env.get("GOOGLE_CLIENT_ID") or _env.get("GMAIL_CLIENT_ID") or ""
CLIENT_SECRET = _env.get("GOOGLE_CLIENT_SECRET") or _env.get("GMAIL_CLIENT_SECRET") or ""

def get_credentials():
    return CLIENT_ID, CLIENT_SECRET

def has_credentials():
    return bool(CLIENT_ID and CLIENT_SECRET)

def refresh_token_exchange(refresh_token):
    cid, sec = get_credentials()
    if not cid or not sec:
        raise Exception("Missing GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET in .env")

    data = urllib.parse.urlencode({
        "refresh_token": refresh_token,
        "client_id":     cid,
        "client_secret": sec,
        "grant_type":    "refresh_token",
    }).encode('utf-8')

    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = json.loads(resp.read().decode('utf-8'))
            return body
    except urllib.error.HTTPError as e:
        error_body = ""
        try:
            error_body = e.read().decode('utf-8')
            parsed = json.loads(error_body)
            err_code = parsed.get("error", "http_error")
            if err_code == "invalid_grant":
                raise ValueError("invalid_grant")
        except ValueError:
            raise
        except Exception:
            pass
        raise Exception(f"HTTP {e.code}: {e.reason}")

def resolve_token(token_or_refresh):
    """
    Returns an access token string.
    If input starts with 'ya29.', it's assumed to be a valid access token.
    Otherwise, it's treated as a refresh token and exchanged.
    """
    if token_or_refresh.startswith("ya29."):
        return token_or_refresh
    res = refresh_token_exchange(token_or_refresh)
    if isinstance(res, dict):
        return res.get("access_token", "")
    return str(res)
