#!/usr/bin/env python3
"""Single-owner local audio helper used by II Media Mode.

The Quickshell UI talks JSON-lines over this process' stdin/stdout.  This
process is the only owner of the mpv child and of the exported MPRIS name, so
closing a Media Mode surface cannot leave a second audio engine behind.
"""

from __future__ import annotations

import argparse
import json
import os
import select
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import unquote, urlparse

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

from media.mpris_bridge import DEFAULT_BUS_NAME, MprisBridge
from media.mpv_client import MpvIpcError, MpvIpcClient, MpvProcess
from media.protocol import (
    LOCAL_PLAYER_OPERATIONS,
    PROTOCOL_VERSION,
    ProtocolError,
    decode_request,
    encode,
    error_response,
    event,
    response,
)
from media.queue_store import QueueEntry, QueueError, QueueStore

try:
    from gi.repository import GLib
except ImportError as error:  # pragma: no cover - dependency error reported to caller
    GLib = None
    _GI_IMPORT_ERROR = error
else:
    _GI_IMPORT_ERROR = None


class LocalPlayerDaemon:
    """Serialize local playback commands and mirror their state to MPRIS."""

    def __init__(
        self,
        *,
        socket_path: Path,
        mpv_binary: str,
        null_audio: bool,
        start_paused: bool,
        bus_name: str,
        daemon_socket_path: Path | None = None,
        daemon_mode: bool = False,
        initial_volume: float | None = None,
    ) -> None:
        self.queue = QueueStore()
        self.socket_path = socket_path
        self.mpv = MpvProcess(socket_path, mpv_binary=mpv_binary, null_audio=null_audio, start_paused=start_paused)
        self.start_paused = start_paused
        self.bus_name = bus_name
        self.daemon_socket_path = daemon_socket_path
        self.daemon_mode = daemon_mode
        self.loop: Any = None
        self.bridge: MprisBridge | None = None
        self._output_lock = threading.Lock()
        self._state_lock = threading.RLock()
        self._clients_lock = threading.Lock()
        self._clients: list[socket.socket] = []
        self._server_sock: socket.socket | None = None
        self._stopping = False
        self._playback_status = "Stopped"
        self._position_sec = 0.0
        self._duration_sec = 0.0
        self._volume = max(0.0, min(1.0, float(initial_volume))) if initial_volume is not None else 1.0
        self._crossfade_enabled = False
        self._crossfade_duration_sec = 3.0
        self._last_applied_mpv_volume = -1.0
        self._loop_status = "None"
        self._rate = 1.0
        self._shuffle = False
        self._stopped = False
        self._last_emitted_state: tuple[object, ...] = ()

    @property
    def client(self) -> MpvIpcClient:
        if self.mpv.client is None:
            raise MpvIpcError("local mpv process is unavailable")
        return self.mpv.client

    def _track_snapshot(self) -> dict[str, object] | None:
        current = self.queue.current_entry()
        if current is None:
            return None
        return {
            "entryId": current.entry_id,
            "title": current.title,
            "artists": [current.artist] if current.artist else [],
            "album": current.album,
            "artUrl": current.art_url,
            "lyricsPath": current.lyrics_path,
            "durationSec": self._duration_sec or current.duration_sec,
        }

    def snapshot(self) -> Mapping[str, object]:
        with self._state_lock:
            return self._snapshot_unlocked()

    def _snapshot_unlocked(self) -> dict[str, object]:
        current = self.queue.current_entry()
        has_session = current is not None
        playlist_open = bool(self.queue.playlist_open)
        return {
            "identity": "II Music",
            "desktopEntry": "ii-local-music",
            "playbackStatus": self._playback_status if has_session else "Stopped",
            "positionSec": max(0.0, self._position_sec),
            "volume": min(1.0, max(0.0, self._volume)),
            "loopStatus": self._loop_status,
            "rate": self._rate,
            "shuffle": self._shuffle,
            "track": self._track_snapshot(),
            "canControl": has_session,
            "canPlay": has_session,
            "canPause": has_session,
            "canSeek": has_session and self._duration_sec > 0,
            "canGoNext": playlist_open and self._queue_index() < len(self.queue.entries) - 1,
            "canGoPrevious": playlist_open and (self._queue_index() > 0 or self._position_sec > 0),
            "sessionActive": has_session,
            "queue": self.queue.snapshot(),
        }

    def _queue_index(self) -> int:
        current_id = self.queue.current_entry_id
        for index, entry in enumerate(self.queue.entries):
            if entry.entry_id == current_id:
                return index
        return -1

    def _emit_to(self, client: socket.socket | None, message: Mapping[str, object]) -> None:
        encoded = encode(message) + "\n"
        if client is not None:
            try:
                client.sendall(encoded.encode("utf-8"))
            except (BrokenPipeError, OSError):
                pass
        else:
            with self._output_lock:
                try:
                    sys.stdout.write(encoded)
                    sys.stdout.flush()
                except (BrokenPipeError, OSError):
                    pass

    def _emit(self, message: Mapping[str, object]) -> None:
        encoded = encode(message) + "\n"
        with self._output_lock:
            try:
                sys.stdout.write(encoded)
                sys.stdout.flush()
            except (BrokenPipeError, OSError):
                pass
        with self._clients_lock:
            dead: list[socket.socket] = []
            for c in self._clients:
                try:
                    c.sendall(encoded.encode("utf-8"))
                except (BrokenPipeError, OSError):
                    dead.append(c)
            for c in dead:
                try:
                    self._clients.remove(c)
                except ValueError:
                    pass

    def _read_property(self, name: str, fallback: Any) -> Any:
        try:
            value = self.client.get_property(name, timeout=0.25)
        except MpvIpcError:
            return fallback
        return fallback if value is None else value

    def _state_fingerprint_unlocked(self) -> tuple[object, ...]:
        return (
            self._playback_status,
            round(self._position_sec, 2),
            round(self._duration_sec, 2),
            round(self._volume, 3),
            round(self._rate, 3),
            self._loop_status,
            self._shuffle,
            self.queue.current_entry_id,
            self.queue.revision,
        )

    def _apply_mpv_volume(self, volume: float) -> None:
        target = max(0.0, min(100.0, volume * 100.0))
        if abs(self._last_applied_mpv_volume - target) > 0.4:
            try:
                self.client.set_property("volume", target)
                self._last_applied_mpv_volume = target
            except MpvIpcError:
                pass

    def _refresh_state_unlocked(self) -> bool:
        """Read mpv's current state and return whether public state changed."""

        if self.mpv.client is None:
            return False

        prev_fingerprint = self._state_fingerprint_unlocked()
        has_session = self.queue.current_entry() is not None
        if has_session:
            pause = bool(self._read_property("pause", True))
            eof_reached = bool(self._read_property("eof-reached", False))
            self._position_sec = max(0.0, float(self._read_property("time-pos", self._position_sec) or 0.0))
            if self._duration_sec <= 0:
                self._duration_sec = max(0.0, float(self._read_property("duration", self._duration_sec) or 0.0))
            playlist_pos = self._read_property("playlist-pos", None)
            if isinstance(playlist_pos, int) and 0 <= playlist_pos < len(self.queue.entries):
                entry_id = self.queue.entries[playlist_pos].entry_id
                if self.queue.current_entry_id != entry_id:
                    self.queue.play(entry_id)
                    self._position_sec = 0.0
                    self._duration_sec = 0.0
            if self._stopped or (eof_reached and pause):
                self._playback_status = "Stopped"
            else:
                self._playback_status = "Paused" if pause else "Playing"

            if self._playback_status == "Playing" and self._crossfade_enabled:
                fade_dur = self._crossfade_duration_sec
                fade_factor = 1.0
                if fade_dur > 0:
                    if self._position_sec < fade_dur:
                        fade_factor = min(1.0, max(0.0, self._position_sec / fade_dur))
                    if self._duration_sec > fade_dur * 1.5:
                        rem = self._duration_sec - self._position_sec
                        if rem < fade_dur:
                            fade_factor = min(fade_factor, max(0.0, rem / fade_dur))
                self._apply_mpv_volume(self._volume * fade_factor)
            elif not self._crossfade_enabled:
                self._apply_mpv_volume(self._volume)
        else:
            self._playback_status = "Stopped"
            self._position_sec = 0.0
            self._duration_sec = 0.0

        curr_fingerprint = self._state_fingerprint_unlocked()
        return curr_fingerprint != prev_fingerprint

    def _publish_state(self, *, force: bool = False, seeked_position_sec: float | None = None) -> None:
        with self._state_lock:
            fingerprint = self._state_fingerprint_unlocked()
            changed = force or fingerprint != self._last_emitted_state
            if changed:
                self._last_emitted_state = fingerprint
                snapshot = self._snapshot_unlocked()
            else:
                snapshot = None
        if not changed or snapshot is None:
            return
        self._emit(event("state", snapshot))
        if self.bridge is not None:
            self.bridge.publish(seeked_position_sec=seeked_position_sec)

    def _schedule_publish(self, *, force: bool = False, seeked_position_sec: float | None = None) -> None:
        if GLib is None:
            return

        def publish() -> bool:
            self._publish_state(force=force, seeked_position_sec=seeked_position_sec)
            return False

        GLib.idle_add(publish)

    def _valid_paths(self, raw_paths: object) -> list[Path]:
        if not isinstance(raw_paths, list) or not raw_paths:
            raise ProtocolError("invalidPaths", "paths must be a non-empty list")
        paths: list[Path] = []
        for raw_path in raw_paths:
            if not isinstance(raw_path, str) or not raw_path.strip():
                raise ProtocolError("invalidPaths", "every path must be a non-empty string")
            path = Path(raw_path).expanduser().resolve(strict=False)
            if not path.is_file():
                raise ProtocolError("unreadablePath", f"not a readable file: {path}")
            paths.append(path)
        return paths

    def _validated_entries(self, raw_entries: object) -> list[QueueEntry]:
        if not isinstance(raw_entries, list) or not raw_entries:
            raise ProtocolError("invalidEntries", "entries must be a non-empty list")
        raw_paths: list[object] = []
        for raw_entry in raw_entries:
            if not isinstance(raw_entry, Mapping):
                raise ProtocolError("invalidEntries", "every entry must be an object")
            raw_paths.append(raw_entry.get("path"))
        paths = self._valid_paths(raw_paths)
        entries: list[QueueEntry] = []
        for raw_entry, path in zip(raw_entries, paths, strict=True):
            assert isinstance(raw_entry, Mapping)
            raw_duration = raw_entry.get("durationSec")
            if raw_duration is None:
                duration = None
            else:
                try:
                    duration = max(0.0, float(raw_duration))
                except (TypeError, ValueError) as error:
                    raise ProtocolError("invalidEntries", "durationSec must be numeric") from error
            raw_mtime = raw_entry.get("mtime")
            try:
                mtime = float(raw_mtime) if raw_mtime is not None else 0.0
            except (TypeError, ValueError):
                mtime = 0.0
            raw_ctime = raw_entry.get("ctime")
            try:
                ctime = float(raw_ctime) if raw_ctime is not None else 0.0
            except (TypeError, ValueError):
                ctime = 0.0
            entries.append(QueueEntry.create(
                path,
                track_id=raw_entry.get("trackId") if isinstance(raw_entry.get("trackId"), str) else None,
                title=raw_entry.get("title") if isinstance(raw_entry.get("title"), str) else None,
                artist=raw_entry.get("artist") if isinstance(raw_entry.get("artist"), str) else "",
                album=raw_entry.get("album") if isinstance(raw_entry.get("album"), str) else "",
                art_url=raw_entry.get("artUrl") if isinstance(raw_entry.get("artUrl"), str) else "",
                lyrics_path=raw_entry.get("lyricsPath") if isinstance(raw_entry.get("lyricsPath"), str) else "",
                duration_sec=duration,
                mtime=mtime,
                ctime=ctime,
            ))
        return entries

    def _open_paths_unlocked(
        self,
        raw_paths: object,
        raw_session_kind: object = None,
        raw_entries: object = None,
    ) -> None:
        entries = self._validated_entries(raw_entries) if raw_entries is not None else []
        paths = [Path(entry.path) for entry in entries] if entries else self._valid_paths(raw_paths)
        if not entries:
            entries = [QueueEntry.create(path) for path in paths]
        session_kind = raw_session_kind if isinstance(raw_session_kind, str) else ""
        if session_kind not in {"single", "playlist"}:
            session_kind = "single" if len(paths) == 1 else "playlist"
        if session_kind == "single" and len(paths) != 1:
            raise ProtocolError("invalidSession", "single sessions accept exactly one path")

        try:
            self.client.command("playlist-clear")
            for index, path in enumerate(paths):
                self.client.command("loadfile", (str(path), "replace" if index == 0 else "append"))
            self.client.set_property("playlist-pos", 0)
            # `loadfile` is accepted before mpv has selected and initialized
            # the demuxer.  A follow-up seek issued by a click in the newly
            # shown UI would otherwise race that initialization and fail with
            # mpv's unhelpful "error running command".
            self.client.wait_for_property("path", lambda value: value == str(paths[0]), timeout=2.5)
            self.client.set_property("pause", self.start_paused)
            self._apply_mpv_volume(0.0 if self._crossfade_enabled else self._volume)
        except MpvIpcError as error:
            raise ProtocolError("playbackError", str(error)) from error

        self.queue.open(entries, session_kind=session_kind)
        self._shuffle = False
        self._stopped = False
        self._playback_status = "Paused" if self.start_paused else "Playing"
        self._position_sec = 0.0
        self._duration_sec = 0.0

    def _set_pause_unlocked(self, pause: bool) -> None:
        if self.queue.current_entry() is None:
            return
        self.client.set_property("pause", pause)
        self._stopped = False
        self._playback_status = "Paused" if pause else "Playing"

    def _set_position_unlocked(self, position_sec: object) -> float:
        if self.queue.current_entry() is None:
            return self._position_sec
        try:
            position = float(position_sec)
        except (TypeError, ValueError) as error:
            raise ProtocolError("invalidPosition", "positionSec must be a number") from error
        upper_bound = self._duration_sec if self._duration_sec > 0 else position
        target = max(0.0, min(position, upper_bound))
        self.client.command("seek", (target, "absolute"))
        self._position_sec = target
        return target

    def _set_volume_unlocked(self, value: object) -> None:
        try:
            volume = float(value)
        except (TypeError, ValueError) as error:
            raise ProtocolError("invalidVolume", "volume must be a number") from error
        volume = min(1.0, max(0.0, volume))
        self._volume = volume
        if not self._crossfade_enabled or self._playback_status != "Playing":
            self._apply_mpv_volume(volume)
        else:
            fade_dur = self._crossfade_duration_sec
            fade_factor = 1.0
            if fade_dur > 0:
                if self._position_sec < fade_dur:
                    fade_factor = min(1.0, max(0.0, self._position_sec / fade_dur))
                if self._duration_sec > fade_dur * 1.5:
                    rem = self._duration_sec - self._position_sec
                    if rem < fade_dur:
                        fade_factor = min(fade_factor, max(0.0, rem / fade_dur))
            self._apply_mpv_volume(volume * fade_factor)

    def _set_loop_status_unlocked(self, value: object) -> None:
        status = str(value)
        if status not in {"None", "Track", "Playlist"}:
            raise ProtocolError("invalidLoopStatus", "loop status must be None, Track or Playlist")
        self.client.set_property("loop-file", "inf" if status == "Track" else "no")
        self.client.set_property("loop-playlist", "inf" if status == "Playlist" else "no")
        self._loop_status = status

    def _set_rate_unlocked(self, value: object) -> None:
        try:
            rate = float(value)
        except (TypeError, ValueError) as error:
            raise ProtocolError("invalidRate", "rate must be a number") from error
        rate = min(2.0, max(0.25, rate))
        self.client.set_property("speed", rate)
        self._rate = rate

    def _next_unlocked(self) -> None:
        current_index = self._queue_index()
        if current_index < 0 or current_index + 1 >= len(self.queue.entries):
            return
        paused = self._playback_status != "Playing"
        next_entry = self.queue.entries[current_index + 1]
        self.client.set_property("playlist-pos", current_index + 1)
        self.client.wait_for_property("path", lambda value: value == next_entry.path, timeout=2.5)
        self.queue.play(next_entry.entry_id)
        self._position_sec = 0.0
        if not paused:
            self.client.set_property("pause", False)

    def _previous_unlocked(self) -> None:
        if self.queue.current_entry() is None:
            return
        if self._position_sec > 3.0:
            self._set_position_unlocked(0.0)
            return
        previous = self.queue.previous()
        if previous is None:
            return
        index = self._queue_index()
        self.client.set_property("playlist-pos", index)
        self.client.wait_for_property("path", lambda value: value == previous.path, timeout=2.5)
        self._position_sec = 0.0

    @staticmethod
    def _playlist_move_target(source_index: int, destination_index: int) -> int:
        """Translate a post-move queue index into mpv's target-entry index."""

        # mpv's second `playlist-move` argument identifies the entry that the
        # moved item takes the place of. When moving down, the desired final
        # index is therefore one position after that target in the old list.
        return destination_index + 1 if source_index < destination_index else destination_index

    def _apply_effective_order_unlocked(self, next_entries: list[QueueEntry], *, shuffle: bool) -> None:
        """Move mpv entries into `next_entries` without restarting playback."""

        working = list(self.queue.entries)
        for destination_index, desired in enumerate(next_entries):
            source_index = next(index for index, entry in enumerate(working) if entry.entry_id == desired.entry_id)
            if source_index == destination_index:
                continue
            self.client.command(
                "playlist-move",
                (source_index, self._playlist_move_target(source_index, destination_index)),
            )
            moved = working.pop(source_index)
            working.insert(destination_index, moved)
        self.queue.set_effective_order(working, shuffle=shuffle)

    def _set_shuffle_unlocked(self, value: object) -> None:
        if not isinstance(value, bool):
            raise ProtocolError("invalidShuffle", "shuffle must be a boolean")
        if self.queue.current_entry() is None:
            self._shuffle = value
            return
        if value == self.queue.shuffle_enabled:
            self._shuffle = value
            return
        next_entries = self.queue.shuffled_order() if value else list(self.queue.base_entries)
        self._apply_effective_order_unlocked(next_entries, shuffle=value)
        self._shuffle = value

    def _append_entries_unlocked(self, raw_entries: object) -> None:
        if self.queue.current_entry() is None:
            raise ProtocolError("noSession", "open a local playlist before appending music")
        additions = self._validated_entries(raw_entries)
        try:
            for entry in additions:
                self.client.command("loadfile", (entry.path, "append"))
        except MpvIpcError as error:
            raise ProtocolError("playbackError", str(error)) from error
        self.queue.append(additions)

    def _play_entry_unlocked(self, raw_entry_id: object) -> None:
        if not isinstance(raw_entry_id, str) or not raw_entry_id:
            raise ProtocolError("invalidQueueEntry", "entryId must be a non-empty string")
        try:
            index = self.queue.index_of(raw_entry_id)
            entry = self.queue.entries[index]
        except QueueError as error:
            raise ProtocolError("unknownQueueEntry", str(error)) from error
        try:
            self.client.set_property("playlist-pos", index)
            self.client.wait_for_property("path", lambda value: value == entry.path, timeout=2.5)
            self.client.set_property("pause", False)
        except MpvIpcError as error:
            raise ProtocolError("playbackError", str(error)) from error
        self.queue.play(entry.entry_id)
        self._position_sec = 0.0
        self._stopped = False
        self._playback_status = "Playing"

    def _move_entry_unlocked(self, raw_entry_id: object, raw_destination_index: object) -> None:
        if self.queue.shuffle_enabled:
            raise ProtocolError("shuffleActive", "turn shuffle off before manually reordering the queue")
        if not isinstance(raw_entry_id, str) or not raw_entry_id:
            raise ProtocolError("invalidQueueEntry", "entryId must be a non-empty string")
        if isinstance(raw_destination_index, bool) or not isinstance(raw_destination_index, int):
            raise ProtocolError("invalidQueueIndex", "destinationIndex must be an integer")
        try:
            destination_index = raw_destination_index
            source_index = self.queue.index_of(raw_entry_id)
        except (TypeError, ValueError) as error:
            raise ProtocolError("invalidQueueIndex", "destinationIndex must be an integer") from error
        except QueueError as error:
            raise ProtocolError("unknownQueueEntry", str(error)) from error
        if not 0 <= destination_index < len(self.queue.entries):
            raise ProtocolError("invalidQueueIndex", "destinationIndex is outside the queue")
        if source_index == destination_index:
            return
        try:
            self.client.command(
                "playlist-move",
                (source_index, self._playlist_move_target(source_index, destination_index)),
            )
        except MpvIpcError as error:
            raise ProtocolError("playbackError", str(error)) from error
        self.queue.move(raw_entry_id, destination_index)

    def _remove_entries_unlocked(self, raw_entry_ids: object) -> None:
        if not isinstance(raw_entry_ids, list) or not raw_entry_ids:
            raise ProtocolError("invalidQueueEntry", "entryIds must be a non-empty list")
        if any(not isinstance(entry_id, str) or not entry_id for entry_id in raw_entry_ids):
            raise ProtocolError("invalidQueueEntry", "every entryId must be a non-empty string")
        entry_ids = list(dict.fromkeys(raw_entry_ids))
        try:
            indices = sorted((self.queue.index_of(entry_id) for entry_id in entry_ids), reverse=True)
        except QueueError as error:
            raise ProtocolError("unknownQueueEntry", str(error)) from error
        if len(entry_ids) >= len(self.queue.entries):
            raise ProtocolError("lastQueueEntry", "the last queue entry cannot be removed")

        current = self.queue.current_entry()
        current_removed = current is not None and current.entry_id in entry_ids
        current_index = self.queue.index_of(current.entry_id) if current is not None else -1
        survivors = [entry for entry in self.queue.entries if entry.entry_id not in set(entry_ids)]
        next_current = survivors[min(current_index, len(survivors) - 1)] if current_removed else current
        paused = self._playback_status != "Playing"
        try:
            for index in indices:
                self.client.command("playlist-remove", (index,))
            if current_removed and next_current is not None:
                next_index = next(index for index, entry in enumerate(survivors) if entry.entry_id == next_current.entry_id)
                self.client.set_property("playlist-pos", next_index)
                self.client.wait_for_property("path", lambda value: value == next_current.path, timeout=2.5)
                if paused:
                    self.client.set_property("pause", True)
        except MpvIpcError as error:
            raise ProtocolError("playbackError", str(error)) from error
        self.queue.remove(entry_ids)
        if current_removed:
            self._position_sec = 0.0

    def _clear_future_unlocked(self) -> None:
        future_entry_ids = self.queue.future_entry_ids()
        if future_entry_ids:
            self._remove_entries_unlocked(future_entry_ids)

    def _open_uri_unlocked(self, uri: object) -> None:
        if not isinstance(uri, str):
            raise ProtocolError("invalidUri", "uri must be a file URI")
        parsed = urlparse(uri)
        if parsed.scheme != "file":
            raise ProtocolError("invalidUri", "only file URIs are supported")
        self._open_paths_unlocked([unquote(parsed.path)])

    def _sort_queue_unlocked(self, criterion: str, descending: bool) -> None:
        if self.queue.current_entry() is None:
            return
        sorted_entries = self.queue.sort(criterion=criterion, descending=descending)
        self._apply_effective_order_unlocked(sorted_entries, shuffle=False)
        self._shuffle = False

    def _set_crossfade_unlocked(self, enable: bool, duration: float) -> None:
        self._crossfade_enabled = enable
        self._crossfade_duration_sec = duration
        if not enable:
            self._apply_mpv_volume(self._volume)

    def _execute_unlocked(self, operation: str, payload: Mapping[str, Any]) -> tuple[dict[str, object], float | None, bool]:
        """Apply one operation; returns response, seek event and state change hint."""

        seeked_position: float | None = None
        if operation == "ping":
            return {"status": "ready", "busName": self.bus_name}, None, False
        if operation == "snapshot":
            self._refresh_state_unlocked()
            return self._snapshot_unlocked(), None, False
        if operation == "open":
            self._open_paths_unlocked(payload.get("paths"), payload.get("sessionKind"), payload.get("entries"))
        elif operation == "openUri":
            self._open_uri_unlocked(payload.get("uri"))
        elif operation == "play":
            self._set_pause_unlocked(False)
        elif operation == "pause":
            self._set_pause_unlocked(True)
        elif operation == "playPause":
            self._set_pause_unlocked(self._playback_status == "Playing")
        elif operation == "stop":
            if self.queue.current_entry() is not None:
                # A freshly selected playlist item can expose its path before
                # mpv has exposed a seekable timeline. Stop must still pause
                # deterministically in that brief window; the next Play will
                # use mpv's current position if a zero seek could not yet be
                # applied, rather than reporting a failed media key action.
                try:
                    self._set_position_unlocked(0.0)
                except MpvIpcError:
                    self._position_sec = 0.0
                self._set_pause_unlocked(True)
                self._stopped = True
                self._playback_status = "Stopped"
        elif operation == "next":
            self._next_unlocked()
        elif operation == "previous":
            self._previous_unlocked()
        elif operation == "seek":
            seeked_position = self._set_position_unlocked(payload.get("positionSec"))
        elif operation == "seekRelative":
            try:
                offset = float(payload.get("offsetSec"))
            except (TypeError, ValueError) as error:
                raise ProtocolError("invalidPosition", "offsetSec must be a number") from error
            seeked_position = self._set_position_unlocked(self._position_sec + offset)
        elif operation == "setPosition":
            seeked_position = self._set_position_unlocked(payload.get("positionSec"))
        elif operation == "setVolume":
            self._set_volume_unlocked(payload.get("value", payload.get("volume")))
        elif operation == "setLoopStatus":
            self._set_loop_status_unlocked(payload.get("value"))
        elif operation == "setRate":
            self._set_rate_unlocked(payload.get("value"))
        elif operation == "setShuffle":
            self._set_shuffle_unlocked(payload.get("value"))
        elif operation == "append":
            self._append_entries_unlocked(payload.get("entries"))
        elif operation == "playEntry":
            self._play_entry_unlocked(payload.get("entryId"))
        elif operation == "moveEntry":
            self._move_entry_unlocked(payload.get("entryId"), payload.get("destinationIndex"))
        elif operation == "removeEntries":
            self._remove_entries_unlocked(payload.get("entryIds"))
        elif operation == "clearFuture":
            self._clear_future_unlocked()
        elif operation in {"sort", "sortQueue"}:
            criterion = str(payload.get("criterion", "title")).lower()
            descending = bool(payload.get("descending", False))
            self._sort_queue_unlocked(criterion, descending)
        elif operation == "setCrossfade":
            enable = bool(payload.get("enable", payload.get("enabled", False)))
            try:
                duration = max(0.5, min(30.0, float(payload.get("durationSec", 3.0))))
            except (TypeError, ValueError):
                duration = 3.0
            self._set_crossfade_unlocked(enable, duration)
        else:  # guarded by LOCAL_PLAYER_OPERATIONS; defensive for MPRIS input
            raise ProtocolError("unsupportedOperation", f"unsupported operation: {operation}")

        self._refresh_state_unlocked()
        return self._snapshot_unlocked(), seeked_position, True

    def _handle_mpris_command(self, command: str, payload: Mapping[str, Any]) -> None:
        self._emit(event("mprisCommand", {"command": command, "payload": dict(payload)}))
        if command == "raise":
            self._emit(event("raiseRequested"))
            return
        if command in {"quit", "shutdown"}:
            self._stopping = True
            GLib.idle_add(self.loop.quit)
            return
        with self._state_lock:
            _, seeked_position, changed = self._execute_unlocked(command, payload)
        if changed:
            self._schedule_publish(force=True, seeked_position_sec=seeked_position)

    def _start_socket_server(self) -> None:
        if not self.daemon_socket_path:
            return
        self.daemon_socket_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(self.daemon_socket_path.parent, 0o700)
        except OSError:
            pass
        if self.daemon_socket_path.exists():
            try:
                self.daemon_socket_path.unlink()
            except OSError:
                pass
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(str(self.daemon_socket_path))
        try:
            os.chmod(self.daemon_socket_path, 0o600)
        except OSError:
            pass
        sock.listen(16)
        self._server_sock = sock
        thread = threading.Thread(target=self._accept_clients, name="ii-daemon-accept", daemon=True)
        thread.start()

    def _accept_clients(self) -> None:
        assert self._server_sock is not None
        while not self._stopping:
            try:
                client, _ = self._server_sock.accept()
            except OSError:
                break
            with self._clients_lock:
                self._clients.append(client)
            self._emit_to(client, event("ready", {"busName": self.bus_name, "protocolVersion": 1}))
            with self._state_lock:
                self._emit_to(client, event("state", self._snapshot_unlocked()))
            thread = threading.Thread(
                target=self._read_client,
                args=(client,),
                name=f"ii-daemon-client-{id(client)}",
                daemon=True,
            )
            thread.start()

    def _read_client(self, client: socket.socket) -> None:
        fileobj = client.makefile("r", encoding="utf-8", errors="replace")
        try:
            for line in fileobj:
                if not line:
                    break
                self._dispatch(line, client=client)
                if self._stopping:
                    break
        except (OSError, ConnectionResetError):
            pass
        finally:
            try:
                fileobj.close()
            except OSError:
                pass
            try:
                client.close()
            except OSError:
                pass
            with self._clients_lock:
                try:
                    self._clients.remove(client)
                except ValueError:
                    pass

    def _dispatch(self, raw_line: str, client: socket.socket | None = None) -> None:
        request_id: str | None = None
        try:
            request = decode_request(raw_line)
            request_id = request.request_id
            if request.operation not in LOCAL_PLAYER_OPERATIONS:
                raise ProtocolError("unsupportedOperation", f"unsupported operation: {request.operation}")
            if request.operation == "shutdown":
                self._emit_to(client, response(request, {"status": "stopping"}))
                self._stopping = True
                GLib.idle_add(self.loop.quit)
                return
            with self._state_lock:
                payload, seeked_position, changed = self._execute_unlocked(request.operation, request.payload)
            self._emit_to(client, response(request, payload))
            if changed:
                self._schedule_publish(force=True, seeked_position_sec=seeked_position)
        except (ProtocolError, QueueError) as error:
            code = error.code if isinstance(error, ProtocolError) else "queueError"
            self._emit_to(client, error_response(request_id, code, str(error)))
        except Exception as error:
            self._emit_to(client, error_response(request_id, "internalError", str(error)))

    def _handle_signal(self, signum: int, frame: Any) -> None:
        self._stopping = True
        if self.loop is not None:
            GLib.idle_add(self.loop.quit)

    def _read_stdin(self) -> None:
        if self.daemon_mode:
            return
        for line in sys.stdin:
            self._dispatch(line)
            if self._stopping:
                return
        if not self._stopping:
            self._stopping = True
            GLib.idle_add(self.loop.quit)

    def _tick(self) -> bool:
        if self._stopping:
            return False
        with self._state_lock:
            changed = self._refresh_state_unlocked()
        if changed:
            self._publish_state()
        return True

    def run(self) -> int:
        if GLib is None:
            self._emit(error_response(None, "missingDependency", f"PyGObject is required: {_GI_IMPORT_ERROR}"))
            return 1
        self.loop = GLib.MainLoop()
        try:
            signal.signal(signal.SIGTERM, self._handle_signal)
            signal.signal(signal.SIGINT, self._handle_signal)
        except (ValueError, OSError):
            pass
        try:
            self.mpv.start()
            self.bridge = MprisBridge(self.snapshot, self._handle_mpris_command, bus_name=self.bus_name)
            self.bridge.start()
            if self.daemon_socket_path:
                self._start_socket_server()
            self._emit(event("ready", {"busName": self.bus_name, "protocolVersion": 1}))
            if not self.daemon_mode:
                reader = threading.Thread(target=self._read_stdin, name="ii-local-media-stdin", daemon=True)
                reader.start()
            GLib.timeout_add(100, self._tick)
            self.loop.run()
            return 0
        except Exception as error:
            self._emit(error_response(None, "startupFailed", str(error)))
            return 1
        finally:
            if self._server_sock is not None:
                try:
                    self._server_sock.close()
                except OSError:
                    pass
            if self.daemon_socket_path and self.daemon_socket_path.exists():
                try:
                    self.daemon_socket_path.unlink()
                except OSError:
                    pass
            with self._clients_lock:
                for c in self._clients:
                    try:
                        c.close()
                    except OSError:
                        pass
                self._clients.clear()
            if self.bridge is not None:
                self.bridge.stop()
            self.mpv.stop()


