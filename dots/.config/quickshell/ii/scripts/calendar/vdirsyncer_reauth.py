#!/usr/bin/env python3
"""Interactive Google Calendar OAuth reauthorization helper for vdirsyncer.

When a Google refresh token expires or is revoked (causing 'invalid_grant'
during vdirsyncer sync), this script provides a zero-terminal browser login.
It extracts credentials from vdirsyncer's configuration (falling back to
ii/.env), spins up a local loopback server, prompts the user in their default
browser via xdg-open, exchanges the authorization code for fresh tokens,
and atomically updates vdirsyncer's token file with safe permissions (0600).
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import html
import http.server
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_SCOPES = (
    "https://www.googleapis.com/auth/calendar "
    "https://www.googleapis.com/auth/calendar.events "
    "email profile"
)


def default_vdirsyncer_config() -> Path | None:
    configured = os.environ.get("VDIRSYNCER_CONFIG", "").strip()
    candidates = [
        Path(configured).expanduser() if configured else None,
        Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser() / "vdirsyncer" / "config",
        Path("~/.vdirsyncer/config").expanduser(),
    ]
    return next((candidate for candidate in candidates if candidate is not None and candidate.is_file()), None)


def parse_vdirsyncer_sections(path: Path) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current: dict[str, str] | None = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = sections.setdefault(line[1:-1].strip(), {})
            continue
        if current is None or "=" not in line:
            continue
        key, value = line.split("=", 1)
        current[key.strip()] = value.strip().strip('"').strip("'")
    return sections


def read_env_credentials() -> tuple[str, str]:
    env_path = Path(__file__).resolve().parents[2] / ".env"
    if not env_path.is_file():
        return "", ""
    client_id = ""
    client_secret = ""
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        k = key.strip()
        v = val.strip().strip('"').strip("'")
        if k in ("GOOGLE_CLIENT_ID", "GMAIL_CLIENT_ID") and not client_id:
            client_id = v
        elif k in ("GOOGLE_CLIENT_SECRET", "GMAIL_CLIENT_SECRET") and not client_secret:
            client_secret = v
    return client_id, client_secret


def get_vdirsyncer_google_credentials(config_path: Path | None = None) -> dict[str, Any]:
    cfg = config_path or default_vdirsyncer_config()
    token_file = Path("~/.vdirsyncer/google_calendar_token").expanduser()
    client_id = ""
    client_secret = ""

    if cfg and cfg.is_file():
        sections = parse_vdirsyncer_sections(cfg)
        for name, data in sections.items():
            if name.startswith("storage ") and data.get("type") == "google_calendar":
                if data.get("token_file"):
                    token_file = Path(os.path.expanduser(data["token_file"]))
                if data.get("client_id"):
                    client_id = data["client_id"]
                if data.get("client_secret"):
                    client_secret = data["client_secret"]
                break

    if not client_id or not client_secret:
        env_id, env_secret = read_env_credentials()
        client_id = client_id or env_id
        client_secret = client_secret or env_secret

    return {
        "config_path": cfg,
        "token_file": token_file,
        "client_id": client_id,
        "client_secret": client_secret,
    }


def write_atomic_token(token_file: Path, token_payload: dict[str, Any]) -> None:
    token_file.parent.mkdir(parents=True, exist_ok=True)
    tmp_file = token_file.parent / f".{token_file.name}.tmp.{os.getpid()}"
    serialized = json.dumps(token_payload, indent=2)
    tmp_file.write_text(serialized, encoding="utf-8")
    try:
        os.chmod(tmp_file, 0o600)
    except OSError:
        pass
    os.replace(tmp_file, token_file)


SUCCESS_HTML = b"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Google Calendar Connected</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #111318;
      color: #e2e2e9;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #1e2025;
      border-radius: 24px;
      padding: 48px;
      text-align: center;
      max-width: 440px;
      box-shadow: 0 16px 40px rgba(0,0,0,0.5);
    }
    .icon {
      font-size: 56px;
      margin-bottom: 16px;
      color: #a8c8ff;
    }
    h1 {
      font-size: 24px;
      margin: 0 0 12px;
      font-weight: 600;
    }
    p {
      color: #92959e;
      font-size: 15px;
      line-height: 1.5;
      margin: 0;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">&#10003;</div>
    <h1>Google Calendar Connected</h1>
    <p>Timetable synchronization with vdirsyncer was authorized successfully. You can close this tab now.</p>
  </div>
</body>
</html>
"""


