#!/usr/bin/env python3
"""Scanner tests for the transactional local-media import candidate."""

from __future__ import annotations

import sys
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from media.library_index import scan


def write_silence(path: Path, seconds: float = 0.25) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(8000)
        output.writeframes(b"\0\0" * int(8000 * seconds))


def final_payload(records: list[dict[str, object]]) -> dict[str, object]:
    return next(record["payload"] for record in records if record["event"] == "finished")


class LocalMediaImportTests(unittest.TestCase):
    def test_folder_scan_is_deterministic_and_a_one_track_folder_is_a_playlist(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-local-media-import-") as temp_dir:
            root = Path(temp_dir)
            write_silence(root / "z-last.wav")
            write_silence(root / "nested" / "a-first.wav")
            (root / "nested" / "a-first.lrc").write_text("[00:00.00]Offline lyric\n", encoding="utf-8")
            (root / "broken.mp3").write_text("not audio", encoding="utf-8")
            records = list(scan([root], request_id="folder-1", folder=True, cache_dir=root / "cache"))
            payload = final_payload(records)
            self.assertEqual(payload["sessionKind"], "playlist")
            self.assertEqual([entry["title"] for entry in payload["entries"]], ["a-first", "z-last"])
            self.assertEqual(payload["entries"][0]["lyricsPath"], str(root / "nested" / "a-first.lrc"))
            self.assertEqual(payload["skipped"], 1)

            single_root = root / "single"
            write_silence(single_root / "only.wav")
            single_payload = final_payload(list(scan([single_root], request_id="folder-one", folder=True, cache_dir=root / "cache")))
            self.assertEqual(single_payload["sessionKind"], "playlist")
            self.assertEqual(len(single_payload["entries"]), 1)

    def test_playlist_preserves_explicit_duplicates_and_resolves_relative_paths(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-local-media-playlist-") as temp_dir:
            root = Path(temp_dir)
            song = root / "tracks" / "song with spaces.wav"
            write_silence(song)
            playlist = root / "queue.m3u8"
            playlist.write_text("#EXTM3U\ntracks/song with spaces.wav\ntracks/song with spaces.wav\nmissing.mp3\n", encoding="utf-8")
            payload = final_payload(list(scan([playlist], request_id="m3u-1", folder=False, cache_dir=root / "cache")))
            entries = payload["entries"]
            self.assertEqual(payload["sessionKind"], "playlist")
            self.assertEqual(len(entries), 2)
            self.assertEqual(entries[0]["trackId"], entries[1]["trackId"])
            self.assertEqual(entries[0]["title"], "song with spaces")
            self.assertEqual(payload["skipped"], 1)

    def test_invalid_candidate_finishes_empty_without_committing_a_session(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-local-media-invalid-") as temp_dir:
            root = Path(temp_dir)
            invalid = root / "invalid.mp3"
            invalid.write_text("not an mp3", encoding="utf-8")
            payload = final_payload(list(scan([invalid], request_id="invalid-1", folder=False, cache_dir=root / "cache")))
            self.assertEqual(payload["entries"], [])
            self.assertEqual(payload["skipped"], 1)
            self.assertEqual(payload["sessionKind"], "single")

    def test_ttml_sidecar_lyrics_are_discovered(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-local-media-ttml-") as temp_dir:
            root = Path(temp_dir)
            track = root / "song.wav"
            ttml = root / "song.ttml"
            write_silence(track)
            ttml.write_text('<tt xmlns="http://www.w3.org/ns/ttml"><body><div><p begin="00:00.00">Test</p></div></body></tt>', encoding="utf-8")
            payload = final_payload(list(scan([track], request_id="ttml-1", folder=False, cache_dir=root / "cache")))
            self.assertEqual(len(payload["entries"]), 1)
            self.assertEqual(payload["entries"][0]["lyricsPath"], str(ttml))


if __name__ == "__main__":
    unittest.main()
