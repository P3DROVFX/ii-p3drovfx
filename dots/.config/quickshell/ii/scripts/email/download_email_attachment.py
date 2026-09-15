#!/usr/bin/env python3
import sys, json, base64, os, urllib.request, urllib.parse
import gmail_config

def main():
    if len(sys.argv) < 5:
        print(json.dumps({"error": "Missing args."}))
        return

    refresh_token = sys.argv[1]
    message_id = sys.argv[2]
    attachment_id = sys.argv[3]
    filename = sys.argv[4]

    try:
        token = gmail_config.resolve_token(refresh_token)
        url = f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{message_id}/attachments/{attachment_id}"
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            b64_data = data.get("data", "")
            
            padded = b64_data.replace("-", "+").replace("_", "/")
            padded += "=" * (4 - len(padded) % 4)
            raw_bytes = base64.b64decode(padded)
            
            # Default to ~/Downloads, but allow custom dir
            target_dir = sys.argv[5] if len(sys.argv) > 5 else os.path.expanduser("~/Downloads")
            os.makedirs(target_dir, exist_ok=True)
            
            base, ext = os.path.splitext(filename)
            counter = 1
            final_path = os.path.join(target_dir, filename)
            while os.path.exists(final_path):
                final_path = os.path.join(target_dir, f"{base} ({counter}){ext}")
                counter += 1
                
            with open(final_path, "wb") as f:
                f.write(raw_bytes)
                
            print(json.dumps({"success": True, "path": final_path, "attachmentId": attachment_id}))
            
    except Exception as e:
        print(json.dumps({"error": str(e), "attachmentId": attachment_id}))

if __name__ == "__main__":
    main()
