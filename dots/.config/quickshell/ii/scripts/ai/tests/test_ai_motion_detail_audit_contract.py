"""Contracts for the AI chat movement-and-detail audit items."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
CONFIG = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
SETTINGS = (ROOT / "modules/settings/configs/AiAssistantConfig.qml").read_text(encoding="utf-8")
CHAT = (ROOT / "modules/ii/sidebarPolicies/AiChat.qml").read_text(encoding="utf-8")
MESSAGE = (ROOT / "modules/ii/sidebarPolicies/aiChat/AiMessage.qml").read_text(encoding="utf-8")
CONTROL_BAR = (ROOT / "modules/ii/sidebarPolicies/aiChat/ChatControlBar.qml").read_text(encoding="utf-8")
PICKER = (ROOT / "services/ai/blocks/AiModelPickerPopover.qml").read_text(encoding="utf-8")
RIPPLE_BUTTON = (ROOT / "modules/common/widgets/RippleButton.qml").read_text(encoding="utf-8")
STYLED_LIST_VIEW = (ROOT / "modules/common/widgets/StyledListView.qml").read_text(encoding="utf-8")
STYLED_FLICKABLE = (ROOT / "modules/common/widgets/StyledFlickable.qml").read_text(encoding="utf-8")
SEARCH_SURFACE = (ROOT / "services/ai/AiSearchSurface.qml").read_text(encoding="utf-8")
SEARCH_NAVIGATOR = (ROOT / "services/ai/AiSearchNavigator.qml").read_text(encoding="utf-8")
AI_SERVICE = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")


class MotionPreferenceTests(unittest.TestCase):
    def test_one_persisted_preference_drives_search_and_sidebar(self):
        self.assertIn("property bool reducedMotion: false", CONFIG)
        self.assertIn("Reduce motion in AI chat", SETTINGS)
        self.assertIn("Config.options.sidebar.ai.reducedMotion", SEARCH_SURFACE)
        self.assertIn("Config.options.sidebar.ai.reducedMotion", SEARCH_NAVIGATOR)
        self.assertIn("readonly property bool reducedMotion", CHAT)

    def test_reopening_only_staggers_settled_visible_messages(self):
        for token in (
            "transcriptRevealToken",
            "transcriptRevealDelay",
            "!root.streaming",
            "Appearance.animation.elementMoveEnter",
            "Appearance.rounding.verysmall",
        ):
            with self.subTest(token=token):
                self.assertIn(token, MESSAGE)


class DetailTests(unittest.TestCase):
    def test_composer_has_a_context_ruler_that_warns_before_pruning(self):
        for token in (
            "id: contextRuler",
            "Ai.estimatedContextTokens",
            "Ai.estimateMessageTokens({ attachments: Ai.attachments })",
            "Saved memory",
            "pruningOnNextPrompt",
            "summarize the oldest turns",
        ):
            with self.subTest(token=token):
                self.assertIn(token, CHAT)

    def test_activity_rows_are_linked_by_an_animated_vertical_ruler(self):
        self.assertIn("id: timelineRuler", MESSAGE)
        self.assertIn("visibleStepCount > 1", MESSAGE)
        self.assertIn("Appearance.animation.elementMoveSmall", MESSAGE)

    def test_approval_body_exits_while_a_result_row_enters(self):
        self.assertIn("approvalCardKinds", AI_SERVICE)
        self.assertIn("resolvedApprovalStates", AI_SERVICE)
        self.assertIn("id: pendingCard", MESSAGE)
        self.assertIn("id: resolutionRow", MESSAGE)
        self.assertIn("Appearance.animation.elementMoveExit", MESSAGE)
        self.assertIn("Appearance.animation.elementMoveEnter", MESSAGE)

    def test_small_transcript_details_have_direct_interactions(self):
        for token in (
            "newItemCount",
            "onDoubleClicked: root.editRequested",
            "function selectPinnedModel",
            "DropArea",
        ):
            with self.subTest(token=token):
                self.assertIn(token, CHAT if token != "onDoubleClicked: root.editRequested" else MESSAGE)
        self.assertIn("function pinnedModelShortcut", PICKER)
        self.assertIn("function modelSelectionTooltip", PICKER)
        self.assertIn("id: modelSelectButton", PICKER)
        self.assertIn("root.modelSelectionTooltip", PICKER)
        self.assertIn("function togglePinned", PICKER)
        self.assertIn("id: modelActionCircle", PICKER)
        self.assertIn("id: modelActionMouse", PICKER)
        self.assertIn('modelRow.pinned ? "keep_off" : "keep"', PICKER)
        self.assertIn("function modelPinTooltip", PICKER)
        self.assertIn("onClicked: root.togglePinned(modelRow.entry.id)", PICKER)
        self.assertIn('groupId: "pinned"', PICKER)
        self.assertIn("const pinnedIds", PICKER)
        self.assertIn("!pinnedIds.includes(model.id)", PICKER)
        self.assertIn("id: modelCheckIcon", PICKER)
        self.assertIn("id: modelPinIcon", PICKER)
        self.assertIn("modelChipTooltip", CONTROL_BAR)

    def test_shared_buttons_enable_hover_for_cursor_and_tooltips(self):
        self.assertIn("    hoverEnabled: true\n", RIPPLE_BUTTON)
        self.assertIn("hoverEnabled: root.hoverEnabled", RIPPLE_BUTTON)

    def test_scroll_acceleration_does_not_cover_delegate_cursors(self):
        self.assertIn("WheelHandler", STYLED_LIST_VIEW)
        self.assertIn("WheelHandler", STYLED_FLICKABLE)
        self.assertNotIn("MouseArea {", STYLED_LIST_VIEW)
        self.assertNotIn("MouseArea {", STYLED_FLICKABLE)


if __name__ == "__main__":
    unittest.main()
