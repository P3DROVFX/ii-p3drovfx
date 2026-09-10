#!/usr/bin/env python3
"""List the commits a GitHub branch is ahead of a local checkout by.

Usage: fetch_commits.py OWNER/REPO BASE_SHA HEAD_SHA [--max-pages N] [--body-chars N]
       fetch_commits.py OWNER/REPO --recent=N [--branch=NAME] [--body-chars N]

The second form lists the newest N commits of a branch instead, in the same
shape (with "ahead" 0), for the About page's recent-changes list when the
checkout is already up to date.

Pages the compare API (250 commits per page, the endpoint's ceiling) and prints
one compact JSON object on stdout:

    {"ahead": 412, "truncated": false, "commits": [
        {"sha": "...", "subject": "...", "body": "...", "author": "...", "date": "..."},
        ...
    ]}

Commits are newest-first. The compare response carries the full diff of the
range, hundreds of KB per page, so it is reduced here rather than handed to
QML. Any failure (offline, rate-limited, unknown SHA) prints nothing and
exits non-zero; the shell then falls back to "an update exists, count unknown".
"""

import json
import sys
import urllib.error
import urllib.request

PER_PAGE = 250
API = "https://api.github.com/repos/{slug}/compare/{base}...{head}?per_page={per_page}&page={page}"
RECENT_API = "https://api.github.com/repos/{slug}/commits?sha={branch}&per_page={count}"


def fetch_json(url, timeout=15):
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "ii-shell-updates",
    })
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def fetch_page(slug, base, head, page, timeout=15):
    return fetch_json(API.format(slug=slug, base=base, head=head, per_page=PER_PAGE, page=page), timeout)


def fetch_recent(slug, branch, count, timeout=15):
    return fetch_json(RECENT_API.format(slug=slug, branch=branch, count=count), timeout)


def reduce_commit(item, body_chars):
    message = str((item.get("commit") or {}).get("message") or "")
    lines = message.splitlines()
    subject = lines[0].strip() if lines else ""
    body = "\n".join(lines[1:]).strip()
    if body_chars >= 0 and len(body) > body_chars:
        body = body[:body_chars].rstrip() + "…"
    author = ((item.get("commit") or {}).get("author") or {}).get("name") or ""
    date = ((item.get("commit") or {}).get("author") or {}).get("date") or ""
    return {
        "sha": str(item.get("sha") or ""),
        "subject": subject,
        "body": body,
        "author": str(author),
        "date": str(date),
    }


def collect(slug, base, head, max_pages=8, body_chars=400, fetch=fetch_page):
    """Walk the pages and return the reduced payload, or None on failure."""
    commits = []
    ahead = 0
    truncated = False
    page = 1
    while page <= max_pages:
        data = fetch(slug, base, head, page)
        if not isinstance(data, dict):
            return None
        if page == 1:
            ahead = int(data.get("total_commits") or data.get("ahead_by") or 0)
        batch = data.get("commits") or []
        commits.extend(reduce_commit(item, body_chars) for item in batch)
        if len(batch) < PER_PAGE or len(commits) >= ahead:
            break
        page += 1
    else:
        truncated = len(commits) < ahead
    commits.reverse()
    return {"ahead": max(ahead, len(commits)), "truncated": truncated, "commits": commits}


def collect_recent(slug, branch, count, body_chars=400, fetch=fetch_recent):
    """The newest `count` commits of `branch`, newest first, or None on failure."""
    data = fetch(slug, branch, count)
    if not isinstance(data, list):
        return None
    commits = [reduce_commit(item, body_chars) for item in data if isinstance(item, dict)]
    return {"ahead": 0, "truncated": False, "commits": commits}


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    opts = {"max-pages": 8, "body-chars": 400, "recent": 0, "branch": "main"}
    for flag in (a for a in argv if a.startswith("--")):
        name, _, value = flag[2:].partition("=")
        if name == "branch":
            opts[name] = value or "main"
        elif name in opts:
            opts[name] = int(value)
    recent = opts["recent"] > 0
    if len(args) != (1 if recent else 3):
        sys.stderr.write(__doc__)
        return 2
    try:
        if recent:
            payload = collect_recent(args[0], opts["branch"], opts["recent"], opts["body-chars"])
        else:
            payload = collect(args[0], args[1], args[2], opts["max-pages"], opts["body-chars"])
    except (urllib.error.URLError, urllib.error.HTTPError, ValueError, OSError) as exc:
        sys.stderr.write(f"fetch_commits: {exc}\n")
        return 1
    if payload is None:
        return 1
    json.dump(payload, sys.stdout, separators=(",", ":"), ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
