"""Contracts for the Dev tools cheatsheet page and the tools added with it (2026-09).

The page is a larger host for the same DevToolsRegistry the Search Tools panel
uses, so a tool exists once. These tests pin what fails quietly when it drifts:
the default, the tab mapping, shortcuts that would steal the cheatsheet's own,
and state that would be written into undeclared Persistent keys.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class CheatsheetDevToolsContracts(unittest.TestCase):
    def setUp(self):
        self.page = source("modules/ii/cheatsheet/CheatsheetDevTools.qml")
        self.cheatsheet = source("modules/ii/cheatsheet/Cheatsheet.qml")
        self.registry = source("modules/common/DevToolsRegistry.qml")
        self.engine = source("modules/common/functions/devtools.js")

    def test_page_is_opt_in_and_reachable_everywhere(self):
        self.assertIn("property bool enableDevTools: false", source("modules/common/Config.qml"))
        self.assertIn("if (Config.options.cheatsheet.enableDevTools)", self.cheatsheet)
        # Pages are chosen by tab icon, so the icon must stay unique.
        self.assertIn('case "handyman":\n                                            return "CheatsheetDevTools.qml";', self.cheatsheet)
        self.assertEqual(self.cheatsheet.count('"icon": "handyman"'), 1)
        self.assertIn("Config.options.cheatsheet.enableDevTools = checked", source("modules/settings/configs/CheatSheetConfig.qml"))
        self.assertIn('"devTools": devToolsAppContent', source("panelFamilies/TabletFamily.qml"))
        self.assertIn('enabled: () => Config.options?.cheatsheet?.enableDevTools ?? false', source("modules/tablet/appWindow/TabletSystemApps.qml"))
        self.assertIn('"CheatsheetDevTools.qml"', source("scripts/tests/run_cheatsheet_tabs_smoke.py"))

    def test_page_shares_the_search_registry_instead_of_copying_tools(self):
        self.assertIn("DevToolsRegistry.search(root.filterText, root.selectedCategory)", self.page)
        self.assertIn("DevToolsRegistry.run(tool.id, input, root.activeOptions)", self.page)
        # The engine is reached through the registry, never imported a second time.
        self.assertNotIn('import "', self.page)

    def test_button_components_do_not_redeclare_final_properties(self):
        """`icon` and `text` are FINAL on Button; redeclaring one blanks the page."""
        for name in ("ChipButton", "ActionButton", "ToolRow"):
            start = self.page.index(f"component {name}: RippleButton {{")
            body = self.page[start:self.page.index("\n    }\n", start)]
            self.assertNotIn("property string icon", body, name)
            self.assertNotIn("property string text", body, name)

    def test_page_is_responsive(self):
        self.assertIn("readonly property bool railVisible: root.width >= 1100", self.page)
        self.assertIn("readonly property bool editorsSideBySide: root.width >= 1380", self.page)
        self.assertIn("readonly property bool compact: root.width < 720", self.page)
        # Many choices become a menu instead of a row wider than the page.
        self.assertIn("(root.compact || (modelData.choices ?? []).length > 5)", self.page)
        self.assertIn("KeyHintBar {\n                Layout.fillWidth: true", self.page)
        self.assertNotIn("border.", self.page)

    def test_shortcuts_follow_the_active_tab_and_leave_ctrl_digits_alone(self):
        shortcuts = [line for line in self.page.splitlines() if line.strip().startswith("Shortcut {")]
        self.assertGreater(len(shortcuts), 0)
        for line in shortcuts:
            self.assertIn("enabled: root.isTabActive", line)
            # Ctrl+1..9 switch cheatsheet tabs.
            for digit in "123456789":
                self.assertNotIn(f'"Ctrl+{digit}"', line)

    def test_remembered_selection_uses_declared_persistent_keys(self):
        persistent = source("modules/common/Persistent.qml")
        self.assertIn('property string devToolsToolId: ""', persistent)
        self.assertIn('property string devToolsCategory: "all"', persistent)
        self.assertIn("Persistent.states.cheatsheet.devToolsToolId = tool.id", self.page)
        self.assertIn("Persistent.states.cheatsheet.devToolsCategory = root.selectedCategory", self.page)

    def test_new_tools_are_registered_and_dispatched(self):
        for tool_id in ("id_generator", "hash_generator", "hex_text", "json_csv", "byte_size",
                        "url_parser", "http_status", "cron_explainer", "chmod_calculator"):
            self.assertIn(f'id: "{tool_id}"', self.registry)
            self.assertIn(f'case "{tool_id}":', self.engine)
        self.assertIn('{ id: "web", label: Translation.tr("Web & system"), icon: "public" }', self.registry)
        self.assertIn('{ value: "7", label: Translation.tr("v7 · time-ordered") }', self.registry)

    def test_search_tools_panel_can_edit_text_options(self):
        panel = source("modules/ii/overview/ToolsPanel.qml")
        self.assertIn('visible: optionGroupItem.currentOptionDef.type === "text"', panel)
        self.assertIn("onTextEdited: root.setOption(optionGroupItem.currentOptionDef.id, text)", panel)


if __name__ == "__main__":
    unittest.main()
