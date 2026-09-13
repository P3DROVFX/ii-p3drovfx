#!/usr/bin/env python3
"""The mic button itself: how a person actually starts a dictation.

`AiVoiceService` only ever supplied the state machine; nothing called
`startRecording()` from either composer until this pass. These tests pin the
two things most likely to regress silently, because both fail without ever
raising a QML error:

  * Both composers share one `Ai.voiceService`. Without tagging each call
    with a surface name ("sidebar" / "search") and checking it back before
    consuming a finished draft, a recording started in one would also insert
    itself into the other composer if it happened to be loaded, hidden, in
    the background.

  * The button must disable itself while transcribing — otherwise a second
    click mid-transcription races `startRecording()` against a `state` that
    is neither "idle" nor "pending-start", which the function already
    refuses, but a disabled button is the honest signal instead of a click
    that silently does nothing.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SIDEBAR = (ROOT / "modules" / "ii" / "sidebarPolicies" / "AiChat.qml").read_text(encoding="utf-8")
SEARCH = (ROOT / "modules" / "ii" / "overview" / "AiSearchComposer.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class SidebarMicButtonTests(unittest.TestCase):
    def button_block(self) -> str:
        return body_between(SIDEBAR, 'ComposerCircleButton { // Dictate a message with the local voice backend',
                             "\n                                    RippleButton { // Send button")

    def test_hidden_when_voice_is_turned_off_in_settings(self):
        self.assertIn("visible: Config.options.ai.voice.enabled", self.button_block())

    def test_disabled_while_transcribing(self):
        self.assertIn('enabled: Ai.voiceService.state !== "transcribing"', self.button_block())

    def test_recording_click_stops_rather_than_starting_again(self):
        block = self.button_block()
        self.assertIn('case "recording":\n                                                Ai.voiceService.stopRecording();', block)

    def test_error_click_resets_before_retrying(self):
        block = self.button_block()
        error_branch = body_between(block, 'case "error":', 'default:')
        self.assertIn("Ai.voiceService.cancel();", error_branch)
        self.assertIn('Ai.voiceService.startRecording("sidebar");', error_branch)

    def test_idle_click_tags_the_recording_as_the_sidebar_surface(self):
        triggered = body_between(self.button_block(), "onTriggered: {", "\n\n                                        StyledToolTip")
        default_branch = body_between(triggered, "default:", "\n                                            }")
        self.assertIn('Ai.voiceService.startRecording("sidebar");', default_branch)

    def test_review_consumption_is_gated_to_the_sidebar_surface(self):
        connections = body_between(
            SIDEBAR,
            "target: Ai.voiceService\n        function onStateChanged() {",
            "\n    }",
        )
        self.assertIn('Ai.voiceService.activeSurface !== "sidebar"', connections)
        self.assertIn("Ai.voiceService.attachDraft(text)", connections)
        self.assertIn("messageInputField.text", connections)

    def test_the_review_handler_does_not_claim_the_search_surface(self):
        connections = body_between(
            SIDEBAR,
            "target: Ai.voiceService\n        function onStateChanged() {",
            "\n    }",
        )
        self.assertNotIn('"search"', connections)


class SearchMicButtonTests(unittest.TestCase):
    def voice_button_component(self) -> str:
        return body_between(SEARCH, "component VoiceButton: RailIconButton {", "\n    }")

    def test_hidden_when_voice_is_turned_off_in_settings(self):
        self.assertIn("visible: Config.options.ai.voice.enabled", self.voice_button_component())

    def test_disabled_while_transcribing(self):
        self.assertIn('enabled: Ai.voiceService.state !== "transcribing"', self.voice_button_component())

    def test_click_delegates_to_a_single_shared_activate_function(self):
        # Both the mouse click and the Enter/Space key path must go through
        # the same function, or keyboard and pointer users get different
        # behaviour for the same button.
        self.assertIn("onClicked: root.activateVoice()", self.voice_button_component())
        keys_block = body_between(
            SEARCH,
            "VoiceButton {\n                        id: voiceButton",
            "\n                    SendButton {",
        )
        self.assertIn("root.activateVoice();", keys_block)

    def test_activate_voice_tags_the_recording_as_the_search_surface(self):
        fn = body_between(SEARCH, "function activateVoice() {", "\n    }")
        self.assertIn('Ai.voiceService.startRecording("search");', fn)
        self.assertIn("Ai.voiceService.stopRecording();", fn)
        error_branch = body_between(fn, 'case "error":', "default:")
        self.assertIn("Ai.voiceService.cancel();", error_branch)

    def test_review_consumption_is_gated_to_the_search_surface(self):
        connections = body_between(
            SEARCH,
            "target: Ai.voiceService\n        function onStateChanged() {",
            "\n    }",
        )
        self.assertIn('Ai.voiceService.activeSurface !== "search"', connections)
        self.assertIn("Ai.voiceService.attachDraft(text)", connections)
        self.assertIn("root.insertVoiceText(text)", connections)

    def test_the_review_handler_does_not_claim_the_sidebar_surface(self):
        connections = body_between(
            SEARCH,
            "target: Ai.voiceService\n        function onStateChanged() {",
            "\n    }",
        )
        self.assertNotIn('"sidebar"', connections)

    def test_insert_voice_text_reuses_the_paste_idiom(self):
        # Appends at the end of whatever is already drafted, through the same
        # setDraft()/Ai.draft pair pasteClipboard() uses, rather than a
        # second, divergent way of writing into the draft.
        fn = body_between(SEARCH, "function insertVoiceText(text) {", "\n    }")
        self.assertIn("root.setDraft(next)", fn)
        self.assertIn("Ai.draft = next", fn)

    def test_the_draft_width_reservation_collapses_when_voice_is_off(self):
        self.assertIn(
            'readonly property real voiceButtonReserve: Config.options.ai.voice.enabled '
            '? (root.controlExtent + root.controlGap) : 0',
            SEARCH,
        )


class SharedServiceSpinningIndicatorTests(unittest.TestCase):
    """Both buttons borrow the same `progress_activity` + spin idiom already
    used by the bar's own recording indicator, rather than inventing a new
    one."""

    def test_sidebar_button_spins_only_while_transcribing(self):
        self.assertIn('spinning: Ai.voiceService.state === "transcribing"', SIDEBAR)

    def test_search_button_spins_only_while_transcribing(self):
        self.assertIn('spinning: Ai.voiceService.state === "transcribing"', SEARCH)

    def test_sidebar_circle_button_supports_spinning_generically(self):
        component = body_between(SIDEBAR, "component ComposerCircleButton: RippleButton {", "\n    }\n\n    /** One way of attaching")
        self.assertIn("property bool spinning: false", component)
        self.assertIn("RotationAnimator on rotation {", component)

    def test_search_rail_icon_button_supports_spinning_generically(self):
        component = body_between(SEARCH, "component RailIconButton: RippleButton {", "\n    }\n\n    component RailTextButton")
        self.assertIn("property bool spinning: false", component)
        self.assertIn("RotationAnimator on rotation {", component)


if __name__ == "__main__":
    unittest.main()