def terminate_daemon(daemon_sock_path: Path, socket_path: Path) -> int:
    sock = try_connect(daemon_sock_path)
    if sock is not None:
        try:
            req = json.dumps({
                "protocolVersion": PROTOCOL_VERSION,
                "requestId": "terminate-cli",
                "op": "shutdown",
                "payload": {},
            }) + "\n"
            sock.sendall(req.encode("utf-8"))
            sock.shutdown(socket.SHUT_WR)
            sock.settimeout(1.0)
            try:
                sock.recv(1024)
            except OSError:
                pass
        except OSError:
            pass
        finally:
            try:
                sock.close()
            except OSError:
                pass

    deadline = time.monotonic() + 1.0
    while time.monotonic() < deadline and daemon_sock_path.exists():
        time.sleep(0.05)

    if daemon_sock_path.exists():
        try:
            daemon_sock_path.unlink()
        except OSError:
            pass

    if socket_path.exists():
        try:
            socket_path.unlink()
        except OSError:
            pass

    return 0


def probe_daemon(daemon_sock_path: Path) -> bool:
    if not daemon_sock_path.exists():
        return False
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(0.5)
        sock.connect(str(daemon_sock_path))
        sock.close()
        return True
    except (ConnectionRefusedError, FileNotFoundError, OSError):
        try:
            daemon_sock_path.unlink(missing_ok=True)
        except OSError:
            pass
        return False


