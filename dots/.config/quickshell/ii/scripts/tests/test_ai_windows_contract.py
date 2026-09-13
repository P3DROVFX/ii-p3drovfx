#!/usr/bin/env python3
"""Contract tests for window/workspace actions backed by HyprlandData."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REGISTRY = (ROOT / "services/ai/AiToolRegistry.qml").read_text(encoding="utf-8")
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
ADAPTER = (ROOT / "services/ai/integrations/AiWindowsIntegration.qml").read_text(encoding="utf-8") if (ROOT / "services/ai/integrations/AiWindowsIntegration.qml").exists() else ""


class AiWindowsContractTests(unittest.TestCase):
    def test_registry_exposes_read_focus_move_and_switch(self):
        for tool_id in ("windows_list", "window_focus", "window_move_to_workspace", "workspace_switch"):
            self.assertIn(f'id: "{tool_id}"', REGISTRY)
        self.assertIn("address must come from windows_list", REGISTRY)

    def test_adapter_resolves_addresses_from_live_list(self):
        self.assertIn("HyprlandData.windowList", ADAPTER)
        self.assertIn("windowByAddress", ADAPTER)
        self.assertIn("function list", ADAPTER)
        self.assertIn("function previewMove", ADAPTER)
        self.assertIn("function focus", ADAPTER)
        self.assertIn("function move", ADAPTER)
        self.assertNotIn("hyprctl", ADAPTER)

    def test_ai_journal_and_card_cover_move_approval(self):
        self.assertIn("toolWindowsList", AI)
        self.assertIn("toolWindowMove", AI)
        self.assertIn("approveWindowMove", AI)
        self.assertIn("rejectWindowMove", AI)
        self.assertIn('"window_move_to_workspace": pending', AI)


if __name__ == "__main__":
    unittest.main()
