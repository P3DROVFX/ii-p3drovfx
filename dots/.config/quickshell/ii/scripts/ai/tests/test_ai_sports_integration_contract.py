#!/usr/bin/env python3
"""Contracts for the UI-independent ESPN AI adapter."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ADAPTER = (ROOT / "services" / "ai" / "integrations" / "AiSportsIntegration.qml").read_text(encoding="utf-8")
SERVICE = (ROOT / "services" / "SportsService.qml").read_text(encoding="utf-8")
REGISTRY = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
AI = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")


class AiSportsIntegrationTests(unittest.TestCase):
    def test_registry_exposes_search_and_force_refresh_as_read_only_tools(self):
        for tool_id in ("sports_search_games", "sports_refresh_games"):
            with self.subTest(tool=tool_id):
                self.assertIn(f'id: "{tool_id}"', REGISTRY)
                block = REGISTRY.split(f'id: "{tool_id}"', 1)[1].split('\n        },', 1)[0]
                self.assertIn('kind: "externalRead"', block)
                self.assertIn('network: "required"', block)
                self.assertIn('requiredServices: ["sports"]', block)
                self.assertIn('league:', block)

    def test_adapter_is_parameterized_and_independent_of_widget_config(self):
        self.assertIn("XMLHttpRequest", ADAPTER)
        self.assertIn("cacheTtlMs", ADAPTER)
        self.assertIn("site.web.api.espn.com", ADAPTER)
        self.assertIn("hostIndex", ADAPTER)
        self.assertIn("fetchedAt", ADAPTER)
        self.assertIn("venue", ADAPTER)
        self.assertIn("broadcast", ADAPTER)
        self.assertIn("const eventStatus = item.status", ADAPTER)
        self.assertIn("competitors", ADAPTER)
        self.assertIn("statusValues", ADAPTER)
        self.assertIn("localIsoDate", ADAPTER)
        self.assertNotIn("Config.options", ADAPTER)
        self.assertNotIn("monitoredLeagues", ADAPTER)

    def test_ai_subscriber_lifecycle_has_no_config_write(self):
        self.assertIn("property int aiSubscribers", SERVICE)
        self.assertIn("function acquireAiSubscriber()", SERVICE)
        self.assertIn("function releaseAiSubscriber()", SERVICE)
        lifecycle = SERVICE.split("function acquireAiSubscriber()", 1)[1].split("function formatMatchTime", 1)[0]
        self.assertNotIn("Config.options", lifecycle)
        self.assertIn("SportsService.acquireAiSubscriber", ADAPTER)
        self.assertIn("SportsService.releaseAiSubscriber", ADAPTER)

    def test_dispatch_and_late_callback_are_correlated(self):
        self.assertIn('"sports_search_games": call => root.toolSports(call, false)', AI)
        self.assertIn('"sports_refresh_games": call => root.toolSports(call, true)', AI)
        self.assertIn("root.broker.isPending(String(key))", AI)
        self.assertIn("String(sessionId) !== activeSession", AI)


if __name__ == "__main__":
    unittest.main()
