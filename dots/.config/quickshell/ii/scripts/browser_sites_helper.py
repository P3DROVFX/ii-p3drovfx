#!/usr/bin/env python3
"""Local Mozilla profile, site index, favicon, and private-window helper.

The QML service invokes this script only for coarse background work.  SQLite is
always opened through immutable URIs, so a running browser is never locked and
the launcher's per-keystroke matching remains entirely in memory.
"""

from __future__ import annotations

import argparse
import configparser
import glob
import hashlib
import json
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence
from urllib.parse import quote, unquote, urlsplit


PROFILE_GLOBS = (
    ".*/profiles.ini",
    ".*/*/profiles.ini",
    ".var/app/*/.*/profiles.ini",
    ".var/app/*/.*/*/profiles.ini",
)
PRIVATE_URL_MARKER = "__URL__"
DEFAULT_MAX_CACHE_ENTRIES = 256
MOZLZ4_MAGIC = b"mozLz40\0"
MAX_SESSIONSTORE_COMPRESSED_BYTES = 128 * 1024 * 1024
MAX_SESSIONSTORE_DECOMPRESSED_BYTES = 256 * 1024 * 1024


@dataclass(frozen=True)
class ProfileDiscovery:
    profile_path: Path
    places_path: Path
    places_mtime: float
    profiles_ini: Path | None

    @property
    def favicons_path(self) -> Path:
        return self.profile_path / "favicons.sqlite"


@dataclass(frozen=True)
class PrivateWindowSupport:
    supported: bool = False
    command: list[str] | None = None
    desktop_id: str = ""

    def __post_init__(self) -> None:
        if self.command is None:
            object.__setattr__(self, "command", [])


def _config_parser() -> configparser.ConfigParser:
    return configparser.ConfigParser(interpolation=None, strict=False)


def _candidate(profile_path: Path, ini_path: Path | None) -> ProfileDiscovery | None:
    try:
        profile = profile_path.expanduser().resolve()
        places = profile / "places.sqlite"
        if not profile.is_dir() or not places.is_file():
            return None
        return ProfileDiscovery(profile, places, places.stat().st_mtime, ini_path)
    except OSError:
        return None


def _profile_path(base: Path, raw_path: str, relative: bool) -> Path:
    expanded = os.path.expandvars(raw_path.strip())
    path = Path(expanded).expanduser()
    if relative and not path.is_absolute():
        path = base / path
    return path


def _newest(candidates: Iterable[ProfileDiscovery]) -> ProfileDiscovery | None:
    materialized = list(candidates)
    if not materialized:
        return None
    return max(
        materialized,
        key=lambda item: (item.places_mtime, str(item.profile_path)),
    )


def resolve_profiles_ini(ini_path: str | Path) -> ProfileDiscovery | None:
    """Resolve one profiles.ini using Install, Profile Default, then mtime."""

    ini = Path(ini_path).expanduser().resolve()
    parser = _config_parser()
    try:
        with ini.open("r", encoding="utf-8-sig") as handle:
            parser.read_file(handle)
    except (OSError, configparser.Error, UnicodeError):
        return None

    base = ini.parent
    install_candidates: list[ProfileDiscovery] = []
    for section in parser.sections():
        if not section.lower().startswith("install"):
            continue
        raw_default = parser.get(section, "Default", fallback="").strip()
        if not raw_default:
            continue
        candidate = _candidate(
            _profile_path(base, raw_default, relative=True), ini
        )
        if candidate is not None:
            install_candidates.append(candidate)
    selected = _newest(install_candidates)
    if selected is not None:
        return selected

    profile_candidates: list[tuple[ProfileDiscovery, bool]] = []
    for section in parser.sections():
        if not section.lower().startswith("profile"):
            continue
        raw_path = parser.get(section, "Path", fallback="").strip()
        if not raw_path:
            continue
        is_relative = parser.get(section, "IsRelative", fallback="1").strip() == "1"
        candidate = _candidate(_profile_path(base, raw_path, is_relative), ini)
        if candidate is None:
            continue
        is_default = parser.get(section, "Default", fallback="0").strip() == "1"
        profile_candidates.append((candidate, is_default))

    default_candidates = [item for item, is_default in profile_candidates if is_default]
    if default_candidates:
        return _newest(default_candidates)
    return _newest(item for item, _ in profile_candidates)


