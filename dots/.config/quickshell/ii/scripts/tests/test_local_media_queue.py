#!/usr/bin/env python3
"""Phase-0 tests for the pure local-media queue model."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from media.queue_store import QueueEntry, QueueError, QueueStore


def entry(name: str) -> QueueEntry:
    return QueueEntry.create(Path("/tmp") / name, title=Path(name).stem)


class QueueStoreTests(unittest.TestCase):
    def test_single_session_never_becomes_queue_eligible(self) -> None:
        store = QueueStore()
        one = entry("one.ogg")
        store.open([one], session_kind="single")

        self.assertEqual(store.snapshot()["sessionKind"], "single")
        self.assertFalse(store.snapshot()["playlistOpen"])
        self.assertEqual(store.snapshot()["currentEntryId"], one.entry_id)

    def test_playlist_can_contain_one_track_and_remains_a_playlist(self) -> None:
        store = QueueStore()
        one = entry("one.ogg")
        store.open([one], session_kind="playlist")

        self.assertEqual(store.snapshot()["sessionKind"], "playlist")
        self.assertTrue(store.snapshot()["playlistOpen"])
        self.assertIsNone(store.next())

    def test_duplicate_tracks_have_independent_occurrence_ids(self) -> None:
        store = QueueStore()
        first = QueueEntry.create("/tmp/same.flac", track_id="track-same")
        second = QueueEntry.create("/tmp/same.flac", track_id="track-same")
        store.open([first, second], session_kind="playlist")
        store.remove([first.entry_id])

        self.assertEqual([item["entryId"] for item in store.snapshot()["entries"]], [second.entry_id])
        self.assertEqual(store.current_entry_id, second.entry_id)

    def test_move_preserves_current_identity_and_revision(self) -> None:
        store = QueueStore()
        first, second, third = entry("first.mp3"), entry("second.mp3"), entry("third.mp3")
        store.open([first, second, third], session_kind="playlist")
        store.play(second.entry_id)
        revision_before_move = store.revision
        store.move(third.entry_id, 0)

        self.assertEqual(store.current_entry_id, second.entry_id)
        self.assertEqual([item["entryId"] for item in store.snapshot()["entries"]], [third.entry_id, first.entry_id, second.entry_id])
        self.assertEqual(store.revision, revision_before_move + 1)

    def test_remove_current_advances_to_next_survivor(self) -> None:
        store = QueueStore()
        first, second, third = entry("first.mp3"), entry("second.mp3"), entry("third.mp3")
        store.open([first, second, third], session_kind="playlist")
        store.play(second.entry_id)
        store.remove([second.entry_id])

        self.assertEqual(store.current_entry_id, third.entry_id)
        self.assertEqual([item["entryId"] for item in store.snapshot()["entries"]], [first.entry_id, third.entry_id])

    def test_single_promotes_to_playlist_only_when_another_track_is_appended(self) -> None:
        store = QueueStore()
        first, second = entry("first.mp3"), entry("second.mp3")
        store.open([first], session_kind="single")
        store.append([second])

        self.assertEqual(store.session_kind, "playlist")
        self.assertTrue(store.playlist_open)

    def test_shuffle_keeps_current_entry_and_can_restore_base_order(self) -> None:
        store = QueueStore()
        first, second, third = entry("first.mp3"), entry("second.mp3"), entry("third.mp3")
        store.open([first, second, third], session_kind="playlist")
        store.play(second.entry_id)
        shuffled = store.shuffled_order()
        self.assertEqual(shuffled[0].entry_id, second.entry_id)
        store.set_effective_order(shuffled, shuffle=True)
        self.assertTrue(store.shuffle_enabled)
        store.set_effective_order(store.base_entries, shuffle=False)
        self.assertFalse(store.shuffle_enabled)
        self.assertEqual([item.entry_id for item in store.entries], [first.entry_id, second.entry_id, third.entry_id])

    def test_invalid_single_and_unknown_entry_are_rejected(self) -> None:
        store = QueueStore()
        with self.assertRaises(QueueError):
            store.open([entry("a.mp3"), entry("b.mp3")], session_kind="single")
        with self.assertRaises(QueueError):
            store.move("missing", 0)

    def test_sort_queue_by_multiple_criteria_and_directions(self) -> None:
        store = QueueStore()
        e1 = QueueEntry.create("/tmp/zebra.mp3", title="Zebra", artist="Bob", duration_sec=120.0, mtime=100.0, ctime=300.0)
        e2 = QueueEntry.create("/tmp/apple.mp3", title="Apple", artist="Charlie", duration_sec=300.0, mtime=200.0, ctime=100.0)
        e3 = QueueEntry.create("/tmp/mango.mp3", title="Mango", artist="Alice", duration_sec=60.0, mtime=300.0, ctime=200.0)
        store.open([e1, e2, e3], session_kind="playlist")

        # Title ascending
        by_title_asc = store.sort(criterion="title", descending=False)
        self.assertEqual([e.title for e in by_title_asc], ["Apple", "Mango", "Zebra"])

        # Title descending
        by_title_desc = store.sort(criterion="title", descending=True)
        self.assertEqual([e.title for e in by_title_desc], ["Zebra", "Mango", "Apple"])

        # Artist ascending
        by_artist_asc = store.sort(criterion="artist", descending=False)
        self.assertEqual([e.artist for e in by_artist_asc], ["Alice", "Bob", "Charlie"])

        # Duration ascending
        by_dur_asc = store.sort(criterion="duration", descending=False)
        self.assertEqual([e.title for e in by_dur_asc], ["Mango", "Zebra", "Apple"])

        # Duration descending
        by_dur_desc = store.sort(criterion="duration", descending=True)
        self.assertEqual([e.title for e in by_dur_desc], ["Apple", "Zebra", "Mango"])

        # Modification date ascending & descending
        by_mtime_asc = store.sort(criterion="mtime", descending=False)
        self.assertEqual([e.title for e in by_mtime_asc], ["Zebra", "Apple", "Mango"])
        by_mtime_desc = store.sort(criterion="mtime", descending=True)
        self.assertEqual([e.title for e in by_mtime_desc], ["Mango", "Apple", "Zebra"])

        # Creation date ascending & descending
        by_ctime_asc = store.sort(criterion="ctime", descending=False)
        self.assertEqual([e.title for e in by_ctime_asc], ["Apple", "Mango", "Zebra"])
        by_ctime_desc = store.sort(criterion="ctime", descending=True)
        self.assertEqual([e.title for e in by_ctime_desc], ["Zebra", "Mango", "Apple"])


if __name__ == "__main__":
    unittest.main()
