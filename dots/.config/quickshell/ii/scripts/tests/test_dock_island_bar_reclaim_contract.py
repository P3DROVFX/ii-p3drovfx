"""Contracts for a full-width dock beside a Dynamic Island bar.

The island bar style reserves a whole strip but draws a pill in it, so the dock
reads the pill's real extent (published by the bar window) and takes the strip
back with a negative layer margin where the pill does not reach it.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
DOCK = (ROOT / "modules/ii/dock/Dock.qml").read_text()
STATES = (ROOT / "GlobalStates.qml").read_text()
VBAR = (ROOT / "modules/ii/verticalBar/VerticalBar.qml").read_text()
HBAR = (ROOT / "modules/ii/bar/core/BarWindow.qml").read_text()


class DockIslandBarReclaimContractTests(unittest.TestCase):
    def test_globalstates_holds_the_published_pill(self):
        self.assertIn("property var barIslands: ({})", STATES)
        self.assertIn("function setBarIsland(screenName, edge, extent, reserve)", STATES)

    def test_both_bar_windows_publish_and_clear_on_destruction(self):
        for src in (VBAR, HBAR):
            self.assertIn("GlobalStates.setBarIsland(islandPublisher.screenName, islandPublisher.edge", src)
            self.assertIn('GlobalStates.setBarIsland(islandPublisher.screenName, "", 0, 0)', src)

    def test_autohide_bars_reserve_nothing_to_reclaim(self):
        self.assertIn("Config.options.bar.autoHide.enable ? 0", VBAR)
        self.assertIn("BarInteraction.autoHide", HBAR)

    def test_dock_gives_the_strip_back_through_negative_margins(self):
        self.assertIn("readonly property real islandReclaim", DOCK)
        for side in ("left", "right", "top", "bottom"):
            self.assertIn(f'{side}: dockRoot.barIsland?.edge === "{side}" ? -Math.round(dockRoot.islandReclaim) : 0', DOCK)

    def test_reclaim_only_takes_what_the_compositor_withheld(self):
        # A pinned dock can already span the screen: its natural size caps the margin.
        self.assertIn("dockRoot._naturalW = dockRoot.width - Math.round(dockRoot.islandReclaim)", DOCK)
        self.assertIn("dockRoot._naturalH = dockRoot.height - Math.round(dockRoot.islandReclaim)", DOCK)


if __name__ == "__main__":
    unittest.main()