def find_profiles_ini(home: str | Path) -> list[Path]:
    home_path = Path(home).expanduser().resolve()
    found: set[Path] = set()
    for pattern in PROFILE_GLOBS:
        for raw_path in glob.glob(str(home_path / pattern)):
            path = Path(raw_path)
            try:
                if path.is_file():
                    found.add(path.resolve())
            except OSError:
                continue
    return sorted(found, key=str)


def _override_path(home: Path, override: str) -> Path:
    raw = override.strip()
    if raw.startswith("file://"):
        raw = unquote(urlsplit(raw).path)
    if raw == "~":
        return home
    if raw.startswith("~/"):
        return home / raw[2:]
    return Path(os.path.expandvars(raw)).expanduser()


def discover_profile(
    home: str | Path | None = None, override: str = ""
) -> ProfileDiscovery | None:
    """Discover the active profile without naming a browser or vendor."""

    home_path = Path(home) if home is not None else Path.home()
    home_path = home_path.expanduser().resolve()
    if override.strip():
        return _candidate(_override_path(home_path, override), None)

    candidates = (
        resolved
        for ini in find_profiles_ini(home_path)
        if (resolved := resolve_profiles_ini(ini)) is not None
    )
    return _newest(candidates)


def immutable_sqlite_uri(database: str | Path) -> str:
    absolute = Path(database).expanduser().resolve()
    return "file:" + quote(str(absolute), safe="/") + "?immutable=1"


def _connect_immutable(database: str | Path) -> sqlite3.Connection:
    return sqlite3.connect(immutable_sqlite_uri(database), uri=True)


def _parsed_http_url(raw_url: str):
    try:
        parsed = urlsplit(raw_url)
    except ValueError:
        return None
    if parsed.scheme.lower() not in ("http", "https") or not parsed.hostname:
        return None
    return parsed


def _host_for_parsed(parsed) -> str:
    hostname = (parsed.hostname or "").lower().rstrip(".")
    try:
        port = parsed.port
    except ValueError:
        port = None
    if port is None or (parsed.scheme.lower() == "http" and port == 80) or (
        parsed.scheme.lower() == "https" and port == 443
    ):
        return hostname
    return f"{hostname}:{port}"


def _history_root_url(parsed) -> str:
    hostname = (parsed.hostname or "").lower().rstrip(".")
    authority = f"[{hostname}]" if ":" in hostname else hostname
    try:
        port = parsed.port
    except ValueError:
        port = None
    if port is not None and not (
        (parsed.scheme.lower() == "http" and port == 80)
        or (parsed.scheme.lower() == "https" and port == 443)
    ):
        authority += f":{port}"
    return f"{parsed.scheme.lower()}://{authority}/"


def _site_record(
    title: str, url: str, frecency: int, bookmarked: bool, parsed=None
) -> dict[str, object]:
    parsed = parsed or _parsed_http_url(url)
    if parsed is None:
        raise ValueError("Not an HTTP(S) URL")
    return {
        "title": title.strip(),
        "url": url,
        "host": _host_for_parsed(parsed),
        "path": parsed.path or "/",
        "frecency": int(frecency),
        "bookmarked": bool(bookmarked),
        "source": "favorite" if bookmarked else "suggested",
    }


def _sessionstore_candidates(profile_path: str | Path) -> list[Path]:
    backup_dir = Path(profile_path).expanduser() / "sessionstore-backups"
    return [
        backup_dir / "recovery.jsonlz4",
        backup_dir / "recovery.baklz4",
        backup_dir / "previous.jsonlz4",
    ]


