from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
APPEARANCE_PATH = ROOT / "modules" / "common" / "Appearance.qml"
RULES_LUA_PATH = Path("/home/pedro/.config/hypr/hyprland/rules.lua")


class PopupTransparencyBlurContract(unittest.TestCase):
    def setUp(self):
        self.appearance_text = APPEARANCE_PATH.read_text(encoding="utf-8")
        if RULES_LUA_PATH.exists():
            self.rules_lua_text = RULES_LUA_PATH.read_text(encoding="utf-8")
        else:
            self.rules_lua_text = ""

    def test_appearance_defines_popup_properties(self):
        self.assertIn("readonly property bool popupBlurEnabled:", self.appearance_text)
        self.assertIn("readonly property real popupIgnoreAlpha:", self.appearance_text)

    def test_appearance_defines_push_and_script_functions(self):
        self.assertIn("function getLayerRulesScript(): string", self.appearance_text)
        self.assertIn("function pushHyprlandLayerRules()", self.appearance_text)

    def test_popup_blur_conditional_logic(self):
        self.assertIn("if (root.popupBlurEnabled)", self.appearance_text)
        self.assertIn("blur = false, blur_popups = false", self.appearance_text)

    def test_transparency_connections_exist(self):
        self.assertIn("onPopupBlurEnabledChanged: root.pushHyprlandLayerRules()", self.appearance_text)
        self.assertIn("Connections", self.appearance_text)
        self.assertIn("function onPopupsChanged() { root.pushHyprlandLayerRules(); }", self.appearance_text)
        self.assertIn("function onEnableChanged() { root.pushHyprlandLayerRules(); }", self.appearance_text)

    def test_no_forbidden_borders_introduced(self):
        # Ensure our changes did not introduce border.width into Appearance.qml
        lines = [line for line in self.appearance_text.splitlines() if "getLayerRulesScript" in line or "popupBlur" in line]
        for line in lines:
            self.assertNotIn("border.width", line)

    def test_rules_lua_popup_ignore_alpha_safe_default(self):
        if self.rules_lua_text:
            match = re.search(r'match = \{ namespace = "quickshell:popup" \}, ignore_alpha = ([0-9.]+)', self.rules_lua_text)
            self.assertIsNotNone(match, "quickshell:popup ignore_alpha rule found in rules.lua")
            val = float(match.group(1))
            self.assertGreaterEqual(val, 0.4, "Default ignore_alpha for popups must be >= 0.4 to guard drop shadows")


if __name__ == "__main__":
    unittest.main()
