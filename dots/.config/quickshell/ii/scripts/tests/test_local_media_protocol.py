#!/usr/bin/env python3
"""Protocol and no-audio mpv integration tests for local media phase 0."""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from media.mpv_client import MpvProcess
from media.protocol import PROTOCOL_VERSION, ProtocolError, decode_request, event, response
from fixtures.local_media.generate import generate_fixture_set


def write_silence(path: Path, seconds: float = 0.25) -> None:
    sample_rate = 8000
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(b"\0\0" * int(sample_rate * seconds))


class ProtocolTests(unittest.TestCase):
    def test_request_response_and_event_are_versioned(self) -> None:
        request = decode_request(json.dumps({
            "protocolVersion": PROTOCOL_VERSION,
            "requestId": "request-1",
            "op": "snapshot",
            "payload": {},
        }))
        self.assertEqual(request.operation, "snapshot")
        self.assertEqual(response(request, {"revision": 7})["requestId"], "request-1")
        self.assertEqual(event("ready")["protocolVersion"], PROTOCOL_VERSION)

    def test_protocol_rejects_unknown_version_and_non_object_payload(self) -> None:
        with self.assertRaises(ProtocolError) as wrong_version:
            decode_request('{"protocolVersion":0,"requestId":"a","op":"ping"}')
        self.assertEqual(wrong_version.exception.code, "unsupportedProtocol")

        with self.assertRaises(ProtocolError) as wrong_payload:
            decode_request('{"protocolVersion":1,"requestId":"a","op":"ping","payload":[]}')
    def test_protocol_supports_sort_and_crossfade_operations(self) -> None:
        sort_req = decode_request(json.dumps({
            "protocolVersion": PROTOCOL_VERSION,
            "requestId": "sort-1",
            "op": "sortQueue",
            "payload": {"criterion": "duration", "descending": True},
        }))
        self.assertEqual(sort_req.operation, "sortQueue")
        self.assertEqual(sort_req.payload["criterion"], "duration")
        self.assertTrue(sort_req.payload["descending"])

        crossfade_req = decode_request(json.dumps({
            "protocolVersion": PROTOCOL_VERSION,
            "requestId": "fade-1",
            "op": "setCrossfade",
            "payload": {"enable": True, "durationSec": 5},
        }))
        self.assertEqual(crossfade_req.operation, "setCrossfade")
        self.assertTrue(crossfade_req.payload["enable"])
        self.assertEqual(crossfade_req.payload["durationSec"], 5)

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is not installed")
    def test_fixture_generator_covers_local_media_inputs_without_committed_binaries(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-local-media-fixtures-") as temp_dir:
            fixtures = generate_fixture_set(temp_dir)
            self.assertEqual(set(fixtures), {"wav", "mp3", "flac", "opus", "cover", "lrc", "txt", "invalid"})
            self.assertTrue(all(path.is_file() and path.stat().st_size > 0 for path in fixtures.values()))
            self.assertIn("[00:00.00]", fixtures["lrc"].read_text(encoding="utf-8"))


@unittest.skipUnless(shutil.which("mpv"), "mpv is not installed")
class NullAudioMpvTests(unittest.TestCase):
    def test_mpv_supports_events_two_tracks_pause_seek_and_single_eof_advance_without_audio_output(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-local-media-phase0-") as temp_dir:
            root = Path(temp_dir)
            first_audio_file = root / "first.wav"
            second_audio_file = root / "second.wav"
            socket_path = root / "mpv.sock"
            write_silence(first_audio_file, seconds=0.75)
            write_silence(second_audio_file, seconds=1.5)
            process = MpvProcess(socket_path, null_audio=True)
            client = process.start()
            try:
                client.set_property("pause", True)
                client.command("observe_property", (17, "playlist-pos"))
                client.command("loadfile", (str(first_audio_file), "replace"))
                client.command("loadfile", (str(second_audio_file), "append"))
                loaded_path = client.wait_for_property("path", lambda value: value == str(first_audio_file), timeout=2.5)
                self.assertEqual(loaded_path, str(first_audio_file))
                playlist = client.wait_for_property("playlist", lambda value: isinstance(value, list) and len(value) == 2, timeout=2.5)
                entry_ids = [entry["id"] for entry in playlist]
                self.assertEqual(len(entry_ids), len(set(entry_ids)))
                position_event = client.wait_for_event(lambda value: value.get("event") == "property-change" and value.get("id") == 17 and value.get("data") == 0)
                self.assertEqual(position_event["name"], "playlist-pos")
                self.assertGreater(float(client.wait_for_property("duration", lambda value: value and value > 0, timeout=2.5)), 0)
                client.command("seek", (0.1, "absolute"))
                self.assertGreaterEqual(float(client.wait_for_property("time-pos", lambda value: value is not None and value >= 0.08, timeout=2.5)), 0.08)
                client.command("seek", (0.6, "absolute"))
                client.set_property("pause", False)
                self.assertEqual(client.wait_for_property("playlist-pos", lambda value: value == 1, timeout=2.5), 1)
                client.set_property("pause", True)
                self.assertEqual(client.get_property("playlist-pos"), 1)
                self.assertTrue(client.get_property("pause"))
            finally:
                process.stop()
            self.assertFalse(socket_path.exists())


if __name__ == "__main__":
    unittest.main()
