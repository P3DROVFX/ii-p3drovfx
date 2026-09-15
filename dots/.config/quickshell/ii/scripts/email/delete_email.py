#!/usr/bin/env python3
import sys, urllib.request, json, os
# Add current directory to path so gmail_config can be imported
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import gmail_config

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"success": False, "error": "Usage: delete_email.py <refresh_token> <message_id> [mode=trash|permanent]"}))
        sys.exit(1)

    refresh_token = sys.argv[1]
    message_id = sys.argv[2]
    mode = sys.argv[3] if len(sys.argv) > 3 else "trash"

    log_path = os.path.expanduser("~/.cache/quickshell-gmail/delete.log")
    try:
        with open(log_path, "a") as log:
            log.write(f"--- Delete Attempt: {mode} {message_id} ---\n")
            
            try:
                token = gmail_config.resolve_token(refresh_token)
                log.write("Token resolved\n")
            except Exception as e:
                log.write(f"Token error: {str(e)}\n")
                print(json.dumps({"success": False, "error": f"Token error: {str(e)}"}))
                sys.exit(1)

            if mode == "trash":
                url = f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{message_id}/trash"
                method = "POST"
            elif mode == "untrash":
                url = f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{message_id}/untrash"
                method = "POST"
            else:
                url = f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{message_id}"
                method = "DELETE"

            log.write(f"Request: {method} {url}\n")
            req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {token}"})
            try:
                with urllib.request.urlopen(req) as resp:
                    log.write(f"Response code: {resp.getcode()}\n")
                    print(json.dumps({"success": True}))
            except urllib.error.HTTPError as e:
                body = e.read().decode()
                log.write(f"HTTP Error {e.code}: {body}\n")
                print(json.dumps({"success": False, "error": f"HTTP {e.code}: {body}"}))
            except Exception as e:
                log.write(f"Error: {str(e)}\n")
                print(json.dumps({"success": False, "error": str(e)}))
    except Exception as e:
        print(json.dumps({"success": False, "error": f"Log error: {str(e)}"}))

if __name__ == "__main__":
    main()
