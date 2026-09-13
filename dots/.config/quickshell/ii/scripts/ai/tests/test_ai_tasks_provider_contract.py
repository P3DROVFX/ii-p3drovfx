#!/usr/bin/env python3
"""Contracts for the provider-neutral task adapter."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
INTEGRATION = (ROOT / "services" / "ai" / "integrations" / "AiTasksIntegration.qml").read_text(encoding="utf-8")
TODO = (ROOT / "services" / "Todo.qml").read_text(encoding="utf-8")
TICKTICK = (ROOT / "services" / "TickTickService.qml").read_text(encoding="utf-8")
API = (ROOT / "scripts" / "ticktick" / "api.py").read_text(encoding="utf-8")
REGISTRY = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
AI = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
MESSAGE = (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessage.qml").read_text(encoding="utf-8")


class ProviderContractTests(unittest.TestCase):
    def test_contract_has_all_provider_operations(self):
        for operation in ("listTaskLists", "listTasks", "createTask", "updateTask", "completeTask", "deleteTask"):
            with self.subTest(operation=operation):
                self.assertIn(f"function {operation}", INTEGRATION)

    def test_provider_selection_never_guesses_a_list_from_text(self):
        self.assertIn("resolveProvider", INTEGRATION)
        self.assertIn("args?.provider", INTEGRATION)
        self.assertIn("args?.listId", INTEGRATION)
        self.assertIn("Unknown task provider", INTEGRATION)

    def test_preview_normalizes_absolute_due_date_and_destination(self):
        for field in ("provider", "accountId", "listId", "listName", "title", "notes", "dueDate", "dueDateDisplay"):
            self.assertIn(field + ":", INTEGRATION)
        self.assertIn("toISOString()", INTEGRATION)
        self.assertIn("toLocaleString()", INTEGRATION)

    def test_local_provider_has_stable_ids_and_reviewable_mutations(self):
        for token in ("aiProviderId", "aiCreateTask", "aiUpdateTask", "aiCompleteTask", "aiDeleteTask"):
            self.assertIn(token, TODO)
        self.assertIn('id: "local-"', TODO)

    def test_ticktick_transport_keeps_operations_correlated(self):
        for token in ("aiOperationFinished", "aiRequest", "operationId", "callId"):
            self.assertIn(token, TICKTICK)
        self.assertIn("aiUpdateTask", TICKTICK)

    def test_ticktick_helper_supports_update_without_a_shell(self):
        self.assertIn('if op == "update":', API)
        self.assertIn('request(token, "POST", f"/task/{path_part(task_id)}", task)', API)
        code = API.split('"""', 2)[2]
        for forbidden in ("bash -c", "subprocess", "shell=True", "os.system"):
            self.assertNotIn(forbidden, code)

    def test_creation_is_registered_as_external_write_and_requires_approval(self):
        for tool_id in ("tasks_list", "tasks_search", "tasks_create"):
            self.assertIn(f'id: "{tool_id}"', REGISTRY)
        create = REGISTRY.split('id: "tasks_create"', 1)[1].split('id: "sports_search_games"', 1)[0]
        self.assertIn('kind: "externalWrite"', create)
        self.assertIn('defaultApproval: "ask"', create)

    def test_creation_is_wired_to_journal_and_native_cards(self):
        for token in ("tasksIntegration", '"tasks_create": call => root.toolTasksCreate(call)', '"tasks_create": pending => root.startTaskCreate(pending)', "approveTask", "rejectTask"):
            self.assertIn(token, AI)
        for token in ('case "taskPreview":', 'case "taskResults":', "id: taskPreviewCard", "id: taskResultsCard"):
            self.assertIn(token, MESSAGE)

    def test_mutations_are_explicitly_reviewed(self):
        for tool_id in ("tasks_update", "tasks_complete", "tasks_delete"):
            block = REGISTRY.split(f'id: "{tool_id}"', 1)[1].split('id: "', 1)[0]
            self.assertIn('kind: "externalWrite"', block)
            self.assertIn('defaultApproval: "ask"', block)
            self.assertIn('required: ["provider", "taskId"]', block)
        self.assertIn('"tasks_update": pending => root.startTaskMutation(pending, "update")', AI)
        self.assertIn('"tasks_delete": pending => root.startTaskMutation(pending, "delete")', AI)

    def test_mutation_card_has_no_retry_action(self):
        card = (ROOT / "services" / "ai" / "blocks" / "AiTaskMutationCard.qml").read_text(encoding="utf-8")
        self.assertIn("approveTaskMutation", card)
        self.assertIn("rejectTaskMutation", card)
        self.assertNotIn("retry", card.lower())
        self.assertIn('case "taskMutationPreview":', MESSAGE)


if __name__ == "__main__":
    unittest.main()
