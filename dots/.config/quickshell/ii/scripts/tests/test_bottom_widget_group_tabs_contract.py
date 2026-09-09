#!/usr/bin/env python3
"""Regression contract for Dashboard bottom-group tab state colors."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "modules/ii/sidebarDashboard/BottomWidgetGroup.qml").read_text(encoding="utf-8")


class BottomWidgetGroupTabColorTests(unittest.TestCase):
    def test_tabs_keep_distinct_layer_and_selected_container_states(self):
        tab = SOURCE.split("NavigationRailButton {", 1)[1].split("property real _navBtnScale", 1)[0]
        self.assertIn("showToggledHighlight: true", tab)
        self.assertIn("colBackgroundHover: Appearance.colors.colLayer2Hover", tab)
        self.assertIn("colBackgroundActive: Appearance.colors.colLayer2Active", tab)
        self.assertIn("colBackgroundToggled: Appearance.colors.colSecondaryContainer", tab)
        self.assertIn("colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover", tab)
        self.assertIn("colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive", tab)
        self.assertNotIn("colPrimaryHover", tab)


if __name__ == "__main__":
    unittest.main()
