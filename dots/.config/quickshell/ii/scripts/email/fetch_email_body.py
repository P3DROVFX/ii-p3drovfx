#!/usr/bin/env python3
"""Fetch full body of a Gmail message.
Sanitizes HTML for Qt RichText rendering. Saves raw HTML to a temp file.
Usage: fetch_email_body.py <refresh_token> <message_id>
Outputs JSON: { "body": "<sanitized html>", "htmlPath": "<path>", "attachments": [...] }
"""
import sys, json, base64, re, os, urllib.request, urllib.parse
from html.parser import HTMLParser
import html as html_mod
import gmail_config

# ─── HTTP ────────────────────────────────────────────────────────────

def api_get(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

def decode_base64url(data):
    padded = data.replace("-", "+").replace("_", "/")
    padded += "=" * (4 - len(padded) % 4)
    return base64.b64decode(padded).decode("utf-8", errors="replace")

# ─── MIME traversal ─────────────────────────────────────────────────────────

def parse_ics_event_info(ics_text):
    """Extract basic event info from raw ICS text. Returns dict or None."""
    try:
        import re as _re
        # Unfold lines
        lines = ics_text.splitlines()
        unfolded = ""
        for line in lines:
            if line.startswith((' ', '\t')):
                unfolded += line[1:]
            else:
                unfolded += "\n" + line
        
        # Extract the first VEVENT block
        vevent_match = _re.search(r'BEGIN:VEVENT.*?END:VEVENT', unfolded, _re.DOTALL | _re.IGNORECASE)
        if not vevent_match:
            return None
        vevent_text = vevent_match.group(0)

        def find(key):
            pattern = rf'^{key}(?:;.*?)?:(.*)'
            m = _re.search(pattern, vevent_text, _re.MULTILINE | _re.IGNORECASE)
            return m.group(1).strip() if m else ''

        def parse_dt(dtstr):
            if not dtstr: return '', ''
            # Handle YYYYMMDDTHHMMSS...
            if 'T' in dtstr:
                # Remove everything after T and clean numbers
                parts = dtstr.split('T')
                d_part = _re.sub(r'[^0-9]', '', parts[0])
                t_part = _re.sub(r'[^0-9]', '', parts[1])
                if len(d_part) >= 8:
                    d_fmt = f"{d_part[:4]}-{d_part[4:6]}-{d_part[6:8]}"
                    t_fmt = f"{t_part[:2]}:{t_part[2:4]}" if len(t_part) >= 4 else ""
                    return d_fmt, t_fmt
            else:
                # Handle YYYYMMDD
                clean = _re.sub(r'[^0-9]', '', dtstr)
                if len(clean) >= 8:
                    return f"{clean[:4]}-{clean[4:6]}-{clean[6:8]}", ""
            return '', ''

        title = find('SUMMARY')
        dtstart_raw = find('DTSTART')
        dtend_raw = find('DTEND')

        if not title and not dtstart_raw:
            return None

        date, start_time = parse_dt(dtstart_raw)
        _, end_time = parse_dt(dtend_raw)

        return {
            'title': title,
            'date': date,
            'startTime': start_time,
            'endTime': end_time,
        }
    except Exception:
        return None


def extract_parts(payload):
    """Return (html_body, plain_body, attachments) from MIME payload."""
    html_body, plain_body = "", ""
    attachments = []
    mime = payload.get("mimeType", "")
    filename = payload.get("filename", "")

    if filename:
        attachment_id = payload.get("body", {}).get("attachmentId", "")
        size = payload.get("body", {}).get("size", 0)
        att = {
            "name": filename,
            "mimeType": mime,
            "attachmentId": attachment_id,
            "size": size,
        }
        # For small ICS files, the content may be inline (no attachmentId needed)
        if mime in ("text/calendar", "application/ics") or filename.lower().endswith(".ics"):
            inline_data = payload.get("body", {}).get("data", "")
            if inline_data:
                try:
                    ics_text = decode_base64url(inline_data)
                    att["eventInfo"] = parse_ics_event_info(ics_text)
                except Exception:
                    att["eventInfo"] = None
            else:
                att["eventInfo"] = None
        attachments.append(att)
    elif mime == "text/html":
        d = payload.get("body", {}).get("data", "")
        if d: html_body = decode_base64url(d)
    elif mime == "text/plain":
        d = payload.get("body", {}).get("data", "")
        if d: plain_body = decode_base64url(d)
        if filename:
            attachments.append({
                "name": filename,
                "mimeType": mime,
                "attachmentId": attachment_id,
                "size": size,
            })
    elif mime in ("text/calendar", "application/ics"):
        # Inline calendar part without a filename (common in Exchange/Outlook invites)
        d = payload.get("body", {}).get("data", "")
        if d:
            try:
                ics_text = decode_base64url(d)
                event_info = parse_ics_event_info(ics_text)
                if event_info:
                    # Represent as a virtual attachment
                    attachments.append({
                        "name": "invite.ics",
                        "mimeType": mime,
                        "attachmentId": payload.get("body", {}).get("attachmentId", ""),
                        "size": payload.get("body", {}).get("size", len(d)),
                        "eventInfo": event_info,
                    })
            except Exception:
                pass

    for part in payload.get("parts", []):
        h, p, a = extract_parts(part)
        if h and not html_body: html_body = h
        if p and not plain_body: plain_body = p
        attachments.extend(a)

    return html_body, plain_body, attachments

# ─── HTML sanitizer for Qt RichText ─────────────────────────────────────────
#
# Strategy:
#   • Keep ONLY tags that Qt RichText renders well
#   • Strip color/font-family attrs — QML theme provides those
#   • PRESERVE text-align (center/right/left) — converted to align= attribute
#   • PRESERVE font-size relative values (large/small) as <big>/<small>
#   • Remove ALL <img> — Qt Text can't load external URLs
#   • Remove <font color=...> — overrides theme (but keep <font size=...>)
#   • Convert button-like <a> into visually distinct clickable links
#   • Flatten <table>/<tr>/<td> into line breaks
#   • Preserve: headings, bold, italic, underline, lists, links, hr, center

def extract_alignment(style):
    """Extract text-align from a CSS style string. Returns 'center', 'right', 'left' or ''."""
    if not style:
        return ""
    m = re.search(r'text-align\s*:\s*(center|right|left|justify)', style, re.I)
    return m.group(1).lower() if m else ""

def extract_font_size(style):
    """Return 'big' or 'small' hint from CSS font-size if clearly larger/smaller."""
    if not style:
        return ""
    m = re.search(r'font-size\s*:\s*(\d+)(?:px|pt)', style, re.I)
    if m:
        size = int(m.group(1))
        if size >= 20:
            return "big"
        if size <= 10:
            return "small"
    return ""

class _HtmlSanitizer(HTMLParser):
    # Tags Qt RichText renders correctly
    KEEP_TAGS = {"p", "h1", "h2", "h3", "h4", "h5", "h6",
                 "b", "strong", "i", "em", "u", "s", "strike",
                 "a", "ul", "ol", "li", "br", "hr",
                 "center", "blockquote", "big", "small", "sup", "sub",
                 "pre", "code"}
    # Tags whose entire subtree we skip
    SKIP_TAGS = {"script", "style", "head", "noscript", "nav", "svg"}
    # Block-level tags that should get a line break treatment
    BLOCK_TAGS = {"div", "section", "article", "header", "footer",
                  "main", "aside", "figure", "figcaption"}
    # Void tags (no closing tag in HTML)
    VOID_TAGS  = {"br", "hr", "img", "meta", "link", "input", "area", "col"}

    def __init__(self):
        super().__init__()
        self.result = []
        self._skip_depth = 0
        self._current_link_href = None
        self._link_has_bg = False
        self._tag_stack = []

    def _block_attrs(self, tag, attrs_dict):
        """Return a safe attribute string for block-level tags (only alignment)."""
        style = attrs_dict.get("style", "")
        align = attrs_dict.get("align", extract_alignment(style))
        if align in ("center", "right", "justify"):
            return f' align="{align}"'
        return ""

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)

        # Handle skip context
        if self._skip_depth > 0:
            if tag in self.SKIP_TAGS:
                self._skip_depth += 1
            return
        if tag in self.SKIP_TAGS:
            self._skip_depth += 1
            return

        # Remove images entirely
        if tag == "img":
            self._tag_stack.append((tag, ""))
            return

        # Remove <font> entirely
        if tag == "font":
            self._tag_stack.append((tag, ""))
            return

        emitted_start = ""
        emitted_end = ""

        # Flatten tables
        if tag in ("table", "tr", "thead", "tbody", "tfoot", "td", "th"):
            style = attrs_dict.get("style", "")
            align = attrs_dict.get("align", extract_alignment(style))
            
            if align == "center" or "margin: auto" in style or "margin: 0 auto" in style:
                emitted_start = "<center>"
                emitted_end = "</center>"
            else:
                if tag in ("table", "tr", "thead", "tbody", "tfoot"):
                    emitted_start = "<br>"
                else:
                    emitted_start = " "
                    
            self.result.append(emitted_start)
            self._tag_stack.append((tag, emitted_end))
            return

        # Headings — preserve with alignment
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            extra = self._block_attrs(tag, attrs_dict)
            self.result.append(f"<{tag}{extra}>")
            self._tag_stack.append((tag, f"</{tag}>"))
            return

        # Paragraphs — preserve with alignment
        if tag == "p":
            extra = self._block_attrs(tag, attrs_dict)
            self.result.append(f"<p{extra}>")
            self._tag_stack.append((tag, "</p>"))
            return

        # Center tag — pass through as-is
        if tag == "center":
            self.result.append("<center>")
            self._tag_stack.append((tag, "</center>"))
            return

        # Links — detect button-style and preserve href
        if tag == "a":
            href = attrs_dict.get("href", "")
            style = attrs_dict.get("style", "")
            self._current_link_href = href
            self._link_has_bg = bool(re.search(r'background(?:-color)?', style, re.I))
            if href:
                escaped_href = html_mod.escape(href, quote=True)
                self.result.append(f'<a href="{escaped_href}">')
                self._tag_stack.append((tag, "</a>"))
            else:
                self._tag_stack.append((tag, ""))
            return

        # div/span/section → check alignment, add line break for blocks
        if tag in self.BLOCK_TAGS:
            style = attrs_dict.get("style", "")
            align = extract_alignment(style)
            if align == "center":
                self.result.append("<center>")
                self._tag_stack.append((tag, "</center>"))
            elif align == "right":
                self.result.append('<p align="right">')
                self._tag_stack.append((tag, "</p>"))
            else:
                self.result.append("<br>")
                self._tag_stack.append((tag, ""))
            return

        if tag == "span":
            style = attrs_dict.get("style", "")
            # Detect italic/bold encoded in style
            if "font-style:italic" in style.replace(" ", "") or "font-style: italic" in style:
                self.result.append("<i>")
                self._tag_stack.append((tag, "</i>"))
            elif "font-weight:bold" in style.replace(" ", "") or "font-weight: bold" in style:
                self.result.append("<b>")
                self._tag_stack.append((tag, "</b>"))
            else:
                self._tag_stack.append((tag, ""))
            return

        # All other KEEP_TAGS
        if tag in self.KEEP_TAGS:
            if tag in self.VOID_TAGS:
                self.result.append(f"<{tag}>")
                self._tag_stack.append((tag, ""))
            else:
                self.result.append(f"<{tag}>")
                self._tag_stack.append((tag, f"</{tag}>"))
            return

        self._tag_stack.append((tag, ""))

    def handle_endtag(self, tag):
        if self._skip_depth > 0:
            if tag in self.SKIP_TAGS:
                self._skip_depth -= 1
            return

        # Find matching tag in stack
        idx = -1
        for i in range(len(self._tag_stack)-1, -1, -1):
            if self._tag_stack[i][0] == tag:
                idx = i
                break

        if idx != -1:
            _, emitted_end = self._tag_stack[idx]

            if tag == "a":
                if self._link_has_bg and self._current_link_href:
                    self.result.append(" ↗")
                self.result.append(emitted_end)
                if self._link_has_bg:
                    self.result.append("<br>")
                self._current_link_href = None
                self._link_has_bg = False
            else:
                if emitted_end:
                    self.result.append(emitted_end)

            # Pop tags
            del self._tag_stack[idx:]



    def handle_data(self, data):
        if self._skip_depth > 0:
            return
        self.result.append(html_mod.escape(data))

    def handle_entityref(self, name):
        if self._skip_depth > 0: return
        self.result.append(f"&{name};")

    def handle_charref(self, name):
        if self._skip_depth > 0: return
        self.result.append(f"&#{name};")

    def get_html(self):
        raw = "".join(self.result)
        # Collapse 3+ consecutive <br> into max 2
        raw = re.sub(r'(\s*<br>\s*){3,}', '<br><br>', raw, flags=re.IGNORECASE)
        # Remove leading/trailing <br>
        raw = re.sub(r'^(\s*<br>\s*)+', '', raw, flags=re.IGNORECASE)
        raw = re.sub(r'(\s*<br>\s*)+$', '', raw, flags=re.IGNORECASE)
        return raw.strip()