def try_connect(daemon_sock_path: Path) -> socket.socket | None:
    if not daemon_sock_path.exists():
        return None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(1.0)
        sock.connect(str(daemon_sock_path))
        sock.settimeout(None)
        return sock
    except (ConnectionRefusedError, FileNotFoundError, OSError):
        try:
            daemon_sock_path.unlink(missing_ok=True)
        except OSError:
            pass
        return None


def run_client_bridge(sock: socket.socket) -> int:
    """Bridge stdin/stdout to the daemon UNIX domain socket without buffer traps."""
    sock_fd = sock.fileno()
    stdin_fd = sys.stdin.fileno()
    sock_buf = ""
    stdin_buf = ""

    sock.setblocking(False)
    try:
        os.set_blocking(stdin_fd, False)
    except OSError:
        pass

    try:
        while True:
            rlist, _, _ = select.select([sock_fd, stdin_fd], [], [])
            if sock_fd in rlist:
                try:
                    chunk = sock.recv(8192)
                except BlockingIOError:
                    chunk = b""
                if not chunk:
                    break
                sock_buf += chunk.decode("utf-8", errors="replace")
                while "\n" in sock_buf:
                    line, sock_buf = sock_buf.split("\n", 1)
                    sys.stdout.write(line + "\n")
                    sys.stdout.flush()

            if stdin_fd in rlist:
                try:
                    chunk = os.read(stdin_fd, 8192)
                except BlockingIOError:
                    chunk = b""
                if not chunk:
                    break
                stdin_buf += chunk.decode("utf-8", errors="replace")
                while "\n" in stdin_buf:
                    line, stdin_buf = stdin_buf.split("\n", 1)
                    sock.sendall((line + "\n").encode("utf-8"))
    except (KeyboardInterrupt, OSError):
        pass
    finally:
        try:
            sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            sock.close()
        except OSError:
            pass

    return 0


