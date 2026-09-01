#!/usr/bin/env python3
"""Regression contract for NavigationRailButton's expanded-width sizing."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "modules/common/widgets/NavigationRailButton.qml").read_text(encoding="utf-8")


class NavigationRailButtonContractTests(unittest.TestCase):
    def test_fill_width_content_uses_natural_width_without_visual_width_cycle(self):
        content_item = SOURCE.split("contentItem: Item {", 1)[1].split("Rectangle {", 1)[0]
        self.assertNotIn("implicitWidth: root.visualWidth", content_item)
        self.assertIn("implicitWidth: root.expanded ? root.contentWidth : root.baseSize", content_item)
        self.assertIn("readonly property real contentWidth: root.baseSize + 20 + itemText.implicitWidth", SOURCE)


if __name__ == "__main__":
    unittest.main()
