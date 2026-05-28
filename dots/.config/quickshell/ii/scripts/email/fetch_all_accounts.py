#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.parse
import concurrent.futures
import gmail_config

def api_get(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

def fetch_detail(msg_id, token, account_email):
    url = f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{msg_id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date"
    detail = api_get(url, token)
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
        "timestamp": int(detail.get("internalDate", 0)) // 1000,
        "account":  account_email
    }

def fetch_account_inbox(account, max_results):
    email = account.get("email")
    refresh_token = account.get("refreshToken")
    
    try:
        token = gmail_config.resolve_token(refresh_token)
        
        q_param = "in:inbox {category:primary category:updates category:promotions category:social}"
        query_params = f"q={urllib.parse.quote(q_param)}&maxResults={max_results}"
        
        listing = api_get(f"https://gmail.googleapis.com/gmail/v1/users/me/messages?{query_params}", token)
        messages = listing.get("messages", [])
        
        results = []
        if messages:
            with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
                futures = {pool.submit(fetch_detail, m["id"], token, email): i for i, m in enumerate(messages)}
                for future in concurrent.futures.as_completed(futures):
                    try:
                        results.append(future.result())
                    except Exception:
                        pass
        return results
    except Exception as e:
        # print(f"Error fetching {email}: {e}", file=sys.stderr)
        return []

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"messages": []}))
        sys.exit(0)

    try:
        accounts = json.loads(sys.argv[1])
        max_results = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    except Exception:
        print(json.dumps({"messages": []}))
        sys.exit(1)

    all_messages = []
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(accounts)) as pool:
        futures = [pool.submit(fetch_account_inbox, acc, max_results) for acc in accounts]
        for future in concurrent.futures.as_completed(futures):
            all_messages.extend(future.result())

    # Sort all messages by timestamp descending
    all_messages.sort(key=lambda x: x.get("timestamp", 0), reverse=True)
    
    # Trim to max_results total? Or just keep all.
    # Usually All Inboxes should show a decent amount.
    print(json.dumps({"messages": all_messages[:max_results*2]}))

if __name__ == "__main__":
    main()
