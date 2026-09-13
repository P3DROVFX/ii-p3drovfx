#!/usr/bin/env python3
"""Web access for the AI sidebar, as two small tools any model can call.

The providers that ship their own search only expose it to their own models,
so a local Qwen could never look anything up. These two commands close that:

  search QUERY [COUNT]   Searches and prints the results as JSON.
  fetch URL              Fetches a page and prints its readable text as JSON.

Search tries the backends in order: a local SearXNG (AI_SEARXNG_URL, default
http://127.0.0.1:8888), Brave (BRAVE_SEARCH_KEY), DuckDuckGo Lite, the regular
DuckDuckGo HTML endpoint, and Wikipedia. The keyless Lite endpoint is useful
for a local model because the regular endpoint currently serves a challenge
page to non-browser clients. Running a local SearXNG is still preferred, but
the model gets real search results even when that optional service is down.

`fetch` takes its URL from the model, so it is the one entry point an attacker
reaches by writing on a web page the model happens to read. It refuses anything
that resolves off the public internet — loopback, the LAN, link-local (which is
where cloud metadata lives), CGNAT — and it re-checks every redirect hop rather
than letting urllib chase them, because a public hostname that 302s to
127.0.0.1 is the usual way past a check done only on the first URL. The search
backends are exempt: their addresses come from the user's own configuration,
and a local SearXNG is supposed to be local.

Nothing here follows redirects to non-HTTP schemes, runs scripts, or writes
anything to disk.
"""

import html
import ipaddress
import json
import os
import re
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) quickshell-ai/1.0"
TIMEOUT = 20
MAX_TEXT = 20_000
# Read cap for a fetched page, before any tag stripping. A page bigger than
# this is not a page worth reading to a language model.
MAX_BYTES = 4_000_000
MAX_REDIRECTS = 5
# What a reader can do anything with. An image or an archive is a download,
# not a source, and letting one through is how a fetch turns into a probe.
READABLE_TYPES = (
    "text/html",
    "text/plain",
    "text/markdown",
    "application/xhtml+xml",
    "application/json",
    "application/xml",
    "text/xml",
)


def get(url: str, headers: dict | None = None) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace")


def strip_tags(markup: str) -> str:
    """Readable text out of a page, without pulling in a parser."""
    markup = re.sub(r"(?is)<(script|style|noscript|template)\b.*?</\1>", " ", markup)
    markup = re.sub(r"(?is)<(nav|footer|aside|form)\b.*?</\1>", " ", markup)
    markup = re.sub(r"(?is)<br\s*/?>", "\n", markup)
    markup = re.sub(r"(?is)</(p|div|section|article|li|h[1-6]|tr)>", "\n", markup)
    text = re.sub(r"(?s)<[^>]+>", " ", markup)
    text = html.unescape(text)
    text = re.sub(r"[ \t\r\f\v]+", " ", text)
    text = re.sub(r"\n\s*\n\s*\n+", "\n\n", text)
    return text.strip()


def title_of(markup: str) -> str:
    match = re.search(r"(?is)<title[^>]*>(.*?)</title>", markup)
    return html.unescape(match.group(1)).strip() if match else ""


def searxng(query: str, count: int) -> list | None:
    base = os.environ.get("AI_SEARXNG_URL", "http://127.0.0.1:8888").rstrip("/")
    url = f"{base}/search?q={urllib.parse.quote(query)}&format=json"
    try:
        payload = json.loads(get(url))
    except Exception:
        return None
    results = []
    for item in payload.get("results", [])[:count]:
        results.append({
            "title": item.get("title", ""),
            "url": item.get("url", ""),
            "snippet": item.get("content", ""),
        })
    return results or None


def brave(query: str, count: int) -> list | None:
    key = os.environ.get("BRAVE_SEARCH_KEY", "").strip()
    if not key:
        return None
    url = f"https://api.search.brave.com/res/v1/web/search?q={urllib.parse.quote(query)}&count={count}"
    try:
        payload = json.loads(get(url, {"X-Subscription-Token": key, "Accept": "application/json"}))
    except Exception:
        return None
    results = []
    for item in payload.get("web", {}).get("results", [])[:count]:
        results.append({
            "title": item.get("title", ""),
            "url": item.get("url", ""),
            "snippet": strip_tags(item.get("description", "")),
        })
    return results or None


