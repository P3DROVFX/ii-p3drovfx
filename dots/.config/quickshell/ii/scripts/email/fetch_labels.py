#!/usr/bin/env python3
import sys, json, urllib.request, concurrent.futures
import gmail_config

def api_get(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

def fetch_label_detail(label_id, token):
    url = f"https://gmail.googleapis.com/gmail/v1/users/me/labels/{label_id}"
    return api_get(url, token)

def main():
    if len(sys.argv) < 2:
        print("{}")
        sys.exit(0)

    refresh_token = sys.argv[1]
    enabled_labels = sys.argv[2].split(",") if len(sys.argv) > 2 and sys.argv[2] else []

    try:
        token = gmail_config.resolve_token(refresh_token)
    except Exception:
        print("{}")
        sys.exit(1)

    try:
        listing = api_get("https://gmail.googleapis.com/gmail/v1/users/me/labels", token)
        labels = listing.get("labels", [])
        
        # We only need to fetch details for "user" labels that are enabled
        # AND system labels that are used in the app
        target_system_labels = {"INBOX", "SPAM", "SENT", "TRASH", "STARRED", "IMPORTANT", "CATEGORY_PURCHASES"}
        target_labels = [lbl for lbl in labels if (lbl.get("type") == "user" and lbl.get("id") in enabled_labels) or lbl.get("id") in target_system_labels]
        
        if target_labels:
            with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
                futures = {pool.submit(fetch_label_detail, lbl["id"], token): lbl for lbl in target_labels}
                for future in concurrent.futures.as_completed(futures):
                    lbl_ref = futures[future]
                    try:
                        detail = future.result()
                        lbl_ref["messagesUnread"] = detail.get("messagesUnread", 0)
                    except Exception:
                        lbl_ref["messagesUnread"] = 0
                        
        print(json.dumps({"labels": labels}))
    except Exception as e:
        print("{}")

if __name__ == "__main__":
    main()
