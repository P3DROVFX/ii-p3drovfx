"""Contracts for Ctrl+letter result keybinds in plain Search (2026-09).

A result gets a keybind from More actions → Add keybind; the row turns into a
recorder (Ctrl fixed, one letter, Clear/Done, Enter saves, Esc cancels). The
shortcut then runs from the plain Search field only. These tests pin the parts
that fail quietly: reserved letters, the plain-Search gate, declared storage,
and the capture row owning its keys.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class ResultKeybindContracts(unittest.TestCase):
    def setUp(self):
        self.launcher = source("services/LauncherSearch.qml")
        self.item = source("modules/ii/overview/SearchItem.qml")
        self.bar = source("modules/ii/overview/SearchBar.qml")

    def test_storage_and_toggle_are_declared(self):
        # Writes to undeclared Persistent/Config keys vanish without an error.
        self.assertIn("property list<var> resultKeybinds: []", source("modules/common/Persistent.qml"))
        self.assertIn("property JsonObject resultKeybinds: JsonObject {", source("modules/common/Config.qml"))
        self.assertIn("Persistent.states.search.resultKeybinds = kept", self.launcher)
        aliases = source("modules/settings/configs/widgets/LauncherAliasesConfig.qml")
        self.assertIn("Config.options.search.resultKeybinds.enable = checked", aliases)
        self.assertIn("LauncherSearch.removeResultKeybind(keybindDelegate.modelData.letter)", aliases)

    def test_reserved_letters_include_ctrl_k_and_text_editing(self):
        self.assertIn('const reserved = ["a", "c", "k", "p", "v", "x", "z"];', self.launcher)
        # Both the store and the recorder refuse them.
        self.assertIn("root.reservedKeybindLetters().indexOf(wanted) !== -1", self.launcher)
        self.assertIn("LauncherSearch.reservedKeybindLetters().indexOf(letter) !== -1", self.item)

    def test_keybinds_run_from_plain_search_only(self):
        start = self.bar.index("// Ctrl+letter keybinds the user bound to results.")
        block = self.bar[start:start + 700]
        self.assertIn("!root.activePanelMode && !root.aiModeActive && event.modifiers === Qt.ControlModifier", block)
        self.assertIn("LauncherSearch.runResultKeybind(", block)
        # Ctrl+K and Ctrl+P are matched before any user keybind.
        self.assertLess(self.bar.index('matchesShortcut(event, "actions", "Ctrl+K")'), start)
        self.assertLess(self.bar.index('matchesShortcut(event, "favorite", "Ctrl+P")'), start)

    def test_more_actions_offers_add_change_and_remove(self):
        actions = source("modules/common/SearchResultActions.qml")
        self.assertIn('existing ? Translation.tr("Change keybind") : Translation.tr("Add keybind")', actions)
        self.assertIn('Translation.tr("Remove Ctrl+%1")', actions)
        # Only a surface that can show the recorder offers it.
        self.assertIn('typeof captureKeybind === "function"', actions)
        self.assertIn("onCaptureKeybind: () => root.openKeybindCapture()", self.item)

    def test_capture_row_locks_one_letter_and_owns_its_keys(self):
        start = self.item.index("// While recording a keybind, every key belongs to the recorder.")
        block = self.item[start:start + 1400]
        self.assertIn("root.closeKeybindCapture();", block)
        self.assertIn("root.saveKeybindCapture();", block)
        # The first letter fills the slot; later letters wait for Clear.
        self.assertIn("event.key >= Qt.Key_A && event.key <= Qt.Key_Z && root.capturedLetter.length === 0", block)
        self.assertIn('text: Translation.tr("Clear")', self.item)
        self.assertIn('text: Translation.tr("Done")', self.item)
        widget = source("modules/ii/overview/SearchWidget.qml")
        self.assertIn("if (searchItem.keybindCaptureOpen || searchItem.aliasCaptureOpen)\n                                        return;", widget)
        self.assertIn("onKeybindCaptureFinished: root.focusSearchInput()", widget)
        self.assertEqual(self.item.count("onIsSelectedChanged"), 1)

    def test_bindings_resolve_without_the_original_row(self):
        for prefix in ('key.startsWith("app:")', 'key.startsWith("panel:")', 'key.startsWith("quicklink:")'):
            self.assertIn(prefix, self.launcher)
        self.assertIn("root._computeResults().find(result => root.keybindableKey(result) === key)", self.launcher)
        self.assertIn("SearchResultActions.build(result, {})[0].execute();", self.launcher)
        # Values that change per query are never bindable.
        self.assertIn("/^(math:|fallback:|clip:|cmd:shell|web:search|ai:ask)/", self.launcher)


if __name__ == "__main__":
    unittest.main()
