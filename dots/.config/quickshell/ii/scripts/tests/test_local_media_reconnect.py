#!/usr/bin/env python3
"""Test local media daemon persistence across Quickshell reloads."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts" / "media" / "local_player.py"


@unittest.skipUnless(shutil.which("mpv"), "mpv is not installed")
class LocalMediaDaemonReconnectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix="ii-daemon-test-")
        self.daemon_sock = Path(self.temp_dir.name) / "daemon.sock"
        self.mpv_sock = Path(self.temp_dir.name) / "mpv.sock"
        self.bus_name = f"org.mpris.MediaPlayer2.ii_test_{os.getpid()}"

    def tearDown(self) -> None:
        # Probe and shutdown if running
        p = subprocess.run(
            [sys.executable, str(HELPER), "--probe", "--daemon-socket", str(self.daemon_sock)],
            capture_output=True,
        )
        if p.returncode == 0:
            bridge = subprocess.Popen(
                [
                    sys.executable,
                    str(HELPER),
                    "--daemon-socket",
                    str(self.daemon_sock),
                    "--socket",
                    str(self.mpv_sock),
                    "--mpris-name",
                    self.bus_name,
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                text=True,
            )
            assert bridge.stdin is not None
            bridge.stdin.write(json.dumps({"protocolVersion": 1, "requestId": "shut", "op": "shutdown"}) + "\n")
            bridge.stdin.flush()
            bridge.wait(timeout=3)
            if bridge.stdout:
                bridge.stdout.close()
            if bridge.stdin:
                bridge.stdin.close()
        self.temp_dir.cleanup()

    def test_daemon_persists_across_bridge_restarts(self) -> None:
        # 1. Initial probe returns 1 (no daemon)
        p = subprocess.run(
            [sys.executable, str(HELPER), "--probe", "--daemon-socket", str(self.daemon_sock)],
            capture_output=True,
        )
        self.assertEqual(p.returncode, 1)

        # 2. Start bridge client
        bridge1 = subprocess.Popen(
            [
                sys.executable,
                str(HELPER),
                "--daemon-socket",
                str(self.daemon_sock),
                "--socket",
                str(self.mpv_sock),
                "--mpris-name",
                self.bus_name,
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        assert bridge1.stdout is not None
        ready_line = bridge1.stdout.readline()
        ready_data = json.loads(ready_line)
        self.assertEqual(ready_data.get("event"), "ready")

        state_line = bridge1.stdout.readline()
        state_data = json.loads(state_line)
        self.assertEqual(state_data.get("event"), "state")

        # 3. Probe returns 0 (daemon is active)
        p = subprocess.run(
            [sys.executable, str(HELPER), "--probe", "--daemon-socket", str(self.daemon_sock)],
            capture_output=True,
        )
        self.assertEqual(p.returncode, 0)

        # 4. Terminate bridge 1 (simulating Quickshell reload)
        bridge1.terminate()
        bridge1.wait()
        if bridge1.stdout:
            bridge1.stdout.close()
        if bridge1.stdin:
            bridge1.stdin.close()
        time.sleep(0.2)

        # Daemon must still be running!
        p = subprocess.run(
            [sys.executable, str(HELPER), "--probe", "--daemon-socket", str(self.daemon_sock)],
            capture_output=True,
        )
        self.assertEqual(p.returncode, 0)

        # 5. Connect bridge 2 (simulating Quickshell restart after reload)
        bridge2 = subprocess.Popen(
            [
                sys.executable,
                str(HELPER),
                "--daemon-socket",
                str(self.daemon_sock),
                "--socket",
                str(self.mpv_sock),
                "--mpris-name",
                self.bus_name,
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        assert bridge2.stdout is not None
        b2_ready = json.loads(bridge2.stdout.readline())
        self.assertEqual(b2_ready.get("event"), "ready")

        b2_state = json.loads(bridge2.stdout.readline())
        self.assertEqual(b2_state.get("event"), "state")

        # 6. Shutdown cleanly
        assert bridge2.stdin is not None
        bridge2.stdin.write(json.dumps({"protocolVersion": 1, "requestId": "shut", "op": "shutdown"}) + "\n")
        bridge2.stdin.flush()
        shut_reply = json.loads(bridge2.stdout.readline())
        self.assertTrue(shut_reply.get("ok"))
        bridge2.wait(timeout=3)
        if bridge2.stdout:
            bridge2.stdout.close()
        if bridge2.stdin:
            bridge2.stdin.close()

        time.sleep(0.3)
        # Probe returns 1 after shutdown
        p = subprocess.run(
            [sys.executable, str(HELPER), "--probe", "--daemon-socket", str(self.daemon_sock)],
            capture_output=True,
        )
        self.assertEqual(p.returncode, 1)


if __name__ == "__main__":
    unittest.main()
