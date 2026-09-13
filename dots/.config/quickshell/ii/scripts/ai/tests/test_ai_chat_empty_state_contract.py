#!/usr/bin/env python3
"""Contract tests for the sidebar AI empty-state geometry."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CHAT = (ROOT / "modules" / "ii" / "sidebarPolicies" / "AiChat.qml").read_text(encoding="utf-8")
PLACEHOLDER = (ROOT / "modules" / "common" / "widgets" / "PagePlaceholder.qml").read_text(encoding="utf-8")


class SidebarEmptyStateTests(unittest.TestCase):
    def test_empty_state_stage_ends_before_the_hint_rail(self):
        stage = CHAT.split("id: emptyStateStage", 1)[1].split("\n                    Loader {", 1)[0]
        self.assertIn("bottom: emptyStateKeys.top", stage)
        self.assertIn("bottomMargin: Appearance.rounding.large", stage)
        self.assertIn("anchors.fill: parent", stage)

    def test_sidebar_hero_uses_the_larger_profile(self):
        stage = CHAT.split("id: emptyStateStage", 1)[1].split("\n                    Loader {", 1)[0]
        self.assertIn("iconSize: Appearance.font.pixelSize.huge * 3", stage)
        self.assertIn("iconPadding: Appearance.rounding.normal", stage)
        self.assertIn("titlePixelSize: Appearance.font.pixelSize.huge", stage)
        self.assertIn("descriptionPixelSize: Appearance.font.pixelSize.normal", stage)

    def test_page_placeholder_exposes_optional_size_controls(self):
        self.assertIn("property alias iconSize: shapeWidget.iconSize", PLACEHOLDER)
        self.assertIn("property alias iconPadding: shapeWidget.padding", PLACEHOLDER)
        self.assertIn("property real titlePixelSize", PLACEHOLDER)
        self.assertIn("property real descriptionPixelSize", PLACEHOLDER)


if __name__ == "__main__":
    unittest.main()
