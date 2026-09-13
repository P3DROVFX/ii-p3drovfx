#!/usr/bin/env python3
"""Pure, ID-based queue state for the local player.

This is intentionally independent of mpv.  mpv entry IDs are temporary process
details, while `QueueEntry.entry_id` identifies one occurrence in the user's
queue, including deliberate duplicates of the same file.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from random import SystemRandom
from typing import Iterable
from uuid import uuid4


class QueueError(ValueError):
    pass


@dataclass(frozen=True)
class QueueEntry:
    entry_id: str
    track_id: str
    path: str
    title: str
    artist: str = ""
    album: str = ""
    art_url: str = ""
    lyrics_path: str = ""
    duration_sec: float | None = None
    mtime: float = 0.0
    ctime: float = 0.0

    @classmethod
    def create(
        cls,
        path: str | Path,
        *,
        track_id: str | None = None,
        title: str | None = None,
        artist: str = "",
        album: str = "",
        art_url: str = "",
        lyrics_path: str = "",
        duration_sec: float | None = None,
        mtime: float = 0.0,
        ctime: float = 0.0,
    ) -> "QueueEntry":
        resolved_path = str(Path(path).expanduser().resolve(strict=False))
        if not resolved_path:
            raise QueueError("path must not be empty")
        if duration_sec is not None and duration_sec < 0:
            raise QueueError("duration_sec must be non-negative")
        if mtime == 0.0 or ctime == 0.0:
            try:
                st = Path(resolved_path).stat()
                if mtime == 0.0:
                    mtime = float(st.st_mtime)
                if ctime == 0.0:
                    ctime = float(getattr(st, "st_birthtime", st.st_ctime))
            except OSError:
                pass
        return cls(
            entry_id=uuid4().hex,
            track_id=track_id or uuid4().hex,
            path=resolved_path,
            title=title or Path(resolved_path).stem,
            artist=artist,
            album=album,
            art_url=art_url,
            lyrics_path=lyrics_path,
            duration_sec=duration_sec,
            mtime=mtime,
            ctime=ctime,
        )

    def snapshot(self) -> dict[str, object]:
        return {
            "entryId": self.entry_id,
            "trackId": self.track_id,
            "path": self.path,
            "title": self.title,
            "artist": self.artist,
            "album": self.album,
            "artUrl": self.art_url,
            "lyricsPath": self.lyrics_path,
            "durationSec": self.duration_sec,
            "mtime": self.mtime,
            "ctime": self.ctime,
        }


@dataclass
class QueueStore:
    """Single-writer queue model with stable IDs and monotonic revisions."""

    entries: list[QueueEntry] = field(default_factory=list)
    base_entries: list[QueueEntry] = field(default_factory=list)
    session_kind: str = "empty"
    playlist_open: bool = False
    current_entry_id: str | None = None
    history: list[str] = field(default_factory=list)
    shuffle_enabled: bool = False
    revision: int = 0
    _cached_entries: list[dict[str, object]] = field(default_factory=list, init=False, repr=False)
    _cached_revision: int = field(default=-1, init=False, repr=False)

    def _validate_unique_entries(self, entries: Iterable[QueueEntry]) -> list[QueueEntry]:
        result = list(entries)
        ids = [entry.entry_id for entry in result]
        if len(ids) != len(set(ids)):
            raise QueueError("queue entry IDs must be unique")
        return result

    def _bump(self) -> None:
        self.revision += 1

    def _entry_index(self, entry_id: str) -> int:
        for index, entry in enumerate(self.entries):
            if entry.entry_id == entry_id:
                return index
        raise QueueError(f"unknown queue entry: {entry_id}")

    def index_of(self, entry_id: str) -> int:
        """Return the effective playback index for one queue occurrence."""

        return self._entry_index(entry_id)

    def current_entry(self) -> QueueEntry | None:
        if self.current_entry_id is None:
            return None
        return self.entries[self._entry_index(self.current_entry_id)]

    def open(self, entries: Iterable[QueueEntry], *, session_kind: str) -> None:
        next_entries = self._validate_unique_entries(entries)
        if session_kind not in {"single", "playlist"}:
            raise QueueError("session_kind must be single or playlist")
        if not next_entries:
            raise QueueError("cannot open an empty session")
        if session_kind == "single" and len(next_entries) != 1:
            raise QueueError("single sessions contain exactly one entry")

        self.entries = next_entries
        self.base_entries = list(next_entries)
        self.session_kind = session_kind
        self.playlist_open = session_kind == "playlist"
        self.current_entry_id = next_entries[0].entry_id
        self.history = []
        self.shuffle_enabled = False
        self._bump()

    def append(self, entries: Iterable[QueueEntry]) -> None:
        additions = self._validate_unique_entries(entries)
        if not additions:
            return
        existing_ids = {entry.entry_id for entry in self.entries}
        if existing_ids.intersection(entry.entry_id for entry in additions):
            raise QueueError("cannot append an existing queue entry ID")
        if self.session_kind == "empty":
            self.open(additions, session_kind="playlist" if len(additions) > 1 else "single")
            return

        self.entries.extend(additions)
        self.base_entries.extend(additions)
        if self.session_kind == "single":
            self.session_kind = "playlist"
            self.playlist_open = True
        self._bump()

    def shuffled_order(self) -> list[QueueEntry]:
        """Return a fresh effective order while keeping the current track live."""

        current = self.current_entry()
        if current is None:
            return list(self.entries)
        future = [entry for entry in self.entries if entry.entry_id != current.entry_id]
        SystemRandom().shuffle(future)
        return [current, *future]

    def sort(self, criterion: str = "title", descending: bool = False) -> list[QueueEntry]:
        """Return entries sorted by criterion."""
        c = (criterion or "title").lower()

        def sort_key(entry: QueueEntry):
            if c == "title":
                return (entry.title.lower(), entry.artist.lower())
            elif c == "artist":
                return (entry.artist.lower() if entry.artist else "zzz", entry.title.lower())
            elif c == "album":
                return (entry.album.lower() if entry.album else "zzz", entry.title.lower())
            elif c == "duration":
                return (entry.duration_sec if entry.duration_sec is not None else -1.0, entry.title.lower())
            elif c == "mtime":
                return (entry.mtime, entry.title.lower())
            elif c == "ctime":
                return (entry.ctime, entry.title.lower())
            return (entry.title.lower(), entry.artist.lower())

        return sorted(self.entries, key=sort_key, reverse=descending)

    def set_effective_order(self, entries: Iterable[QueueEntry], *, shuffle: bool) -> None:
        """Commit an mpv-synchronized effective order without altering base order."""

        next_entries = self._validate_unique_entries(entries)
        current_ids = {entry.entry_id for entry in self.entries}
        next_ids = {entry.entry_id for entry in next_entries}
        if current_ids != next_ids or len(next_entries) != len(self.entries):
            raise QueueError("effective order must contain every existing queue entry exactly once")
        self.entries = next_entries
        self.shuffle_enabled = shuffle
        if not shuffle:
            self.base_entries = list(next_entries)
        self._bump()

    def play(self, entry_id: str) -> None:
        self._entry_index(entry_id)
        if self.current_entry_id and self.current_entry_id != entry_id:
            self.history.append(self.current_entry_id)
        self.current_entry_id = entry_id
        self._bump()

    def next(self) -> QueueEntry | None:
        current = self.current_entry()
        if current is None:
            return None
        index = self._entry_index(current.entry_id)
        if index + 1 >= len(self.entries):
            return None
        self.play(self.entries[index + 1].entry_id)
        return self.current_entry()

    def previous(self) -> QueueEntry | None:
        current = self.current_entry()
        if current is None:
            return None
        while self.history:
            candidate = self.history.pop()
            if any(entry.entry_id == candidate for entry in self.entries):
                self.current_entry_id = candidate
                self._bump()
                return self.current_entry()
        index = self._entry_index(current.entry_id)
        if index == 0:
            return current
        self.current_entry_id = self.entries[index - 1].entry_id
        self._bump()
        return self.current_entry()

    def move(self, entry_id: str, destination_index: int) -> None:
        source_index = self._entry_index(entry_id)
        if not 0 <= destination_index < len(self.entries):
            raise QueueError("destination_index is outside the queue")
        if source_index == destination_index:
            return
        entry = self.entries.pop(source_index)
        self.entries.insert(destination_index, entry)
        if not self.shuffle_enabled:
            self.base_entries = list(self.entries)
        self._bump()

    def remove(self, entry_ids: Iterable[str]) -> None:
        ids = list(dict.fromkeys(entry_ids))
        if not ids:
            return
        known = {entry.entry_id for entry in self.entries}
        unknown = set(ids).difference(known)
        if unknown:
            raise QueueError(f"unknown queue entries: {', '.join(sorted(unknown))}")

        current_index = self._entry_index(self.current_entry_id) if self.current_entry_id else -1
        remove_set = set(ids)
        survivors = [entry for entry in self.entries if entry.entry_id not in remove_set]
        if not survivors:
            raise QueueError("cannot remove the last queue entry")
        if self.current_entry_id in remove_set:
            next_current = survivors[min(current_index, len(survivors) - 1)] if survivors else None
            self.current_entry_id = next_current.entry_id if next_current else None
        self.entries = survivors
        self.base_entries = [entry for entry in self.base_entries if entry.entry_id not in remove_set]
        self.history = [entry_id for entry_id in self.history if entry_id not in remove_set]
        self._bump()

    def future_entry_ids(self) -> list[str]:
        current = self.current_entry()
        if current is None:
            return []
        index = self._entry_index(current.entry_id)
        return [entry.entry_id for entry in self.entries[index + 1:]]

    def snapshot(self) -> dict[str, object]:
        if self._cached_revision != self.revision:
            self._cached_entries = [entry.snapshot() for entry in self.entries]
            self._cached_revision = self.revision
        return {
            "revision": self.revision,
            "sessionKind": self.session_kind,
            "playlistOpen": self.playlist_open,
            "currentEntryId": self.current_entry_id,
            "historyEntryIds": list(self.history),
            "shuffle": self.shuffle_enabled,
            "entries": self._cached_entries,
        }
