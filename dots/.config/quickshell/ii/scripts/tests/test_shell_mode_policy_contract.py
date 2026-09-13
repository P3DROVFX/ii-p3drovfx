#!/usr/bin/env python3
"""Regression contract for Default/Connect bar compatibility."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class ShellModePolicyContractTests(unittest.TestCase):
    def test_connect_is_blocked_for_dynamic_island_at_top_or_bottom(self):
        policy = read("modules/common/ShellModePolicy.qml")

        self.assertIn("Config.options.bar.cornerStyle === 3", policy)
        self.assertIn("&& !Config.options.bar.vertical", policy)
        self.assertIn("readonly property bool canSelectConnect: Config.ready\n        && !root.dynamicIslandHorizontal", policy)
        self.assertIn('mode === "connect" && !root.canSelectConnect', policy)
        self.assertNotIn("Config.options.bar.cornerStyle = 0", policy)

    def test_settings_explain_why_connect_is_unavailable(self):
        policy = read("modules/common/ShellModePolicy.qml")
        settings = read("modules/settings/configs/BarConfig.qml")

        self.assertIn("readonly property string connectBlockedReasonKey: root.dynamicIslandHorizontal", policy)
        self.assertIn('"Connect mode is unavailable while Dynamic Island is at the top or bottom."', policy)
        self.assertIn('"enabled": ShellModePolicy.canSelectConnect', settings)
        self.assertIn("visible: ShellModePolicy.connectBlockedReasonKey.length > 0", settings)
        self.assertIn("text: Translation.tr(ShellModePolicy.connectBlockedReasonKey)", settings)
        self.assertNotIn("Bar corner style was automatically set to Hug.", settings)


if __name__ == "__main__":
    unittest.main()
