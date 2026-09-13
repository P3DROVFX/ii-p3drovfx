"""Regression contracts for navigating regenerated answer branches."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
AI = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
MESSAGE = (
    ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessage.qml"
).read_text(encoding="utf-8")


class AiAnswerVariantTests(unittest.TestCase):
    def test_branch_index_forms_a_stable_variant_group(self):
        for token in (
            "function answerVariantSessionIds(messageId: string): var",
            "entry?.parentId",
            "entry?.branchMessageId",
            "function latestVisibleAssistantMessageId(): string",
            "function shouldShowAnswerVariants(messageId: string): bool",
            "function openAnswerVariant(messageId: string, offset: int)",
        ):
            with self.subTest(token=token):
                self.assertIn(token, AI)

    def test_answer_exposes_compact_position_and_navigation_controls(self):
        for token in (
            "answerVariantIds",
            "showAnswerVariants",
            'text: "<" + String(root.answerVariantIndex + 1) + "/" + String(root.answerVariantIds.length) + ">"',
            "Ai.openAnswerVariant(root.messageId, -1)",
            "Ai.openAnswerVariant(root.messageId, 1)",
        ):
            with self.subTest(token=token):
                self.assertIn(token, MESSAGE)


if __name__ == "__main__":
    unittest.main()