def active_sessionstore(profile_path: str | Path) -> Path | None:
    """Return the freshest live-session snapshot in Firefox preference order."""

    for candidate in _sessionstore_candidates(profile_path):
        try:
            if candidate.is_file() and candidate.stat().st_size > len(MOZLZ4_MAGIC) + 4:
                return candidate
        except OSError:
            continue
    return None


def sessionstore_status(profile_path: str | Path) -> tuple[str, float]:
    path = active_sessionstore(profile_path)
    if path is None:
        return "", 0.0
    try:
        return str(path), path.stat().st_mtime
    except OSError:
        return "", 0.0


def decompress_mozlz4(raw: bytes) -> bytes:
    """Decode Firefox's mozLz4 wrapper without a third-party dependency."""

    if not raw.startswith(MOZLZ4_MAGIC) or len(raw) < len(MOZLZ4_MAGIC) + 4:
        raise ValueError("Not a Mozilla LZ4 session")
    expected_size = int.from_bytes(raw[8:12], "little")
    if expected_size < 0 or expected_size > MAX_SESSIONSTORE_DECOMPRESSED_BYTES:
        raise ValueError("Mozilla session is larger than the safety limit")

    source = memoryview(raw)[12:]
    output = bytearray()
    cursor = 0
    while cursor < len(source):
        token = source[cursor]
        cursor += 1

        literal_length = token >> 4
        if literal_length == 15:
            while True:
                if cursor >= len(source):
                    raise ValueError("Truncated Mozilla LZ4 literal length")
                extension = source[cursor]
                cursor += 1
                literal_length += extension
                if extension != 255:
                    break
        literal_end = cursor + literal_length
        if literal_end > len(source):
            raise ValueError("Truncated Mozilla LZ4 literals")
        output.extend(source[cursor:literal_end])
        cursor = literal_end
        if len(output) > MAX_SESSIONSTORE_DECOMPRESSED_BYTES:
            raise ValueError("Mozilla session exceeds the safety limit")
        if cursor >= len(source):
            break

        if cursor + 2 > len(source):
            raise ValueError("Truncated Mozilla LZ4 match offset")
        offset = int(source[cursor]) | (int(source[cursor + 1]) << 8)
        cursor += 2
        if offset <= 0 or offset > len(output):
            raise ValueError("Invalid Mozilla LZ4 match offset")

        match_length = (token & 0x0F) + 4
        if (token & 0x0F) == 15:
            while True:
                if cursor >= len(source):
                    raise ValueError("Truncated Mozilla LZ4 match length")
                extension = source[cursor]
                cursor += 1
                match_length += extension
                if extension != 255:
                    break
        if len(output) + match_length > MAX_SESSIONSTORE_DECOMPRESSED_BYTES:
            raise ValueError("Mozilla session exceeds the safety limit")
        while match_length > 0:
            chunk_length = min(match_length, offset)
            start = len(output) - offset
            output.extend(output[start:start + chunk_length])
            match_length -= chunk_length

    if len(output) != expected_size:
        raise ValueError("Mozilla LZ4 size does not match its header")
    return bytes(output)


