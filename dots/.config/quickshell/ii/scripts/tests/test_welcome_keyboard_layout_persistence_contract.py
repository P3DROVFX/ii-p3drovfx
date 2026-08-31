#!/usr/bin/env python3
"""Regression contract for Welcome's persistent XKB layout destination."""

import unittest
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
WELCOME = (ROOT / "modules" / "welcome" / "WelcomeKeyboardLayoutPage.qml").read_text(encoding="utf-8")
FLOW = (ROOT / "modules" / "welcome" / "WelcomeFlow.qml").read_text(encoding="utf-8")
WINDOW = (ROOT / "modules" / "welcome" / "WelcomeWindow.qml").read_text(encoding="utf-8")
HYPRLAND_CONFIG = (ROOT / "services" / "HyprlandConfig.qml").read_text(encoding="utf-8")
PERSISTENCE_SCRIPT = ROOT / "scripts" / "hyprland" / "persist_welcome_keyboard_layout.py"


class WelcomeKeyboardLayoutPersistenceContracts(unittest.TestCase):
    def test_welcome_persists_xkb_in_custom_input_not_shell_overrides(self):
        self.assertIn("HyprlandConfig.persistWelcomeKeyboardLayout(layoutValue, variantValue)", WELCOME)
        self.assertNotIn("HyprlandConfig.setMany({", WELCOME)
        self.assertNotIn("HyprlandConfig.resetMany", WELCOME)
        self.assertNotIn('Quickshell.execDetached(["hyprctl", "keyword"', WELCOME)
        self.assertIn("property bool persistencePending: false", WELCOME)
        self.assertIn("readonly property bool navigationLocked: root.persistencePending", WELCOME)
        self.assertIn("signal advanceRequested()", WELCOME)
        self.assertIn("if (success)\n                root.advanceRequested();", WELCOME)
        self.assertIn("function onAdvanceRequested()", FLOW)
        self.assertIn("function currentPageLocksNavigation(): bool", FLOW)
        self.assertIn("onCloseRequested: root.closeWhenNavigationUnlocked()", WINDOW)
        self.assertIn("function closeWhenNavigationUnlocked(): void", WINDOW)
        self.assertIn("if (!flow.currentPageLocksNavigation())", WINDOW)

    def test_service_uses_a_dedicated_serialized_keyboard_persistence_operation(self):
        self.assertIn("customInputPath", HYPRLAND_CONFIG)
        self.assertIn("/hypr/custom/input.lua", HYPRLAND_CONFIG)
        self.assertIn("persist_welcome_keyboard_layout.py", HYPRLAND_CONFIG)
        self.assertIn("function persistWelcomeKeyboardLayout(layout: string, variant: string)", HYPRLAND_CONFIG)
        self.assertIn("welcomeKeyboardLayoutPersisted", HYPRLAND_CONFIG)
        self.assertIn("property var configWriteQueue: []", HYPRLAND_CONFIG)
        self.assertIn("function _queueShellOverridesCommand(command: string)", HYPRLAND_CONFIG)
        self.assertIn("function _startNextConfigWrite()", HYPRLAND_CONFIG)

    def test_persistence_keeps_hand_written_input_and_cleans_only_exact_legacy_lines(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            custom_input = Path(temporary_directory) / "custom" / "input.lua"
            shell_overrides = Path(temporary_directory) / "hyprland" / "shellOverrides" / "main.lua"
            custom_input.parent.mkdir(parents=True)
            shell_overrides.parent.mkdir(parents=True)
            custom_input.write_text(
                "-- Hand-written input preferences remain intact.\n"
                "hl.config({\n"
                "  input = {\n"
                "    kb_layout = \"us, br\",\n"
                "    kb_options = \"grp:alt_shift_toggle\",\n"
                "    sensitivity = -0.1,\n"
                "  }\n"
                "})\n"
                "hl.config({input={kb_layout=\"manual\",kb_options=\"caps:escape\"}})\n",
                encoding="utf-8",
            )
            original_custom_input = custom_input.read_text(encoding="utf-8")
            shell_overrides.write_text(
                'hl.config({input={kb_layout="us,br"}})\n'
                'hl.config({input={kb_variant="intl,"}})\n'
                'hl.config({input={kb_options="grp:win_space_toggle"}})\n'
                'hl.config({animations={enabled=false}})\n',
                encoding="utf-8",
            )

            subprocess.run(
                [
                    "python3",
                    str(PERSISTENCE_SCRIPT),
                    "--custom-input",
                    str(custom_input),
                    "--shell-overrides",
                    str(shell_overrides),
                    "--layout",
                    "br",
                    "--variant",
                    "abnt2",
                ],
                check=True,
            )
            subprocess.run(
                [
                    "python3",
                    str(PERSISTENCE_SCRIPT),
                    "--custom-input",
                    str(custom_input),
                    "--shell-overrides",
                    str(shell_overrides),
                    "--layout",
                    "us",
                    "--variant",
                    "intl",
                ],
                check=True,
            )

            persisted = custom_input.read_text(encoding="utf-8")
            overrides = shell_overrides.read_text(encoding="utf-8")
            self.assertIn(original_custom_input, persisted)
            self.assertEqual(persisted.count("-- quickshell:welcome-keyboard:start"), 1)
            self.assertEqual(persisted.count("-- quickshell:welcome-keyboard:end"), 1)
            self.assertIn('kb_layout = "us"', persisted)
            self.assertIn('kb_variant = "intl"', persisted)
            self.assertNotIn('kb_layout = "br"', persisted)
            self.assertNotIn('kb_variant = "abnt2"', persisted)
            self.assertNotIn('hl.config({input={kb_layout="us,br"}})', overrides)
            self.assertNotIn('hl.config({input={kb_variant="intl,"}})', overrides)
            self.assertIn('hl.config({input={kb_options="grp:win_space_toggle"}})', overrides)
            self.assertIn('hl.config({animations={enabled=false}})', overrides)

    def test_invalid_xkb_input_leaves_files_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            custom_input = Path(temporary_directory) / "input.lua"
            shell_overrides = Path(temporary_directory) / "main.lua"
            custom_input.write_text("-- custom\n", encoding="utf-8")
            shell_overrides.write_text('hl.config({input={kb_layout="us"}})\n', encoding="utf-8")

            result = subprocess.run(
                [
                    "python3",
                    str(PERSISTENCE_SCRIPT),
                    "--custom-input",
                    str(custom_input),
                    "--shell-overrides",
                    str(shell_overrides),
                    "--layout",
                    "us;rm",
                    "--variant",
                    "intl",
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(custom_input.read_text(encoding="utf-8"), "-- custom\n")
            self.assertEqual(shell_overrides.read_text(encoding="utf-8"), 'hl.config({input={kb_layout="us"}})\n')


if __name__ == "__main__":
    unittest.main()