def sanitize_html(html_str):
    try:
        parser = _HtmlSanitizer()
        parser.feed(html_str)
        return parser.get_html()
    except Exception:
        text = re.sub(r'<[^>]+>', '', html_str).strip()
        return linkify_text(text)

def linkify_text(text):
    """Convert plain text to minimal HTML with clickable links."""
    escaped = html_mod.escape(text)
    url_pattern = re.compile(r'(https?://[^\s<>"\'\]\[]+)')
    escaped = url_pattern.sub(r'<a href="\1">\1</a>', escaped)
    return escaped.replace('\n', '<br>')

def format_size(size_bytes):
    """Human-readable file size."""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    if size_bytes < 1024 * 1024:
        return f"{size_bytes // 1024} KB"
    return f"{size_bytes / (1024 * 1024):.1f} MB"

def mime_icon(mime):
    """Return a Material Symbol name for a MIME type."""
    if mime.startswith("image/"): return "image"
    if mime.startswith("video/"): return "movie"
    if mime.startswith("audio/"): return "music_note"
    if "pdf" in mime: return "picture_as_pdf"
    if "zip" in mime or "tar" in mime or "gzip" in mime or "7z" in mime: return "folder_zip"
    if "word" in mime or "document" in mime: return "description"
    if "sheet" in mime or "excel" in mime or "csv" in mime: return "table_chart"
    if "presentation" in mime or "powerpoint" in mime: return "slideshow"
    if "text/" in mime: return "article"
    return "attach_file"