def read_open_tabs(profile_path: str | Path) -> list[dict[str, object]]:
    """Read the current HTTP(S) tab entries from Firefox sessionstore."""

    session_path = active_sessionstore(profile_path)
    if session_path is None:
        return []
    try:
        compressed_size = session_path.stat().st_size
        if compressed_size > MAX_SESSIONSTORE_COMPRESSED_BYTES:
            return []
        session = json.loads(decompress_mozlz4(session_path.read_bytes()))
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return []

    windows = session.get("windows", []) if isinstance(session, dict) else []
    if not isinstance(windows, list):
        return []
    selected_window = max(0, int(session.get("selectedWindow", 1) or 1) - 1)
    by_url: dict[str, dict[str, object]] = {}
    for window_index, window in enumerate(windows):
        if not isinstance(window, dict):
            continue
        tabs = window.get("tabs", [])
        if not isinstance(tabs, list):
            continue
        selected_tab = max(0, int(window.get("selected", 1) or 1) - 1)
        for tab_index, tab in enumerate(tabs):
            if not isinstance(tab, dict):
                continue
            entries = tab.get("entries", [])
            if not isinstance(entries, list) or not entries:
                continue
            entry_index = max(0, int(tab.get("index", len(entries)) or len(entries)) - 1)
            entry = entries[min(entry_index, len(entries) - 1)]
            if not isinstance(entry, dict):
                continue
            url = str(entry.get("url", ""))
            parsed = _parsed_http_url(url)
            if parsed is None:
                continue
            title = str(entry.get("title") or "").strip() or _host_for_parsed(parsed)
            record = _site_record(title, url, 0, False, parsed)
            record.update({
                "source": "open",
                "selected": window_index == selected_window and tab_index == selected_tab,
                "pinned": bool(tab.get("pinned", False)),
                "lastAccessed": int(tab.get("lastAccessed", 0) or 0),
                "tabCount": 1,
            })
            existing = by_url.get(url)
            if existing is None:
                by_url[url] = record
                continue
            count = int(existing.get("tabCount", 1)) + 1
            existing_priority = (
                bool(existing.get("selected")),
                bool(existing.get("pinned")),
                int(existing.get("lastAccessed", 0)),
            )
            record_priority = (
                bool(record.get("selected")),
                bool(record.get("pinned")),
                int(record.get("lastAccessed", 0)),
            )
            chosen = record if record_priority > existing_priority else existing
            chosen["selected"] = bool(existing.get("selected")) or bool(record.get("selected"))
            chosen["pinned"] = bool(existing.get("pinned")) or bool(record.get("pinned"))
            chosen["lastAccessed"] = max(
                int(existing.get("lastAccessed", 0)),
                int(record.get("lastAccessed", 0)),
            )
            chosen["tabCount"] = count
            by_url[url] = chosen

    tabs = list(by_url.values())
    tabs.sort(key=lambda site: (
        not bool(site.get("selected")),
        not bool(site.get("pinned")),
        -int(site.get("lastAccessed", 0)),
        str(site.get("url", "")),
    ))
    return tabs


def merge_site_sources(
    open_tabs: Sequence[dict[str, object]],
    indexed_sites: Sequence[dict[str, object]],
) -> list[dict[str, object]]:
    """Merge live tabs over bookmarks/history without ambiguous duplicates."""

    indexed_by_url = {str(site.get("url", "")): site for site in indexed_sites}
    open_urls: set[str] = set()
    open_hosts: set[str] = set()
    merged_tabs: list[dict[str, object]] = []
    for raw_tab in open_tabs:
        tab = dict(raw_tab)
        url = str(tab.get("url", ""))
        host = str(tab.get("host", ""))
        if not url:
            continue
        base = indexed_by_url.get(url)
        if base is not None:
            tab["bookmarked"] = bool(base.get("bookmarked", False))
            tab["frecency"] = int(base.get("frecency", 0))
        tab["source"] = "open"
        open_urls.add(url)
        if host:
            open_hosts.add(host)
        merged_tabs.append(tab)

    remaining = []
    for site in indexed_sites:
        url = str(site.get("url", ""))
        host = str(site.get("host", ""))
        if url in open_urls:
            continue
        if site.get("source") == "suggested" and host in open_hosts:
            continue
        remaining.append(dict(site))
    return merged_tabs + remaining


