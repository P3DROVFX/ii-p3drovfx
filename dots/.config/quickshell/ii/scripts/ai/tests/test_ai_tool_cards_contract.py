#!/usr/bin/env python3
"""A tool that needs to show something adds a card, and nothing else.

Every tool with something to display used to add a property to the message, a
branch to the serializer and a Loader to the transcript — three edits in three
files, per tool, forever. Cards are one array with a `kind`, so the transcript
picks a component and the serializer writes the array without knowing what is
in it. These tests pin that, and pin the two things that break quietly: an old
session losing its card, and a newer session's unknown card taking the whole
transcript down with it.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
DATA = (ROOT / "services" / "ai" / "AiMessageData.qml").read_text(encoding="utf-8")
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
MESSAGE = (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessage.qml").read_text(encoding="utf-8")
DIFF_CARD = (ROOT / "services" / "ai" / "blocks" / "AiConfigDiffCard.qml").read_text(encoding="utf-8")
REQUEST = (ROOT / "services" / "ai" / "AiRequest.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class ShapeTests(unittest.TestCase):
    def test_the_message_carries_one_array_not_a_field_per_tool(self):
        self.assertIn("property var toolCards: []", DATA)

    def test_the_retired_fields_are_marked_as_read_only_history(self):
        legacy = body_between(DATA, "// Legacy, kept so a session saved", "property int toolCallSerial")
        self.assertIn("pendingMemory", legacy)
        self.assertIn("pendingChanges", legacy)

    def test_nothing_writes_to_the_retired_fields_any_more(self):
        # Only the migration reads them, and it reads from parsed JSON rather
        # than from a live message.
        for forbidden in ("message.pendingChanges =", "message.pendingMemory ="):
            with self.subTest(token=forbidden):
                self.assertNotIn(forbidden, AI_QML)

    def test_a_card_has_everything_needed_to_draw_it_without_the_tool(self):
        adder = body_between(AI_QML, "function addToolCard(message, card)", "/** Changes one card")
        for field in ("callId", "tool", "kind", "state", "summary", "data", "createdAt"):
            with self.subTest(field=field):
                self.assertIn(f"{field}:", adder)

    def test_updating_a_card_finds_it_by_its_call(self):
        updater = body_between(AI_QML, "function updateToolCard(message, callId: string", "function toolCardFor")
        self.assertIn("String(card.callId) !== String(callId)", updater)
        self.assertIn("Object.assign({}, card, changes", updater)


class RenderingTests(unittest.TestCase):
    def test_the_transcript_picks_a_component_by_kind(self):
        self.assertIn("Ai.visibleToolCards(root.messageData)", MESSAGE)
        self.assertIn('case "settingsDiff":', MESSAGE)
        self.assertIn('case "memoryFact":', MESSAGE)

    def test_external_read_cards_are_wired_to_the_shared_transcript(self):
        for kind, component in (
            ("gmailResults", "gmailResultsCard"),
            ("sportsResults", "sportsResultsCard"),
        ):
            with self.subTest(kind=kind):
                self.assertIn(f'case "{kind}":', MESSAGE)
                self.assertIn(f"id: {component}", MESSAGE)

    def test_completed_settings_results_remain_visible_with_pending_cards(self):
        # `settingsResults` was joined by `fileResults` (Phase 2): both are
        # "the result is the point" cards, kept once done the same way a
        # search engine's results page does not disappear once read. The
        # allowlist moved into `resultCardKinds` so a new one is one entry,
        # not a second inline check.
        visible_cards = body_between(AI_QML, "function visibleToolCards(message): var", "/** The broker's key")
        self.assertIn('card.state === "pending"', visible_cards)
        self.assertIn("root.resultCardKinds.indexOf(card.kind) >= 0", visible_cards)
        kinds = body_between(AI_QML, "readonly property var resultCardKinds:", "\n\n    function visibleToolCards")
        self.assertIn('"settingsResults"', kinds)
        self.assertIn('"fileResults"', kinds)

    def test_an_unknown_kind_still_draws_something(self):
        # A session written by a newer build must open, not blank out.
        self.assertIn("return unknownCard;", MESSAGE)
        self.assertIn("id: unknownCard", MESSAGE)

    def test_no_loader_tests_a_tool_specific_property_any_more(self):
        for gone in ("messageData?.pendingChanges?.length", "messageData?.pendingMemory?.length"):
            with self.subTest(token=gone):
                self.assertNotIn(gone, MESSAGE)

    def test_the_diff_card_reads_its_own_card(self):
        self.assertIn("property var card: null", DIFF_CARD)
        self.assertIn("root.card?.data?.changes", DIFF_CARD)
        self.assertNotIn("messageData?.pendingChanges", DIFF_CARD)

    def test_search_and_sidebar_draw_the_same_cards(self):
        # Both surfaces render AiMessage, so a card added for one appears in
        # the other by construction. This guards the shared component.
        panel = (ROOT / "modules" / "ii" / "overview" / "AiChatPanel.qml").read_text(encoding="utf-8")
        self.assertIn("AiMessage", panel)


class PersistenceTests(unittest.TestCase):
    def test_cards_are_written_with_the_message(self):
        self.assertIn('"toolCards": JSON.parse(JSON.stringify(Array.from(message.toolCards ?? [])))', AI_QML)

    def test_a_session_saved_before_cards_still_shows_them(self):
        migration = body_between(AI_QML, "function toolCardsFromJson(data: var)", "function messageFromJson")
        self.assertIn("data?.pendingChanges", migration)
        self.assertIn("data?.pendingMemory", migration)
        self.assertIn('kind: "settingsDiff"', migration)
        self.assertIn('kind: "memoryFact"', migration)

    def test_a_session_that_already_has_cards_is_left_alone(self):
        migration = body_between(AI_QML, "function toolCardsFromJson(data: var)", "function messageFromJson")
        self.assertIn("if (stored.length > 0)", migration)
        self.assertIn("return stored", migration)

    def test_an_in_flight_request_snapshots_the_cards(self):
        self.assertIn("toolCards: JSON.parse(JSON.stringify(message.toolCards ?? []))", REQUEST)
        self.assertNotIn("pendingChanges:", REQUEST)


if __name__ == "__main__":
    unittest.main()
