#!/usr/bin/env python3
"""Pin the no-duplicate/no-blind-retry invariants of task mutations."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
INTEGRATION = (ROOT / "services" / "ai" / "integrations" / "AiTasksIntegration.qml").read_text(encoding="utf-8")
MUTATION_CARD = (ROOT / "services" / "ai" / "blocks" / "AiTaskMutationCard.qml").read_text(encoding="utf-8")


class TaskIdempotencyTests(unittest.TestCase):
    def test_mutations_use_the_existing_durable_journal(self):
        for token in ("beginToolExecution(message, \"tasks_create\"", "argsHash", "executionStarted", "operationId"):
            self.assertIn(token, AI)

    def test_external_failure_becomes_inspection_not_an_automatic_retry(self):
        self.assertIn('status: mutating ? "needsInspection" : "error"', INTEGRATION)
        self.assertNotIn("retry", MUTATION_CARD.lower())

    def test_duplicate_provider_callbacks_are_ignored_after_pending_is_removed(self):
        self.assertIn("delete root.pendingOperations[id]", INTEGRATION)
        self.assertIn("if (!job)", INTEGRATION)

    def test_duplicate_approval_clicks_do_not_start_a_second_journal(self):
        self.assertIn("root.pendingToolExecution?.message === message", AI)


if __name__ == "__main__":
    unittest.main()
