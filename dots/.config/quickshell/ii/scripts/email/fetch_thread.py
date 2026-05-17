#!/usr/bin/env python3
"""Fetch full thread from Gmail.
Usage: fetch_thread.py <refresh_token> <thread_id>
Outputs JSON array of message objects: [{ "id": "...", "body": "...", "snippet": "...", "from": "...", "date": "...", "attachments": [...] }, ...]
"""
import sys, json, base64, re, os, urllib.request, urllib.parse
import gmail_config
import fetch_email_body

def api_get(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

def main():
    if len(sys.argv) < 3:
        print(json.dumps([]))
        sys.exit(0)

    refresh_token = sys.argv[1]
    thread_id     = sys.argv[2]

    try:
        token = gmail_config.resolve_token(refresh_token)
    except Exception:
        print(json.dumps([]))
        sys.exit(1)

    try:
        thread = api_get(
            f"https://gmail.googleapis.com/gmail/v1/users/me/threads/{thread_id}?format=full",
            token
        )
    except Exception:
        print(json.dumps([]))
        sys.exit(1)

    messages = thread.get("messages", [])
    results = []

    for msg in messages:
        msg_id = msg.get("id")
        headers = {h["name"]: h["value"] for h in msg.get("payload", {}).get("headers", [])}
        
        html_body, plain_body, attachments = fetch_email_body.extract_parts(msg.get("payload", {}))
        
        # Enrich attachments
        for att in attachments:
            att["icon"] = fetch_email_body.mime_icon(att.get("mimeType", ""))
            att["sizeLabel"] = fetch_email_body.format_size(att.get("size", 0))
        
        if html_body:
            safe_html = fetch_email_body.sanitize_html(html_body)
        elif plain_body:
            safe_html = fetch_email_body.linkify_text(plain_body)
        else:
            safe_html = fetch_email_body.linkify_text(msg.get("snippet", ""))

        results.append({
            "id": msg_id,
            "threadId": thread_id,
            "from": headers.get("From", ""),
            "subject": headers.get("Subject", ""),
            "date": headers.get("Date", ""),
            "snippet": msg.get("snippet", ""),
            "body": safe_html,
            "attachments": attachments,
            "unread": "UNREAD" in msg.get("labelIds", []),
            "starred": "STARRED" in msg.get("labelIds", []),
            "labels": msg.get("labelIds", []),
            "timestamp": int(msg.get("internalDate", 0)) // 1000
        })

    print(json.dumps(results))

if __name__ == "__main__":
    main()
