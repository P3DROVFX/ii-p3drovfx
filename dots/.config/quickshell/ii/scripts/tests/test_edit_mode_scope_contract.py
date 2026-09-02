#!/usr/bin/env python3
"""Edit Mode scope contract.

The mode edits layout, plus an ENUMERATED set of appearance preferences its
quick-settings pages own (the bar's and the dock's). Every config write
reachable from the mode's own files must land on an allowlisted path, and the
Config helpers the mode calls must themselves write only allowlisted paths.

The point of the list is not that it is short; it is that it is a list. A page
that starts writing something new has to say so here first.

Known blind spot: the write regex cannot see a bracket write
(`Config.options.dock[key] = ...`), which the dock's widget page and the bar's
style rows both use. Those keys are listed anyway, so the allowlist stays an
honest description of the mode's reach even where the test cannot enforce it.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# What the mode REARRANGES, as `Config.options.<path>` (prefix match on `.`).
LAYOUT_PATHS = {
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
    "lock.islands.hidden",
    "lock.nowPlaying",
    "lock.sports",
    "lock.showAlarm",
    "lock.showWeather",
    "lock.showLockedText",
    "lock.security.fingerprint.showIndicator",
}

# What the mode's quick-settings pages may CHOOSE. Arranging a bar and saying
# how it is drawn are the same task, and leaving the mode to do half of it is
# what made the mode feel unfinished - but the reach is spelled out rather than
# handed a `bar.`/`dock.` prefix.
PREFERENCE_PATHS = {
    # The shell's corners, and the fake screen frame drawn around the bar.
    "appearance.fakeScreenRounding",
    "appearance.wrappedFrameThickness",
    "appearance.roundingValue",
    "appearance.sharpMode",
    # Repairs the bar's own selectors have always made alongside their write.
    "sidebar.sidebarStyle",
    # The bar's face.
    "bar.sizes",
    "bar.autoHide.enable",
    "bar.cornerStyle",
    "bar.barBackgroundStyle",
    "bar.barGroupStyle",
    "bar.expressiveColors",
    "bar.expressiveGroupColor",
    "bar.transparentGlow",
    "bar.dropShadow",
    "bar.floatStyleShadow",
    # One widget's style variant, written as `bar.styles[key]`.
    "bar.styles",
    # The dock's face.
    "dock.position",
    "dock.height",
    "dock.dockStyle",
    "dock.islandsStyle",
    "dock.islandSpacing",
    "dock.dockRadius",
    "dock.widgetRadius",
    "dock.monochromeIcons",
    "dock.dimInactiveIcons",
    "dock.enableShapeMask",
    "dock.enableMagnification",
    "dock.iconSpacing",
    "dock.pinnedOnStartup",
    "dock.hoverToReveal",
    "dock.smartGrouping",
    # The dock's widgets and buttons, written as `dock[key]`.
    "dock.enableMediaWidget",
    "dock.enableWeatherWidget",
    "dock.enableSportsWidget",
    "dock.enableLivePreviewWidget",
    "dock.showPhoneButton",
    "dock.showOverviewButton",
    "dock.showPinButton",
    "dock.showTrashButton",
    "dock.showNotificationBadges",
    "dock.showDividers",
}

# What the Style catalogue may choose. The wallpaper paths themselves are
# written by the Wallpapers service on the catalogue's behalf and are not in
# here on purpose: the mode never writes them directly, and the service is
# the one place that also runs the switch script.
STYLE_PATHS = {
    "background.useSeparateLockscreenWallpaper",
    "background.useSeparateLightModeWallpaper",
    # The scheme, written back by a history replay of the swatch grid's pick.
    "appearance.palette.type",
}

ALLOWED_PATHS = LAYOUT_PATHS | PREFERENCE_PATHS | STYLE_PATHS

# Config helpers the mode may call; each must write only ALLOWED_PATHS.
ALLOWED_HELPERS = {
    "addWidgetToDesktop",
    "removeWidgetFromDesktop",
    "removeWidgetInstance",
    "duplicateWidgetInstance",
    "updateWidgetPosition",
    "updateWidgetLockBehavior",
    "updateWidgetScale",
    "updateWidgetPinned",
    "clearWidgetLockPositions",
    "setLockIslandOrder",
    "setLockIslandHidden",
    # Flushes the adapter; writes no option of its own. A history replay of a
    # scheme pick calls it so the switch script reads the scheme it was given.
    "saveOptionsNow",
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
        self.assertEqual(paths, {p for p in LAYOUT_PATHS if p.startswith("lock.") and "islands" not in p})


if __name__ == "__main__":
    unittest.main()
