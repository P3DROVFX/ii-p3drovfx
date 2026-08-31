"""Offline contracts and golden metrics for the Overview Typing Test."""

from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def source(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def breakdown(target: str, entered: str) -> dict[str, int]:
    target_chars = list(target)
    entered_chars = list(entered)
    correct = sum(a == b for a, b in zip(target_chars, entered_chars))
    incorrect = min(len(target_chars), len(entered_chars)) - correct
    return {
        "correct": correct,
        "incorrect": incorrect,
        "extra": max(0, len(entered_chars) - len(target_chars)),
        "missed": max(0, len(target_chars) - len(entered_chars)),
    }


def wpm(characters: int, seconds: float) -> float:
    return characters / 5 / (seconds / 60) if seconds > 0 else 0


class TypingTestContractTests(unittest.TestCase):
    def test_registry_declares_a_hosted_panel_owned_input(self) -> None:
        registry = source("modules/common/SearchPanelRegistry.qml")
        self.assertIn('id: "typingTest"', registry)
        self.assertIn('source: "TypingTestPanel.qml"', registry)
        self.assertIn('queryProperty: "", inputOwner: "panel", hosted: true', registry)

    def test_search_uses_the_generic_input_owner_contract(self) -> None:
        widget = source("modules/ii/overview/SearchWidget.qml")
        bar = source("modules/ii/overview/SearchBar.qml")
        self.assertIn('activePanel?.inputOwner === "panel"', widget)
        self.assertIn("function focusPrimaryInput()", widget)
        self.assertNotIn('activePanelId === "typingTest"', widget)
        self.assertIn("property bool activePanelOwnsInput: false", bar)
        self.assertIn("readOnly: root.activePanelOwnsInput", bar)
        self.assertIn("!root.syncingSearchText && !root.activePanelOwnsInput", bar)

    def test_config_and_settings_expose_the_feature(self) -> None:
        config = source("modules/common/Config.qml")
        modules = source("modules/settings/configs/widgets/LauncherModulesConfig.qml")
        settings = source("modules/settings/configs/AppSearchConfig.qml")
        prefixes = source("modules/settings/configs/widgets/LauncherPrefixesConfig.qml")
        for text in (config, modules, settings, prefixes):
            self.assertIn("typingTest", text)
        self.assertIn('property string typingTest: "^"', config)
        self.assertIn('property bool enable: true', config)

    def test_runtime_is_local_and_input_path_has_no_process(self) -> None:
        runtime = "\n".join(
            source(path)
            for path in (
                "modules/ii/overview/TypingTestPanel.qml",
                "modules/ii/overview/typing/TypingTestEngine.qml",
                "services/TypingLanguages.qml",
            )
        )
        self.assertNotIn("Process {", runtime)
        self.assertNotIn("https://", runtime)
        self.assertNotIn("http://", runtime)
        self.assertIn("TextInput", runtime)
        self.assertIn("onTextEdited", runtime)
        self.assertIn("Date.now()", runtime)

    def test_assets_are_attributed_and_manifest_checksums_match(self) -> None:
        assets = ROOT / "assets" / "typing"
        self.assertTrue((assets / "ATTRIBUTION.md").is_file())
        manifest = json.loads((assets / "languages-manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["source"], "monkeytypegame/monkeytype")
        self.assertEqual(manifest["license"], "GPL-3.0-only")
        self.assertEqual(len(manifest["languages"]), 7)
        for language in manifest["languages"]:
            pack_path = assets / language["file"]
            self.assertTrue(pack_path.is_file(), language["id"])
            encoded = pack_path.read_bytes()
            self.assertEqual(hashlib.sha256(encoded).hexdigest(), language["sha256"])
            pack = json.loads(encoded)
            self.assertIsInstance(pack["words"], list)
            self.assertGreater(len(pack["words"]), 20)
            self.assertTrue(all(isinstance(word, str) and word for word in pack["words"]))

    def test_golden_metrics(self) -> None:
        self.assertEqual(breakdown("hello world", "hello world"), {
            "correct": 11, "incorrect": 0, "extra": 0, "missed": 0,
        })
        self.assertEqual(breakdown("hello world", "hello xorld"), {
            "correct": 10, "incorrect": 1, "extra": 0, "missed": 0,
        })
        self.assertEqual(breakdown("hello", "hellooo"), {
            "correct": 5, "incorrect": 0, "extra": 2, "missed": 0,
        })
        self.assertEqual(breakdown("hello world", "hello wo"), {
            "correct": 8, "incorrect": 0, "extra": 0, "missed": 3,
        })
        self.assertEqual(wpm(50, 60), 10)
        self.assertEqual(wpm(50, 0), 0)

    def test_sync_script_is_development_only_and_pinned(self) -> None:
        script = source("scripts/typing/sync_monkeytype_languages.py")
        self.assertIn("--commit", script)
        self.assertIn("raw.githubusercontent.com/monkeytypegame/monkeytype", script)
        self.assertIn("sha256", script)
        self.assertNotIn("import Quickshell", script)


if __name__ == "__main__":
    unittest.main()
