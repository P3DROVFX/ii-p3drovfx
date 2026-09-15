#!/usr/bin/env python3
"""Manage II's read-only HTTP ICS subscriptions without rewriting user config.

The script owns only the text between its two explicit markers.  Both config
files are otherwise treated as opaque user files and are atomically replaced
only after every input and both renderings have validated.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlsplit


BEGIN_MARKER = "# >>> II TIMETABLE SUBSCRIPTIONS >>>"
END_MARKER = "# <<< II TIMETABLE SUBSCRIPTIONS <<<"
_MARKED_BLOCK = re.compile(
    rf"(?ms)^{re.escape(BEGIN_MARKER)}\n.*?^{re.escape(END_MARKER)}\n?"
)
_CALENDARS_HEADER = re.compile(r"(?m)^\[calendars\]\s*$")
_TOP_LEVEL_HEADER = re.compile(r"(?m)^\[(?!\[)[^\]\r\n]+\]\s*$")


class SubscriptionError(ValueError):
    """A safe, user-facing error for invalid subscription input."""


@dataclass(frozen=True)
class Subscription:
    url: str
    ident: str
    local_path: Path


def normalize_url(value: object) -> str:
    """Accept an absolute HTTP(S) ICS URL without changing its query string."""
    url = str(value or "").strip()
    if not url or any(char.isspace() for char in url):
        raise SubscriptionError("Calendar URL must not be empty or contain whitespace.")
    parts = urlsplit(url)
    if parts.scheme not in {"http", "https"} or not parts.netloc:
        raise SubscriptionError("Calendar URL must start with http:// or https://.")
    if '"' in url or "\\" in url:
        raise SubscriptionError("Calendar URL contains an unsupported character.")
    return url


def subscriptions_from_urls(urls: Iterable[object], root: Path) -> list[Subscription]:
    """Normalise, de-duplicate and give each URL a stable safe section name."""
    result: list[Subscription] = []
    seen: set[str] = set()
    for raw_url in urls:
        url = normalize_url(raw_url)
        if url in seen:
            continue
        seen.add(url)
        digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:12]
        ident = f"ii_timetable_ics_{digest}"
        result.append(Subscription(url=url, ident=ident, local_path=root / ident))
    return result


def _without_managed_block(text: str) -> str:
    return _MARKED_BLOCK.sub("", text).rstrip()


def _with_managed_block(text: str, body: str) -> str:
    clean = _without_managed_block(text)
    if not body:
        return (clean + "\n") if clean else ""
    prefix = (clean + "\n\n") if clean else ""
    return prefix + BEGIN_MARKER + "\n" + body.rstrip() + "\n" + END_MARKER + "\n"


def _json_value(value: object) -> str:
    """vdirsyncer values use JSON syntax through RawConfigParser."""
    return json.dumps(str(value), ensure_ascii=False)


def render_vdirsyncer_config(
    existing: str,
    status_path: Path,
    subscriptions: list[Subscription],
) -> str:
    """Render pairs/storage sections, preserving every user-owned line."""
    if not subscriptions:
        return _with_managed_block(existing, "")

    clean = _without_managed_block(existing)
    has_general = re.search(r"(?m)^\[general\]\s*$", clean) is not None
    if clean and not has_general:
        raise SubscriptionError("The existing vdirsyncer config is missing [general].")

    lines: list[str] = []
    if not has_general:
        lines.extend([
            "[general]",
            "status_path = " + _json_value(status_path),
            "",
        ])

    for subscription in subscriptions:
        local_storage = subscription.ident + "_local"
        remote_storage = subscription.ident + "_remote"
        lines.extend([
            f"[pair {subscription.ident}]",
            "a = " + _json_value(local_storage),
            "b = " + _json_value(remote_storage),
            "collections = null",
            'conflict_resolution = "b wins"',
            'partial_sync = "revert"',
            "",
            f"[storage {local_storage}]",
            'type = "filesystem"',
            "path = " + _json_value(subscription.local_path),
            'fileext = ".ics"',
            "",
            f"[storage {remote_storage}]",
            'type = "http"',
            "url = " + _json_value(subscription.url),
            "",
        ])
    return _with_managed_block(existing, "\n".join(lines))


def render_khal_config(
    existing: str,
    subscription_root: Path,
    subscriptions_enabled: bool,
    outlook_root: Path | None = None,
    outlook_enabled: bool = False,
) -> str:
    """Insert II-owned readonly khal sources inside [calendars]."""
    clean = _without_managed_block(existing)
    if not subscriptions_enabled and not outlook_enabled:
        return (clean + "\n") if clean else ""

    calendars = _CALENDARS_HEADER.search(clean)
    if calendars is None:
        raise SubscriptionError("The khal config is missing its [calendars] section.")
    following = _TOP_LEVEL_HEADER.search(clean, calendars.end())
    insertion = following.start() if following else len(clean)
    lines = [BEGIN_MARKER]
    if subscriptions_enabled:
        lines.extend([
            "[[ii_timetable_subscriptions]]",
            f"path = {subscription_root}/*",
            "type = discover",
            "readonly = True",
            "",
        ])
    if outlook_enabled:
        if outlook_root is None:
            raise SubscriptionError("Outlook calendar path is missing.")
        lines.extend([
            "[[ii_timetable_outlook]]",
            f"path = {outlook_root}",
            "type = calendar",
            "readonly = True",
            "",
        ])
    lines.extend([END_MARKER, ""])
    body = "\n".join(lines)
    before = clean[:insertion].rstrip()
    after = clean[insertion:]
    return before + "\n\n" + body + after.lstrip("\n")


def _read_text(path: Path, *, required: bool) -> str:
    if path.exists():
        return path.read_text(encoding="utf-8")
    if required:
        raise SubscriptionError(f"Required config file does not exist: {path}")
    return ""


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    original_mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    file_descriptor, temporary_name = tempfile.mkstemp(prefix=".ii-timetable-", dir=path.parent)
    try:
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as file:
            file.write(text)
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary_name, original_mode)
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def apply_subscriptions(payload: dict[str, Any]) -> dict[str, Any]:
    """Apply desired URLs as the managed part of vdirsyncer and khal configs."""
    vdirsyncer_path = Path(str(payload.get("vdirsyncerConfigPath") or "")).expanduser()
    khal_path = Path(str(payload.get("khalConfigPath") or "")).expanduser()
    status_path = Path(str(payload.get("statusPath") or "")).expanduser()
    subscription_root = Path(str(payload.get("subscriptionRoot") or "")).expanduser()
    raw_outlook_root = str(payload.get("outlookRoot") or "").strip()
    outlook_root = Path(raw_outlook_root).expanduser() if raw_outlook_root else subscription_root.parent / "timetable-outlook"
    outlook_enabled = bool(payload.get("outlookEnabled"))
    if not all((vdirsyncer_path.name, khal_path.name, status_path.name, subscription_root.name, outlook_root.name)):
        raise SubscriptionError("Subscription paths are incomplete.")

    raw_urls = payload.get("subscriptions") or []
    if not isinstance(raw_urls, list):
        raise SubscriptionError("Subscriptions must be a list of URLs.")
    subscriptions = subscriptions_from_urls(raw_urls, subscription_root)

    # Render both files before changing either one. A malformed or missing khal
    # config therefore never leaves a half-created vdirsyncer configuration.
    vdirsyncer_existing = _read_text(vdirsyncer_path, required=False)
    khal_existing = _read_text(khal_path, required=bool(subscriptions) or outlook_enabled)
    vdirsyncer_next = render_vdirsyncer_config(vdirsyncer_existing, status_path, subscriptions)
    khal_next = render_khal_config(
        khal_existing,
        subscription_root,
        bool(subscriptions),
        outlook_root,
        outlook_enabled,
    ) if khal_existing or subscriptions or outlook_enabled else ""

    for subscription in subscriptions:
        subscription.local_path.mkdir(parents=True, exist_ok=True)
    if outlook_enabled:
        outlook_root.mkdir(parents=True, exist_ok=True)
    if subscriptions:
        status_path.mkdir(parents=True, exist_ok=True)

    changed = False
    if vdirsyncer_next != vdirsyncer_existing:
        _atomic_write(vdirsyncer_path, vdirsyncer_next)
        changed = True
    if khal_existing and khal_next != khal_existing:
        _atomic_write(khal_path, khal_next)
        changed = True

    return {
        "ok": True,
        "changed": changed,
        "syncRequired": changed and bool(subscriptions),
        "subscriptions": [
            {"url": item.url, "calendar": item.ident, "readOnly": True}
            for item in subscriptions
        ],
    }


def main() -> None:
    try:
        line = sys.stdin.readline()
        if not line:
            raise SubscriptionError("Expected one JSON request on stdin.")
        payload = json.loads(line)
        if not isinstance(payload, dict):
            raise SubscriptionError("Subscription request must be an object.")
        print(json.dumps(apply_subscriptions(payload)))
    except (SubscriptionError, ValueError, OSError, json.JSONDecodeError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))


if __name__ == "__main__":
    main()
