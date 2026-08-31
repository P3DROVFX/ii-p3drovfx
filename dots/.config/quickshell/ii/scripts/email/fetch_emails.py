#!/usr/bin/env python3
"""Fetch Gmail messages for a given label. Handles token refresh internally.
Usage: fetch_emails.py <refresh_token> <label_id> [max_results]
Outputs JSON array of message objects to stdout.
"""
import sys, json, urllib.request, urllib.parse, concurrent.futures, re
import gmail_config

def api_get(url, token):
    try:
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8", errors="ignore"))
    except Exception:
        return {}

def fetch_detail(msg_id, token):
    url = f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{msg_id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date"
    detail = api_get(url, token)
    if not detail or "id" not in detail:
        return None
    headers = {h["name"]: h["value"] for h in detail.get("payload", {}).get("headers", [])}
    label_ids = detail.get("labelIds", [])
    subject = headers.get("Subject", "")
    sender  = headers.get("From", "")
    snippet = detail.get("snippet", "")
    return {
        "id":       detail["id"],
        "threadId": detail.get("threadId", ""),
        "subject":  subject or "(no subject)",
        "from":     sender,
        "date":     headers.get("Date", ""),
        "snippet":  snippet,
        "unread":   "UNREAD" in label_ids,
        "starred":  "STARRED" in label_ids,
        "labels":   label_ids,
        "timestamp": int(detail.get("internalDate", 0)) // 1000
    }

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"messages": [], "nextPageToken": "", "historyId": ""}))
        sys.exit(0)

    refresh_token = sys.argv[1]
    raw_label = sys.argv[2].strip()
    label_upper = raw_label.upper()
    max_results = int(sys.argv[3]) if len(sys.argv) > 3 else 50
    
    flags_arg = ""
    page_token = ""
    last_history_id = ""
    
    if label_upper == "INBOX":
        arg4 = sys.argv[4] if len(sys.argv) > 4 else ""
        if "," in arg4:
            flags_arg = arg4
            page_token = sys.argv[5] if len(sys.argv) > 5 else ""
            last_history_id = sys.argv[6] if len(sys.argv) > 6 else ""
        else:
            flags_arg = ""
            page_token = arg4
            last_history_id = sys.argv[5] if len(sys.argv) > 5 else ""
    else:
        page_token = sys.argv[4] if len(sys.argv) > 4 else ""
        last_history_id = sys.argv[5] if len(sys.argv) > 5 else ""

    try:
        token = gmail_config.resolve_token(refresh_token)
    except Exception:
        print(json.dumps({"messages": [], "nextPageToken": "", "historyId": ""}))
        sys.exit(1)

    profile = api_get("https://gmail.googleapis.com/gmail/v1/users/me/profile", token)
    current_history_id = profile.get("historyId", "")

    if last_history_id and last_history_id == current_history_id and not page_token:
        print(json.dumps({
            "messages": [], 
            "nextPageToken": "", 
            "historyId": current_history_id,
            "noChange": True
        }))
        return

    if last_history_id and not page_token:
        try:
            h_url = f"https://gmail.googleapis.com/gmail/v1/users/me/history?startHistoryId={last_history_id}&maxResults=100"
            history_data = api_get(h_url, token)
            if "history" not in history_data:
                print(json.dumps({
                    "messages": [], 
                    "nextPageToken": "", 
                    "historyId": current_history_id,
                    "noChange": True
                }))
                return
        except Exception:
            pass

    if label_upper == "INBOX":
        if flags_arg and "," in flags_arg:
            flags = flags_arg.split(",")
            # Only filter if user explicitly selected a custom subset of categories
            if len(flags) == 3 and not (flags[0] == flags[1] == flags[2]):
                cats = ["category:primary"]
                if flags[0] == "1": cats.append("category:updates")
                if flags[1] == "1": cats.append("category:promotions")
                if flags[2] == "1": cats.append("category:social")
                q_cats = "{" + " ".join(cats) + "}"
                q_param = f"in:inbox {q_cats}"
                query_params = f"q={urllib.parse.quote(q_param)}&maxResults={max_results}"
            else:
                # Default, all enabled (1,1,1) or all disabled (0,0,0 legacy) -> fetch all INBOX
                query_params = f"labelIds=INBOX&maxResults={max_results}"
        else:
            query_params = f"labelIds=INBOX&maxResults={max_results}"
    elif raw_label.upper().startswith("SEARCH:"):
        q = raw_label[7:]
        query_params = f"q={urllib.parse.quote(q)}&maxResults={max_results}"
    else:
        query_params = f"labelIds={label_upper}&maxResults={max_results}"

    if page_token:
        query_params += f"&pageToken={urllib.parse.quote(page_token)}"

    listing = api_get(
        f"https://gmail.googleapis.com/gmail/v1/users/me/messages?{query_params}",
        token
    )

    messages = listing.get("messages", [])
    next_page_token = listing.get("nextPageToken", "")

    if not messages:
        print(json.dumps({
            "messages": [], 
            "nextPageToken": next_page_token,
            "historyId": current_history_id
        }))
        return

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        futures = {pool.submit(fetch_detail, m["id"], token): i for i, m in enumerate(messages)}
        for future in concurrent.futures.as_completed(futures):
            try:
                res = future.result()
                if res is not None:
                    results.append((futures[future], res))
            except Exception:
                pass

    results.sort(key=lambda x: x[0])
    
    print(json.dumps({
        "messages": [r[1] for r in results],
        "nextPageToken": next_page_token,
        "historyId": current_history_id
    }))

if __name__ == "__main__":
    main()
