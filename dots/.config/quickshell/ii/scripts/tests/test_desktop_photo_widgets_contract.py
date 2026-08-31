#!/usr/bin/env python3
"""Regression contract for GIF and shape support across all Desktop Photo widgets."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class DesktopPhotoWidgetsContractTests(unittest.TestCase):
    def setUp(self):
        photo_dir = ROOT / "modules/ii/background/widgets/photo"
        self.photo_widget = (photo_dir / "PhotoWidget.qml").read_text(encoding="utf-8")
        self.photo_1x1_widget = (photo_dir / "Photo1x1Widget.qml").read_text(encoding="utf-8")
        self.photo_weather_2x1 = (photo_dir / "PhotoWeather2x1Widget.qml").read_text(encoding="utf-8")
        self.photo_pill_2x1 = (photo_dir / "PhotoPill2x1Widget.qml").read_text(encoding="utf-8")
        self.photo_minimal_temp_2x1 = (photo_dir / "PhotoMinimalTemp2x1Widget.qml").read_text(encoding="utf-8")
        
        config_dir = ROOT / "modules/settings/configs/widgets"
        self.photo_config = (config_dir / "DesktopPhotoWidgetConfig.qml").read_text(encoding="utf-8")
        self.photo_1x1_config = (config_dir / "DesktopPhoto1x1Config.qml").read_text(encoding="utf-8")

    def test_all_photo_widgets_use_animated_image_for_gif_support_with_cpu_optimizations(self):
        widgets = [
            self.photo_widget,
            self.photo_1x1_widget,
            self.photo_weather_2x1,
            self.photo_pill_2x1,
            self.photo_minimal_temp_2x1
        ]
        for w in widgets:
            self.assertIn("AnimatedImage", w)
            self.assertIn("Image {", w)
            self.assertIn("!GlobalStates.activeWorkspaceHasWindows", w)
            self.assertIn("playing: root.shouldPlay", w)
            self.assertIn("paused: !root.shouldPlay", w)
            self.assertIn("layer.effect: OpacityMask", w)

    def test_photo_config_pickers_include_gif_support(self):
        self.assertIn("*.gif", self.photo_config)
        self.assertIn("*.gif", self.photo_1x1_config)

    def test_photo_1x1_config_supports_all_material_shapes(self):
        self.assertIn("Cookie9Sided", self.photo_1x1_config)
        self.assertIn("PixelTriangle", self.photo_1x1_config)
        self.assertIn("Flower", self.photo_1x1_config)
        self.assertIn("Bun", self.photo_1x1_config)


if __name__ == "__main__":
    unittest.main()
