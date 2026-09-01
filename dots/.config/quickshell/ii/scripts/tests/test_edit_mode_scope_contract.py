#!/usr/bin/env python3
"""Edit Mode scope contract.

The mode edits layout, nothing else. Every config write reachable from the
mode's own files must land on an allowlisted path, and the Config helpers the
mode calls must themselves write only allowlisted paths.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Paths the mode may write, as `Config.options.<path>` (prefix match on `.`).
ALLOWED_PATHS = {
    "background.activeWidgets",
    "background.widgets.enableSnap",
    "bar.layouts.left",
    "bar.layouts.center",
    "bar.layouts.right",
    "dock.order",
    "dock.pinnedApps",
    "lock.islands.main",
    "lock.islands.left",
    "lock.islands.right",
    "lock.nowPlaying",
    "lock.sports",
    "lock.showAlarm",
    "lock.showWeather",
    "lock.showLockedText",
    "lock.security.fingerprint.showIndicator",
}

# Config helpers the mode may call; each must write only ALLOWED_PATHS.
ALLOWED_HELPERS = {
    "addWidgetToDesktop",
    "removeWidgetFromDesktop",
    "updateWidgetPosition",
    "updateWidgetLockBehavior",
    "updateWidgetScale",
    "updateWidgetPinned",
    "clearWidgetLockPositions",
    "setLockIslandOrder",
}

MODE_FILES = sorted(
    list((ROOT / "modules/ii/editMode").glob("*.qml"))
    + list((ROOT / "modules/ii/bar").glob("BarEdit*.qml"))
    + list((ROOT / "modules/ii/background/desktopMenu").glob("*.qml"))
)

WRITE_RE = re.compile(r"Config\.options\.([A-Za-z0-9_.]+)\s*=(?!=)")
HELPER_RE = re.compile(r"Config\.([A-Za-z_][A-Za-z0-9_]*)\(")
ROOT_WRITE_RE = re.compile(r"root\.options\.([A-Za-z0-9_.]+)\s*=(?!=)")


def allowed(path):
    return any(path == a or path.startswith(a + ".") for a in ALLOWED_PATHS)


def function_body(source, name):
    start = source.index(f"function {name}(")
    depth, i = 0, source.index("{", start)
    for j in range(i, len(source)):
        if source[j] == "{":
            depth += 1
        elif source[j] == "}":
            depth -= 1
            if depth == 0:
                return source[i:j + 1]
    raise AssertionError(f"unterminated body for {name}")


class EditModeScopeContract(unittest.TestCase):
    def test_mode_files_exist(self):
        self.assertGreater(len(MODE_FILES), 8)

    def test_direct_writes_are_allowlisted(self):
        for path in MODE_FILES:
            for m in WRITE_RE.finditer(path.read_text()):
                self.assertTrue(allowed(m.group(1)), f"{path.name} writes Config.options.{m.group(1)}")

    def test_helpers_are_allowlisted(self):
        for path in MODE_FILES:
            for m in HELPER_RE.finditer(path.read_text()):
                self.assertIn(m.group(1), ALLOWED_HELPERS, f"{path.name} calls Config.{m.group(1)}()")

    def test_helpers_write_only_allowlisted_paths(self):
        source = (ROOT / "modules/common/Config.qml").read_text()
        for name in ALLOWED_HELPERS:
            body = function_body(source, name)
            for m in ROOT_WRITE_RE.finditer(body):
                self.assertTrue(allowed(m.group(1)), f"Config.{name} writes options.{m.group(1)}")
            # Island order goes through the islands object; pin that too.
            if name == "setLockIslandOrder":
                self.assertIn("root.options.lock.islands", body)

    def test_drawer_lock_switches_are_the_six_toggles(self):
        drawer = (ROOT / "modules/ii/editMode/EditModeDrawer.qml").read_text()
        keys = re.findall(r'"key":\s*"([A-Za-z]+)",\s*"group":\s*"(lock|fingerprint)"', drawer)
        paths = {("lock." if g == "lock" else "lock.security.fingerprint.") + k for k, g in keys}
        self.assertEqual(paths, {p for p in ALLOWED_PATHS if p.startswith("lock.") and "islands" not in p})


if __name__ == "__main__":
    unittest.main()
