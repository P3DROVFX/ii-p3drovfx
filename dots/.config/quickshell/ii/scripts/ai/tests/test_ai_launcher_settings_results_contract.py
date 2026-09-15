#!/usr/bin/env python3
"""Settings matches in the launcher must behave like launcher results."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
LAUNCHER = (ROOT / "services" / "LauncherSearch.qml").read_text(encoding="utf-8")
SEARCH_WIDGET = (ROOT / "modules" / "ii" / "overview" / "SearchWidget.qml").read_text(encoding="utf-8")
SETTING_CARD = (ROOT / "services" / "ai" / "blocks" / "AiSettingResultCard.qml").read_text(encoding="utf-8")


class LauncherSettingsResultsTests(unittest.TestCase):
    def test_applications_precede_settings_matches(self):
        apps = LAUNCHER.index("result = result.concat(appResultObjects);")
        settings = LAUNCHER.index("result = result.concat(settingsResultObjects);")
        self.assertLess(apps, settings)

    def test_settings_cards_are_inset_inside_a_full_width_loader_wrapper(self):
        # Loader resizes its directly loaded item to its own explicit width.
        # The Settings card therefore needs a full-width wrapper; merely
        # moving the card with x leaves its right edge outside the delegate.
        card_loader = SEARCH_WIDGET.split("id: settingResultCard", 1)[1].split("id: normalSearchItem", 1)[0]
        self.assertIn("Item {", card_loader)
        self.assertIn("anchors.left: parent.left", card_loader)
        self.assertIn("anchors.right: parent.right", card_loader)
        self.assertIn("anchors.margins: Appearance.sizes.elevationMargin", card_loader)
        self.assertNotIn("width: Math.max", card_loader)
        self.assertIn("launcherStyle: true", card_loader)

    def test_launcher_card_has_its_own_surface_background(self):
        self.assertIn("property bool launcherStyle: false", SETTING_CARD)
        self.assertIn("Appearance.colors.colSurfaceContainerHigh", SETTING_CARD)

    def test_settings_card_receives_the_list_selection_for_search_radius(self):
        card_loader = SEARCH_WIDGET.split("id: settingResultCard", 1)[1].split("id: normalSearchItem", 1)[0]
        for token in (
            "listIndex: resultDelegate.index",
            "listCount: appResults.count",
            "listCurrentIndex: appResults.currentIndex",
        ):
            with self.subTest(token=token):
                self.assertIn(token, card_loader)
        for token in (
            "readonly property bool isSelected",
            "readonly property bool isAboveSelected",
            "readonly property bool isBelowSelected",
            "topLeftRadius:",
            "bottomLeftRadius:",
        ):
            with self.subTest(token=token):
                self.assertIn(token, SETTING_CARD)

    def test_settings_rows_expose_keyboard_actions_for_every_control_type(self):
        card_loader = SEARCH_WIDGET.split("id: settingResultCard", 1)[1].split("id: normalSearchItem", 1)[0]
        for token in (
            "function clicked()",
            "function navigateLeft()",
            "function navigateRight()",
            "supportsHorizontalNavigation",
        ):
            with self.subTest(token=token):
                self.assertIn(token, card_loader)
        for token in (
            "function activate()",
            "function adjustBy(direction: int)",
            'root.settingType === "bool"',
            'root.settingType === "int"',
            'root.settingType === "real"',
            'root.settingType === "enum"',
            'root.settingType === "string"',
        ):
            with self.subTest(token=token):
                self.assertIn(token, SETTING_CARD)

    def test_search_routes_horizontal_keys_only_to_the_selected_setting_row(self):
        self.assertIn("selectedResultHandlesHorizontalNavigation", SEARCH_WIDGET)
        self.assertIn("selectedResultSupportsHorizontalNavigation", (ROOT / "modules" / "ii" / "overview" / "SearchBar.qml").read_text(encoding="utf-8"))
        self.assertIn("root.navigateSelectedResult(\"left\")", SEARCH_WIDGET)
        self.assertIn("root.navigateSelectedResult(\"right\")", SEARCH_WIDGET)

    def test_selected_setting_card_uses_primary_hover_not_switch_primary(self):
        self.assertIn("HoverHandler {", SETTING_CARD)
        card_surface = SETTING_CARD.split("color: root.launcherStyle", 1)[1].split("HoverHandler", 1)[0]
        self.assertIn("root.isHovered ? Appearance.colors.colSurfaceContainerHighestHover", card_surface)
        self.assertIn("root.isSelected ? Appearance.colors.colPrimaryHover", card_surface)

    def test_open_button_reuses_the_chat_settings_open_redirect(self):
        opener = SETTING_CARD.split("function openInSettings()", 1)[1].split("\n    }", 1)[0]
        self.assertIn("Ai.toolSettingsOpen({", opener)
        self.assertIn("pageId: String(root.setting?.pageId ?? \"\")", opener)
        self.assertIn("subPage: String(root.setting?.subPage ?? \"\")", opener)
        self.assertIn("sectionTitle:", opener)


if __name__ == "__main__":
    unittest.main()
