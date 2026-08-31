#!/usr/bin/env python3
"""Regression contracts for the in-window Settings search and navigation."""

import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "ai"))

import ai_settings_index  # noqa: E402


SEARCH_REGISTRY = (ROOT / "services" / "SearchRegistry.qml").read_text(encoding="utf-8")
SEARCH_PAGE = (ROOT / "modules" / "settings" / "configs" / "SearchPage.qml").read_text(encoding="utf-8")
SEARCH_BAR = (ROOT / "modules" / "settings" / "SearchBar.qml").read_text(encoding="utf-8")
WINDOW = (ROOT / "SettingsWindow.qml").read_text(encoding="utf-8")
SUBPAGE_HOST = (ROOT / "modules" / "common" / "widgets" / "ConfigSubPageHost.qml").read_text(encoding="utf-8")
CONTENT_SECTION = (ROOT / "modules" / "common" / "widgets" / "ContentSection.qml").read_text(encoding="utf-8")
CONFIG_SWITCH = (ROOT / "modules" / "common" / "widgets" / "ConfigSwitch.qml").read_text(encoding="utf-8")
TASKS = (ROOT / "modules" / "settings" / "configs" / "TasksAccountsConfig.qml").read_text(encoding="utf-8")


def between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class VisualSearchContracts(unittest.TestCase):
    def test_only_compact_semantic_controls_are_cloned(self):
        widget_list = between(SEARCH_REGISTRY, "let types = [", "];\n        for (let t")
        for wanted in (
            "ConfigSwitch",
            "ConfigSpinBox",
            "ConfigSelectionArray",
            "ConfigTextField",
            "ConfigSlider",
            "ConfigComboBox",
            "ConfigLightDarkToggle",
            "ConfigSubpageRow",
        ):
            self.assertIn(f'"{wanted}"', widget_list)

        for forbidden in (
            "NoticeBox",
            "ShortcutBox",
            "Flow",
            "RowLayout",
            "ColumnLayout",
            "ServiceCard",
            "RippleButtonWithIcon",
            "ConfigListView",
        ):
            self.assertNotIn(f'"{forbidden}"', widget_list)

    def test_sections_without_renderable_controls_are_rejected(self):
        ranking = between(SEARCH_REGISTRY, "function getDynamicSearchResults", "function getResultsRanked")
        self.assertIn("const hasRenderableItems", ranking)
        self.assertIn("if (hasRenderableItems)", ranking)
        self.assertNotIn("sectionTitleScore > 0 || searchStringScore > 0", ranking)

    def test_page_local_id_dependencies_are_not_cloned(self):
        extraction = between(SEARCH_REGISTRY, "function extractDeclaredIds", "function indexQmlFile")
        self.assertIn("function usesExternalId", extraction)
        self.assertIn("if (usesExternalId(b.inner, fileScopedIds))", extraction)
        self.assertIn("const fileScopedIds = extractDeclaredIds(qmlText);", SEARCH_REGISTRY)

    def test_multi_word_queries_require_every_token(self):
        scorer = between(SEARCH_REGISTRY, "function getMatchScore", "function getDynamicSearchResults")
        self.assertIn("if (tokenScore === 0)", scorer)
        self.assertIn("return 0;", scorer)
        self.assertIn('section.title + " " + item.text', SEARCH_REGISTRY)

    def test_backup_overview_policy_text_is_not_a_live_search_control(self):
        sections = ai_settings_index.extract_blocks(TASKS, "ContentSection")
        backup = next(
            block for block in sections
            if "Backup overview" in ai_settings_index.property_expression(block["inner"], "title")
        )
        renderable_types = (
            "ConfigSwitch",
            "ConfigSpinBox",
            "ConfigSelectionArray",
            "ConfigTextField",
            "ConfigSlider",
            "ConfigComboBox",
            "ConfigLightDarkToggle",
            "ConfigSubpageRow",
        )
        controls = [
            block
            for component in renderable_types
            for block in ai_settings_index.extract_blocks(backup["inner"], component)
        ]
        self.assertEqual([], controls)

    def test_cloned_subpage_controls_route_to_the_original_page(self):
        self.assertIn("searchResult: true", SEARCH_PAGE)
        self.assertIn("property bool searchResult: false", CONTENT_SECTION)
        self.assertIn("searchSection.navigateToPage(root.configPage.toString())", CONFIG_SWITCH)

    def test_quickshell_urls_are_not_prefixed_as_relative_paths(self):
        resolver = between(WINDOW, "function resolveSubPageEntry", "function restoreSubPagePath")
        self.assertIn("/^[A-Za-z][A-Za-z0-9+.-]*:/.test(raw)", resolver)

    def test_shape_morph_finishes_before_the_next_shape(self):
        shapes = between(SEARCH_BAR, "readonly property var indicatorShapes", "]\n\n        property int currentShapeIndex")
        for cramped in ("Sunny", "VerySunny", "Flower", "SoftBurst"):
            self.assertNotIn(f"MaterialShape.Shape.{cramped}", shapes)
        timer = between(SEARCH_BAR, "id: shapeAnimTimer", "repeat: false")
        self.assertIn("searchIconShape.animation?.duration", timer)


