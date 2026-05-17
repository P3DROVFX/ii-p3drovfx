import os
import json
import urllib.request
import urllib.parse

def _load_env():
    # .env is in the parent directory of 'scripts', which is two levels up from 'scripts/email'
    # Actually, Directories.scriptPath is quickshell/ii/scripts
    # .env is in quickshell/ii/.env
    # So it's ../../.env from scripts/email/
    env_path = os.path.join(os.path.dirname(__file__), '..', '..', '.env')
    env = {}
    try:
        with open(os.path.realpath(env_path)) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    env[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return env

_env = _load_env()
CLIENT_ID = _env.get("GMAIL_CLIENT_ID")
CLIENT_SECRET = _env.get("GMAIL_CLIENT_SECRET")

def get_credentials():
    return CLIENT_ID, CLIENT_SECRET

def has_credentials():
    return bool(CLIENT_ID and CLIENT_SECRET)

def refresh_token_exchange(refresh_token):
    cid, sec = get_credentials()
    if not cid or not sec:
        raise Exception("Missing GMAIL_CLIENT_ID or GMAIL_CLIENT_SECRET in .env")
        
    data = urllib.parse.urlencode({
        "refresh_token": refresh_token,
        "client_id":     cid,
        "client_secret": sec,
        "grant_type":    "refresh_token",
    }).encode()
    
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())["access_token"]

def resolve_token(token_or_refresh):
    """
    Returns an access token. 
    If input starts with 'ya29.', it's assumed to be a valid access token.
    Otherwise, it's treated as a refresh token and exchanged.
    """
    if token_or_refresh.startswith("ya29."):
        return token_or_refresh
    return refresh_token_exchange(token_or_refresh)
