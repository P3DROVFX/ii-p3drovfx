#!/usr/bin/env python3
"""Private D-Bus integration test for the Phase-2 local-media helper."""

from __future__ import annotations

import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts" / "media" / "local_player.py"
CONTRACT = ROOT / "scripts" / "tests" / "fixtures" / "local_media" / "phase2_contract.json"


class IsolatedDBusFixture:
    def __init__(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix="ii-local-media-dbus-")
        self.process = subprocess.Popen(
            ["dbus-daemon", "--session", "--print-address=1", "--nofork"],
            cwd=self.temp_dir.name,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert self.process.stdout is not None
        self.address = self.process.stdout.readline().strip()
        if not self.address.startswith("unix:"):
            raise RuntimeError(f"failed to start private D-Bus: {self.address}")

    def environment(self) -> dict[str, str]:
        environment = os.environ.copy()
        environment["DBUS_SESSION_BUS_ADDRESS"] = self.address
        return environment

    def close(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            if stream is not None and not stream.closed:
                stream.close()
        self.temp_dir.cleanup()


@unittest.skipUnless(shutil.which("dbus-daemon") and shutil.which("gdbus") and shutil.which("mpv"), "D-Bus tools or mpv are not installed")
class LocalMediaMprisTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = IsolatedDBusFixture()
        self.temp_dir = tempfile.TemporaryDirectory(prefix="ii-local-media-helper-")
        self.bus_name = f"org.mpris.MediaPlayer2.ii_phase2_{os.getpid()}"
        self.process = subprocess.Popen(
            [
                sys.executable,
                str(HELPER),
                "--test-null-audio",
                "--test-start-paused",
                "--socket",
                str(Path(self.temp_dir.name) / "player.sock"),
                "--mpris-name",
                self.bus_name,
            ],
            env=self.fixture.environment(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.first_audio = Path(self.temp_dir.name) / "first.wav"
        self.second_audio = Path(self.temp_dir.name) / "second.wav"
        self.third_audio = Path(self.temp_dir.name) / "third.wav"
        self.third_lyrics = Path(self.temp_dir.name) / "third.lrc"
        self._write_silence(self.first_audio, seconds=1.25)
        self._write_silence(self.second_audio, seconds=1.5)
        self._write_silence(self.third_audio, seconds=1.75)
        self.third_lyrics.write_text("[00:00.00]Third lyric\n", encoding="utf-8")
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        self.first_event = self._read_json_line()

    @staticmethod
    def _write_silence(path: Path, *, seconds: float) -> None:
        with wave.open(str(path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(8000)
            output.writeframes(b"\0\0" * int(8000 * seconds))

    def tearDown(self) -> None:
        if self.process.poll() is None:
            assert self.process.stdin is not None
            self.process.stdin.write(json.dumps({"protocolVersion": 1, "requestId": "cleanup", "op": "shutdown"}) + "\n")
            self.process.stdin.flush()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=2)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            if stream is not None and not stream.closed:
                stream.close()
        self.fixture.close()
        self.temp_dir.cleanup()

    def _read_json_line(self, timeout: float = 3.0) -> dict[str, object]:
        assert self.process.stdout is not None
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.process.stdout], [], [], max(0, deadline - time.monotonic()))
            if ready:
                line = self.process.stdout.readline()
                if line:
                    return json.loads(line)
            if self.process.poll() is not None:
                stderr = self.process.stderr.read() if self.process.stderr else ""
                self.fail(f"helper exited early: {stderr}")
            time.sleep(0.01)
        self.fail("timed out waiting for helper JSON output")

    def _request(self, request_id: str, operation: str, payload: dict[str, object] | None = None) -> dict[str, object]:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps({
            "protocolVersion": 1,
            "requestId": request_id,
            "op": operation,
            "payload": payload or {},
        }) + "\n")
        self.process.stdin.flush()
        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            message = self._read_json_line()
            if message.get("requestId") == request_id:
                return message
        self.fail(f"timed out waiting for request {request_id}")

    def _event(self, event_name: str, timeout: float = 3.0) -> dict[str, object]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            message = self._read_json_line(timeout=max(0.1, deadline - time.monotonic()))
            if message.get("event") == event_name:
                return message
        self.fail(f"timed out waiting for event {event_name}")

    def test_helper_exports_mpris_on_a_private_bus_and_controls_one_local_session(self) -> None:
        contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(self.first_event["event"], "ready")
        self.assertEqual(self.first_event["payload"]["busName"], self.bus_name)
        self.assertIn("open", contract["operations"])
        self.assertIn("setVolume", contract["operations"])
        self.assertIn("state", contract["events"])

        reply = subprocess.run(
            [
                "gdbus", "call", "--session", "--dest", self.bus_name,
                "--object-path", "/org/mpris/MediaPlayer2",
                "--method", "org.freedesktop.DBus.Properties.Get",
                "org.mpris.MediaPlayer2", "Identity",
            ],
            env=self.fixture.environment(),
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertIn("II Music", reply.stdout)

        seek = subprocess.run(
            [
                "gdbus", "call", "--session", "--dest", self.bus_name,
                "--object-path", "/org/mpris/MediaPlayer2",
                "--method", "org.mpris.MediaPlayer2.Player.Seek", "1000000",
            ],
            env=self.fixture.environment(),
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        self.assertEqual(seek.returncode, 0, seek.stderr)
        seek_event = self._event("mprisCommand")
        self.assertEqual(seek_event["payload"]["command"], "seekRelative")
        self.assertEqual(seek_event["payload"]["payload"]["offsetSec"], 1.0)

        opened = self._request("open-1", "open", {
            "paths": [str(self.first_audio), str(self.second_audio)],
            "sessionKind": "playlist",
        })
        self.assertTrue(opened["ok"])
        self.assertEqual(opened["payload"]["queue"]["sessionKind"], "playlist")
        self.assertEqual(opened["payload"]["track"]["title"], "first")
        self.assertTrue(opened["payload"]["canGoNext"])

        volume = self._request("volume-1", "setVolume", {"volume": 0.42})
        self.assertTrue(volume["ok"])
        self.assertAlmostEqual(volume["payload"]["volume"], 0.42, places=2)
        seek_capability = volume["payload"]["canSeek"]
        for attempt in range(20):
            if seek_capability:
                break
            time.sleep(0.05)
            seek_capability = self._request(f"snapshot-seek-{attempt}", "snapshot")["payload"]["canSeek"]
        self.assertTrue(seek_capability)
        next_track = self._request("next-1", "next")
        self.assertTrue(next_track["ok"])
        self.assertEqual(next_track["payload"]["track"]["title"], "second")

        appended = self._request("append-1", "append", {
            "entries": [{
                "path": str(self.third_audio),
                "trackId": "third-track",
                "title": "third",
                "artist": "II",
                "lyricsPath": str(self.third_lyrics),
            }],
        })
        self.assertTrue(appended["ok"])
        entries_after_append = appended["payload"]["queue"]["entries"]
        self.assertEqual([entry["title"] for entry in entries_after_append], ["first", "second", "third"])

        moved = self._request("move-1", "moveEntry", {
            "entryId": entries_after_append[0]["entryId"],
            "destinationIndex": 2,
        })
        self.assertTrue(moved["ok"])
        self.assertEqual([entry["title"] for entry in moved["payload"]["queue"]["entries"]], ["second", "third", "first"])
        self.assertEqual(moved["payload"]["track"]["title"], "second")

        played_entry = self._request("play-entry-1", "playEntry", {
            "entryId": moved["payload"]["queue"]["entries"][1]["entryId"],
        })
        self.assertTrue(played_entry["ok"])
        self.assertEqual(played_entry["payload"]["track"]["title"], "third")
        self.assertEqual(played_entry["payload"]["track"]["lyricsPath"], str(self.third_lyrics))

        shuffled = self._request("shuffle-1", "setShuffle", {"value": True})
        self.assertTrue(shuffled["ok"])
        self.assertTrue(shuffled["payload"]["shuffle"])
        self.assertTrue(shuffled["payload"]["queue"]["shuffle"])
        unshuffled = self._request("shuffle-2", "setShuffle", {"value": False})
        self.assertTrue(unshuffled["ok"])
        self.assertEqual([entry["title"] for entry in unshuffled["payload"]["queue"]["entries"]], ["second", "third", "first"])

        cleared_future = self._request("clear-future-1", "clearFuture")
        self.assertTrue(cleared_future["ok"])
        self.assertEqual([entry["title"] for entry in cleared_future["payload"]["queue"]["entries"]], ["second", "third"])

        stopped = self._request("stop-1", "stop")
        self.assertTrue(stopped["ok"])
        self.assertEqual(stopped["payload"]["playbackStatus"], "Stopped")
        resumed = self._request("play-1", "play")
        self.assertTrue(resumed["ok"])
        self.assertEqual(resumed["payload"]["playbackStatus"], "Playing")

        duplicate_socket = Path(self.temp_dir.name) / "duplicate.sock"
        duplicate = subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "--test-null-audio",
                "--test-start-paused",
                "--socket",
                str(duplicate_socket),
                "--mpris-name",
                self.bus_name,
            ],
            env=self.fixture.environment(),
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        self.assertEqual(duplicate.returncode, 1)
        self.assertIn("startupFailed", duplicate.stdout)
        self.assertFalse(duplicate_socket.exists())

        ping = self._request("ping-1", "ping")
        self.assertTrue(ping["ok"])
        self.assertEqual(ping["payload"]["busName"], self.bus_name)
        snapshot = self._request("snapshot-1", "snapshot")
        self.assertEqual(snapshot["payload"]["queue"]["sessionKind"], "playlist")

        shutdown = self._request("shutdown-1", "shutdown")
        self.assertEqual(shutdown["payload"]["status"], "stopping")
        self.assertEqual(self.process.wait(timeout=3), 0)
        self.assertFalse((Path(self.temp_dir.name) / "player.sock").exists())


if __name__ == "__main__":
    unittest.main()
