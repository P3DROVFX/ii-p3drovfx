#!/usr/bin/env python3
"""Regression contracts for the persisted AI model and its usage chart.

These source-level checks cover startup ordering without needing to start a
second Quickshell instance, which would be unsafe in the live desktop session.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
SEARCH_PAGE_QML = (ROOT / "services" / "ai" / "AiSearchPage.qml").read_text(encoding="utf-8")
SEARCH_PANEL_QML = (ROOT / "modules" / "ii" / "overview" / "AiChatPanel.qml").read_text(encoding="utf-8")
SIDEBAR_CONTROLS_QML = (
    ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "ChatControlBar.qml"
).read_text(encoding="utf-8")
USAGE_DASHBOARD_QML = (
    ROOT / "modules" / "settings" / "configs" / "ai" / "AiUsageDashboard.qml"
).read_text(encoding="utf-8")
COLUMN_CHART_QML = (
    ROOT / "modules" / "ii" / "usage" / "UsageColumnChart.qml"
).read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class AiModelPersistenceUiContractTests(unittest.TestCase):
    def test_boot_restores_model_only_after_persistent_state_is_ready(self):
        restore = body_between(
            AI_QML,
            "function restorePersistentDefaults()",
            "function resetSessionSettings()",
        )
        self.assertIn("if (!Persistent.ready", restore)
        self.assertIn("root.migrateAiDefaults()", restore)
        self.assertIn("root.resetSessionSettings()", restore)
        self.assertIn("target: Persistent", AI_QML)
        self.assertIn("root.restorePersistentDefaults()", AI_QML)

        startup = body_between(AI_QML, "Component.onCompleted:", "// Boot-time index")
        self.assertNotIn("root.resetSessionSettings()", startup)
        self.assertNotIn("setModel(currentModelId", startup)

    def test_model_picks_remain_persistent_across_surfaces(self):
        set_model = body_between(AI_QML, "function setModel(", "/** Ids of models picked")
        self.assertIn("root.persistDefaultModel(model.id)", set_model)
        for surface in (SEARCH_PAGE_QML, SEARCH_PANEL_QML, SIDEBAR_CONTROLS_QML):
            self.assertIn("Ai.setModel(modelId, false)", surface.replace("modelRow.modelData.id", "modelId"))

    def test_loading_an_old_session_does_not_replace_the_saved_default(self):
        apply_session = body_between(AI_QML, "function applySession(", "function migrateAiDefaults()")
        self.assertIn("root.sessionModelId = session.modelId ?? root.defaultModelId", apply_session)
        self.assertNotIn("Persistent.states.ai.defaultModelId", apply_session)

    def test_usage_dashboard_requests_substantially_wider_columns(self):
        self.assertIn("property real barSpacing:", COLUMN_CHART_QML)
        self.assertIn("spacing: root.barSpacing", COLUMN_CHART_QML)
        self.assertIn("barWidth: Appearance.rounding.large", USAGE_DASHBOARD_QML)
        self.assertIn("minimumBarWidth: grid.periodMode === \"today\"", USAGE_DASHBOARD_QML)
        self.assertIn("barSpacing: Appearance.rounding.verysmall / 2", USAGE_DASHBOARD_QML)


if __name__ == "__main__":
    unittest.main()
