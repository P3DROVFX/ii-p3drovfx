#!/usr/bin/env python3
"""Regression contracts for streamed answers and their usage accounting."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
OPENAI_STRATEGY = (ROOT / "services" / "ai" / "OpenAiCompatStrategy.qml").read_text(encoding="utf-8")
AI_SERVICE = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
AI_MESSAGE = (ROOT / "services" / "ai" / "AiMessageData.qml").read_text(encoding="utf-8")
AI_USAGE = (ROOT / "services" / "AiUsage.qml").read_text(encoding="utf-8")
USAGE_DASHBOARD = (
    ROOT / "modules" / "settings" / "configs" / "ai" / "AiUsageDashboard.qml"
).read_text(encoding="utf-8")
# Both surfaces draw the same turn now; the Search panel is that component in
# its compact density.
TRANSCRIPT_MESSAGE = (
    ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessage.qml"
).read_text(encoding="utf-8")
SEARCH_PANEL = (ROOT / "modules" / "ii" / "overview" / "AiChatPanel.qml").read_text(encoding="utf-8")


class AiStreamUsageContractTests(unittest.TestCase):
    def test_reported_cost_is_persisted_in_the_usage_ledger(self):
        self.assertIn("message.requestCost", AI_SERVICE)
        self.assertIn("function costSince(daysBack: int): real", AI_USAGE)
        self.assertIn("function costResponsesSince(daysBack: int): int", AI_USAGE)
        self.assertIn("function formatCost(value): string", AI_USAGE)
        self.assertIn("costResponses", AI_USAGE)
        self.assertIn("Reported cost", USAGE_DASHBOARD)

    def test_native_ollama_uses_native_generation_and_terminal_counters(self):
        self.assertIn("num_predict: maxOutputTokens(model)", OPENAI_STRATEGY)
        self.assertIn("data?.prompt_eval_count", OPENAI_STRATEGY)
        self.assertIn("data?.eval_count", OPENAI_STRATEGY)
        self.assertIn("nativeMessage.content", OPENAI_STRATEGY)

    def test_native_ollama_tool_calls_and_object_arguments_are_collected(self):
        # `/api/chat` places calls under `message.tool_calls` and gives the
        # arguments as an object, unlike the OpenAI delta string fragments.
        self.assertIn("nativeMessage.tool_calls", OPENAI_STRATEGY)
        collector = OPENAI_STRATEGY.split("function collectToolCalls(fragments)", 1)[1].split("function hasPendingCalls", 1)[0]
        self.assertIn('typeof argumentsValue === "string"', collector)
        self.assertIn("JSON.stringify(argumentsValue)", collector)

    def test_native_ollama_replays_tool_exchanges_in_its_own_wire_shape(self):
        request_builder = OPENAI_STRATEGY.split("function buildRequestData(", 1)[1].split("function buildAuthorizationHeader", 1)[0]
        # Native Ollama expects decoded arguments plus tool_name, rather than
        # OpenAI's JSON string arguments and tool_call_id pair.
        self.assertIn('"arguments": call.args ?? ({})', request_builder)
        self.assertIn('"tool_name": message.functionName', request_builder)

    def test_finished_stream_is_accounted_after_the_last_frame(self):
        on_line = AI_SERVICE.split("onLine: data =>", 1)[1].split("onRetrying:", 1)[0]
        on_finished = AI_SERVICE.split("onFinished: (reason, status, code) =>", 1)[1]
        self.assertNotIn("root.markDone(requester.message)", on_line)
        self.assertIn("root.markDone(message)", on_finished)

    def test_context_connections_keep_a_qobject_target_while_a_turn_is_removed(self):
        # A run can finish and remove its response before the context
        # estimator rebinds. Connections cannot accept undefined as target.
        self.assertIn("root.messageByID[root.currentRunResponseId] ?? root", AI_SERVICE)

    def test_turn_owns_usage_and_session_persists_it(self):
        for token_property in ("inputTokens", "outputTokens", "totalTokens"):
            self.assertIn(f"property int {token_property}: -1", AI_MESSAGE)
            self.assertIn(f'"{token_property}": message.{token_property}', AI_SERVICE)
            self.assertIn(f'"{token_property}": data.{token_property} ?? -1', AI_SERVICE)

    def test_usage_waits_for_its_persisted_ledger(self):
        self.assertIn("property var pendingResponses: []", AI_USAGE)
        self.assertIn("root.flushPendingResponses()", AI_USAGE)
        self.assertIn("root.applyResponse(record)", AI_USAGE)

    def test_restored_final_answer_has_a_direct_transcript_dependency(self):
        # The dependency is explicit rather than hidden behind a helper: QML
        # cannot always infer a property read made inside a singleton call, and
        # a restored answer used to render from a stale, empty model.
        self.assertIn("readonly property string transcriptContent", TRANSCRIPT_MESSAGE)
        self.assertIn("onTranscriptContentChanged:", TRANSCRIPT_MESSAGE)
        self.assertIn("reuseBlocks(root.messageBlocks, root.transcriptContent)", TRANSCRIPT_MESSAGE)
        # A finished answer always rebuilds, whatever the streaming coalescer
        # was in the middle of.
        self.assertIn("onDoneChanged:", TRANSCRIPT_MESSAGE)

    def test_both_surfaces_share_one_transcript(self):
        self.assertIn("AiMessage {", SEARCH_PANEL)
        self.assertIn('density: "compact"', SEARCH_PANEL)
        self.assertFalse(
            (ROOT / "modules" / "ii" / "overview" / "AiChatPanelMessage.qml").exists(),
            "the second transcript implementation is gone for good",
        )


if __name__ == "__main__":
    unittest.main()
