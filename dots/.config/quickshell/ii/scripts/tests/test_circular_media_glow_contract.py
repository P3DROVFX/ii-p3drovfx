"""Regression contract for circular media's blur-safe glow."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WIDGETS_WINDOW = ROOT / "modules/ii/background/BackgroundWidgetsWindow.qml"
CIRCULAR_MEDIA = ROOT / "modules/ii/background/widgets/media/CircularMediaWidget.qml"


class CircularMediaGlowContractTests(unittest.TestCase):
    def setUp(self):
        self.widgets_window = WIDGETS_WINDOW.read_text(encoding="utf-8")
        self.circular_media = CIRCULAR_MEDIA.read_text(encoding="utf-8")

    def test_circular_fix_does_not_change_the_shared_widget_canvas_rule(self):
        self.assertIn("WlrLayershell.namespace: \"quickshell:backgroundWidgets\"", self.widgets_window)
        appearance = (ROOT / "modules/common/Appearance.qml").read_text(encoding="utf-8")
        self.assertFalse("name = 'ii:appearance:background-widgets'" in appearance)

    def test_local_glow_blurs_do_not_clamp_their_effect_texture_edges(self):
        blur_count = self.circular_media.count("FastBlur {")
        self.assertGreater(blur_count, 0)
        self.assertEqual(blur_count, self.circular_media.count("transparentBorder: true"))

    def test_low_ignore_alpha_disables_only_circular_translucent_effects(self):
        self.assertIn("readonly property bool blurredEffectsSafe: Appearance.ignoreAlpha > 0.3", self.circular_media)
        self.assertIn("visible: root.blurredEffectsSafe && (Config.options.background.widgets.enableShadows ?? true)", self.circular_media)
        self.assertIn("layer.enabled: root.blurredEffectsSafe", self.circular_media)
        self.assertIn("visible: root.blurredEffectsSafe && (Config.options.background.widgets.circular_media.enableGlassReflection ?? true)", self.circular_media)


if __name__ == "__main__":
    unittest.main()
