#!/usr/bin/env python3
"""Static regression contracts for the AI P0 fixes.

These tests intentionally inspect the small QML/Python boundaries that are
easy to regress without a running Wayland shell: draft ownership, command
vocabulary, context compaction correlation and attachment safety.
"""

import unittest
import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
REGISTRY_QML = (ROOT / "services" / "ai" / "AiActionRegistry.qml").read_text(encoding="utf-8")
SEARCH_QML = (ROOT / "modules" / "ii" / "overview" / "SearchWidget.qml").read_text(encoding="utf-8")
COMPOSER_QML = (ROOT / "modules" / "ii" / "overview" / "AiSearchComposer.qml").read_text(encoding="utf-8")
SIDEBAR_QML = (ROOT / "modules" / "ii" / "sidebarPolicies" / "AiChat.qml").read_text(encoding="utf-8")
ATTACH_PY = (ROOT / "scripts" / "ai" / "ai_attach.py").read_text(encoding="utf-8")
ATTACH_SPEC = importlib.util.spec_from_file_location("ai_attach", ROOT / "scripts" / "ai" / "ai_attach.py")
ATTACH_MODULE = importlib.util.module_from_spec(ATTACH_SPEC)
ATTACH_SPEC.loader.exec_module(ATTACH_MODULE)


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class AiP0ContractTests(unittest.TestCase):
    def test_composer_does_not_clear_before_submission_ack(self):
        send = body_between(COMPOSER_QML, "function send()", "function focusInput()")
        self.assertNotIn("draftInput.clear()", send)
        self.assertNotIn("Ai.draft =", send)
        search_send = body_between(SEARCH_QML, "function sendAiMessage", "function executeAiCommand")
        self.assertNotIn("Ai.draft = \"\"", search_send)
        sidebar_input = body_between(SIDEBAR_QML, "function handleInput", "Connections {")
        self.assertIn("Ai.clearDraftIfCurrent()", sidebar_input)
        self.assertNotIn("messageInputField.clear()", sidebar_input)

    def test_commands_use_the_same_canonical_ids_as_hosts(self):
        for command_id in ("chats", "clear", "temp", "think", "web", "tools", "effort"):
            self.assertIn(f'id: "{command_id}"', REGISTRY_QML)
        search_handler = body_between(SEARCH_QML, "function executeAiCommand", "function setSearchingText")
        for command_id in ("chats", "clear", "temp", "think", "web", "tools", "effort"):
            self.assertIn(f'case "{command_id}"', search_handler)

    def test_context_compaction_is_correlated_and_serialized(self):
        self.assertIn("property var pendingContextCompaction", AI_QML)
        self.assertIn("function contextCompactionKey", AI_QML)
        self.assertIn("function createApiStrategy", AI_QML)
        self.assertIn("skipCompaction: true", AI_QML)
        self.assertIn("contextSummaryKey", AI_QML)
        self.assertIn("windowed.oversized", AI_QML)
        self.assertIn("Math.ceil((file.bytes ?? 0) / 3)", AI_QML)
        self.assertIn("id: contextEstimateTimer", AI_QML)
        self.assertIn("onContentChanged() { root.scheduleContextEstimate(); }", AI_QML)

    def test_finish_event_has_run_and_message_identity(self):
        self.assertIn("signal responseFinished(var result)", AI_QML)
        event = body_between(AI_QML, "root.responseFinished({", "});")
        for field in ("runId", "sessionId", "requestMessageId", "responseMessageId", "requiresAttention"):
            self.assertIn(f"{field}:", event)

    def test_attachment_probe_blocks_secrets_and_caps_extraction(self):
        self.assertIn("def is_sensitive_path", ATTACH_PY)
        self.assertIn('"sensitive": True', ATTACH_PY)
        self.assertIn("select.select", ATTACH_PY)
        self.assertIn("limit + 1", ATTACH_PY)
        self.assertIn("attachment blocked: credential or secret path", ATTACH_PY)
        self.assertTrue(ATTACH_MODULE.is_sensitive_path("/tmp/.env"))
        self.assertTrue(ATTACH_MODULE.is_sensitive_path("/home/test/.ssh/id_ed25519"))
        self.assertFalse(ATTACH_MODULE.is_sensitive_path("/tmp/notes.txt"))


if __name__ == "__main__":
    unittest.main()
