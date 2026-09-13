#!/usr/bin/env python3
"""Regression contracts for three chat-UX fixes reported after real use.

1. Tool-call turns fired a desktop notification of their own, so one answer
   that used the web (search, then read a page) sent three notifications
   instead of one.
2. A thinking block, once expanded by hand, was remembered as a *global*
   preference (`Persistent.states.ai.expandThoughts`) and every future
   thought in every future message opened pre-expanded from then on and
   never auto-collapsed — turning a long tool-using answer into a very
   tall scroll.
3. The composer had no shell-style prompt recall: Up/Down did nothing from
   an empty draft, so resending or lightly editing an earlier question
   meant finding it in the transcript and retyping it.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
THINK_BLOCK_QML = (ROOT / "services" / "ai" / "blocks" / "AiMessageThinkBlock.qml").read_text(encoding="utf-8")
AI_MESSAGE_QML = (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessage.qml").read_text(encoding="utf-8")
PERSISTENT_QML = (ROOT / "modules" / "common" / "Persistent.qml").read_text(encoding="utf-8")
SIDEBAR_QML = (ROOT / "modules" / "ii" / "sidebarPolicies" / "AiChat.qml").read_text(encoding="utf-8")
SEARCH_COMPOSER_QML = (ROOT / "modules" / "ii" / "overview" / "AiSearchComposer.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class NotificationPerExchangeTests(unittest.TestCase):
    def test_mark_done_only_notifies_when_no_follow_up_is_coming(self):
        body = body_between(AI_QML, "function markDone(message: AiMessageData) {", "\n    function ")
        self.assertIn("root.notifyResponseFinished(message)", body)
        # The notify call must be conditioned on the message carrying no
        # tool calls — a message that issued one always gets a follow-up
        # turn from `AiToolBroker.finish()`, sync or async, so it is not
        # the end of the exchange the user is waiting to hear about.
        guarded = body.split("root.notifyResponseFinished(message)", 1)[0]
        self.assertIn("toolCalls", guarded.splitlines()[-3:][0] + "".join(guarded.splitlines()[-3:]))
        self.assertIn("=== 0", guarded[-200:])

    def test_usage_and_persistence_still_happen_for_every_message(self):
        # Only the notification is gated — accounting, autosave and the
        # responseFinished signal must keep firing for every finished
        # request, tool round-trip or not, or intermediate turns would be
        # lost on a crash and usage stats would undercount real requests.
        body = body_between(AI_QML, "function markDone(message: AiMessageData) {", "\n    function ")
        self.assertIn("AiUsage.recordResponse(", body)
        self.assertIn("root.commitRunSession(", body)
        self.assertIn("root.responseFinished({", body)


class ThinkingAutoCollapseTests(unittest.TestCase):
    def test_no_sticky_global_expand_preference_remains(self):
        for source in (THINK_BLOCK_QML, AI_MESSAGE_QML, PERSISTENT_QML):
            self.assertNotIn("expandThoughts", source)

    def test_inline_think_block_collapses_when_its_own_turn_completes(self):
        self.assertIn("onCompletedChanged: root.expanded = !root.completed", THINK_BLOCK_QML)
        self.assertIn("Component.onCompleted: root.expanded = !root.completed", THINK_BLOCK_QML)
        toggle = body_between(THINK_BLOCK_QML, "function toggle() {", "\n    }")
        self.assertNotIn("Persistent", toggle)

    def test_reasoning_row_forces_collapse_once_the_thought_is_complete(self):
        thinking_row = body_between(AI_MESSAGE_QML, "id: stepThinkingRow", "\n\n                AiActivityRow {\n                    // What it looked up")
        self.assertIn("onThoughtCompleteChanged", thinking_row)
        self.assertNotIn("Persistent", thinking_row)

    def test_search_and_tool_rows_reset_on_done(self):
        search_row = body_between(AI_MESSAGE_QML, "id: stepSearchRow", "\n\n                Repeater {")
        self.assertIn("function onStepDoneChanged()", search_row)
        self.assertIn("searchExpanded = false", search_row)
        tool_row = body_between(AI_MESSAGE_QML, "id: stepToolRow", "\n                    }\n                }\n            }\n\n            // The common case")
        self.assertIn("function onStepDoneChanged()", tool_row)
        self.assertIn("toolExpanded = false", tool_row)


class MultiStepAccordionTests(unittest.TestCase):
    """A tool round-trip issues one assistant message per network turn.
    Each used to render as a full turn of its own — one bubble's worth of
    chrome per step — which turned an answer that searched the web and
    read a page into a page-long scroll. Every step but the last is now
    hidden from the transcript's own model, and the terminal message folds
    all of them, itself included, into one line that expands on request.
    """

    def test_non_terminal_assistant_messages_are_computed_once(self):
        body = body_between(AI_QML, "readonly property var nonTerminalRunMessageIds: {", "\n    }")
        self.assertIn('=== "assistant"', body)

    def test_every_transcript_filter_uses_the_shared_predicate(self):
        # All five duplicated filters in the sidebar, and the Search
        # panel's own, must ask the same question or their indices
        # (scroll anchors, turn navigation, the list itself) drift apart.
        sidebar = SIDEBAR_QML.count("Ai.isTranscriptEntry(id)")
        self.assertGreaterEqual(sidebar, 5)
        search_panel = (ROOT / "modules" / "ii" / "overview" / "AiChatPanel.qml").read_text(encoding="utf-8")
        self.assertIn("Ai.isTranscriptEntry(id)", search_panel)

    def test_leading_activity_messages_walks_backward_from_the_id(self):
        body = body_between(AI_QML, "function leadingActivityMessages(id: string): var {", "\n    }")
        self.assertIn("ids.indexOf(id)", body)
        self.assertIn('role !== "assistant"', body)
        self.assertIn("leading.unshift(", body)

    def test_a_tool_round_trip_is_folded_across_its_hidden_carriers(self):
        """The carrier that hands a tool's result back to the model is
        written with `role: "user"` because that is what the wire format
        wants, and it sits between the two assistant messages of every
        round-trip. Both sides of the fold used to read plain adjacency in
        `messageIDs`, so no continuation was ever recognised as one: a turn
        that called three tools drew three "Thought for ..." rows and named
        the model three times instead of folding into a single line.
        """
        carrier = body_between(AI_QML, "function isHiddenCarrier(id: string): bool {", "\n    }")
        self.assertIn("visibleToUser === false", carrier)

        # Looking ahead for the next continuation steps over carriers.
        hidden = body_between(AI_QML, "readonly property var nonTerminalRunMessageIds: {", "\n    }")
        self.assertIn("root.isHiddenCarrier(ids[next])", hidden)
        self.assertNotIn("ids[i + 1]", hidden)

        # Walking back to collect the steps skips them the same way.
        leading = body_between(AI_QML, "function leadingActivityMessages(id: string): var {", "\n    }")
        self.assertIn("root.isHiddenCarrier(ids[i])", leading)

    def test_message_computes_its_own_step_group(self):
        body = body_between(AI_MESSAGE_QML, "readonly property var stepGroup:", "\n")
        self.assertIn("Ai.leadingActivityMessages(root.messageId)", body)

    def test_the_summary_row_is_live_only_for_multi_step_turns_and_final_for_any_activity(self):
        row = body_between(AI_MESSAGE_QML, "id: stepsSummaryRow", "\n            }\n        }")
        self.assertIn("shown: root.done ? root.hasActivity : root.stepGroup.length > 1", row)
        self.assertIn("root.stepGroup.length", row)

    def test_the_summary_row_is_open_live_and_folds_when_done(self):
        row = body_between(AI_MESSAGE_QML, "id: stepsSummaryRow", "\n            }\n        }")
        self.assertIn("expanded: stepsSummaryRow.userChoice ? stepsSummaryRow.userExpanded : root.streaming", row)
        self.assertIn("function onDoneChanged()", row)
        self.assertIn("stepsSummaryRow.userExpanded = false", row)

    def test_the_summary_row_expands_into_every_step_via_step_activity(self):
        row = body_between(AI_MESSAGE_QML, "id: stepsSummaryRow", "\n            }\n        }")
        self.assertIn("values: root.stepGroup", row)
        self.assertIn("delegate: StepActivity {", row)

    def test_step_activity_is_self_contained_reused_directly_and_in_the_group(self):
        # No free `root.*` reference: it is instantiated both directly and
        # from inside the summary row's own Repeater delegate.
        component = body_between(AI_MESSAGE_QML, "component StepActivity: Item {", "\n            }\n\n            // While a single-step")
        self.assertNotIn("root.", component)
        self.assertIn("required property var stepData", component)


class CompletedActivityAccordionTests(unittest.TestCase):
    def test_completed_activity_uses_one_outer_accordion_for_single_step_turns(self):
        row = body_between(AI_MESSAGE_QML, "id: stepsSummaryRow", "\n            }\n        }")
        self.assertIn("shown: root.done ? root.hasActivity : root.stepGroup.length > 1", row)
        self.assertIn("label: root.done", row)
        self.assertIn("root.finalActivityLabel", row)
        self.assertIn("values: root.stepGroup", row)

    def test_inner_activity_rows_are_hidden_until_the_final_row_is_expanded(self):
        self.assertIn("visible: !root.done && root.stepGroup.length <= 1", AI_MESSAGE_QML)
        self.assertIn("shown: root.done ? root.hasActivity : root.stepGroup.length > 1", AI_MESSAGE_QML)

    def test_short_thinking_also_keeps_the_completed_outer_accordion(self):
        summary = body_between(AI_MESSAGE_QML, "function summarizeActivity(): var {", "\n    readonly property var activitySummary")
        self.assertIn('hasThought = hasThought || String(step?.thought ?? "").length > 0', summary)
        self.assertIn("hasActivity: hasActivity", summary)


class PromptHistoryTests(unittest.TestCase):
    def test_ai_exposes_the_users_own_prompts_oldest_first(self):
        body = body_between(AI_QML, "readonly property var ownPromptHistory: {", "\n    }")
        self.assertIn('role !== "user"', body)
        self.assertIn("visibleToUser === false", body)

    def _assert_composer_wired(self, source: str, field_name: str):
        self.assertIn("property int promptHistoryIndex: -1", source)
        self.assertIn("function stepPromptHistory(", source)
        step = body_between(source, "function stepPromptHistory(", "\n    }")
        self.assertIn("Ai.ownPromptHistory", step)
        # Up walks older (negative delta), Down walks newer / back to the
        # live draft (positive delta) — never the other way around.
        self.assertIn("delta > 0", step)
        self.assertIn("delta < 0", step)
        keys = source.split("Keys.onPressed", 1)[1]
        self.assertIn("Qt.Key_Up && event.modifiers === Qt.NoModifier", keys)
        self.assertIn("Qt.Key_Down && event.modifiers === Qt.NoModifier", keys)
        self.assertIn(f"{field_name}.text.length === 0 || root.promptHistoryIndex !== -1", keys)

    def test_sidebar_composer_recalls_history_on_bare_arrows(self):
        self._assert_composer_wired(SIDEBAR_QML, "messageInputField")

    def test_search_composer_recalls_history_on_bare_arrows(self):
        self._assert_composer_wired(SEARCH_COMPOSER_QML, "draftInput")

    def test_manual_edits_break_out_of_the_history_walk(self):
        for source, anchor in (
            (SIDEBAR_QML, "onTextChanged: {"),
            (SEARCH_COMPOSER_QML, "function onDraftChanged() {"),
        ):
            body = body_between(source, anchor, "\n")
            # Just the anchor line is not enough context in every file;
            # widen to the next closing brace of that handler instead.
        sidebar_on_text_changed = body_between(SIDEBAR_QML, "onTextChanged: {\n                                    // Kept per chat", "root.resetPromptHistory();")
        self.assertIn("navigatingPromptHistory", sidebar_on_text_changed)
        search_on_draft_changed = body_between(SEARCH_COMPOSER_QML, "function onDraftChanged() {", "root.resetPromptHistory();")
        self.assertIn("navigatingPromptHistory", search_on_draft_changed)


if __name__ == "__main__":
    unittest.main()


class VanishingTurnTests(unittest.TestCase):
    """Two ways a turn could disappear out from under the reader.

    Both were reported from real use, minutes apart.

    1. A finished answer went blank and only came back after closing and
       reopening the chat. `AiMessage.opacity` is bound to
       `shouldAnimateArrival`, and the arrival animation is the only thing
       that ever drives it back up. A turn that was still streaming when a
       reveal was requested declined the entrance and left the token
       unclaimed, so the instant it stopped streaming `reopening` turned
       true, the binding drove opacity to zero, and nothing was left to
       animate it back.
    2. A prompt was accepted, the composer cleared, and the submission then
       rolled back — leaving no message, no chat, and no text: the draft is
       cleared once the request is on the wire and was never restored when
       the transaction failed after that point.
    """

    def test_declining_an_entrance_writes_the_turn_visible(self):
        """Declining has to drop the bindings, not just skip the animation.

        `opacity` and the arrival transform are bound to
        `shouldAnimateArrival`. An answer is built while it is still
        streaming, which is exactly when that condition reads false, so it
        declines — and if the decline only returns, the bindings survive with
        no animation ever having run to break them. The answer then finishes,
        `streaming` goes false against an `arriving` that is `Date.now()`
        based and so never re-evaluates, the condition flips true, and the
        binding drives opacity to zero with nothing left to raise it. The
        turn stayed laid out and kept answering the mouse; it was simply
        never painted again until the chat was reopened.
        """
        body = body_between(AI_MESSAGE_QML, "function startArrival() {", "\n    }")
        early_return = body.split("if (root.reopening)", 1)[0]
        self.assertIn("root.settleVisible()", early_return)

        settle = body_between(AI_MESSAGE_QML, "function settleVisible() {", "\n    }")
        # Written, not bound: that is the whole point.
        self.assertIn("root.opacity = 1", settle)
        self.assertIn("arrivalTransform.y = 0", settle)
        self.assertIn("root.handledRevealToken = root.transcriptRevealToken", settle)

    def test_a_finished_answer_settles_rather_than_replaying_an_entrance(self):
        # The token never changes in this path, so `onTranscriptRevealTokenChanged`
        # cannot be the only place the decision is made — and the answer has
        # been on screen throughout, so it must not fade in over itself.
        self.assertIn("onStreamingChanged:", AI_MESSAGE_QML)
        body = body_between(AI_MESSAGE_QML, "onStreamingChanged:", "\n    }")
        self.assertIn("!root.streaming", body)
        self.assertIn("root.settleVisible()", body)
        self.assertNotIn("startArrival", body)

    def test_a_reveal_is_never_played_over_a_live_answer(self):
        body = body_between(SIDEBAR_QML, "function revealTranscript() {", "\n    }")
        self.assertIn("Ai.isGenerating", body)
        self.assertIn("return", body)

    def test_a_rolled_back_submission_gives_the_prompt_back(self):
        body = body_between(AI_QML, "function restoreDraftAfterFailedSubmission(pending) {", "\n    }")
        self.assertIn("pending?.draftTextAtSubmit", body)
        self.assertIn("root.draft = text", body)
        self.assertIn("root.draftRestored(text)", body)
        # Never over the top of something newer the user has started typing.
        self.assertIn("root.draft.length > 0", body)

    def test_the_failure_path_is_the_one_that_restores(self):
        # `finishPendingSubmission` handles failure and cancellation only —
        # the success path clears `pendingSubmission` inline after the
        # request starts — so restoring there cannot resurrect a sent prompt.
        body = body_between(AI_QML, "function finishPendingSubmission(pending, cancelled, reason) {", "\n    function ")
        self.assertIn("root.restoreDraftAfterFailedSubmission(pending)", body)
        self.assertIn("root.rollbackPendingMessages(pending)", body)


class ComposerAndAttachmentChromeTests(unittest.TestCase):
    """Two pieces of chrome that misbehaved on a narrow sidebar."""

    def test_the_composer_model_pill_is_capped_by_what_is_actually_free(self):
        """A fraction of the row is not the same as the room left in it.

        The cap was a flat 62% of the composer row. The plus, the microphone
        and the send button plus their four gaps take about 148px, so on any
        row narrower than ~390px the two together came to more than the row.
        A RowLayout will not shrink an item below its implicit width, so the
        overflow went to the trailing controls and pushed the send button off
        the edge instead of cutting the model's name.
        """
        body = body_between(SIDEBAR_QML, "id: composerModelPill", "contentItem: RowLayout {")
        self.assertNotIn("composerControlsRow.width * 0.62", body)
        # Counted, not guessed: three circles and one gap more than circles.
        self.assertIn("readonly property int fixedCircles", body)
        self.assertIn("composerControlExtent * composerModelPill.fixedCircles", body)
        self.assertIn("root.composerGap * (composerModelPill.fixedCircles + 1)", body)
        # And the pill must say it can be squeezed, or the layout overflows
        # rather than shrinking it.
        self.assertIn("Layout.minimumWidth: root.composerControlExtent", body)

    def test_the_pill_and_its_label_both_measure_against_that_cap(self):
        body = body_between(SIDEBAR_QML, "id: composerModelPill", "StyledToolTip {")
        # Both the pill's own width and the elide budget for the name.
        self.assertEqual(body.count("composerModelPill.widthLimit"), 3)

    def test_an_attached_document_only_shows_its_path_on_hover(self):
        """`StyledToolTip` reads `parent.hovered` and treats a parent that has
        no such property as *always visible*. The chip for a sent file is a
        plain Rectangle, so every attached document pinned its full path open
        over the transcript from the moment the chat was opened.
        """
        body = body_between(AI_MESSAGE_QML, "id: sentFile", "\n            }\n        }")
        self.assertIn("HoverHandler", body)
        self.assertIn("extraVisibleCondition: false", body)
        self.assertIn("alternativeVisibleCondition: sentFileHover.hovered", body)
