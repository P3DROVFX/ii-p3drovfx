#!/usr/bin/env python3
"""Contract and regression tests for DevTools / Tools Panel in Quickshell."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class DevToolsContractTests(unittest.TestCase):
    def test_devtools_registry_is_a_singleton_with_all_tier_1_tools(self):
        registry = source("modules/common/DevToolsRegistry.qml")
        self.assertIn("pragma Singleton", registry)
        
        expected_tools = (
            "uuid", "password", "lorem",
            "base64", "url_encode", "html_entities", "jwt_decoder",
            "number_base", "unix_timestamp", "color_converter",
            "json_formatter",
            "case_converter", "escape_string", "text_inspector",
            "line_tools", "whitespace_tools", "regex_tester",
            "slugify", "text_diff"
        )
        for tool_id in expected_tools:
            self.assertIn(f'id: "{tool_id}"', registry, f"Missing tool {tool_id} in DevToolsRegistry")

    def test_devtools_registry_has_categorization_and_options(self):
        registry = source("modules/common/DevToolsRegistry.qml")
        for cat in ("generators", "encoders", "converters", "formatters", "text"):
            self.assertIn(f'id: "{cat}"', registry)
        self.assertIn("function byId", registry)
        self.assertIn("function run", registry)
        self.assertIn("function search", registry)
        self.assertIn("function inlineMatches", registry)

    def test_tools_panel_matches_design_and_action_contracts(self):
        panel = source("modules/ii/overview/ToolsPanel.qml")
        self.assertIn("SearchPanelScaffold", panel)
        self.assertIn("supportsSectionToggle: true", panel)
        self.assertIn("DevToolsRegistry.search", panel)
        self.assertIn("function execute", panel)
        self.assertIn("function copyOutput", panel)
        self.assertIn("function pasteFromClipboard", panel)
        self.assertIn("function setOption", panel)
        self.assertIn("ConfiguredKeyHint", panel)
        self.assertNotIn("border.", panel)

    def test_search_panel_registry_declares_tools(self):
        registry = source("modules/common/SearchPanelRegistry.qml")
        self.assertIn('id: "tools"', registry)
        self.assertIn('source: "ToolsPanel.qml"', registry)
        self.assertIn('searchIcon: "wand_stars"', registry)
        self.assertIn('searchShape: "Burst"', registry)

    def test_launcher_search_integrates_tools(self):
        launcher = source("services/LauncherSearch.qml")
        self.assertIn("function toolEntries", launcher)
        self.assertIn("function createToolResult", launcher)
        self.assertIn("DevToolsRegistry.inlineMatches", launcher)


if __name__ == "__main__":
    unittest.main()