def _error_html(msg: str) -> bytes:
    escaped = html.escape(msg)
    return f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Authentication Failed</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #111318;
      color: #e2e2e9;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }}
    .card {{
      background: #1e2025;
      border-radius: 24px;
      padding: 48px;
      text-align: center;
      max-width: 440px;
      box-shadow: 0 16px 40px rgba(0,0,0,0.5);
    }}
    .icon {{
      font-size: 56px;
      margin-bottom: 16px;
      color: #ffb4ab;
    }}
    h1 {{
      font-size: 24px;
      margin: 0 0 12px;
      font-weight: 600;
    }}
    p {{
      color: #92959e;
      font-size: 15px;
      line-height: 1.5;
      margin: 0;
    }}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">&#10007;</div>
    <h1>Authentication Failed</h1>
    <p>{escaped}</p>
  </div>
</body>
</html>""".encode("utf-8")


def notify_quickshell_ipc() -> None:
    shell_dir = Path(__file__).resolve().parents[2]
    try:
        subprocess.run(
            ["qs", "-c", str(shell_dir), "ipc", "call", "calendar", "onGoogleAuthComplete"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
    except Exception:
        pass


def run_reauth(
    client_id: str,
    client_secret: str,
    token_file: Path,
    port: int = 42072,
    scopes: str = DEFAULT_SCOPES,
) -> dict[str, Any]:
    if not client_id or not client_secret:
        return {
            "ok": False,
            "code": "missing_credentials",
            "error": "Google Client ID or Client Secret not found in vdirsyncer config or ii/.env",
        }

    redirect_uri = f"http://127.0.0.1:{port}/callback"
    code_verifier = secrets.token_urlsafe(64)
    code_challenge = (
        base64.urlsafe_b64encode(hashlib.sha256(code_verifier.encode("utf-8")).digest())
        .rstrip(b"=")
        .decode("utf-8")
    )

    auth_url = (
        f"https://accounts.google.com/o/oauth2/v2/auth"
        f"?client_id={urllib.parse.quote(client_id, safe='')}"
        f"&redirect_uri={urllib.parse.quote(redirect_uri, safe='')}"
        f"&response_type=code"
        f"&scope={urllib.parse.quote(scopes)}"
        f"&code_challenge={code_challenge}"
        f"&code_challenge_method=S256"
        f"&access_type=offline"
        f"&prompt=consent"
    )

    try:
        subprocess.Popen(
            ["xdg-open", auth_url],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception as exc:
        return {
            "ok": False,
            "code": "browser_error",
            "error": f"Failed to launch browser: {exc}",
            "auth_url": auth_url,
        }

    exchange_state: dict[str, Any] = {"done": False, "result": None}

    class CallbackHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: Any) -> None:
            pass

        def _send_page(self, status: int, content: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(content)
            self.wfile.flush()
            self.close_connection = True

        def do_GET(self) -> None:
            if self.path == "/favicon.ico":
                self.send_response(204)
                self.send_header("Connection", "close")
                self.end_headers()
                self.close_connection = True
                return

            if not self.path.startswith("/callback"):
                self._send_page(404, _error_html("Not found"))
                return

            params = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.path).query))
            code = params.get("code", "")
            error = params.get("error", "")

            if error:
                exchange_state["result"] = {
                    "ok": False,
                    "code": "denied",
                    "error": f"Google authorization denied: {error}",
                }
                exchange_state["done"] = True
                self._send_page(400, _error_html(f"Authorization denied: {error}"))
                return

            if not code:
                exchange_state["result"] = {
                    "ok": False,
                    "code": "missing_code",
                    "error": "No authorization code returned",
                }
                exchange_state["done"] = True
                self._send_page(400, _error_html("No authorization code returned"))
                return

            try:
                data = urllib.parse.urlencode({
                    "code": code,
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "redirect_uri": redirect_uri,
                    "grant_type": "authorization_code",
                    "code_verifier": code_verifier,
                }).encode("utf-8")

                req = urllib.request.Request(
                    "https://oauth2.googleapis.com/token",
                    data=data,
                    headers={"Content-Type": "application/x-www-form-urlencoded"},
                )
                with urllib.request.urlopen(req, timeout=30) as resp:
                    tokens = json.loads(resp.read().decode("utf-8"))

                refresh_token = str(tokens.get("refresh_token") or "")
                access_token = str(tokens.get("access_token") or "")
                expires_in = int(tokens.get("expires_in") or 3600)
                token_type = str(tokens.get("token_type") or "Bearer")

                if not refresh_token:
                    exchange_state["result"] = {
                        "ok": False,
                        "code": "missing_refresh_token",
                        "error": "Google did not return a refresh token. Revoke app access or retry.",
                    }
                    exchange_state["done"] = True
                    self._send_page(400, _error_html("Google did not return a refresh token."))
                    return

                email = ""
                try:
                    userinfo_req = urllib.request.Request(
                        "https://www.googleapis.com/oauth2/v2/userinfo",
                        headers={"Authorization": f"Bearer {access_token}"},
                    )
                    with urllib.request.urlopen(userinfo_req, timeout=10) as u_resp:
                        userinfo = json.loads(u_resp.read().decode("utf-8"))
                        email = str(userinfo.get("email") or "")
                except Exception:
                    pass

                vdirsyncer_token = {
                    "access_token": access_token,
                    "expires_in": expires_in,
                    "scope": ["https://www.googleapis.com/auth/calendar"],
                    "token_type": token_type,
                    "expires_at": time.time() + expires_in,
                    "refresh_token": refresh_token,
                }
                write_atomic_token(token_file, vdirsyncer_token)

                exchange_state["result"] = {
                    "ok": True,
                    "email": email,
                    "token_file": str(token_file),
                    "expires_in": expires_in,
                    "refresh_token": refresh_token,
                    "access_token": access_token,
                }
                exchange_state["done"] = True

                # Notify Quickshell IPC immediately so UI updates without delay
                notify_quickshell_ipc()

                # Send success page to the browser
                self._send_page(200, SUCCESS_HTML)

            except urllib.error.HTTPError as err:
                err_text = err.read().decode("utf-8", errors="ignore")
                msg = f"Token exchange failed ({err.code}): {err_text or err.reason}"
                exchange_state["result"] = {
                    "ok": False,
                    "code": "http_error",
                    "error": msg,
                }
                exchange_state["done"] = True
                self._send_page(400, _error_html(msg))
            except Exception as exc:
                msg = f"Token exchange error: {exc}"
                exchange_state["result"] = {
                    "ok": False,
                    "code": "token_exchange_failed",
                    "error": msg,
                }
                exchange_state["done"] = True
                self._send_page(400, _error_html(msg))

    http.server.HTTPServer.allow_reuse_address = True
    try:
        httpd = http.server.HTTPServer(("127.0.0.1", port), CallbackHandler)
    except Exception as exc:
        return {
            "ok": False,
            "code": "server_bind_error",
            "error": f"Failed to bind HTTP server on port {port}: {exc}",
        }

    httpd.timeout = 1.0
    start_time = time.time()
    # Wait at most 300 seconds for user to complete OAuth in browser
    while not exchange_state["done"] and (time.time() - start_time < 300):
        httpd.handle_request()

    try:
        httpd.server_close()
    except Exception:
        pass

    return exchange_state["result"] or {
        "ok": False,
        "code": "timeout",
        "error": "Google authorization timed out waiting for browser login",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Reauthorize Google Calendar for vdirsyncer")
    parser.add_argument("--port", type=int, default=42072, help="Local loopback port")
    parser.add_argument("--config", type=str, default="", help="Path to vdirsyncer config file")
    args = parser.parse_args()

    cfg_path = Path(args.config).expanduser() if args.config else None
    creds = get_vdirsyncer_google_credentials(cfg_path)
    result = run_reauth(
        client_id=creds["client_id"],
        client_secret=creds["client_secret"],
        token_file=creds["token_file"],
        port=args.port,
    )

    print(json.dumps(result, separators=(",", ":")), flush=True)
    sys.stdout.flush()
    sys.stderr.flush()
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
