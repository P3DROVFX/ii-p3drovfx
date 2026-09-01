#!/usr/bin/env python3
"""Contract tests for the optional token-speed metric in the chat toolbar."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CONFIG = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
ADVANCED = (ROOT / "modules" / "settings" / "configs" / "ai" / "AdvancedAiConfig.qml").read_text(encoding="utf-8")
AI = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
TOOLBAR = (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "ChatControlBar.qml").read_text(encoding="utf-8")
OPENAI_STRATEGY = (ROOT / "services" / "ai" / "OpenAiCompatStrategy.qml").read_text(encoding="utf-8")
MESSAGE = (ROOT / "services" / "ai" / "AiMessageData.qml").read_text(encoding="utf-8")


class TokenToolbarMetricTests(unittest.TestCase):
    def test_config_defaults_to_accumulated_usage(self):
        self.assertIn("property bool showTokensPerSecond: false", CONFIG)
        self.assertIn("property bool showOpenRouterSessionCost: false", CONFIG)

    def test_advanced_config_exposes_the_persistent_toggle(self):
        self.assertIn('text: Translation.tr("Show tokens per second in the chat toolbar")', ADVANCED)
        self.assertIn("checked: Config.options.ai.showTokensPerSecond", ADVANCED)
        self.assertIn("Config.options.ai.showTokensPerSecond = checked;", ADVANCED)
        self.assertIn('text: Translation.tr("Show OpenRouter session cost in the chat toolbar")', ADVANCED)
        self.assertIn("checked: Config.options.ai.showOpenRouterSessionCost", ADVANCED)
        self.assertIn("Config.options.ai.showOpenRouterSessionCost = checked;", ADVANCED)

    def test_speed_uses_latest_completed_user_visible_answer(self):
        self.assertIn("readonly property real lastAnswerTokensPerSecond", AI)
        self.assertIn("message.outputTokens", AI)
        self.assertIn("message.completedAt", AI)
        self.assertIn("message.createdAt", AI)
        self.assertIn("function formatTokensPerSecond", AI)

    def test_toolbar_switches_between_usage_and_speed(self):
        self.assertIn("readonly property bool perSecond: Config.options.ai.showTokensPerSecond", TOOLBAR)
        self.assertIn("Ai.formatTokensPerSecond(tokenIndicator.rate)", TOOLBAR)
        self.assertIn("Ai.shortTokenCount(tokenIndicator.total)", TOOLBAR)
        self.assertIn('text: tokenIndicator.costMode ? "payments"', TOOLBAR)

    def test_openrouter_cost_is_reported_persisted_and_summed_per_session(self):
        self.assertIn("const cost = knownCost(usage.cost);", OPENAI_STRATEGY)
        self.assertIn("function knownCost", OPENAI_STRATEGY)
        self.assertIn("cost: cost", OPENAI_STRATEGY)
        self.assertIn("property real requestCost: -1", MESSAGE)
        self.assertIn("requester.message.requestCost = result.tokenUsage.cost", AI)
        self.assertIn("readonly property real sessionOpenRouterCost", AI)
        self.assertIn('startsWith("openrouter:")', AI)
        self.assertIn("function formatOpenRouterCost", AI)
        self.assertIn('"requestCost": message.requestCost', AI)
        self.assertIn('"requestCost": data.requestCost ?? -1', AI)

    def test_toolbar_cost_mode_replaces_the_pill_but_tooltip_keeps_all_metrics(self):
        self.assertIn("readonly property bool costMode: Config.options.ai.showOpenRouterSessionCost", TOOLBAR)
        self.assertIn("readonly property real sessionCost: Ai.sessionOpenRouterCost", TOOLBAR)
        self.assertIn("Ai.formatOpenRouterCost(tokenIndicator.sessionCost)", TOOLBAR)
        self.assertIn('Translation.tr("OpenRouter session cost: %1")', TOOLBAR)
        self.assertIn('Translation.tr("Latest answer speed: %1")', TOOLBAR)
        self.assertIn('Translation.tr("Total chat tokens: %1")', TOOLBAR)


if __name__ == "__main__":
    unittest.main()
