#!/usr/bin/env python3
"""Contract tests for reviewed AI note actions."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REGISTRY = (ROOT / "services/ai/AiToolRegistry.qml").read_text(encoding="utf-8")
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
MESSAGE = (ROOT / "modules/ii/sidebarPolicies/aiChat/AiMessage.qml").read_text(encoding="utf-8")
ADAPTER = (ROOT / "services/ai/integrations/AiNotesIntegration.qml").read_text(encoding="utf-8") if (ROOT / "services/ai/integrations/AiNotesIntegration.qml").exists() else ""


class AiNotesContractTests(unittest.TestCase):
    def test_registry_exposes_preview_and_write_tools(self):
        for tool_id in ("notes_preview_append", "notes_append", "notes_create_from_answer"):
            self.assertIn(f'id: "{tool_id}"', REGISTRY)
        self.assertIn('kind: "localWrite"', REGISTRY)
        self.assertIn('defaultApproval: "ask"', REGISTRY)

    def test_adapter_bounds_markdown_and_provenance(self):
        self.assertIn("function previewAppend", ADAPTER)
        self.assertIn("function append", ADAPTER)
        self.assertIn("function create", ADAPTER)
        self.assertIn("provenance", ADAPTER)
        self.assertNotIn("prompt", ADAPTER)

    def test_ai_has_handlers_and_journalled_starters(self):
        for name in ("toolNotesPreviewAppend", "toolNotesAppend", "toolNotesCreate"):
            self.assertIn(name, AI)
        for tool_id in ("notes_append", "notes_create_from_answer"):
            self.assertIn(f'"{tool_id}": pending', AI)
        self.assertIn("function approveNotes", AI)
        self.assertIn("function rejectNotes", AI)

    def test_transcript_has_a_review_card_for_notes(self):
        self.assertIn('case "notesPreview"', MESSAGE)
        self.assertIn("AiNotesCard", MESSAGE)


if __name__ == "__main__":
    unittest.main()
