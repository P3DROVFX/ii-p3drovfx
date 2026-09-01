#!/usr/bin/env python3
"""Regression contracts for the QML AI draft lifecycle.

The composer can accept input before its on-disk draft store has finished
loading.  These checks keep that early input, and a successful send that
clears it, from being overwritten by the delayed hydration path.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
LAUNCHER_SEARCH_QML = (ROOT / "services" / "LauncherSearch.qml").read_text(encoding="utf-8")
SEARCH_WIDGET_QML = (ROOT / "modules" / "ii" / "overview" / "SearchWidget.qml").read_text(encoding="utf-8")
SEARCH_BAR_QML = (ROOT / "modules" / "ii" / "overview" / "SearchBar.qml").read_text(encoding="utf-8")
OVERVIEW_QML = (ROOT / "modules" / "ii" / "overview" / "Overview.qml").read_text(encoding="utf-8")
SEARCH_PANEL_QML = (ROOT / "modules" / "ii" / "overview" / "AiChatPanel.qml").read_text(encoding="utf-8")


class AiDraftLifecycleContractTests(unittest.TestCase):
    def test_preload_draft_mutations_are_flushed_before_hydration(self):
        self.assertTrue("property var pendingDraftMutations" in AI_QML)
        self.assertTrue("function writeOrStageDraft" in AI_QML)
        self.assertTrue("function flushPendingDraftMutations" in AI_QML)
        self.assertTrue("root.flushPendingDraftMutations()" in AI_QML)

    def test_started_submission_clears_the_draft_session_captured_at_submit(self):
        self.assertTrue("draftSessionId: root.sessionDraftId()" in AI_QML)
        self.assertTrue("root.clearDraftForSession(pending.draftSessionId" in AI_QML)

    def test_leaving_ai_resets_only_the_search_surface_state(self):
        self.assertTrue("function resetAiSearchState" in SEARCH_WIDGET_QML)
        self.assertTrue("root.searchingText = \"\"" in SEARCH_WIDGET_QML)
        self.assertTrue("root.resetAiSearchState(false)" in SEARCH_WIDGET_QML)

    def test_regular_open_clears_stale_query_unless_this_open_has_an_intent(self):
        opening_handler = OVERVIEW_QML.split("function onOverviewOpenChanged()", 1)[1].split("HyprlandFocusGrab", 1)[0]
        self.assertIn("GlobalStates.activeSearchQuery", opening_handler)
        self.assertIn("const hasIncomingQuery", opening_handler)
        self.assertIn("if (!hasIncomingQuery)", opening_handler)
        self.assertIn("searchWidget.cancelSearch()", opening_handler)

    def test_cancel_search_clears_the_text_input(self):
        self.assertIn('function cancelSearch()', SEARCH_WIDGET_QML)
        self.assertIn('searchBar.searchInput.text = ""', SEARCH_WIDGET_QML)
        self.assertIn('root.searchingText = ""', SEARCH_WIDGET_QML)
        self.assertIn('LauncherSearch.query = ""', SEARCH_WIDGET_QML)

    def test_normal_search_is_cleared_when_the_overview_closes(self):
        """A lazily recreated Overview can miss its next opening signal.

        The search surface therefore has to discard its local query at the
        close boundary too; otherwise a normal query survives until the next
        SearchWidget instance is constructed.
        """
        close_handler = SEARCH_WIDGET_QML.split("function onOverviewOpenChanged()", 1)[1].split("readonly property bool showSuggestionsPanel", 1)[0]
        self.assertIn("if (!GlobalStates.overviewOpen)", close_handler)
        self.assertIn("root.cancelSearch()", close_handler)

    def test_launcher_search_close_reset_can_resolve_global_states(self):
        """The singleton owns a close reset and must import its global scope."""
        self.assertIn("import qs\n", LAUNCHER_SEARCH_QML)
        self.assertIn("target: GlobalStates", LAUNCHER_SEARCH_QML)
        self.assertIn("root.query = \"\"", LAUNCHER_SEARCH_QML)

    def test_search_chat_escape_and_arrow_navigation_are_surface_level(self):
        self.assertIn('property bool activeSurface', SEARCH_PANEL_QML)
        self.assertIn('event.key === Qt.Key_Escape', SEARCH_PANEL_QML)
        self.assertIn('root.requestBackToSearch()', SEARCH_PANEL_QML)
        self.assertIn('function handleEscape()', SEARCH_WIDGET_QML)
        self.assertIn('onActivated: searchWidget.handleEscape()', OVERVIEW_QML)
        self.assertIn('Qt.Key_PageUp', SEARCH_PANEL_QML)
        self.assertIn('Qt.Key_PageDown', SEARCH_PANEL_QML)
        self.assertIn('root.navigateUp()', SEARCH_PANEL_QML)
        self.assertIn('root.navigateDown()', SEARCH_PANEL_QML)

    def test_search_chat_captures_escape_before_focused_child_controls(self):
        self.assertIn("Keys.priority: Keys.BeforeItem", SEARCH_PANEL_QML)
        self.assertIn("function returnToSearch()", SEARCH_PANEL_QML)
        self.assertIn("host.exitAiMode()", SEARCH_PANEL_QML)
        self.assertIn('property: "searchHost"', SEARCH_WIDGET_QML)
        brain_back = SEARCH_PANEL_QML.split("id: brainBackButton", 1)[1].split("// AI Task Title", 1)[0]
        escape_branch = brain_back.split("event.key === Qt.Key_Escape", 1)[1].split("event.key === Qt.Key_Tab", 1)[0]
        self.assertIn("root.returnToSearch()", escape_branch)

    def test_history_reloads_the_selected_chat_and_supports_legacy_content(self):
        self.assertIn('Always reload the selected file', AI_QML)
        self.assertIn('root.sessions.openSession(sessionId)', AI_QML)
        self.assertIn('const persistedRaw = String(data?.rawContent ?? "")', AI_QML)
        self.assertIn('String(data?.content ?? "")', AI_QML)
        self.assertIn('function refreshVisibleMessageIds()', SEARCH_PANEL_QML)

    def test_search_query_handoff_does_not_echo_through_the_hidden_field(self):
        self.assertIn('property bool syncingSearchText', SEARCH_BAR_QML)
        self.assertIn('if (!root.syncingSearchText)', SEARCH_BAR_QML)


if __name__ == "__main__":
    unittest.main()