# ─── Main ───────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"body": "", "htmlPath": "", "attachments": []}))
        sys.exit(0)

    refresh_token = sys.argv[1]
    message_id    = sys.argv[2]

    try:
        token = gmail_config.resolve_token(refresh_token)
    except Exception:
        print(json.dumps({"body": "", "htmlPath": "", "attachments": []}))
        sys.exit(1)

    try:
        msg = api_get(
            f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{message_id}?format=full",
            token
        )
    except Exception:
        print(json.dumps({"body": "", "htmlPath": "", "attachments": []}))
        sys.exit(1)

    html_body, plain_body, attachments = extract_parts(msg.get("payload", {}))

    # Enrich attachments with icon and size label
    for att in attachments:
        att["icon"] = mime_icon(att.get("mimeType", ""))
        att["sizeLabel"] = format_size(att.get("size", 0))
        
        # Prefetch ICS info if small enough (< 100KB)
        if (att.get("mimeType") in ("text/calendar", "application/ics") or
                att.get("name", "").lower().endswith(".ics")):
            if att.get("eventInfo") is None and att.get("attachmentId") and att.get("size", 0) < 100000:
                try:
                    att_data = api_get(
                        f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{message_id}/attachments/{att['attachmentId']}",
                        token
                    )
                    raw_content = decode_base64url(att_data.get("data", ""))
                    att["eventInfo"] = parse_ics_event_info(raw_content)
                except Exception:
                    att["eventInfo"] = None
            elif "eventInfo" not in att:
                att["eventInfo"] = None

    html_path = ""

    if html_body:
        try:
            tmp_path = f"/tmp/qs_email_{message_id}.html"
            with open(tmp_path, "w", encoding="utf-8") as f:
                f.write(html_body)
            html_path = tmp_path
        except Exception:
            html_path = ""
        safe_html = sanitize_html(html_body)
    elif plain_body:
        safe_html = linkify_text(plain_body)
    else:
        safe_html = linkify_text(msg.get("snippet", ""))

    print(json.dumps({
        "body": safe_html,
        "htmlPath": html_path,
        "attachments": attachments,
    }))

if __name__ == "__main__":
    main()
