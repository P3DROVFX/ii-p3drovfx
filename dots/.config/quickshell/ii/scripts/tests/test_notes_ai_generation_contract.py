#!/usr/bin/env python3
"""Contracts for note-level AI writing and selection AI handoff."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP_DIR = ROOT / "modules/ii/notes"
DETAIL = (APP_DIR / "NotesDetail.qml").read_text(encoding="utf-8")
EDITOR = (APP_DIR / "editor/NotesEditor.qml").read_text(encoding="utf-8")
SELECTION_BAR = (APP_DIR / "editor/NotesSelectionBar.qml").read_text(encoding="utf-8")
PROMPT_BAR = (APP_DIR / "NotesAiPromptBar.qml").read_text(encoding="utf-8") if (APP_DIR / "NotesAiPromptBar.qml").exists() else ""
APP = (APP_DIR / "NotesApp.qml").read_text(encoding="utf-8")
WINDOW = (APP_DIR / "NotesAppWindow.qml").read_text(encoding="utf-8")
MARKDOWN = (ROOT / "services/notes/NotesMarkdown.js").read_text(encoding="utf-8")
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
TEXT_TASK = (ROOT / "services/ai/AiTextTask.qml").read_text(encoding="utf-8")
BROKER = (ROOT / "services/ai/AiToolBroker.qml").read_text(encoding="utf-8")


class NotesAiGenerationContractTests(unittest.TestCase):
    def test_note_toolbar_has_the_svg_ask_ai_entry_and_current_model_tooltip(self):
        self.assertIn('iconSource: "spark-symbolic.svg"', DETAIL)
        self.assertIn("currentAiModelName", DETAIL)
        self.assertIn("currentAiModelName", DETAIL[DETAIL.index("iconSource: \"spark-symbolic.svg\""):])
        self.assertIn("Ask AI about this", SELECTION_BAR)

    def test_note_toolbar_replaces_itself_with_a_prompt_and_sends_to_a_task(self):
        self.assertIn("NotesAiPromptBar", DETAIL)
        self.assertIn("AiTextTask", DETAIL)
        self.assertIn("onSubmitted", DETAIL)
        self.assertIn("aiCreateTask.start", DETAIL)
        self.assertIn("permission to write", DETAIL)
        self.assertIn("insertGeneratedText", DETAIL)
        self.assertIn("onTrashChanged", DETAIL)

    def test_selection_ai_waits_for_deferred_loader(self):
        self.assertIn("onLoaded", EDITOR)
        self.assertIn("pendingAiScope", EDITOR)
        self.assertIn("presentPendingAiMenu", EDITOR)
        self.assertNotIn("root.aiLoaded = true; // builds aiLoader synchronously", EDITOR)

    def test_selection_range_survives_focus_moving_to_ai_ui(self):
        self.assertIn("aiSelectionBlockId", EDITOR)
        self.assertIn("aiSelectionStart", EDITOR)
        self.assertIn("aiSelectionEnd", EDITOR)
        self.assertIn("rememberSelection", EDITOR)
        self.assertIn("lastSelectionBlockId", EDITOR)
        self.assertIn("root.replaceActiveSelection(newText)", EDITOR)
        self.assertIn("root.lastSelectionFullText", EDITOR)
        self.assertIn("root.syncFromDocument(true)", EDITOR)
        self.assertIn("aiItem.aiTask.cancel()", EDITOR)
        self.assertNotIn('if (mode === "selection" && root.hasSelection)', EDITOR)

    def test_prompt_bar_is_a_pill_with_an_explicit_send_action(self):
        self.assertTrue(PROMPT_BAR, "NotesAiPromptBar.qml is missing")
        self.assertIn("NotesMetrics.pillRadius", PROMPT_BAR)
        self.assertIn("clip: true", PROMPT_BAR)
        self.assertIn('symbol: root.running ? "stop" : "send"', PROMPT_BAR)
        self.assertIn("signal submitted", PROMPT_BAR)
        self.assertIn("Appearance.font.pixelSize.large", PROMPT_BAR)

    def test_generation_uses_the_chat_indicator_and_keeps_the_window_resident(self):
        self.assertIn("AiTypingIndicator", EDITOR)
        self.assertIn("import qs.services.ai.blocks", EDITOR)
        self.assertIn("externalAiGenerationActive", EDITOR)
        self.assertIn("readonly property bool aiBusy", EDITOR)
        self.assertIn("aiGenerationActive", DETAIL)
        self.assertIn("property bool aiBusy", WINDOW)
        self.assertIn("root.aiBusy", APP)
        self.assertIn("GlobalStates.notesAppOpen || root.aiBusy", APP)

    def test_generated_markdown_is_converted_to_note_native_blocks_without_focusing_it(self):
        self.assertIn("fromAiMarkdown", MARKDOWN)
        self.assertIn("Markdown.fromAiMarkdown", EDITOR)
        generated = EDITOR[EDITOR.index("function insertGeneratedText"):]
        self.assertNotIn("root.focusRequest = first.id", generated[:generated.index("function insertFile")])
        self.assertNotIn("root.focusRequest = root.blockIdAt(at)", generated[:generated.index("function insertFile")])

    def test_ai_releases_the_source_editor_so_markdown_preview_is_live(self):
        self.assertIn("function clearTextFocus", EDITOR)
        self.assertIn("editor.clearTextFocus()", DETAIL)
        replacement = EDITOR[EDITOR.index("function replaceActiveSelection"):EDITOR.index("function onAiReplace")]
        self.assertNotIn("root.focusRequest = blockId", replacement)

    def test_note_writer_uses_the_shared_chat_tool_pipeline(self):
        self.assertIn("toolMode: Ai.responseProfile.toolMode", DETAIL)
        self.assertIn("Ai.toolbox.wireTools", TEXT_TASK)
        self.assertIn("Ai.broker.dispatch", TEXT_TASK)
        self.assertIn("hostOverride", BROKER)
        self.assertIn("host: hostOverride ?? root.host", BROKER)
        self.assertIn("addFunctionOutputMessage", TEXT_TASK)
        self.assertIn("requestFollowUp", TEXT_TASK)

    def test_shared_ai_lease_blocks_overlapping_chat_and_notes_requests(self):
        self.assertIn("property string sharedTaskOwner", AI)
        self.assertIn("function beginSharedTask", AI)
        self.assertIn("function endSharedTask", AI)
        self.assertIn("root.sharedTaskOwner.length > 0", AI)
        self.assertIn("Ai.beginSharedTask(root.sharedTaskKey)", TEXT_TASK)
        self.assertIn("Ai.endSharedTask(root.sharedTaskKey)", TEXT_TASK)
        self.assertIn("root.releaseSharedTask()", TEXT_TASK)


if __name__ == "__main__":
    unittest.main()
