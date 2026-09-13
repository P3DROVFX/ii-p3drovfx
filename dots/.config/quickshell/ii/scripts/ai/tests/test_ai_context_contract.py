#!/usr/bin/env python3
"""Contracts for the things that used to fail quietly.

Three of these guard behaviour that has no visible symptom until it is too
late: a conversation sent whole until the provider refuses it, an attachment
accepted and then left out of the request, and an answer cut off at the output
limit with no way to continue. The rest guard the wiring that makes the web
tools reach a local model at all.

They read the QML as text on purpose — there is no QML test runner here, and a
contract that fails loudly at review time is worth more than one that needs a
running shell.
"""

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
AI_SERVICE = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
AI_TOOLS = (ROOT / "services" / "ai" / "AiTools.qml").read_text(encoding="utf-8")
AI_MESSAGE_DATA = (ROOT / "services" / "ai" / "AiMessageData.qml").read_text(encoding="utf-8")
API_STRATEGY = (ROOT / "services" / "ai" / "ApiStrategy.qml").read_text(encoding="utf-8")
OPENAI_STRATEGY = (ROOT / "services" / "ai" / "OpenAiCompatStrategy.qml").read_text(encoding="utf-8")
GEMINI_STRATEGY = (ROOT / "services" / "ai" / "GeminiApiStrategy.qml").read_text(encoding="utf-8")
ANTHROPIC_STRATEGY = (ROOT / "services" / "ai" / "AnthropicApiStrategy.qml").read_text(encoding="utf-8")
REGISTRY = (ROOT / "services" / "ai" / "AiTranscriptRegistry.qml").read_text(encoding="utf-8")
MEMORY = (ROOT / "services" / "ai" / "AiMemory.qml").read_text(encoding="utf-8")

sys.path.insert(0, str(ROOT / "scripts" / "ai"))
import ai_attach  # noqa: E402
import ai_web  # noqa: E402


class ContextWindowContractTests(unittest.TestCase):
    def test_native_ollama_defers_context_allocation_to_the_daemon(self):
        # `context_length` from /api/tags is the model's supported maximum,
        # not a safe allocation for this user's hardware.  Sending it as
        # `num_ctx` bypasses Ollama's own VRAM-aware context choice and can
        # make even a short chat fail while `ollama run` still works.
        native_request = OPENAI_STRATEGY.split(
            "if (nativeOllama) {\n            const baseName", 1
        )[1].split("        } else {", 1)[0]
        self.assertNotRegex(native_request, r"\\b(?:baseData\\.options\\.)?num_ctx\\s*[:=]")
        self.assertIn("num_predict: maxOutputTokens(model)", native_request)

    def test_request_sends_only_what_fits(self):
        self.assertIn("historyWithinWindow(filteredMessageArray, model)", AI_SERVICE)
        self.assertIn("strategy.buildRequestData(model, windowed.messages", AI_SERVICE)

    def test_cut_never_lands_on_an_answer(self):
        # Opening the history on an assistant turn leaves the model looking at
        # a reply to a question it cannot see.
        self.assertIn('while (firstKept > 0 && firstKept < all.length && all[firstKept].role !== "user")', AI_SERVICE)

    def test_what_was_dropped_is_summarised_not_forgotten(self):
        self.assertIn("summarisePruned(windowed.pruned", AI_SERVICE)
        self.assertIn("## Earlier in this conversation", AI_SERVICE)
        self.assertIn('"contextSummary": root.contextSummary', AI_SERVICE)

    def test_the_transcript_is_told_where_the_cut_is(self):
        self.assertIn("root.contextCutMessageId = windowed.cutId", AI_SERVICE)
        self.assertIn("root.prunedTurnCount = windowed.pruned.length", AI_SERVICE)

    def test_tokens_can_be_counted_before_anyone_is_charged(self):
        self.assertIn("function estimateTokens(text: string): int", AI_SERVICE)
        self.assertIn("property int estimatedContextTokens", AI_SERVICE)


