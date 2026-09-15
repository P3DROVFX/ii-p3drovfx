#!/usr/bin/env python3
import http.server
import urllib.parse
import urllib.request
import urllib.error
import subprocess
import json
import secrets
import hashlib
import base64
import sys
import argparse
import google_config

def main():
    parser = argparse.ArgumentParser(description="Google OAuth desktop authorization flow")
    parser.add_argument("--scope", default="https://www.googleapis.com/auth/tasks email profile", help="OAuth scopes")
    parser.add_argument("--port", type=int, default=42070, help="Local callback port")
    args = parser.parse_args()

    client_id, client_secret = google_config.get_credentials()
    if not client_id or not client_secret:
        print(json.dumps({
            "ok": False,
            "code": "credentials_missing",
            "message": "Google Client ID or Client Secret not configured in .env"
        }), flush=True)
        sys.exit(1)

    port = args.port
    redirect_uri = f"http://localhost:{port}/callback"

    # PKCE
    code_verifier = secrets.token_urlsafe(64)
    code_challenge = base64.urlsafe_b64encode(
        hashlib.sha256(code_verifier.encode('utf-8')).digest()
    ).rstrip(b"=").decode('utf-8')

    auth_url = (
        f"https://accounts.google.com/o/oauth2/v2/auth"
        f"?client_id={urllib.parse.quote(client_id, safe='')}"
        f"&redirect_uri={urllib.parse.quote(redirect_uri, safe='')}"
        f"&response_type=code"
        f"&scope={urllib.parse.quote(args.scope)}"
        f"&code_challenge={code_challenge}"
        f"&code_challenge_method=S256"
        f"&access_type=offline"
        f"&prompt=consent"
    )

    try:
        subprocess.Popen(["xdg-open", auth_url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        print(json.dumps({
            "ok": False,
            "code": "browser_launch_failed",
            "message": f"Failed to launch browser with xdg-open: {e}",
            "auth_url": auth_url
        }), flush=True)
        sys.exit(1)

    result = {
        "done": False,
        "output": None
    }

    class CallbackHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass  # Suppress default server logs on stdout/stderr

        def do_GET(self):
            # Respond immediately to browser to prevent timeout
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Authorized</title></head>
<body style="font-family:sans-serif;text-align:center;padding:60px;background:#1a1a24;color:#e2e2ec">
  <h2>Google Authorization Successful</h2>
  <p>You can close this tab and return to the shell.</p>
</body>
</html>""")
            self.wfile.flush()

            if not self.path.startswith("/callback"):
                return

            params = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(self.path).query))
            code = params.get("code", "")
            error = params.get("error", "")

            if error:
                result["output"] = {
                    "ok": False,
                    "code": "authorization_denied",
                    "message": f"Authorization was denied or canceled: {error}"
                }
                result["done"] = True
                return

            if not code:
                result["output"] = {
                    "ok": False,
                    "code": "missing_code",
                    "message": "No authorization code returned from callback"
                }
                result["done"] = True
                return

            # Exchange code for tokens
            try:
                data = urllib.parse.urlencode({
                    "code": code,
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "redirect_uri": redirect_uri,
                    "grant_type": "authorization_code",
                    "code_verifier": code_verifier,
                }).encode('utf-8')

                req = urllib.request.Request(
                    "https://oauth2.googleapis.com/token",
                    data=data,
                    headers={"Content-Type": "application/x-www-form-urlencoded"}
                )

                with urllib.request.urlopen(req) as resp:
                    tokens = json.loads(resp.read().decode('utf-8'))
            except urllib.error.HTTPError as e:
                err_body = e.read().decode('utf-8', errors='ignore')
                result["output"] = {
                    "ok": False,
                    "code": "token_exchange_failed",
                    "http_status": e.code,
                    "message": f"Token exchange failed: {e.reason}"
                }
                result["done"] = True
                return
            except Exception as e:
                result["output"] = {
                    "ok": False,
                    "code": "network_error",
                    "message": f"Failed to exchange token: {e}"
                }
                result["done"] = True
                return

            refresh_token = tokens.get("refresh_token", "")
            access_token = tokens.get("access_token", "")
            expires_in = tokens.get("expires_in", 3600)
            token_scope = tokens.get("scope", "")

            if not refresh_token:
                result["output"] = {
                    "ok": False,
                    "code": "missing_refresh_token",
                    "message": "Google did not return a refresh token. Revoke access at https://myaccount.google.com/permissions and retry with prompt=consent."
                }
                result["done"] = True
                return

            # Fetch user email and avatar
            email = ""
            picture = ""
            try:
                userinfo_req = urllib.request.Request(
                    "https://www.googleapis.com/oauth2/v2/userinfo",
                    headers={"Authorization": f"Bearer {access_token}"}
                )
                with urllib.request.urlopen(userinfo_req) as resp:
                    userinfo = json.loads(resp.read().decode('utf-8'))
                    email = userinfo.get("email", "")
                    picture = userinfo.get("picture", "")
            except Exception:
                pass

            result["output"] = {
                "ok": True,
                "refresh_token": refresh_token,
                "access_token": access_token,
                "expires_in": expires_in,
                "scope": token_scope,
                "email": email,
                "picture": picture
            }
            result["done"] = True

    http.server.HTTPServer.allow_reuse_address = True
    try:
        httpd = http.server.HTTPServer(("localhost", port), CallbackHandler)
    except Exception as e:
        print(json.dumps({
            "ok": False,
            "code": "port_binding_failed",
            "message": f"Failed to bind local server on port {port}: {e}"
        }), flush=True)
        sys.exit(1)

    while not result["done"]:
        httpd.handle_request()

    httpd.server_close()

    if result["output"]:
        print(json.dumps(result["output"]), flush=True)
        sys.exit(0 if result["output"].get("ok") else 1)
    else:
        print(json.dumps({
            "ok": False,
            "code": "unknown_error",
            "message": "Authorization ended without output"
        }), flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
