#!/usr/bin/env python3
"""Send an email using Gmail API.
Usage: send_email.py <refresh_token> <to> <subject> <body_html>
Outputs JSON: { "success": true } or { "success": false, "error": "<msg>" }
"""
import sys
import json
import base64
import urllib.request
import urllib.parse
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
import mimetypes
import os
import gmail_config

def send_message(token, raw_msg, thread_id=None):
    payload = {"raw": raw_msg}
    if thread_id:
        payload["threadId"] = thread_id
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

def main():
    if len(sys.argv) < 5:
        print(json.dumps({"success": False, "error": "Missing arguments"}))
        sys.exit(0)

    refresh_token = sys.argv[1]
    to_address    = sys.argv[2]
    subject       = sys.argv[3]
    body_html     = sys.argv[4]

    # Parse optional arguments and attachments
    cc_address = None
    bcc_address = None
    thread_id = None
    in_reply_to = None
    references = None
    attachments = []

    i = 5
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == '--cc' and i + 1 < len(sys.argv):
            cc_address = sys.argv[i+1]
            i += 2
        elif arg == '--bcc' and i + 1 < len(sys.argv):
            bcc_address = sys.argv[i+1]
            i += 2
        elif arg == '--thread-id' and i + 1 < len(sys.argv):
            thread_id = sys.argv[i+1]
            i += 2
        elif arg == '--in-reply-to' and i + 1 < len(sys.argv):
            in_reply_to = sys.argv[i+1]
            i += 2
        elif arg == '--references' and i + 1 < len(sys.argv):
            references = sys.argv[i+1]
            i += 2
        elif arg == '--attachments':
            i += 1
        else:
            attachments.append(arg)
            i += 1

    try:
        # 1. Resolve token (access or refresh)
        try:
            token = gmail_config.resolve_token(refresh_token)
        except Exception as e:
            print(json.dumps({"success": False, "error": f"Failed to get access token: {str(e)}"}))
            sys.exit(0)

        # 2. Build MIME message
        message = MIMEMultipart('mixed')
        message['To'] = to_address
        message['From'] = 'me'
        if cc_address:
            message['Cc'] = cc_address
        if bcc_address:
            message['Bcc'] = bcc_address
        message['Subject'] = subject

        if in_reply_to:
            message['In-Reply-To'] = in_reply_to
        if references:
            message['References'] = references

        alt_part = MIMEMultipart('alternative')
        html_part = MIMEText(body_html, 'html', 'utf-8')
        alt_part.attach(html_part)
        message.attach(alt_part)

        # Attachments
        for att_path in attachments:
            if not os.path.isfile(att_path):
                continue
            ctype, encoding = mimetypes.guess_type(att_path)
            if ctype is None or encoding is not None:
                ctype = 'application/octet-stream'
            maintype, subtype = ctype.split('/', 1)
            
            with open(att_path, 'rb') as f:
                part = MIMEBase(maintype, subtype)
                part.set_payload(f.read())
            
            encoders.encode_base64(part)
            filename = os.path.basename(att_path)
            part.add_header('Content-Disposition', 'attachment', filename=filename)
            message.attach(part)

        # 3. Base64url encode the message
        raw_msg = base64.urlsafe_b64encode(message.as_bytes()).decode('utf-8').rstrip('=')

        # 4. Send message
        try:
            response = send_message(token, raw_msg, thread_id)
            if 'id' in response:
                print(json.dumps({"success": True}))
            else:
                print(json.dumps({"success": False, "error": "Unknown API error"}))
        except Exception as e:
             print(json.dumps({"success": False, "error": f"Failed to send email: {str(e)}"}))
             
    except Exception as e:
        print(json.dumps({"success": False, "error": f"Internal error: {str(e)}"}))
        
    sys.exit(0)

if __name__ == "__main__":
    main()