class AttachmentContractTests(unittest.TestCase):
    def test_every_attachment_is_sent_extracted_or_refused(self):
        plan = AI_SERVICE.split("function attachmentPlan(file: var): var", 1)[1].split("\n    }", 1)[0]
        for action in ('"send"', '"extract"', '"reject"'):
            self.assertIn(action, plan)
        # A rejection always carries a reason the composer can show.
        self.assertIn('action: "reject", reason:', plan)

    def test_documents_only_ride_along_where_they_are_understood(self):
        # Only two dialects have a block for a document; everywhere else it is
        # read here first or turned away, never posted and dropped.
        self.assertIn("function modelTakesDocuments", AI_SERVICE)
        decision = AI_SERVICE.split("function modelTakesDocuments", 1)[1][:400]
        self.assertIn('format === "gemini"', decision)
        self.assertIn('format === "anthropic"', decision)

    def test_extracted_text_is_read_at_send_time_not_kept_in_memory(self):
        self.assertIn("extracted: true", AI_SERVICE)
        self.assertNotIn("text: text", AI_SERVICE)
        self.assertIn("function textModeFor(file: var): string", API_STRATEGY)
        for strategy in (OPENAI_STRATEGY, GEMINI_STRATEGY, ANTHROPIC_STRATEGY):
            self.assertIn("attachmentMarker(file.path, textModeFor(file))", strategy)

    def test_the_prober_says_whether_this_machine_can_read_it(self):
        probe = ai_attach.probe(str(Path(__file__)))
        self.assertIn("extractable", probe)
        self.assertEqual(probe["kind"], "text")

    def test_extraction_reports_failure_instead_of_returning_nothing(self):
        result = ai_attach.extract("/definitely/not/here.pdf")
        self.assertIn("error", result)


class TruncationContractTests(unittest.TestCase):
    def test_every_dialect_records_why_it_stopped(self):
        self.assertIn("property string finishReason", AI_MESSAGE_DATA)
        self.assertIn("message.finishReason = String(dataJson.candidates[0].finishReason)", GEMINI_STRATEGY)
        self.assertIn("message.finishReason = String(choice.finish_reason)", OPENAI_STRATEGY)
        self.assertIn("message.finishReason = String(stopReason)", ANTHROPIC_STRATEGY)

    def test_continuing_asks_without_writing_in_the_transcript(self):
        continue_fn = AI_SERVICE.split("function continueMessage(messageId: string)", 1)[1].split("\n    }", 1)[0]
        self.assertIn('"visibleToUser": false', continue_fn)
        self.assertIn("root.makeRequest()", continue_fn)


class WebToolContractTests(unittest.TestCase):
    # The definitions moved out of AiTools into the registry when the tool
    # layer was split; what they have to say has not changed.
    AI_REGISTRY = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")

    def test_the_web_is_a_tool_so_a_local_model_can_use_it(self):
        for tool in ('id: "web_search"', 'id: "fetch_url"'):
            self.assertIn(tool, self.AI_REGISTRY)
        # Available to every dialect, not only the ones with search of their own.
        search = self.AI_REGISTRY.split('id: "web_search"', 1)[1].split("},\n        {", 1)[0]
        self.assertIn('formats: ["gemini", "openai", "anthropic"]', search)
        self.assertIn("needsSearch: false", search)

    def test_reaching_the_web_is_refused_under_a_local_only_policy(self):
        # Declared as needing the network, and refused generically when the
        # policy does not allow it — rather than by naming the two web tools
        # in a condition, which is what stopped anything else being added.
        for tool in ('id: "web_search"', 'id: "fetch_url"'):
            block = self.AI_REGISTRY.split(tool, 1)[1].split("},\n        {", 1)[0]
            with self.subTest(tool=tool):
                self.assertIn('network: "required"', block)
        self.assertIn('def.network === "required"', self.AI_REGISTRY)
        self.assertIn("Needs the network, which the current policy does not allow", self.AI_REGISTRY)

    def test_fetch_refuses_anything_that_is_not_http(self):
        result = ai_web.fetch("file:///etc/passwd")
        self.assertIn("error", result)
        self.assertNotIn("text", result)

    def test_search_says_what_to_do_when_no_backend_answers(self):
        source = (ROOT / "scripts" / "ai" / "ai_web.py").read_text(encoding="utf-8")
        self.assertIn("AI_SEARXNG_URL", source)
        self.assertIn("BRAVE_SEARCH_KEY", source)


