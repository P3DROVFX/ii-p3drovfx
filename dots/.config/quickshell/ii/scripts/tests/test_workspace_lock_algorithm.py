#!/usr/bin/env python3
"""Tests for workspace_lock.js allocation algorithm."""

import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
JS_FILE = ROOT / "modules/common/functions/workspace_lock.js"


def run_allocate(params: dict) -> dict:
    runner = f"""
const fs = require('fs');
const content = fs.readFileSync('{JS_FILE}', 'utf8');
const fn = new Function('params', content + '\\nreturn allocateEmptyWorkspaces(params);');
const res = fn({json.dumps(params)});
console.log(JSON.stringify(res));
"""
    proc = subprocess.run(["node", "-e", runner], capture_output=True, text=True, check=True)
    return json.loads(proc.stdout.strip())


class WorkspaceLockAlgorithmTest(unittest.TestCase):
    def test_single_monitor_finds_next_empty(self):
        # Workspaces 1..6 have windows. Mon is on ws 3.
        window_list = [{"workspace": {"id": i}} for i in range(1, 7)]
        all_monitors = [{"name": "eDP-1", "activeWorkspace": {"id": 3}}]
        monitors = [{"name": "eDP-1", "activeWorkspaceId": 3, "index": 0}]

        res = run_allocate({
            "monitors": monitors,
            "windowList": window_list,
            "allMonitors": all_monitors,
            "useWorkspaceMap": False,
        })
        self.assertEqual(res, {"eDP-1": 7})

    def test_single_monitor_finds_closer_empty_workspace(self):
        # Workspaces 1, 3, 4 have windows. Workspace 2 is empty! Mon is on ws 3.
        window_list = [{"workspace": {"id": 1}}, {"workspace": {"id": 3}}, {"workspace": {"id": 4}}]
        all_monitors = [{"name": "eDP-1", "activeWorkspace": {"id": 3}}]
        monitors = [{"name": "eDP-1", "activeWorkspaceId": 3, "index": 0}]

        res = run_allocate({
            "monitors": monitors,
            "windowList": window_list,
            "allMonitors": all_monitors,
            "useWorkspaceMap": False,
        })
        # ws 2 is distance 1 (3 - 1 = 2) and empty!
        self.assertEqual(res, {"eDP-1": 2})

    def test_multi_monitor_without_workspace_map_allocates_distinct(self):
        # Mon0 on ws 1, Mon1 on ws 2. Windows on 1 and 2.
        window_list = [{"workspace": {"id": 1}}, {"workspace": {"id": 2}}]
        all_monitors = [
            {"name": "eDP-1", "activeWorkspace": {"id": 1}},
            {"name": "HDMI-A-1", "activeWorkspace": {"id": 2}},
        ]
        monitors = [
            {"name": "eDP-1", "activeWorkspaceId": 1, "index": 0},
            {"name": "HDMI-A-1", "activeWorkspaceId": 2, "index": 1},
        ]

        res = run_allocate({
            "monitors": monitors,
            "windowList": window_list,
            "allMonitors": all_monitors,
            "useWorkspaceMap": False,
        })
        # Mon0 should get 3, Mon1 should get 4 (or distinct positive integers)
        self.assertNotEqual(res["eDP-1"], res["HDMI-A-1"])
        self.assertNotIn(res["eDP-1"], [1, 2])
        self.assertNotIn(res["HDMI-A-1"], [1, 2])
        self.assertEqual(res, {"eDP-1": 3, "HDMI-A-1": 4})

    def test_multi_monitor_with_workspace_map_respects_ranges(self):
        # Mon0 range 1..9, Mon1 range 10..18.
        # Mon0 on ws 3 (windows on 1, 2, 3). Mon1 on ws 10 (windows on 10).
        window_list = [
            {"workspace": {"id": 1}},
            {"workspace": {"id": 2}},
            {"workspace": {"id": 3}},
            {"workspace": {"id": 10}},
        ]
        all_monitors = [
            {"name": "eDP-1", "activeWorkspace": {"id": 3}},
            {"name": "HDMI-A-1", "activeWorkspace": {"id": 10}},
        ]
        monitors = [
            {"name": "eDP-1", "activeWorkspaceId": 3, "index": 0},
            {"name": "HDMI-A-1", "activeWorkspaceId": 10, "index": 1},
        ]

        res = run_allocate({
            "monitors": monitors,
            "windowList": window_list,
            "allMonitors": all_monitors,
            "useWorkspaceMap": True,
            "workspaceMap": [0, 9],
            "workspacesShown": 10,
        })
        self.assertEqual(res["eDP-1"], 4)
        self.assertEqual(res["HDMI-A-1"], 11)

    def test_legacy_high_id_recovery(self):
        # If already parked on 2147483644 (from previous crash/lock)
        all_monitors = [{"name": "eDP-1", "activeWorkspace": {"id": 2147483644}}]
        monitors = [{"name": "eDP-1", "activeWorkspaceId": 2147483644, "index": 0}]

        res = run_allocate({
            "monitors": monitors,
            "windowList": [],
            "allMonitors": all_monitors,
            "useWorkspaceMap": False,
        })
        # Recovers to a normal near workspace (1 or 2)
        self.assertLess(res["eDP-1"], 10)


if __name__ == "__main__":
    unittest.main()
