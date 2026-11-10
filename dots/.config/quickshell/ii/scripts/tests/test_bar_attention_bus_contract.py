"""Contracts for keeping the bar's AI attention indicator lightweight."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BarAttentionBusContractTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_bar_policy_buttons_observe_the_lightweight_bus(self):
        for relative in (
            "modules/ii/bar/widgets/policies/PoliciesPanelButton.qml",
            "modules/ii/bar/widgets/policies/ExpressivePoliciesPanelButton.qml",
            "modules/ii/bar/widgets/policies/OutlinePoliciesPanelButton.qml",
        ):
            source = self.read(relative)
            self.assertIn("AiResponseBus", source, relative)
            self.assertNotIn("target: root.aiChatEnabled ? Ai : null", source, relative)
            self.assertNotIn("target: Number(Config.options?.policies?.ai ?? 1) !== 0 ? Ai : null", source, relative)

    def test_ai_publishes_response_events_without_moving_the_existing_signal(self):
        bus = self.read("services/AiResponseBus.qml")
        ai = self.read("services/Ai.qml")
        self.assertIn("signal responseFinished(var result)", bus)
        self.assertIn("AiResponseBus.responseFinished(result);", ai)
        self.assertIn("root.responseFinished(result);", ai)


if __name__ == "__main__":
    unittest.main()
