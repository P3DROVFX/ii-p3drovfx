#!/usr/bin/env python3
"""The semantic Settings tools must stay keyed, validated and reviewable."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
REGISTRY = (ROOT / "services/ai/AiToolRegistry.qml").read_text(encoding="utf-8")
INTEGRATION_PATH = ROOT / "services/ai/integrations/AiSettingsIntegration.qml"
RESULT_CARD = ROOT / "services/ai/blocks/AiSettingResultCard.qml"
LAUNCHER = (ROOT / "services/LauncherSearch.qml").read_text(encoding="utf-8")
SEARCH_WIDGET = (ROOT / "modules/ii/overview/SearchWidget.qml").read_text(encoding="utf-8")


class SemanticSettingsToolsTests(unittest.TestCase):
    def test_settings_adapter_owns_index_read_validation_and_strict_apply(self):
        self.assertTrue(INTEGRATION_PATH.exists())
        source = INTEGRATION_PATH.read_text(encoding="utf-8")
        for token in (
            "settings_index.json",
            "ai_settings_index.py",
            "function search(",
            "function get(",
            "function validate(",
            "function propose(",
            "Config.setNestedValue(key, value, true)",
            "readonly property FileView indexFile: FileView",
            "readonly property Process indexCheck: Process",
            "readonly property Process indexBuild: Process",
        ):
            with self.subTest(token=token):
                self.assertIn(token, source)
        self.assertNotIn(".at(", source)

    def test_registry_exposes_only_the_semantic_settings_schema(self):
        for tool in (
            'id: "settings_search"',
            'id: "settings_get"',
            'id: "settings_open"',
            'id: "settings_propose_changes"',
            'id: "settings_apply_changes"',
        ):
            with self.subTest(tool=tool):
                self.assertIn(tool, REGISTRY)
        self.assertIn('id: "settings_find"', REGISTRY)  # compatibility alias
        self.assertIn('formats: []', REGISTRY.split('id: "settings_find"', 1)[1].split('id:', 1)[0])
        self.assertIn('id: "set_shell_config"', REGISTRY)  # compatibility alias
        self.assertIn('formats: []', REGISTRY.split('id: "set_shell_config"', 1)[1].split('id:', 1)[0])

    def test_ai_routes_semantic_tools_through_the_adapter_and_journal(self):
        self.assertIn("import qs.services.ai.integrations", AI)
        for token in (
            "readonly property AiSettingsIntegration settingsIntegration",
            '"settings_search": call => root.toolSettingsSearch(call)',
            '"settings_open": call => root.toolSettingsOpen(call)',
            '"settings_propose_changes": call => root.toolSettingsProposeChanges(call)',
            '"settings_apply_changes": call => root.toolSettingsApplyChanges(call)',
            '"settings_apply_changes": pending => root.applySettingsChangesNow',
        ):
            with self.subTest(token=token):
                self.assertIn(token, AI)

    def test_settings_search_surfaces_a_strictly_validated_direct_control(self):
        self.assertTrue(RESULT_CARD.exists())
        source = RESULT_CARD.read_text(encoding="utf-8")
        for token in (
            "Ai.settingsIntegration.validate(root.key, value)",
            "Config.setNestedValue(root.key, value, true)",
            "Ai.toolSettingsOpen({",
            "StyledSwitch",
            "StyledSpinBox",
            "StyledSlider",
            "ConfigSelectionArray",
            "MaterialTextField",
        ):
            with self.subTest(token=token):
                self.assertIn(token, source)
        self.assertIn('kind: "settingsResults"', AI)

    def test_setting_result_card_can_open_its_settings_deep_link(self):
        source = RESULT_CARD.read_text(encoding="utf-8")
        self.assertIn("import qs\n", source)
        self.assertIn("Ai.toolSettingsOpen({", source)

    def test_overview_launcher_reuses_the_generated_settings_index_and_card(self):
        for token in (
            "Ai.settingsIntegration.ready",
            "function settingsIntegrationSearch(",
            "Ai.settingsIntegration.search(root.query, 100)",
            "maxInlineResults",
            "function createSettingsResultObject(",
            "settingRef: setting",
        ):
            with self.subTest(token=token):
                self.assertIn(token, LAUNCHER)
        self.assertIn("import qs.services.ai.blocks", SEARCH_WIDGET)
        self.assertIn("AiSettingResultCard", SEARCH_WIDGET)


if __name__ == "__main__":
    unittest.main()