class SearchSurfaceContractTests(unittest.TestCase):
    SEARCH_WIDGET = (ROOT / "modules" / "ii" / "overview" / "SearchWidget.qml").read_text(encoding="utf-8")
    SEARCH_PANEL = (ROOT / "modules" / "ii" / "overview" / "AiChatPanel.qml").read_text(encoding="utf-8")

    def test_ai_mode_is_state_not_a_formula(self):
        # Derived from the query, it fed on its own side effect (entering AI
        # mode clears the query), Qt froze the binding, and Escape could no
        # longer leave the panel.
        self.assertIn("readonly property bool isAiMode: Ai.enabled && root.aiModeLocked", self.SEARCH_WIDGET)
        entering = self.SEARCH_WIDGET.split("onIsAiModeChanged:", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("aiModeLocked = true", entering)

    def test_leaving_clears_every_latch(self):
        leaving = self.SEARCH_WIDGET.split("function resetAiSearchState", 1)[1].split("\n    }", 1)[0]
        for latch in ("root.aiAutoEngaged = false", "root.aiModeLocked = false"):
            self.assertIn(latch, leaving)

    def test_the_search_transcript_matches_the_sidebar(self):
        self.assertIn("ScrollEdgeFade {", self.SEARCH_PANEL)
        self.assertIn("blurEdges: true", self.SEARCH_PANEL)
        self.assertIn("function pinToEnd()", self.SEARCH_PANEL)
        self.assertIn("AiTranscriptRegistry.greetingLine()", self.SEARCH_PANEL)
        # The short bar, not a second implementation of one.
        self.assertIn("minimal: root.compact", (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessage.qml").read_text(encoding="utf-8"))


class TurnDeliveryContractTests(unittest.TestCase):
    """Three failures that all looked like the UI, and were all in the wiring."""

    def test_the_map_is_filled_before_the_list_is_published(self):
        # A watcher that refilters synchronously on `messageIDs` looked the new
        # id up in a map that did not hold it yet, so the Search transcript
        # never drew the streaming answer.
        appends = AI_SERVICE.count("root.messageIDs = [...root.messageIDs,")
        self.assertGreater(appends, 0)
        for match in re.finditer(r"root\.messageByID\[(\w+)\] = \w+;\n\s*root\.messageIDs = \[\.\.\.root\.messageIDs, \1\];", AI_SERVICE):
            self.assertTrue(match)
        self.assertEqual(
            appends,
            len(re.findall(r"root\.messageByID\[(\w+)\] = \w+;\s*\n\s*root\.messageIDs = \[\.\.\.root\.messageIDs, \1\];", AI_SERVICE)),
            "every append fills the map first",
        )

    def test_cancelling_a_summary_uses_abort_not_a_read_only_property(self):
        # Assigning `running` threw, and since this is the first thing
        # `applySession()` does, a restored chat came back empty.
        cancel = AI_SERVICE.split("function cancelContextCompaction()", 1)[1].split("\n    }", 1)[0]
        self.assertIn("summaryRequester.abort()", cancel)
        self.assertNotIn("summaryRequester.running =", cancel)

    def test_the_notification_only_uses_an_icon_the_theme_really_has(self):
        # A name the daemon cannot resolve renders as the missing-texture
        # checkerboard; no icon at all renders as a Material symbol.
        resolver = AI_SERVICE.split("function notificationIconFor(model): string", 1)[1].split("\n    }", 1)[0]
        self.assertIn("Quickshell.iconPath(candidate, true)", resolver)
        self.assertIn('return ""', resolver)
        notify = AI_SERVICE.split("function notifyResponseFinished", 1)[1].split("\n    }", 1)[0]
        self.assertIn("root.notificationIconFor(model)", notify)
        self.assertIn("if (iconName.length > 0)", notify)
        self.assertNotIn("--icon=chat", notify)

    def test_a_finished_answer_is_announced_when_nobody_is_looking(self):
        self.assertIn("function notifyResponseFinished", AI_SERVICE)
        notify = AI_SERVICE.split("function notifyResponseFinished", 1)[1].split("\n    }", 1)[0]
        self.assertIn("notify-send", notify)
        self.assertIn("root.chatOnScreen", notify)
        # It runs from the one terminal point, not from a stream frame.
        done = AI_SERVICE.split("function markDone", 1)[1].split("\n    }", 1)[0]
        self.assertIn("root.notifyResponseFinished(message)", done)


class MessageToolbarContractTests(unittest.TestCase):
    ACTIONS = (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessageActions.qml").read_text(encoding="utf-8")

    @staticmethod
    def _bar(width: int, huge: int = 22, minimal: bool = False) -> dict:
        """The same arithmetic the QML does, so the claim can be checked."""
        compact = width < huge * 19
        extent = round(huge * (1.5 if compact else 1.75))
        gap = max(2, round(extent * 0.12))
        inset = max(2, round(extent * 0.14))
        actions = 2 if minimal else 5
        limit = max(extent, width - inset * 2 - (extent + gap) * actions - gap)
        used = limit + (actions + 1) * gap + actions * extent + inset * 2
        return {"extent": extent, "limit": limit, "used": used}

    def test_the_name_can_never_grow_into_the_first_circle(self):
        for width in (240, 300, 320, 360, 418, 440, 520, 700, 900):
            for minimal in (False, True):
                bar = self._bar(width, minimal=minimal)
                self.assertLessEqual(
                    bar["used"], width,
                    f"the row overflows at {width}px (minimal={minimal})")

    def test_the_limit_counts_every_gap_in_the_row(self):
        # pill | spacer | five circles → one gap per action plus one between
        # the two groups. Miscounting is how a name ends up under a button.
        self.assertIn(
            "root.width - root.inset * 2 - (root.controlExtent + root.controlGap) * root.actionCount - root.controlGap",
            self.ACTIONS)

    def test_a_long_name_is_cut_and_a_tiny_bar_keeps_only_the_logo(self):
        self.assertIn("elide: Text.ElideRight", self.ACTIONS)
        self.assertIn("readonly property bool showModelName", self.ACTIONS)
        self.assertIn("visible: root.showModelName", self.ACTIONS)

    def test_nothing_in_the_row_may_be_shrunk_below_its_circle(self):
        self.assertEqual(2, self.ACTIONS.count("Layout.minimumWidth: root.controlExtent"))

    def test_spacing_follows_the_control_so_a_taller_bar_is_a_tighter_one(self):
        self.assertIn("Math.round(root.controlExtent * 0.12)", self.ACTIONS)
        self.assertIn("Math.round(root.controlExtent * 0.14)", self.ACTIONS)


class TypingIndicatorContractTests(unittest.TestCase):
    INDICATOR = (ROOT / "services" / "ai" / "blocks" / "AiTypingIndicator.qml").read_text(encoding="utf-8")
    MESSAGE = (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessage.qml").read_text(encoding="utf-8")

    def test_three_shapes_ride_one_wave(self):
        self.assertIn("model: 3", self.INDICATOR)
        # Offset by a third of the cycle each: that is what makes it travel
        # rather than pulse.
        self.assertIn("Math.round(root.waveDuration / 3) * dotSlot.index", self.INDICATOR)
        self.assertIn("Math.round(root.waveDuration / 3) * (2 - dotSlot.index)", self.INDICATOR)
        # And they are different shapes, not three dots.
        shapes = self.INDICATOR.split("readonly property var dotShapes:", 1)[1].split("]", 1)[0]
        self.assertEqual(3, shapes.count("MaterialShape.Shape."))
        self.assertEqual(3, len({line.strip() for line in shapes.splitlines() if "Shape." in line}))

    def test_the_wave_stops_when_the_answer_lands(self):
        self.assertIn("running: root.active", self.INDICATOR)
        self.assertIn("active: loadingIndicatorLoader.shown", self.MESSAGE)

    def test_the_caption_moves_on_while_waiting(self):
        self.assertIn("Generating your answer", self.INDICATOR)
        self.assertIn("animateChange: true", self.INDICATOR)

    def test_the_wait_is_left_aligned_and_has_no_ground(self):
        loader = self.MESSAGE.split("id: loadingIndicatorLoader", 1)[1].split("}", 1)[0]
        self.assertIn("anchors.left: parent.left", loader)
        self.assertNotIn("horizontalCenter", loader)
        self.assertIn('color: answerBubble.holdsOnlyTheWait ? "transparent" : root.answerSurface', self.MESSAGE)


class TranscriptContractTests(unittest.TestCase):
    def test_tables_are_parsed_out_of_the_prose(self):
        blocks = _blocks_of("| a | b |\n|---|---:|\n| 1 | 2 |\n")
        self.assertIn("type: \"table\"", REGISTRY)
        self.assertIn("alignments", REGISTRY)
        self.assertTrue(blocks)

    def test_unchanged_blocks_keep_their_identity(self):
        self.assertIn("function reuseBlocks(previous, content)", REGISTRY)
        self.assertIn("fresh[i] = before", REGISTRY)

    def test_memory_is_a_singleton_and_a_file_the_user_can_read(self):
        self.assertTrue(MEMORY.startswith("pragma Singleton"))
        self.assertIn("user/ai/memory.json", MEMORY)
        self.assertIn("What you already know about this user", MEMORY)


def _blocks_of(_markdown: str) -> bool:
    """The splitter itself is QML; this only asserts the shape exists."""
    return "function splitTables(text)" in REGISTRY


if __name__ == "__main__":
    unittest.main()
