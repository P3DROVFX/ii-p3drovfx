"""Contracts for the rounded full-width dock style (full_width_concave)."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CONFIG = (ROOT / "modules/common/Config.qml").read_text()
DOCK = (ROOT / "modules/ii/dock/Dock.qml").read_text()
DOCK_CONTENT = (ROOT / "modules/ii/dock/DockContent.qml").read_text()
APPEARANCE = (ROOT / "modules/settings/configs/widgets/DockAppearanceConfig.qml").read_text()
EDIT_PAGE = (ROOT / "modules/ii/editMode/EditDockAppearancePage.qml").read_text()


class DockFullWidthConcaveStyleContractTests(unittest.TestCase):
    def test_style_is_registered(self):
        self.assertIn('"full_width_concave"]', CONFIG)
        self.assertIn('value: "full_width_concave"', APPEARANCE)
        self.assertIn('"value": "full_width_concave"', EDIT_PAGE)

    def test_it_is_a_full_width_style(self):
        # The flush layout, the square tray and the centred row all come from
        # isFullWidth; the rounded style only adds its corners.
        self.assertIn('readonly property bool isFullWidthConcave: effectiveDockStyle === "full_width_concave"', DOCK_CONTENT)
        self.assertIn('readonly property bool isFullWidth: effectiveDockStyle === "full_width" || isFullWidthConcave', DOCK_CONTENT)

    def test_window_keeps_room_for_the_corners_outside_the_exclusive_zone(self):
        self.assertIn("const concaveCrossPad = (opts.isFullWidthConcave ?? false)", DOCK)
        self.assertIn("Math.max(crossSafety, concaveCrossPad)", DOCK)
        # The exclusive zone stays the tray: windows reach it, the corners
        # round their edge.
        self.assertIn("unmagnifiedThickness: opts.isVertical ? baseContentW + (isFullWidth ? 0 : crossPad) : baseContentH + (isFullWidth ? 0 : crossPad)", DOCK)

    def test_two_corners_drawn_in_the_tray_colour(self):
        self.assertIn("model: (dockRoot.isFullWidthConcave && !dockContent.islandsStyle) ? 2 : 0", DOCK)
        self.assertIn("color: dockVisualBackground.color", DOCK)


if __name__ == "__main__":
    unittest.main()