class NavigationContracts(unittest.TestCase):
    def test_mouse_history_supports_back_and_forward(self):
        self.assertIn("property var navigationForwardHistory: []", WINDOW)
        self.assertIn("function navigateBack()", WINDOW)
        self.assertIn("function navigateForward()", WINDOW)
        self.assertIn("Qt.ForwardButton", WINDOW)
        self.assertIn("Qt.ExtraButton2", WINDOW)
        side_buttons = between(WINDOW, "// PointerHandlers do not own a cursor surface", "// Keep observation reactive")
        self.assertEqual(2, side_buttons.count("TapHandler"))
        self.assertEqual(2, side_buttons.count("onPressedChanged"))
        self.assertNotIn("MouseArea", side_buttons)
        self.assertNotIn("Qt.LeftButton", side_buttons)

    def test_new_navigation_invalidates_the_forward_branch(self):
        remember = between(WINDOW, "function rememberObservedState()", "function beginNavigationSession()")
        self.assertIn("root.navigationForwardHistory = [];", remember)

    def test_visual_subpage_back_uses_the_same_history(self):
        request = between(SUBPAGE_HOST, "function requestBack()", "function findNestedNavigationHost")
        self.assertIn("win.navigateBack()", request)
        self.assertIn("item.goBack.connect(host.requestBack)", SUBPAGE_HOST)


class BarPopupNamingContracts(unittest.TestCase):
    def test_bar_popup_categories_are_unambiguous(self):
        bar = (ROOT / "modules" / "settings" / "configs" / "BarConfig.qml").read_text(encoding="utf-8")
        bar_popups = (ROOT / "modules" / "settings" / "configs" / "widgets" / "BarTooltipsConfig.qml").read_text(encoding="utf-8")
        floating = (ROOT / "modules" / "settings" / "configs" / "widgets" / "BarPopupsConfig.qml").read_text(encoding="utf-8")

        self.assertIn('Translation.tr("Bar popups")', bar)
        self.assertIn('Translation.tr("Floating popups")', bar)
        self.assertIn('Translation.tr("Bar popup behavior")', bar_popups)
        self.assertIn('Translation.tr("Click to show bar popups")', bar_popups)
        self.assertIn('Translation.tr("Floating popup services")', floating)
        self.assertIn('Translation.tr("Enable floating popups")', floating)

        combined = "\n".join((bar, bar_popups, floating))
        self.assertNotIn('Translation.tr("Enable tooltips")', combined)
        self.assertNotIn('Translation.tr("Enable popups")', combined)


if __name__ == "__main__":
    unittest.main()
