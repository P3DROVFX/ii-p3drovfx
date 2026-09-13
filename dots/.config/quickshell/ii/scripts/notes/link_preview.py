#!/usr/bin/env python3
"""Fetch metadata and generate a link preview card for a web URL.

Contract:
- Emits one JSON line on stdout, never unhandled exceptions.
- Exits with 0.
- Respects privacy: accepts --no-network to disable external requests.
- Caches results to avoid redundant network calls.

Usage:
  link_preview.py <url> [--cache-dir <dir>] [--no-network]
"""

import argparse
import hashlib
import html
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

MAX_HTML_BYTES = 512 * 1024  # 512 KB
MAX_MEDIA_BYTES = 1024 * 1024  # 1 MB
DEFAULT_TIMEOUT = 6.0
CACHE_TTL_SECONDS = 7 * 86400  # 7 days

DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/*,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9,pt-BR;q=0.8,pt;q=0.7",
}


def emit(payload: dict) -> int:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()
    return 0


class MetaTagParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = ""
        self.in_title = False
        self.meta = {}
        self.links = {}

    def handle_starttag(self, tag, attrs):
        tag_lower = tag.lower()
        attr_dict = {k.lower(): v for k, v in attrs if v is not None}

        if tag_lower == "title":
            self.in_title = True
        elif tag_lower == "meta":
            prop = attr_dict.get("property", "").lower()
            name = attr_dict.get("name", "").lower()
            content = attr_dict.get("content", "")
            key = prop or name
            if key and content and key not in self.meta:
                self.meta[key] = content
        elif tag_lower == "link":
            rel = attr_dict.get("rel", "").lower()
            href = attr_dict.get("href", "")
            if rel and href:
                for r in rel.split():
                    if r not in self.links:
                        self.links[r] = href

    def handle_endtag(self, tag):
        if tag.lower() == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title and not self.title:
            self.title = data.strip()


def parse_metadata(html_content: str, base_url: str) -> dict:
    parser = MetaTagParser()
    try:
        parser.feed(html_content)
    except Exception:
        pass

    meta = parser.meta
    links = parser.links

    title = (
        meta.get("og:title")
        or meta.get("twitter:title")
        or parser.title
        or ""
    )
    description = (
        meta.get("og:description")
        or meta.get("twitter:description")
        or meta.get("description")
        or ""
    )
    site_name = (
        meta.get("og:site_name")
        or meta.get("twitter:site")
        or ""
    )
    image = (
        meta.get("og:image")
        or meta.get("og:image:url")
        or meta.get("twitter:image")
        or meta.get("twitter:image:src")
        or ""
    )
    favicon = (
        links.get("icon")
        or links.get("shortcut icon")
        or links.get("apple-touch-icon")
        or ""
    )

    # Clean HTML entities
    title = html.unescape(title).strip()
    description = html.unescape(description).strip()
    site_name = html.unescape(site_name).strip()

    # Resolve relative URLs
    if image:
        image = urllib.parse.urljoin(base_url, image)
    if favicon:
        favicon = urllib.parse.urljoin(base_url, favicon)
    else:
        parsed_base = urllib.parse.urlparse(base_url)
        favicon = f"{parsed_base.scheme}://{parsed_base.netloc}/favicon.ico"

    return {
        "title": title,
        "description": description,
        "site_name": site_name,
        "image": image,
        "favicon": favicon,
    }


def download_asset(url: str, dest: Path, max_bytes: int = MAX_MEDIA_BYTES) -> str:
    """Download a thumbnail or favicon to disk and return local path on success."""
    if not url or not url.startswith(("http://", "https://")):
        return ""
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(url, headers=DEFAULT_HEADERS)
        with urllib.request.urlopen(req, timeout=DEFAULT_TIMEOUT) as resp:
            data = resp.read(max_bytes)
            if data:
                dest.write_bytes(data)
                return str(dest)
    except Exception:
        pass
    return ""


def fetch_youtube_oembed(url: str) -> dict:
    """Fetch video metadata using YouTube's official oEmbed endpoint."""
    quoted = urllib.parse.quote(url, safe="")
    oembed_url = f"https://www.youtube.com/oembed?url={quoted}&format=json"
    req = urllib.request.Request(oembed_url, headers=DEFAULT_HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=DEFAULT_TIMEOUT) as resp:
            data = json.loads(resp.read(MAX_HTML_BYTES).decode("utf-8", errors="replace"))
            title = data.get("title", "").strip()
            author = data.get("author_name", "").strip()
            thumb = data.get("thumbnail_url", "").strip()
            provider = data.get("provider_name", "YouTube").strip()
            # English, like every other string the shell shows. This one was "Vídeo por
            # %s", which is the only Portuguese sentence in the app and it reached the
            # screen.
            desc = f"Video by {author}" if author else ""
            if title:
                return {
                    "title": title,
                    "description": desc,
                    "site_name": provider,
                    "image": thumb,
                    # The stable path, not the build-hashed one: the versioned URL
                    # (/s/desktop/<hash>/img/favicon.ico) 404s the moment YouTube ships a
                    # new build, and the shell then retried it on every repaint.
                    "favicon": "https://www.youtube.com/favicon.ico",
                }
    except Exception:
        pass
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description="Link preview generator")
    parser.add_argument("url", help="Target URL to preview")
    parser.add_argument("--cache-dir", default="", help="Cache directory")
    parser.add_argument("--refresh", action="store_true",
                        help="Ignore the cached answer and ask the site again")
    parser.add_argument("--no-network", action="store_true", help="Do not make external requests")
    args = parser.parse_args()

    raw_url = args.url.strip()
    if not raw_url:
        return emit({"ok": False, "error": "Empty URL"})

    if not re.match(r"^https?://", raw_url, re.IGNORECASE):
        return emit({"ok": False, "error": "Invalid scheme (http/https required)", "url": raw_url})

    parsed = urllib.parse.urlparse(raw_url)
    domain = parsed.netloc

    cache_dir = Path(args.cache_dir).expanduser() if args.cache_dir else (
        Path.home() / ".cache/quickshell/media/link_previews"
    )
    cache_dir.mkdir(parents=True, exist_ok=True)

    url_hash = hashlib.sha256(raw_url.encode("utf-8")).hexdigest()[:24]
    cache_file = cache_dir / f"{url_hash}.json"

    # Check cache first. `--refresh` is the one thing that gets past it: without that,
    # "ask the site again" reached this line, found an answer from six days ago and
    # returned it, which looks exactly like the button doing nothing.
    if cache_file.exists() and not args.refresh:
        try:
            cached_data = json.loads(cache_file.read_text(encoding="utf-8"))
            if cached_data.get("ok"):
                now = time.time()
                cached_at = cached_data.get("fetchedAt", 0)
                if now - cached_at < CACHE_TTL_SECONDS:
                    cached_data["cached"] = True
                    return emit(cached_data)
        except Exception:
            pass

    if args.no_network:
        # Privacy mode: emit local domain info only
        result = {
            "ok": True,
            "url": raw_url,
            "domain": domain,
            "title": domain,
            "description": "",
            "site_name": domain,
            "image": "",
            "favicon": "",
            "fetchedAt": int(time.time()),
            "cached": False,
            "offline": True,
        }
        return emit(result)

    # 1. Specialized fast-path for YouTube
    meta = {}
    is_youtube = any(yt in domain.lower() for yt in ("youtube.com", "youtu.be"))
    if is_youtube:
        meta = fetch_youtube_oembed(raw_url)

    # 2. General HTML fetch if needed
    if not meta.get("title") or not meta.get("description"):
        try:
            req = urllib.request.Request(raw_url, headers=DEFAULT_HEADERS)
            with urllib.request.urlopen(req, timeout=DEFAULT_TIMEOUT) as response:
                content_type = response.headers.get("Content-Type", "")
                if not ("text/html" in content_type or "application/xhtml" in content_type or not content_type):
                    # Non-HTML resource (e.g. direct image or pdf)
                    result = {
                        "ok": True,
                        "url": raw_url,
                        "domain": domain,
                        "title": domain,
                        "description": content_type,
                        "site_name": domain,
                        "image": "",
                        "favicon": "",
                        "fetchedAt": int(time.time()),
                        "cached": False,
                    }
                    cache_file.write_text(json.dumps(result), encoding="utf-8")
                    return emit(result)

                html_bytes = response.read(MAX_HTML_BYTES)
                encoding = response.headers.get_content_charset() or "utf-8"
                html_text = html_bytes.decode(encoding, errors="replace")

            html_meta = parse_metadata(html_text, raw_url)
            if not meta:
                meta = html_meta
            else:
                if html_meta.get("description"):
                    meta["description"] = html_meta["description"]
                if not meta.get("title"):
                    meta["title"] = html_meta.get("title", "")
                if not meta.get("image"):
                    meta["image"] = html_meta.get("image", "")
                if not meta.get("favicon"):
                    meta["favicon"] = html_meta.get("favicon", "")
        except Exception as exc:
            if not meta.get("title"):
                result = {
                    "ok": False,
                    "url": raw_url,
                    "domain": domain,
                    "error": str(exc),
                    "fetchedAt": int(time.time()),
                }
                return emit(result)

    local_img = ""
    if meta.get("image"):
        img_ext = os.path.splitext(urllib.parse.urlparse(meta["image"]).path)[1] or ".jpg"
        if len(img_ext) > 5 or "?" in img_ext:
            img_ext = ".jpg"
        local_img = download_asset(meta["image"], cache_dir / f"{url_hash}_thumb{img_ext}")

    local_fav = ""
    if meta.get("favicon"):
        fav_ext = os.path.splitext(urllib.parse.urlparse(meta["favicon"]).path)[1] or ".ico"
        if len(fav_ext) > 5 or "?" in fav_ext:
            fav_ext = ".ico"
        local_fav = download_asset(meta["favicon"], cache_dir / f"{url_hash}_fav{fav_ext}")

    result = {
        "ok": True,
        "url": raw_url,
        "domain": domain,
        "title": meta.get("title") or domain,
        "description": meta.get("description") or "",
        "site_name": meta.get("site_name") or domain,
        # Local paths only. Handing back the remote URL when the download failed made the
        # shell itself fetch it — on every repaint, past the preference that is supposed
        # to decide whether anything leaves this machine, and loudly when it 404s.
        "image": local_img,
        "favicon": local_fav,
        "fetchedAt": int(time.time()),
        "cached": False,
    }

    try:
        cache_file.write_text(json.dumps(result), encoding="utf-8")
    except Exception:
        pass

    return emit(result)


if __name__ == "__main__":
    sys.exit(main())