def build_index(
    places_path: str | Path,
    include_history: bool = True,
    max_indexed_sites: int = 300,
) -> list[dict[str, object]]:
    """Build the compact bookmark/history index from an immutable database."""

    max_history = max(0, int(max_indexed_sites))
    bookmark_query = """
        SELECT p.title, p.url, p.frecency, b.title
        FROM moz_bookmarks AS b
        JOIN moz_places AS p ON p.id = b.fk
        WHERE b.type = 1
          AND (p.url LIKE 'http://%' OR p.url LIKE 'https://%')
        ORDER BY p.id ASC, b.id ASC
    """
    history_query = """
        SELECT p.title, p.url, p.frecency
        FROM moz_places AS p
        WHERE (p.url LIKE 'http://%' OR p.url LIKE 'https://%')
          AND p.title IS NOT NULL
          AND TRIM(p.title) <> ''
          AND p.frecency > 0
          AND NOT EXISTS (
              SELECT 1 FROM moz_bookmarks AS b
              WHERE b.fk = p.id AND b.type = 1
              LIMIT 1
          )
        ORDER BY p.frecency DESC, p.id ASC
    """
    bookmarks_by_url: dict[str, tuple[dict[str, object], int]] = {}
    bookmark_root_hosts: set[str] = set()
    history: list[dict[str, object]] = []

    with closing(_connect_immutable(places_path)) as connection:
        for place_title, url, frecency, bookmark_title in connection.execute(
            bookmark_query
        ):
            parsed = _parsed_http_url(str(url))
            if parsed is None:
                continue
            clean_bookmark_title = str(bookmark_title or "").strip()
            clean_place_title = str(place_title or "").strip()
            if clean_bookmark_title:
                title = clean_bookmark_title
                title_priority = 2
            elif clean_place_title:
                title = clean_place_title
                title_priority = 1
            else:
                title = _host_for_parsed(parsed)
                title_priority = 0
            exact_url = str(url)
            numeric_frecency = int(frecency or 0)
            existing = bookmarks_by_url.get(exact_url)
            if existing is None:
                bookmarks_by_url[exact_url] = (
                    _site_record(title, exact_url, numeric_frecency, True, parsed),
                    title_priority,
                )
            else:
                record, existing_priority = existing
                if title_priority > existing_priority:
                    record["title"] = title
                    existing_priority = title_priority
                record["frecency"] = max(int(record["frecency"]), numeric_frecency)
                bookmarks_by_url[exact_url] = (record, existing_priority)

        bookmarks = [record for record, _priority in bookmarks_by_url.values()]
        bookmarks.sort(key=lambda site: (-int(site["frecency"]), str(site["url"])))
        for record in bookmarks:
            parsed = _parsed_http_url(str(record["url"]))
            if parsed is not None and (parsed.path in ("", "/")) and not parsed.query:
                bookmark_root_hosts.add(str(record["host"]))

        if include_history and max_history > 0:
            seen_history_hosts: set[str] = set()
            for title, url, frecency in connection.execute(history_query):
                parsed = _parsed_http_url(str(url))
                clean_title = str(title or "").strip()
                if parsed is None or not clean_title or int(frecency) <= 0:
                    continue
                host = _host_for_parsed(parsed)
                if host in seen_history_hosts or host in bookmark_root_hosts:
                    continue
                seen_history_hosts.add(host)
                root_url = _history_root_url(parsed)
                history.append(
                    _site_record(
                        clean_title,
                        root_url,
                        int(frecency),
                        False,
                        _parsed_http_url(root_url),
                    )
                )
                if len(history) >= max_history:
                    break
    return bookmarks + history


def _normalized_favicon_host(url_or_host: str) -> str:
    parsed = _parsed_http_url(url_or_host)
    if parsed is not None:
        return (parsed.hostname or "").lower().rstrip(".")
    value = url_or_host.strip().lower().rstrip(".")
    if "/" in value or not value:
        return ""
    bracketed = re.fullmatch(r"\[([^]]+)](?::\d+)?", value)
    if bracketed:
        return bracketed.group(1)
    host_with_port = re.fullmatch(r"([^:]+)(?::\d+)?", value)
    if host_with_port:
        return host_with_port.group(1)
    # An unbracketed value containing multiple colons is an IPv6 hostname, not
    # a hostname/port pair.
    return value


def favicon_cache_path(cache_dir: str | Path, host: str) -> Path | None:
    normalized = _normalized_favicon_host(host)
    if not normalized:
        return None
    digest = hashlib.sha1(normalized.encode("utf-8")).hexdigest()
    return Path(cache_dir).expanduser() / f"{digest}.png"


def _favicon_size_rank(width: object) -> tuple[int, int]:
    try:
        value = int(width or 0)
    except (TypeError, ValueError):
        value = 0
    if 0 < value <= 64:
        return (0, -value)
    if value > 64:
        return (1, value)
    return (2, 0)


