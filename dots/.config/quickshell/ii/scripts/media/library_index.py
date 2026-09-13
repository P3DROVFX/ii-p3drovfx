#!/usr/bin/env python3
"""Incremental, local-only scanner used before a local-media session commits.

The scanner writes JSON Lines so its caller can discard a stale candidate or
terminate the child without changing the active MPV session.  It never plays
files and it never mutates playlists; `local_player.py` receives a completed,
validated manifest only after the scanner emits ``finished``.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import sys
from collections.abc import Iterator, Sequence
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

try:
    import mutagen
except ImportError as error:  # pragma: no cover - reported in scanner output
    mutagen = None
    _MUTAGEN_IMPORT_ERROR = error
else:
    _MUTAGEN_IMPORT_ERROR = None

AUDIO_SUFFIXES = frozenset({".aac", ".aiff", ".alac", ".ape", ".flac", ".m4a", ".m4b", ".mp3", ".ogg", ".oga", ".opus", ".wav", ".wma"})
PLAYLIST_SUFFIXES = frozenset({".m3u", ".m3u8"})
COVER_SUFFIXES = (".jpg", ".jpeg", ".png", ".webp")
LYRICS_SUFFIXES = (".lrc", ".ttml", ".xml", ".txt")


def message(name: str, **payload: object) -> dict[str, object]:
    return {"event": name, "payload": payload}


def local_path(value: str) -> Path:
    parsed = urlparse(value)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path)).expanduser().resolve(strict=False)
    return Path(value).expanduser().resolve(strict=False)


def track_identity(path: Path) -> str:
    """Stable identity for one music file; queue occurrences still get own IDs."""

    try:
        stat = path.stat()
        material = f"{path}\0{stat.st_dev}\0{stat.st_ino}"
    except OSError:
        material = str(path)
    return hashlib.sha256(material.encode("utf-8", "surrogateescape")).hexdigest()


def _first_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, (list, tuple)):
        for item in value:
            text = _first_text(item)
            if text:
                return text
        return ""
    if hasattr(value, "text"):
        return _first_text(getattr(value, "text"))
    text = str(value).strip()
    return text


def _easy_tags(path: Path) -> tuple[str, str, str, float]:
    if mutagen is None:
        raise RuntimeError(f"Mutagen is unavailable: {_MUTAGEN_IMPORT_ERROR}")
    try:
        easy = mutagen.File(path, easy=True)
        full = mutagen.File(path, easy=False)
    except Exception as error:
        # A chosen ``.mp3`` can be truncated, renamed data or otherwise fail
        # before Mutagen creates an object.  It is an invalid import candidate,
        # not a scanner crash that should discard the current session.
        raise ValueError("unsupported or unreadable audio") from error
    if full is None or getattr(full, "info", None) is None:
        raise ValueError("unsupported or unreadable audio")
    tags = getattr(easy, "tags", None) or {}
    title = _first_text(tags.get("title"))
    artist = _first_text(tags.get("artist"))
    album = _first_text(tags.get("album"))
    duration = max(0.0, float(getattr(full.info, "length", 0.0) or 0.0))
    return title, artist, album, duration


def _embedded_cover(path: Path, cache_dir: Path) -> Path | None:
    """Extract common Mutagen artwork containers into a deterministic cache file."""

    if mutagen is None:
        return None
    try:
        audio = mutagen.File(path, easy=False)
    except Exception:
        return None
    if audio is None:
        return None

    data: bytes | None = None
    mime = ""
    pictures = getattr(audio, "pictures", None)
    if pictures:
        picture = pictures[0]
        data = bytes(getattr(picture, "data", b"") or b"")
        mime = str(getattr(picture, "mime", "") or "")
    tags = getattr(audio, "tags", None)
    if data is None and tags:
        for value in tags.values():
            candidate = getattr(value, "data", None)
            if isinstance(candidate, (bytes, bytearray)):
                data = bytes(candidate)
                mime = str(getattr(value, "mime", "") or "")
                break
        if data is None:
            for key in ("covr", "metadata_block_picture"):
                value = tags.get(key)
                if not value:
                    continue
                raw = value[0] if isinstance(value, (list, tuple)) else value
                if key == "metadata_block_picture":
                    try:
                        raw = base64.b64decode(raw)
                    except (ValueError, TypeError):
                        continue
                if isinstance(raw, (bytes, bytearray)):
                    data = bytes(raw)
                    break
    if not data:
        return None

    suffix = mimetypes.guess_extension(mime) or ".jpg"
    key = hashlib.sha256(data).hexdigest()
    target = cache_dir / f"{key}{suffix}"
    if target.is_file():
        return target
    cache_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, target)
    return target


def _folder_cover(path: Path) -> Path | None:
    for stem in ("cover", "folder", "front", "albumart"):
        for suffix in COVER_SUFFIXES:
            candidate = path.parent / f"{stem}{suffix}"
            if candidate.is_file():
                return candidate
    return None


def _sidecar_lyrics(path: Path) -> Path | None:
    """Return a readable LRC/TXT sidecar paired with an audio file."""

    for suffix in LYRICS_SUFFIXES:
        candidate = path.with_suffix(suffix)
        if candidate.is_file() and os.access(candidate, os.R_OK):
            return candidate
    return None


def describe_track(path: Path, cache_dir: Path) -> dict[str, object]:
    resolved = path.expanduser().resolve(strict=False)
    if resolved.suffix.lower() not in AUDIO_SUFFIXES:
        raise ValueError("unsupported extension")
    if not resolved.is_file() or not os.access(resolved, os.R_OK):
        raise ValueError("file is not readable")
    title, artist, album, duration = _easy_tags(resolved)
    cover = _embedded_cover(resolved, cache_dir) or _folder_cover(resolved)
    lyrics = _sidecar_lyrics(resolved)
    try:
        st = resolved.stat()
        mtime = float(st.st_mtime)
        ctime = float(getattr(st, "st_birthtime", st.st_ctime))
    except OSError:
        mtime = 0.0
        ctime = 0.0
    return {
        "path": str(resolved),
        "trackId": track_identity(resolved),
        "title": title or resolved.stem,
        "artist": artist,
        "album": album,
        "durationSec": duration,
        "artUrl": cover.as_uri() if cover else "",
        "lyricsPath": str(lyrics) if lyrics else "",
        "mtime": mtime,
        "ctime": ctime,
    }


def playlist_paths(path: Path) -> Iterator[Path]:
    try:
        lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
    except OSError as error:
        raise ValueError(f"could not read playlist: {error}") from error
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parsed = urlparse(line)
        if parsed.scheme and parsed.scheme != "file":
            continue
        candidate = local_path(line) if parsed.scheme == "file" else (path.parent / line).expanduser().resolve(strict=False)
        yield candidate


def candidate_paths(paths: Sequence[Path], *, folder: bool) -> Iterator[Path]:
    if folder:
        root = paths[0]
        if not root.is_dir():
            raise ValueError("selected folder is not readable")

        def walk_directory(directory: Path) -> Iterator[Path]:
            try:
                children = sorted(directory.iterdir(), key=lambda child: child.name.casefold())
            except OSError:
                return
            # Directories are traversed before files. This gives a stable,
            # human-readable recursive order without collecting a large folder
            # before the first metadata result can be emitted.
            for child in children:
                if child.is_dir() and not child.is_symlink():
                    yield from walk_directory(child)
            for child in children:
                if child.is_file() and child.suffix.lower() in AUDIO_SUFFIXES:
                    yield child

        yield from walk_directory(root)
        return

    for path in paths:
        suffix = path.suffix.lower()
        if suffix in PLAYLIST_SUFFIXES:
            yield from playlist_paths(path)
        else:
            yield path


def scan(
    paths: Sequence[Path],
    *,
    request_id: str,
    folder: bool,
    cache_dir: Path,
) -> Iterator[dict[str, object]]:
    """Yield progress and a final transactional manifest for one candidate."""

    yield message("started", requestId=request_id)
    accepted: list[dict[str, object]] = []
    skipped = 0
    playlist_requested = not folder and any(path.suffix.lower() in PLAYLIST_SUFFIXES for path in paths)
    try:
        candidates = candidate_paths(paths, folder=folder)
        for candidate in candidates:
            try:
                track = describe_track(candidate, cache_dir)
            except (OSError, ValueError, RuntimeError) as error:
                skipped += 1
                yield message("skipped", requestId=request_id, path=str(candidate), reason=str(error))
                continue
            accepted.append(track)
            yield message("track", requestId=request_id, track=track, accepted=len(accepted), skipped=skipped)
    except ValueError as error:
        yield message("failed", requestId=request_id, message=str(error))
        return

    yield message(
        "finished",
        requestId=request_id,
        entries=accepted,
        skipped=skipped,
        sessionKind="playlist" if folder or playlist_requested or len(accepted) > 1 else "single",
    )


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ii local-media scanner")
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument("--folder")
    selection.add_argument("--path", action="append", default=[])
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--cache-dir", type=Path, default=Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell" / "media" / "local-media" / "covers")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    paths = [local_path(args.folder)] if args.folder else [local_path(value) for value in args.path]
    for record in scan(paths, request_id=args.request_id, folder=bool(args.folder), cache_dir=args.cache_dir):
        print(json.dumps(record, ensure_ascii=False, separators=(",", ":")), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
