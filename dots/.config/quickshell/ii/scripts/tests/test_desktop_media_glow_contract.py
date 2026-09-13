#!/usr/bin/env python3
"""Regression contract for the shaped glow of the desktop media widget."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MEDIA_WIDGET = ROOT / "modules/ii/background/widgets/media/MediaWidget.qml"


class DesktopMediaGlowContractTests(unittest.TestCase):
    def setUp(self):
        self.source = MEDIA_WIDGET.read_text(encoding="utf-8")

    def test_glow_uses_stacked_shapes_without_an_effect_texture(self):
        self.assertIn("readonly property real glowPadding", self.source)
        self.assertIn("Repeater {", self.source)
        self.assertIn('"spread": 1.0', self.source)
        self.assertIn("anchors.margins: -root.glowPadding * modelData.spread", self.source)
        self.assertIn("shapeString: root.backgroundShape", self.source)
        self.assertIn("ColorUtils.transparentize(root.artDominantColor, 1 - modelData.alpha)", self.source)

    def test_glow_avoids_blur_buffers_on_the_background_window(self):
        self.assertNotIn("id: blurredArtGlow", self.source)
        self.assertNotIn("transparentBorder: true", self.source)
        self.assertNotIn("id: glowSourceShape", self.source)
        self.assertNotIn("blurMax: root.glowPadding", self.source)


if __name__ == "__main__":
    unittest.main()
