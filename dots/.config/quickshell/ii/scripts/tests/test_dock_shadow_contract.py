"""Contracts for keeping floating dock shadows inside the layer surface."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
DOCK = (ROOT / "modules/ii/dock/Dock.qml").read_text()
ISLAND_SURFACE = (ROOT / "modules/ii/dock/widgets/DockIslandSurface.qml").read_text()


class DockShadowContractTests(unittest.TestCase):
    def test_floating_surface_reserves_full_shadow_envelope(self):
        """Floating and islands styles need one shadow margin on every side."""
        self.assertIn("const floatingPad = isAttached ? 0 : shadowPad", DOCK)
        self.assertIn(
            "const mainPad = isDynamic ? (concaveReserve * 2) : (isHug ? (shadowPad * 2) : (floatingPad * 2))",
            DOCK,
        )
        self.assertIn(
            "const crossPad = isAttached ? (isHug ? shadowPad : 0) : (floatingPad * 2)",
            DOCK,
        )
        self.assertIn("surfaceMargin: floatingPad", DOCK)

    def test_floating_surface_is_inset_from_the_screen_edge(self):
        """The visible tray must sit after the reserved blur padding, not gapsOut."""
        self.assertIn("readonly property real surfaceMargin: dockRoot.sizing.surfaceMargin", DOCK)
        self.assertEqual(DOCK.count("dockRoot.surfaceMargin"), 4)

    def test_islands_keep_the_shared_rectangular_shadow(self):
        self.assertIn("StyledRectangularShadow", ISLAND_SURFACE)
        self.assertIn("target: surface", ISLAND_SURFACE)


if __name__ == "__main__":
    unittest.main()
