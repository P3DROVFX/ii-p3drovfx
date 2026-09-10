"""Regression contract for circular media's compositor-safe glow."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APPEARANCE = ROOT / "modules/common/Appearance.qml"
WIDGETS_WINDOW = ROOT / "modules/ii/background/BackgroundWidgetsWindow.qml"
CIRCULAR_MEDIA = ROOT / "modules/ii/background/widgets/media/CircularMediaWidget.qml"


class CircularMediaGlowContractTests(unittest.TestCase):
    def setUp(self):
        self.appearance = APPEARANCE.read_text(encoding="utf-8")
        self.widgets_window = WIDGETS_WINDOW.read_text(encoding="utf-8")
        self.circular_media = CIRCULAR_MEDIA.read_text(encoding="utf-8")

    def test_widget_canvas_has_a_compositor_blur_opt_out(self):
        generic_rule = "namespace = 'quickshell.*'"
        widget_rule = "name = 'ii:appearance:background-widgets'"

        self.assertIn("WlrLayershell.namespace: \"quickshell:backgroundWidgets\"", self.widgets_window)
        self.assertIn(widget_rule, self.appearance)
        self.assertIn("namespace = 'quickshell:backgroundWidgets'", self.appearance)
        self.assertIn("blur = false, blur_popups = false, ignore_alpha = 1", self.appearance)
        self.assertLess(self.appearance.index(generic_rule), self.appearance.index(widget_rule))

    def test_local_glow_blurs_do_not_clamp_their_effect_texture_edges(self):
        blur_count = self.circular_media.count("FastBlur {")
        self.assertGreater(blur_count, 0)
        self.assertEqual(blur_count, self.circular_media.count("transparentBorder: true"))


if __name__ == "__main__":
    unittest.main()
