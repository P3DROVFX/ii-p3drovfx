#!/usr/bin/env python3
"""Contract tests for local reversible system controls."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REGISTRY = (ROOT / "services/ai/AiToolRegistry.qml").read_text(encoding="utf-8")
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
ADAPTER = (ROOT / "services/ai/integrations/AiSystemControlsIntegration.qml").read_text(encoding="utf-8") if (ROOT / "services/ai/integrations/AiSystemControlsIntegration.qml").exists() else ""


class AiSystemControlsContractTests(unittest.TestCase):
    def test_registry_contains_explicit_value_controls(self):
        for tool_id in ("audio_set", "brightness_set", "dnd_set", "nightlight_set", "theme_set_mode"):
            self.assertIn(f'id: "{tool_id}"', REGISTRY)
        self.assertGreaterEqual(REGISTRY.count('defaultApproval: "ask"'), 5)

    def test_adapter_uses_existing_singletons_and_captures_undo(self):
        for service in ("Audio", "Brightness", "Notifications", "Hyprsunset", "DarkModeService"):
            self.assertIn(service, ADAPTER)
        self.assertIn("function preview", ADAPTER)
        self.assertIn("function apply", ADAPTER)
        self.assertIn("undo", ADAPTER)
        self.assertNotIn("hyprctl", ADAPTER)
        self.assertNotIn("execDetached", ADAPTER)

    def test_ai_has_reviewed_control_flow(self):
        for name in ("toolSystemControl", "approveSystemControl", "rejectSystemControl", "applySystemControl"):
            self.assertIn(name, AI)
        self.assertIn('kind: "systemControlPreview"', AI)
        self.assertIn('"audio_set": pending', AI)
        self.assertIn('"theme_set_mode": pending', AI)


if __name__ == "__main__":
    unittest.main()
