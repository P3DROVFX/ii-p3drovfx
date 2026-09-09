#!/usr/bin/env python3
"""Regression contract for the shaped glow of the desktop media widget."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MEDIA_WIDGET = ROOT / "modules/ii/background/widgets/media/MediaWidget.qml"


class DesktopMediaGlowContractTests(unittest.TestCase):
    def setUp(self):
        self.source = MEDIA_WIDGET.read_text(encoding="utf-8")

    def test_glow_uses_a_padded_native_blur_of_the_current_shape(self):
        self.assertIn("readonly property real glowPadding", self.source)
        self.assertIn("anchors.margins: -root.glowPadding", self.source)
        self.assertIn("MultiEffect {", self.source)
        self.assertIn("source: glowSourceShape", self.source)
        self.assertIn("autoPaddingEnabled: false", self.source)
        self.assertIn("blurMax: root.glowPadding", self.source)
        self.assertIn("shapeString: root.backgroundShape", self.source)
        self.assertIn("color: root.artDominantColor", self.source)

    def test_glow_no_longer_depends_on_the_compatibility_shadow(self):
        self.assertNotIn("id: blurredArtGlow", self.source)
        self.assertNotIn("transparentBorder: true", self.source)


if __name__ == "__main__":
    unittest.main()
