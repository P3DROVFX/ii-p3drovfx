#!/usr/bin/env python3
"""Contract tests for cross-surface AI attention and privacy routing."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SERVICE = (ROOT / "services/AiAttentionService.qml").read_text(encoding="utf-8")
STATUS = (ROOT / "services/AiStatusService.qml").read_text(encoding="utf-8")
WIDGET = (ROOT / "modules/ii/dynamicIsland/widgets/FloatingNotchAiStatus.qml").read_text(encoding="utf-8")
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")


class AiAttentionContractTests(unittest.TestCase):
    def test_service_prioritizes_action_and_builds_exact_deep_links(self):
        for token in ("hasPendingApproval", "needsAction", "priority", "runId", "sessionId", "messageId", "Ai.surfaceRouter.open"):
            self.assertIn(token, SERVICE)

    def test_island_reads_attention_and_can_open_sidebar(self):
        self.assertIn("AiAttentionService", STATUS)
        self.assertIn("needsAction", STATUS)
        self.assertIn("AiAttentionService.open", WIDGET)

    def test_notifications_respect_dnd_and_privacy(self):
        self.assertIn("AiAttentionService.notificationAllowed", AI)
        self.assertIn("Notifications.effectiveSilent", SERVICE)
        self.assertIn("notificationPrivacy", SERVICE)
        self.assertIn("GlobalStates.screenLocked", AI)


if __name__ == "__main__":
    unittest.main()