def wikipedia(query: str, count: int) -> list | None:
    """The one search that answers without a key or a captcha. Encyclopedic
    only, which is why it is last: it is a floor, not a search engine."""
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode({
        "action": "query",
        "list": "search",
        "format": "json",
        "srsearch": query,
        "srlimit": count,
    })
    try:
        payload = json.loads(get(url, {"Accept": "application/json"}))
    except Exception:
        return None
    results = []
    for item in payload.get("query", {}).get("search", []):
        title = item.get("title", "")
        results.append({
            "title": title,
            "url": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(title.replace(" ", "_")),
            "snippet": strip_tags(item.get("snippet", "")),
        })
    return results or None


def duckduckgo(query: str, count: int) -> list | None:
    url = f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(query)}"
    try:
        markup = get(url)
    except Exception:
        return None
    results = []
    pattern = re.compile(
        r'(?is)<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="(?P<href>[^"]+)"[^>]*>(?P<title>.*?)</a>'
        r'.*?(?:<a[^>]+class="[^"]*result__snippet[^"]*"[^>]*>(?P<snippet>.*?)</a>)?'
    )
    for match in pattern.finditer(markup):
        href = html.unescape(match.group("href"))
        # DuckDuckGo wraps every result in its own redirector.
        parsed = urllib.parse.urlparse(href)
        if parsed.path.startswith("/l/"):
            query_args = urllib.parse.parse_qs(parsed.query)
            href = query_args.get("uddg", [href])[0]
        results.append({
            "title": strip_tags(match.group("title")),
            "url": href,
            "snippet": strip_tags(match.group("snippet") or ""),
        })
        if len(results) >= count:
            break
    return results or None


def duckduckgo_lite(query: str, count: int) -> list | None:
    """Parse DuckDuckGo's low-JavaScript results page.

    The regular HTML endpoint returns an anti-bot challenge from this desktop
    session, while Lite keeps the result links and snippets server-rendered.
    This is a read-only fallback and does not loosen `fetch`'s SSRF checks.
    """
    url = f"https://lite.duckduckgo.com/lite/?q={urllib.parse.quote(query)}"
    try:
        markup = get(url)
    except Exception:
        return None

    link_pattern = re.compile(
        r"(?is)<a(?P<attrs>[^>]*\bclass\s*=\s*['\"][^'\"]*\bresult-link\b[^'\"]*['\"][^>]*)>"
        r"(?P<title>.*?)</a>"
    )
    results = []
    for match in link_pattern.finditer(markup):
        href_match = re.search(r"(?is)\bhref\s*=\s*(['\"])(.*?)\1", match.group("attrs"))
        if not href_match:
            continue
        href = html.unescape(href_match.group(2))
        parsed = urllib.parse.urlparse("https:" + href if href.startswith("//") else href)
        if parsed.path.startswith("/l/"):
            href = urllib.parse.parse_qs(parsed.query).get("uddg", [href])[0]

        next_anchor = markup.find("<a", match.end())
        tail = markup[match.end(): next_anchor if next_anchor >= 0 else match.end() + 3000]
        snippet_match = re.search(
            r"(?is)<td[^>]*\bclass\s*=\s*['\"][^'\"]*\bresult-snippet\b[^'\"]*['\"][^>]*>(.*?)</td>",
            tail,
        )
        results.append({
            "title": strip_tags(match.group("title")),
            "url": href,
            "snippet": strip_tags(snippet_match.group(1)) if snippet_match else "",
        })
        if len(results) >= count:
            break
    return results or None


def search(query: str, count: int) -> dict:
    query = query.strip()
    if not query:
        return {"error": "Empty query"}
    for backend, name in ((searxng, "searxng"), (brave, "brave"), (duckduckgo_lite, "duckduckgo-lite"), (duckduckgo, "duckduckgo"), (wikipedia, "wikipedia")):
        results = backend(query, count)
        if results:
            return {"query": query, "engine": name, "results": results}
    return {
        "error": (
            "No search backend is reachable. Run a local SearXNG (AI_SEARXNG_URL, "
            "default http://127.0.0.1:8888) or set BRAVE_SEARCH_KEY. Do not use "
            "run_shell_command as a substitute; report that web search is unavailable."
        ),
        "query": query,
    }


class BlockedTarget(Exception):
    """A URL the model asked for that must not be reached."""