def _favicon_bytes(database: Path, page_url: str) -> bytes | None:
    parsed = _parsed_http_url(page_url)
    if parsed is None:
        return None
    root_url = _history_root_url(parsed)
    host_prefixes = (
        f"http://{_host_for_parsed(parsed)}/%",
        f"https://{_host_for_parsed(parsed)}/%",
    )
    query = """
        SELECT i.data, i.width, p.page_url
        FROM moz_icons AS i
        JOIN moz_icons_to_pages AS relation ON relation.icon_id = i.id
        JOIN moz_pages_w_icons AS p ON p.id = relation.page_id
        WHERE p.page_url = ? OR p.page_url = ?
           OR p.page_url LIKE ? OR p.page_url LIKE ?
    """
    best_key: tuple[tuple[int, int], int] | None = None
    best_data: bytes | None = None
    with closing(_connect_immutable(database)) as connection:
        for data, width, associated_url in connection.execute(
            query, (page_url, root_url, *host_prefixes)
        ):
            if not isinstance(data, bytes) or not data:
                continue
            associated = _parsed_http_url(str(associated_url))
            if associated is None or _normalized_favicon_host(str(associated_url)) != (
                parsed.hostname or ""
            ).lower().rstrip("."):
                continue
            association_rank = 0 if associated_url == page_url else (
                1 if associated_url == root_url else 2
            )
            candidate_key = (_favicon_size_rank(width), association_rank)
            if best_key is None or candidate_key < best_key:
                best_key = candidate_key
                best_data = data
    return best_data


def _prune_favicon_cache(cache_dir: Path, max_cache_entries: int, keep: Path) -> None:
    limit = max(1, int(max_cache_entries))
    try:
        entries = [path for path in cache_dir.glob("*.png") if path.is_file()]
        if len(entries) <= limit:
            return
        entries.sort(key=lambda path: (path.stat().st_mtime, path.name))
        removable = [path for path in entries if path != keep]
        for path in removable[: max(0, len(entries) - limit)]:
            path.unlink(missing_ok=True)
    except OSError:
        return


def extract_favicon(
    profile_path: str | Path,
    page_url: str,
    cache_dir: str | Path,
    max_cache_entries: int = DEFAULT_MAX_CACHE_ENTRIES,
) -> Path | None:
    """Extract one modern Mozilla favicon with an atomic bounded cache write."""

    profile = Path(profile_path).expanduser()
    database = profile / "favicons.sqlite"
    target = favicon_cache_path(cache_dir, page_url)
    if target is None:
        return None
    try:
        if target.is_file() and target.stat().st_size > 0:
            os.utime(target, None)
            _prune_favicon_cache(target.parent, max_cache_entries, target)
            return target.resolve()
        if not database.is_file():
            return None
        data = _favicon_bytes(database, page_url)
        if not data:
            return None
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary_name = ""
        try:
            with tempfile.NamedTemporaryFile(
                mode="wb",
                prefix=f".{target.stem}.",
                suffix=".tmp",
                dir=target.parent,
                delete=False,
            ) as temporary:
                temporary_name = temporary.name
                temporary.write(data)
                temporary.flush()
                os.fsync(temporary.fileno())
            os.replace(temporary_name, target)
        finally:
            if temporary_name:
                try:
                    Path(temporary_name).unlink(missing_ok=True)
                except OSError:
                    pass
        _prune_favicon_cache(target.parent, max_cache_entries, target)
        return target.resolve()
    except (OSError, sqlite3.Error, ValueError):
        return None


def _mimeapps_candidates(
    config_home: Path, data_home: Path, data_dirs: Sequence[Path]
) -> list[Path]:
    return [
        config_home / "mimeapps.list",
        data_home / "applications" / "mimeapps.list",
        *(directory / "applications" / "mimeapps.list" for directory in data_dirs),
    ]


