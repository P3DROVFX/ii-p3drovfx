#!/usr/bin/env python3
"""Speech-to-text: real recording, honest about the missing backend.

This machine has `pw-record` and no local transcription engine, and the
service is supposed to say exactly that rather than pretending otherwise.
Two real bugs were caught by hand-testing before these tests existed:

  * `recorderChecked`/`backendChecked` were set the instant detection was
    *triggered*, not when it *finished* — so the very first call always
    believed an unfinished check had already come back false, and reported
    the wrong reason (recorder missing) when the real gap was the backend.

  * A bare `Timer`/`Process`/`FileView` child of a `QtObject` root has
    nowhere to attach: `QtObject` has no default property, and the file
    failed to load at all until each child got a named `property` wrapper.

Both are pinned here so a future edit cannot quietly reintroduce either.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "services" / "ai" / "AiVoiceService.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class QtObjectAttachmentTests(unittest.TestCase):
    """QtObject has no default property; every child needs a name."""

    def test_every_timer_process_and_fileview_is_a_named_property(self):
        import re
        bare = re.findall(r"\n    (Timer|Process|FileView)\s*\{", SOURCE)
        self.assertEqual(bare, [], f"bare (unnamed) children found: {bare}")

    def test_the_children_that_must_exist_are_all_named(self):
        for child, kind in (("recordingClock", "Timer"), ("maxDurationTimer", "Timer"),
                            ("detectionSettledTimer", "Timer"), ("recorderCheckProc", "Process"),
                            ("backendCheckProc", "Process"), ("recordProc", "Process"),
                            ("transcribeProc", "Process"), ("transcriptFile", "FileView")):
            with self.subTest(child=child):
                self.assertIn(f"property {kind} {child}: {kind} {{", SOURCE)


class DetectionCompletionTests(unittest.TestCase):
    """`checked` means the result is known, not that a check was started."""

    def test_ensure_detected_does_not_mark_checked_before_the_result_is_in(self):
        body = body_between(SOURCE, "function ensureDetected() {", "\n    }")
        self.assertNotIn("root.recorderChecked = true;\n        }", body)
        self.assertIn("!recorderCheckProc.running", body)
        self.assertIn("!backendCheckProc.running", body)

    def test_checked_is_set_only_where_the_result_actually_lands(self):
        recorder_result = body_between(SOURCE, "id: recorderCheckProc", "\n    }")
        self.assertIn("root.recorderChecked = true;", recorder_result)
        self.assertIn("root.recorderAvailable = text.trim()", recorder_result)
        # Order matters: availability is known before checked flips, so a
        # reader of `checked` can trust `available` is already correct.
        self.assertLess(recorder_result.index("recorderAvailable"), recorder_result.index("recorderChecked"))

    def test_backend_checked_is_set_only_on_completion_too(self):
        backend_result = body_between(SOURCE, "id: backendCheckProc", "\n    }")
        self.assertIn("root.backendChecked = true;", backend_result)
        self.assertLess(backend_result.index("backendAvailable"), backend_result.index("backendChecked"))


class FirstCallRaceTests(unittest.TestCase):
    """The very first call must wait for detection instead of guessing."""

    def test_start_recording_waits_for_detection_before_deciding(self):
        body = body_between(SOURCE, "function startRecording(surface = \"\"): bool {", "\n    property Timer detectionSettledTimer")
        self.assertIn("detectionSettled", body)
        self.assertIn('"pending-start"', body)

    def test_the_settle_timer_only_retries_if_still_wanted(self):
        timer = body_between(SOURCE, "property Timer detectionSettledTimer: Timer {", "\n    }")
        self.assertIn('root.state === "pending-start"', timer)

    def test_cancel_stops_the_settle_timer_too(self):
        cancel = body_between(SOURCE, "function cancel() {", "\n    }")
        self.assertIn("detectionSettledTimer.stop()", cancel)

    def test_start_recording_has_no_typed_default_parameter(self):
        # This QML engine rejects typed parameters with default values
        # (`surface: string = ""`) with "Type annotations are not supported
        # (yet)." at load time — a parse error, not a lint warning, that
        # took the whole `Ai` singleton down with it. The parameter must
        # stay untyped to keep the default.
        self.assertNotIn('function startRecording(surface: string', SOURCE)


class ActiveSurfaceTests(unittest.TestCase):
    """Two composers share one recorder; only the caller may claim a draft.

    Without this, starting a recording from the sidebar and letting it
    finish while the Search composer also happens to be loaded (hidden,
    not visible) would hand the transcribed text to both — one insertion
    the user can see, one silently landing in a composer they are not
    looking at.
    """

    def test_the_surface_survives_the_pending_start_wait(self):
        # The settle timer re-enters startRecording() with no argument, so
        # activeSurface must be recorded *before* the async branch, not
        # inside it — otherwise a first-call recording started while
        # detection is still settling would forget who asked.
        body = body_between(SOURCE, "function startRecording(surface = \"\"): bool {", "\n        if (!root.detectionSettled) {")
        self.assertIn("root.activeSurface = surface", body)

    def test_reset_paths_all_clear_the_surface(self):
        for fn in ("cancel", "attachDraft", "discardDraft"):
            body = body_between(SOURCE, f"function {fn}(", "\n    }")
            with self.subTest(fn=fn):
                self.assertIn("root.activeSurface = \"\";", body)

    def test_active_surface_is_a_declared_property(self):
        self.assertIn("property string activeSurface: \"\"", SOURCE)


class StateMachineTests(unittest.TestCase):
    def test_the_documented_states_all_appear(self):
        for state in ("idle", "recording", "transcribing", "review", "error", "pending-start"):
            with self.subTest(state=state):
                self.assertIn(f'"{state}"', SOURCE)

    def test_stopping_uses_a_signal_not_a_hard_kill(self):
        # pw-record needs to be asked to stop so it writes a WAV header for
        # the frames already captured; a killed process leaves an unplayable
        # file.
        stop = body_between(SOURCE, "function stopRecording(): bool {", "\n    }")
        self.assertIn("recordProc.signal(2)", stop)
        self.assertNotIn("running = false", stop)

    def test_leaving_recording_by_any_path_stops_the_clock(self):
        for fn in ("stopRecording", "cancel"):
            body = body_between(SOURCE, f"function {fn}(", "\n    }")
            with self.subTest(fn=fn):
                self.assertIn("recordingClock.stop()", body)

    def test_a_temp_recording_is_deleted_after_transcription(self):
        loaded = body_between(SOURCE, "onLoaded: {", "\n        }")
        self.assertIn("root.cleanupRecording()", loaded)
        self.assertIn("transcribeProc.outputPath", loaded)
        self.assertIn('"rm", "-f"', loaded)

    def test_a_temp_recording_is_deleted_on_cancel(self):
        cancel = body_between(SOURCE, "function cancel() {", "\n    }")
        self.assertIn("root.cleanupRecording()", cancel)

    def test_no_backend_is_a_named_error_not_a_silent_failure(self):
        transcription = body_between(SOURCE, "function startTranscription() {", "\n    }")
        self.assertIn("root.unavailableReason()", transcription)
        self.assertIn('root.state = "error"', transcription)

    def test_the_transcript_becomes_an_editable_draft_never_auto_sent(self):
        loaded = body_between(SOURCE, "onLoaded: {", "\n        }")
        self.assertIn('root.state = "review"', loaded)
        self.assertNotIn("attachDraft", loaded)

    def test_attaching_and_discarding_both_return_to_idle(self):
        for fn in ("attachDraft", "discardDraft"):
            body = body_between(SOURCE, f"function {fn}(", "\n    }")
            with self.subTest(fn=fn):
                self.assertIn('root.state = "idle"', body)


class NoAlwaysListeningTests(unittest.TestCase):
    def test_there_is_no_wake_word_or_continuous_listening(self):
        # The module comment disclaims both by name — "there is no wake word
        # and no listening outside the recording state" — so the thing worth
        # pinning is that nothing *implements* either: no detector property,
        # no signal, no loop that restarts recording on its own.
        self.assertIn("no wake word", SOURCE.lower())
        for forbidden in ("wakewordenabled", "wakeworddetected", "onwakeword", "continuouslisten"):
            with self.subTest(token=forbidden):
                self.assertNotIn(forbidden, SOURCE.lower().replace(" ", ""))
        # Recording only ever starts from an explicit call, never from a
        # timer or a completion handler looping back into itself.
        self.assertNotIn("Timer {\n        onTriggered: root.startRecording", SOURCE)

    def test_a_maximum_recording_duration_exists(self):
        self.assertIn("maxRecordingMs", SOURCE)
        self.assertIn("maxDurationTimer.start()", SOURCE)


class UnavailableReasonTests(unittest.TestCase):
    def test_the_reason_distinguishes_recorder_from_backend(self):
        body = body_between(SOURCE, "function unavailableReason(): string {", "\n    }")
        self.assertIn("recorderAvailable", body)
        self.assertIn("backendAvailable", body)
        self.assertIn("pw-record", body)
        self.assertIn("whisper", body)

    def test_faster_whisper_is_named_but_not_driven(self):
        # It has no stable CLI to shell out to; reporting it as available
        # would offer a tool that then fails every time it is used.
        detection = body_between(SOURCE, "id: backendCheckProc", "\n    }")
        self.assertIn("faster-whisper", detection)
        self.assertIn('found === "whisper-cli" || found === "whisper"', detection)


if __name__ == "__main__":
    unittest.main()