def address_is_reachable(address: str) -> bool:
    """Whether one resolved address belongs to the public internet.

    `is_global` already knows about loopback, the private ranges, link-local
    and carrier-grade NAT, and it unwraps an IPv4 address smuggled inside an
    IPv6 literal. The explicit ranges after it are the ones worth naming: they
    are what someone actually aims at, and naming them keeps this correct on a
    Python whose classification of a range differs from ours.
    """
    try:
        ip = ipaddress.ip_address(address)
    except ValueError:
        return False

    mapped = getattr(ip, "ipv4_mapped", None)
    if mapped is not None:
        return address_is_reachable(str(mapped))

    if ip.is_loopback or ip.is_private or ip.is_link_local:
        return False
    if ip.is_multicast or ip.is_reserved or ip.is_unspecified:
        return False
    if not ip.is_global:
        return False

    if ip.version == 4:
        for network in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
                        "127.0.0.0/8", "169.254.0.0/16", "100.64.0.0/10",
                        "192.0.0.0/24", "198.18.0.0/15"):
            if ip in ipaddress.ip_network(network):
                return False
    else:
        for network in ("::1/128", "fc00::/7", "fe80::/10", "::/128"):
            if ip in ipaddress.ip_network(network):
                return False
    return True


def check_target(url: str) -> tuple[str, int]:
    """Validates one hop and returns its host and port, or raises."""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise BlockedTarget("only http and https URLs can be fetched")
    host = parsed.hostname
    if not host:
        raise BlockedTarget("that URL has no host")
    port = parsed.port or (443 if parsed.scheme == "https" else 80)

    try:
        resolved = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except socket.gaierror:
        raise BlockedTarget(f"{host} could not be resolved") from None
    if not resolved:
        raise BlockedTarget(f"{host} could not be resolved")

    # Every address, not the first: a name that answers with one public
    # address and one private one is the cheapest way past a check that
    # stops at the first.
    for entry in resolved:
        address = entry[4][0]
        if not address_is_reachable(address):
            raise BlockedTarget(
                f"{host} resolves to {address}, which is not on the public internet"
            )
    return host, port


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Hands redirects back so `open_guarded` can check each destination."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def open_guarded(url: str) -> tuple[str, str]:
    """Fetches a page, checking the target again at every redirect.

    urllib follows redirects on its own, which would make the check above
    apply only to the URL the model typed. Redirects are handled here instead,
    one hop at a time, so a public host that forwards to the LAN is refused at
    the hop that tries it.
    """
    opener = urllib.request.build_opener(NoRedirect)
    seen = url
    for _ in range(MAX_REDIRECTS + 1):
        check_target(seen)
        request = urllib.request.Request(seen, headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.1",
        })
        try:
            with opener.open(request, timeout=TIMEOUT) as response:
                content_type = (response.headers.get_content_type() or "").lower()
                if content_type and content_type not in READABLE_TYPES:
                    raise BlockedTarget(f"{content_type} is not readable as text")
                raw = response.read(MAX_BYTES + 1)
                charset = response.headers.get_content_charset() or "utf-8"
                return response.geturl(), raw[:MAX_BYTES].decode(charset, errors="replace")
        except urllib.error.HTTPError as error:
            if error.code not in (301, 302, 303, 307, 308):
                raise
            location = error.headers.get("Location", "")
            error.close()
            if not location:
                raise BlockedTarget(f"HTTP {error.code} without a destination") from None
            seen = urllib.parse.urljoin(seen, location)
    raise BlockedTarget("too many redirects")


def fetch(url: str) -> dict:
    try:
        final_url, markup = open_guarded(url)
    except BlockedTarget as error:
        return {"error": str(error), "url": url, "blocked": True}
    except urllib.error.HTTPError as error:
        return {"error": f"HTTP {error.code}", "url": url}
    except Exception as error:
        return {"error": str(error), "url": url}
    text = strip_tags(markup)
    truncated = len(text) > MAX_TEXT
    result = {
        "url": final_url,
        "title": title_of(markup),
        "text": text[:MAX_TEXT],
        "truncated": truncated,
    }
    if final_url != url:
        result["requestedUrl"] = url
    return result


def main() -> int:
    if len(sys.argv) < 3:
        print(json.dumps({"error": "usage: ai_web.py search QUERY [COUNT] | fetch URL"}))
        return 0
    command = sys.argv[1]
    if command == "search":
        count = 5
        if len(sys.argv) > 3:
            try:
                count = max(1, min(10, int(sys.argv[3])))
            except ValueError:
                count = 5
        print(json.dumps(search(sys.argv[2], count)))
        return 0
    if command == "fetch":
        print(json.dumps(fetch(sys.argv[2])))
        return 0
    print(json.dumps({"error": f"Unknown command {command}"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