def _default_handler_from_mimeapps(paths: Iterable[Path]) -> str:
    for path in paths:
        parser = _config_parser()
        try:
            with path.open("r", encoding="utf-8-sig") as handle:
                parser.read_file(handle)
        except (OSError, configparser.Error, UnicodeError):
            continue
        if not parser.has_section("Default Applications"):
            continue
        for mime in ("x-scheme-handler/https", "x-scheme-handler/http"):
            value = parser.get("Default Applications", mime, fallback="")
            desktop_id = value.split(";", 1)[0].strip()
            if desktop_id:
                return desktop_id
    return ""


def _default_handler_from_xdg_mime() -> str:
    try:
        completed = subprocess.run(
            ["xdg-mime", "query", "default", "x-scheme-handler/https"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip().splitlines()[0] if completed.stdout.strip() else ""


def _desktop_file(
    desktop_id: str, data_home: Path, data_dirs: Sequence[Path]
) -> Path | None:
    bases = [data_home, *data_dirs]
    for base in bases:
        applications = base / "applications"
        direct = applications / desktop_id
        if direct.is_file():
            return direct
        try:
            for candidate in applications.rglob("*.desktop"):
                relative_id = str(candidate.relative_to(applications)).replace(os.sep, "-")
                if candidate.name == desktop_id or relative_id == desktop_id:
                    return candidate
        except OSError:
            continue
    return None


_URL_FIELD_CODE = re.compile(r"%[uUfF]")
_OTHER_FIELD_CODE = re.compile(r"%[ickdDnNvVm]")


def _private_exec_command(exec_line: str) -> list[str]:
    try:
        tokens = shlex.split(exec_line, posix=True)
    except ValueError:
        return []
    if "--private-window" not in tokens or not tokens:
        return []
    command: list[str] = []
    placed_url = False
    for token in tokens:
        if token == "%i":
            continue
        if _URL_FIELD_CODE.search(token):
            replaced = _URL_FIELD_CODE.sub(PRIVATE_URL_MARKER, token)
            command.append(replaced)
            placed_url = True
            continue
        cleaned = _OTHER_FIELD_CODE.sub("", token).replace("%%", "%")
        if cleaned:
            command.append(cleaned)
    if not placed_url:
        command.append(PRIVATE_URL_MARKER)
    return command


def discover_private_window(
    config_home: str | Path | None = None,
    data_home: str | Path | None = None,
    data_dirs: Sequence[str | Path] | None = None,
    desktop_id: str = "",
) -> PrivateWindowSupport:
    """Prove private-window support from the default handler's desktop file."""

    explicit_paths = (
        config_home is not None or data_home is not None or data_dirs is not None
    )
    config = Path(config_home or os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser()
    data = Path(data_home or os.environ.get("XDG_DATA_HOME", "~/.local/share")).expanduser()
    if data_dirs is None:
        raw_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
        directories = [Path(value) for value in raw_dirs.split(":") if value]
    else:
        directories = [Path(value) for value in data_dirs]

    handler = desktop_id.strip()
    if not handler and not explicit_paths:
        handler = _default_handler_from_xdg_mime()
    if not handler:
        handler = _default_handler_from_mimeapps(
            _mimeapps_candidates(config, data, directories)
        )
    if not handler:
        return PrivateWindowSupport()
    desktop = _desktop_file(handler, data, directories)
    if desktop is None:
        return PrivateWindowSupport()

    parser = _config_parser()
    try:
        with desktop.open("r", encoding="utf-8-sig") as handle:
            parser.read_file(handle)
    except (OSError, configparser.Error, UnicodeError):
        return PrivateWindowSupport()
    for section in parser.sections():
        exec_line = parser.get(section, "Exec", fallback="").strip()
        if not exec_line:
            continue
        command = _private_exec_command(exec_line)
        if command:
            return PrivateWindowSupport(True, command, handler)
    return PrivateWindowSupport()


def _path_uri(path: Path) -> str:
    return path.resolve().as_uri()


def _profile_payload(discovery: ProfileDiscovery) -> dict[str, object]:
    session_path, session_mtime = sessionstore_status(discovery.profile_path)
    return {
        "profilePath": str(discovery.profile_path),
        "placesPath": str(discovery.places_path),
        "placesMtime": discovery.places_mtime,
        "faviconsPath": str(discovery.favicons_path),
        "sessionPath": session_path,
        "sessionMtime": session_mtime,
        "profilesIni": str(discovery.profiles_ini or ""),
    }


def _discover_from_args(args) -> ProfileDiscovery | None:
    return discover_profile(args.home, override=getattr(args, "profile", ""))


def _command_discover(args) -> tuple[dict[str, object], int]:
    discovery = _discover_from_args(args)
    if discovery is None:
        return {"ok": False, "error": "No valid Mozilla profile with places.sqlite found"}, 1
    return {"ok": True, **_profile_payload(discovery)}, 0


def _command_status(args) -> tuple[dict[str, object], int]:
    return _command_discover(args)


def _command_build(args) -> tuple[dict[str, object], int]:
    discovery = _discover_from_args(args)
    if discovery is None:
        return {"ok": False, "error": "No valid Mozilla profile with places.sqlite found"}, 1
    try:
        indexed_sites = build_index(
            discovery.places_path,
            include_history=bool(args.include_history),
            max_indexed_sites=args.max_indexed_sites,
        )
        sites = merge_site_sources(
            read_open_tabs(discovery.profile_path),
            indexed_sites,
        )
    except (OSError, sqlite3.Error, ValueError) as error:
        return {"ok": False, "error": f"Could not read places.sqlite: {error}"}, 1

    cache_dir = Path(args.cache_dir).expanduser()
    for site in sites:
        cached = favicon_cache_path(cache_dir, str(site["host"]))
        if cached is not None:
            try:
                if cached.is_file() and cached.stat().st_size > 0:
                    site["favicon"] = _path_uri(cached)
            except OSError:
                pass

    private = discover_private_window()
    return {
        "ok": True,
        **_profile_payload(discovery),
        "sites": sites,
        "privateBrowsingSupported": private.supported,
        "privateCommand": private.command,
        "defaultHandlerDesktopId": private.desktop_id,
    }, 0


def _command_favicon(args) -> tuple[dict[str, object], int]:
    path = extract_favicon(
        args.profile,
        args.url,
        args.cache_dir,
        max_cache_entries=args.max_cache_entries,
    )
    host = _normalized_favicon_host(args.url)
    if path is None:
        return {"ok": False, "host": host, "error": "No local favicon available"}, 1
    return {"ok": True, "host": host, "path": str(path), "source": _path_uri(path)}, 0


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_discovery_arguments(subparser) -> None:
        subparser.add_argument("--home", default=str(Path.home()))
        subparser.add_argument("--profile", default="")

    discover = subparsers.add_parser("discover")
    add_discovery_arguments(discover)
    discover.set_defaults(handler=_command_discover)

    status = subparsers.add_parser("status")
    add_discovery_arguments(status)
    status.set_defaults(handler=_command_status)

    build = subparsers.add_parser("build")
    add_discovery_arguments(build)
    build.add_argument("--max-indexed-sites", type=int, default=300)
    build.add_argument("--include-history", type=int, choices=(0, 1), default=1)
    build.add_argument("--cache-dir", required=True)
    build.set_defaults(handler=_command_build)

    favicon = subparsers.add_parser("favicon")
    favicon.add_argument("--profile", required=True)
    favicon.add_argument("--url", required=True)
    favicon.add_argument("--cache-dir", required=True)
    favicon.add_argument(
        "--max-cache-entries", type=int, default=DEFAULT_MAX_CACHE_ENTRIES
    )
    favicon.set_defaults(handler=_command_favicon)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_argument_parser()
    args = parser.parse_args(argv)
    try:
        payload, exit_code = args.handler(args)
    except Exception as error:  # Last-resort JSON contract for the QML caller.
        payload, exit_code = {"ok": False, "error": str(error)}, 1
    json.dump(payload, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