def connect_or_spawn_daemon(args: argparse.Namespace) -> socket.socket | None:
    daemon_sock = args.daemon_socket
    if daemon_sock is None:
        return None
    runtime_dir = daemon_sock.parent
    runtime_dir.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(runtime_dir, 0o700)
    except OSError:
        pass

    sock = try_connect(daemon_sock)
    if sock is not None:
        return sock

    cmd = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--daemon-mode",
        "--daemon-socket", str(daemon_sock),
        "--socket", str(args.socket),
        "--mpv", args.mpv,
        "--mpris-name", args.mpris_name,
    ]
    if args.volume is not None:
        cmd.extend(["--volume", str(args.volume)])
    subprocess.Popen(
        cmd,
        start_new_session=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        close_fds=True,
    )

    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline:
        sock = try_connect(daemon_sock)
        if sock is not None:
            return sock
        time.sleep(0.05)

    return None


def parse_args(argv: list[str]) -> argparse.Namespace:
    runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "ii-local-media"
    parser = argparse.ArgumentParser(description="ii local-media helper")
    parser.add_argument("--socket", type=Path, default=runtime_dir / "mpv.sock")
    parser.add_argument("--daemon-socket", type=Path, default=runtime_dir / "daemon.sock")
    parser.add_argument("--mpv", default="mpv")
    parser.add_argument("--mpris-name", default=DEFAULT_BUS_NAME)
    parser.add_argument("--volume", type=float, default=None, help="initial volume (0.0 to 1.0)")
    parser.add_argument("--test-null-audio", action="store_true", help="use mpv's null audio output for isolated tests")
    parser.add_argument("--test-start-paused", action="store_true", help="keep test fixtures paused after open")
    parser.add_argument("--daemon-mode", action="store_true", help="run as background daemon server")
    parser.add_argument("--no-daemon", action="store_true", help="run directly in foreground without daemon bridge")
    parser.add_argument("--probe", action="store_true", help="check if daemon is currently running")
    parser.add_argument("--terminate", action="store_true", help="shut down running daemon and clean up sockets")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    if args.terminate:
        return terminate_daemon(args.daemon_socket, args.socket)

    if args.probe:
        return 0 if probe_daemon(args.daemon_socket) else 1

    if args.daemon_mode:
        return LocalPlayerDaemon(
            socket_path=args.socket,
            mpv_binary=args.mpv,
            null_audio=args.test_null_audio,
            start_paused=args.test_start_paused,
            bus_name=args.mpris_name,
            daemon_socket_path=args.daemon_socket,
            daemon_mode=True,
            initial_volume=args.volume,
        ).run()

    if args.no_daemon or args.test_null_audio:
        return LocalPlayerDaemon(
            socket_path=args.socket,
            mpv_binary=args.mpv,
            null_audio=args.test_null_audio,
            start_paused=args.test_start_paused,
            bus_name=args.mpris_name,
            daemon_socket_path=None,
            daemon_mode=False,
            initial_volume=args.volume,
        ).run()

    sock = connect_or_spawn_daemon(args)
    if sock is not None:
        return run_client_bridge(sock)

    return LocalPlayerDaemon(
        socket_path=args.socket,
        mpv_binary=args.mpv,
        null_audio=args.test_null_audio,
        start_paused=args.test_start_paused,
        bus_name=args.mpris_name,
        daemon_socket_path=args.daemon_socket,
        daemon_mode=False,
        initial_volume=args.volume,
    ).run()


if __name__ == "__main__":
    raise SystemExit(main())
