#!/usr/bin/env python3
"""The assistant reads settings by name, not by the file.

`get_shell_config` returned all of config.json — measured on a real machine at
roughly 46 KB, about thirteen thousand tokens, for one switch. A local model
with an 8k window could not hold it, and it was re-sent with every following
turn. These tests pin the replacement: two tools that read what was asked for,
a deprecated third that explains itself, and writes that are checked against
the key's real type before anything is stored.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
TOOLS_QML = (ROOT / "services" / "ai" / "AiTools.qml").read_text(encoding="utf-8")
# Tool definitions live in the registry since the tool layer was split.
REGISTRY_QML = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
CONFIG_QML = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
CARD_QML = (ROOT / "services" / "ai" / "blocks" / "AiConfigDiffCard.qml").read_text(encoding="utf-8")
GLOBAL_QML = (ROOT / "GlobalStates.qml").read_text(encoding="utf-8")
WINDOW_QML = (ROOT / "SettingsWindow.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


def tool_block(tool_id: str) -> str:
    """The registry entry for one tool."""
    marker = f'id: "{tool_id}",'
    index = REGISTRY_QML.index(marker)
    return REGISTRY_QML[index:REGISTRY_QML.index("\n        },", index)]


class ToolRegistryTests(unittest.TestCase):
    def test_the_keyed_readers_are_offered_to_every_dialect(self):
        for tool_id in ("settings_search", "settings_get"):
            with self.subTest(tool=tool_id):
                block = tool_block(tool_id)
                for dialect in ("gemini", "openai", "anthropic"):
                    self.assertIn(f'"{dialect}"', block)

    def test_the_config_dump_is_offered_to_nobody(self):
        block = tool_block("get_shell_config")
        self.assertIn("formats: []", block)

    def test_the_dump_still_has_a_definition_to_answer_with(self):
        # Registered but not offered: a model that calls it from memory is
        # told what replaced it instead of getting "unknown function call".
        self.assertIn('id: "get_shell_config"', REGISTRY_QML)
        block = tool_block("get_shell_config")
        self.assertIn("settings_search", block)
        self.assertIn("settings_get", block)
        # The registry turns that into the refusal the model reads.
        self.assertIn("Replaced by %1", REGISTRY_QML)

    def test_the_write_tool_points_at_the_finder(self):
        block = tool_block("set_shell_config")
        self.assertIn("settings_propose_changes", block)
        self.assertNotIn("get_shell_config", block)

    def test_reading_settings_is_allowed_without_asking_by_default(self):
        defaults = body_between(CONFIG_QML, "property list<string> alwaysAllow:", "\n")
        self.assertIn("settings_search", defaults)
        self.assertIn("settings_get", defaults)
        self.assertNotIn("get_shell_config", defaults)

    def test_a_standing_permission_survives_the_split(self):
        migration = body_between(AI_QML, "function migrateToolPermissions()", "\n    /**")
        self.assertIn("get_shell_config", migration)
        self.assertIn("settings_search", migration)
        self.assertIn("settings_get", migration)


class DispatchTests(unittest.TestCase):
    def test_nothing_serialises_the_whole_configuration_any_more(self):
        self.assertNotIn("toPlainObject(Config.options)", AI_QML)

    def test_the_finder_answers_from_the_config_helpers(self):
        handler = body_between(AI_QML, "function toolSettingsFind(call: var)", "function toolSettingsGet")
        self.assertIn("Config.findKeys(", handler)
        self.assertIn("Config.listGroup(", handler)

    def test_reads_are_capped(self):
        handler = body_between(AI_QML, "function toolSettingsGet(call: var)", "function toolSetShellConfig")
        self.assertIn(".slice(0, 10)", handler)


class WriteSafetyTests(unittest.TestCase):
    def test_the_assistant_writes_strictly(self):
        apply_now = body_between(AI_QML, "function applyConfigChangesNow", "function rejectConfigChanges")
        self.assertIn("Config.setNestedValue(change.key, change.proposed, true)", apply_now)

    def test_the_preview_says_which_changes_are_impossible(self):
        listing = body_between(AI_QML, "function configChangeList", "function applyConfigChanges")
        self.assertIn("Config.validateNestedValue(", listing)
        self.assertIn("valid:", listing)
        self.assertIn("reason:", listing)

    def test_an_impossible_change_can_never_be_kept(self):
        kept = body_between(CARD_QML, "function keptChanges()", "\n    implicitHeight")
        self.assertIn("valid !== false", kept)

    def test_strict_mode_refuses_instead_of_creating_a_path(self):
        setter = body_between(CONFIG_QML, "function setNestedValue(", "\n    // Persist options immediately")
        strict = setter.split("if (strict) {", 1)[1].split("let obj = root.options;", 1)[0]
        # The loose branch below invents missing objects; the strict one must
        # not reach that code at all.
        self.assertNotIn("= {};", strict)
        self.assertIn("validateNestedValue", strict)
        self.assertIn("throw new Error", strict)

    def test_a_string_option_is_not_turned_into_a_number(self):
        validator = body_between(CONFIG_QML, "function validateNestedValue", "function keyPaths")
        string_branch = validator.split('} else if (kind === "string") {', 1)[1]
        self.assertIn("String(raw)", string_branch)
        self.assertNotIn("Number(", string_branch)

    def test_declared_enums_are_enforced(self):
        validator = body_between(CONFIG_QML, "function validateNestedValue", "function keyPaths")
        self.assertIn("root.enumConstraints[", validator)

    def test_a_group_cannot_be_replaced_by_a_scalar(self):
        validator = body_between(CONFIG_QML, "function validateNestedValue", "function keyPaths")
        self.assertIn('kind === "group"', validator)

    def test_the_loose_path_is_untouched_for_the_settings_window(self):
        # Every switch in the settings window is bound to a key that provably
        # exists, and must keep working exactly as before.
        self.assertIn("function setNestedValue(nestedKey, value, strict = false)", CONFIG_QML)


class DeepLinkTests(unittest.TestCase):
    def test_the_section_is_no_longer_dropped(self):
        opener = body_between(GLOBAL_QML, "function openSettingsPage(pageId, subPageId, sectionId)",
                              "function consumePendingSettingsPage")
        self.assertIn("settingsPendingSection", opener)
        # Both exits of the function have to carry it, not just the one with a
        # page id.
        self.assertGreaterEqual(opener.count("root.settingsPendingSection = targetSection;"), 2)

    def test_the_window_picks_the_section_up(self):
        consumer = body_between(WINDOW_QML, "function consumePendingSettingsPage()", "const directIndex")
        self.assertIn("GlobalStates.settingsPendingSection", consumer)
        self.assertIn("pendingSectionHighlight", consumer)


if __name__ == "__main__":
    unittest.main()
