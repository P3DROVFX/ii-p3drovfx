pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Turning speech into a draft the user still has to send.
 *
 *     idle → recording → transcribing → review → attached
 *                ↘ cancelled              ↘ discarded
 *                                          ↘ error
 *
 * Independent of any view on purpose: the state lives here so closing the
 * Search panel mid-recording does not lose the microphone indicator or drop
 * the audio already captured — the same reason the file picker moved into
 * `Ai` instead of living in the sidebar that opened it.
 *
 * Recording is real on any machine with PipeWire (`pw-record`, checked once).
 * Transcription only runs if a local backend is actually found — this
 * machine has none, and the honest answer to that is a setup state, not an
 * attempt to install one. There is no wake word and no listening outside the
 * `recording` state; leaving that state, by any path, always stops capture.
 */
QtObject {
    id: root

    readonly property string voiceDir: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/voice`)
    readonly property int maxRecordingMs: 120000

    // ── Capability ──────────────────────────────────────────────────────
    property bool recorderChecked: false
    property bool recorderAvailable: false
    property bool backendChecked: false
    property bool backendAvailable: false
    /** Which backend answered `which` first: "whisper-cli", "whisper", "faster-whisper", or "". */
    property string backendName: ""
    /** GGML model path, only set when `backendName` is "whisper-cli". */
    property string modelPath: ""

    readonly property bool enabled: Config.options?.ai?.voice?.enabled ?? true
    readonly property bool available: root.enabled && root.recorderAvailable && root.backendAvailable

    // ── State machine ─────────────────────────────────────────────────────
    property string state: "idle" // idle | recording | transcribing | review | error
    property string errorText: ""
    property string draftText: ""
    property real recordingStartedAt: 0
    property real recordingElapsedMs: 0
    property string recordingPath: ""
    /**
     * Which composer asked for this recording ("sidebar", "search", ...).
     * Both composers watch the same shared service, so whichever one calls
     * `startRecording(surface)` is the only one that may consume the
     * resulting `review` draft — otherwise a recording started from the
     * sidebar would also insert itself into a Search composer sitting
     * loaded-but-hidden in the background.
     */
    property string activeSurface: ""

    signal transcribed(string text)
    signal attached(string text)

    /**
     * Kicks off detection at most once. `recorderChecked`/`backendChecked`
     * mean the result is known — set only when the process that finds it
     * out actually finishes — so they double as the honest "has this
     * settled yet" signal `startRecording` waits on below. Guarding
     * re-triggering by the same flag that meant "known" used to set it
     * true the instant the check was *started*, which made every very
     * first call believe an unfinished check had already come back false.
     */
    function ensureDetected() {
        if (!root.recorderChecked && !recorderCheckProc.running)
            recorderCheckProc.running = true;
        if (!root.backendChecked && !backendCheckProc.running)
            backendCheckProc.running = true;
    }

    /**
     * Forces both checks to run again — for the "Check again" button in
     * Settings, after someone installs a backend without restarting the
     * shell. `ensureDetected()` alone would no-op forever once `checked` is
     * true, which is correct for the hot path and wrong for this one.
     */
    function redetect() {
        if (root.state === "recording" || root.state === "transcribing")
            return;
        root.recorderChecked = false;
        root.backendChecked = false;
        root.ensureDetected();
    }

    /**
     * Why recording is not offered right now, empty when it is.
     *
     * Kept as one function rather than several booleans so the UI has one
     * sentence to show instead of reconstructing it from state — the same
     * pattern `AiToolRegistry.availability()` uses for tools.
     */
    function unavailableReason(): string {
        if (!root.enabled)
            return Translation.tr("Voice input is turned off.");
        if (!root.recorderChecked || !root.backendChecked)
            return Translation.tr("Checking for a microphone and a local transcription engine…");
        if (!root.recorderAvailable)
            return Translation.tr("No audio recorder was found (pw-record is missing).");
        if (!root.backendAvailable)
            return Translation.tr("No local speech-to-text engine is installed. whisper.cpp (as `whisper-cli`) is the one this shell knows how to drive; nothing is installed automatically.");
        return "";
    }

    /**
     * True the instant detection is settled either way — the thing worth
     * waiting a beat for on the very first call, rather than reading
     * `available` as false before the two `which` checks below have had the
     * chance to answer.
     */
    readonly property bool detectionSettled: root.recorderChecked && root.backendChecked

    function startRecording(surface = ""): bool {
        root.ensureDetected();
        if (root.state !== "idle" && root.state !== "pending-start")
            return false;
        if (String(surface).length > 0)
            root.activeSurface = surface;
        if (!root.detectionSettled) {
            // The very first call this session: `which` has not answered yet.
            // Waiting one tick for it, rather than reporting "unavailable"
            // from a check that has not actually run, is the difference
            // between a wrong first answer and a half-second delay nobody
            // notices. The timer below re-enters here with no argument, so
            // `activeSurface` — already stored above — is what carries the
            // caller's identity across the wait.
            root.state = "pending-start";
            detectionSettledTimer.start();
            return true;
        }
        root.state = "idle";
        if (!root.available) {
            root.state = "error";
            root.errorText = root.unavailableReason();
            return false;
        }
        Quickshell.execDetached(["mkdir", "-p", root.voiceDir]);
        root.recordingPath = `${root.voiceDir}/rec-${Date.now()}.wav`;
        root.errorText = "";
        root.draftText = "";
        root.recordingElapsedMs = 0;
        root.recordingStartedAt = Date.now();
        root.state = "recording";
        recordProc.command = ["pw-record", "--rate", "16000", "--channels", "1", root.recordingPath];
        recordProc.running = true;
        recordingClock.start();
        maxDurationTimer.start();
        return true;
    }

    property Timer detectionSettledTimer: Timer {
        interval: 60
        repeat: true
        running: false
        onTriggered: {
            if (!root.detectionSettled)
                return;
            stop();
            if (root.state === "pending-start")
                root.startRecording();
        }
    }

    /** Ends capture and moves to transcription, if there is anything to transcribe. */
    function stopRecording(): bool {
        if (root.state !== "recording")
            return false;
        maxDurationTimer.stop();
        recordingClock.stop();
        // SIGINT, not a hard kill: pw-record needs to be asked to stop so it
        // writes a WAV header for the frames already captured. A killed
        // process leaves a file nothing can play back.
        recordProc.signal(2);
        return true;
    }

    /** Stops and throws the capture away, from any state. */
    function cancel() {
        detectionSettledTimer.stop();
        maxDurationTimer.stop();
        recordingClock.stop();
        if (recordProc.running)
            recordProc.signal(2);
        if (transcribeProc.running)
            transcribeProc.running = false;
        root.cleanupRecording();
        root.state = "idle";
        root.draftText = "";
        root.errorText = "";
        root.activeSurface = "";
    }

    function cleanupRecording() {
        if (root.recordingPath.length > 0)
            Quickshell.execDetached(["rm", "-f", root.recordingPath]);
        root.recordingPath = "";
    }

    /** Hands the edited draft to whatever composer asked for it. */
    function attachDraft(text: string) {
        const value = String(text ?? root.draftText ?? "").trim();
        root.state = "idle";
        root.draftText = "";
        root.activeSurface = "";
        root.attached(value);
    }

    function discardDraft() {
        root.state = "idle";
        root.draftText = "";
        root.activeSurface = "";
    }

    function startTranscription() {
        root.state = "transcribing";
        const outputBase = root.recordingPath.replace(/\.wav$/, "");
        if (root.backendName === "whisper-cli") {
            transcribeProc.outputPath = `${outputBase}.txt`;
            // "auto" rather than a fixed language: dictation here is not
            // English-only, and the multilingual base model detects the
            // spoken language itself from the first few seconds of audio.
            transcribeProc.command = ["whisper-cli", "-m", root.modelPath, "-l", "auto",
                "-f", root.recordingPath, "-otxt", "-of", outputBase, "-nt"];
        } else if (root.backendName === "whisper") {
            transcribeProc.outputPath = `${outputBase}.txt`;
            transcribeProc.command = ["whisper", root.recordingPath, "--model", "base",
                "--output_format", "txt", "--output_dir", root.voiceDir, "--fp16", "False"];
        } else {
            root.state = "error";
            root.errorText = root.unavailableReason();
            root.cleanupRecording();
            return;
        }
        transcribeProc.running = true;
    }

    property Timer recordingClock: Timer {
        id: recordingClock
        interval: 200
        repeat: true
        onTriggered: root.recordingElapsedMs = Date.now() - root.recordingStartedAt
    }

    property Timer maxDurationTimer: Timer {
        id: maxDurationTimer
        interval: root.maxRecordingMs
        repeat: false
        onTriggered: root.stopRecording()
    }

    property Process recorderCheckProc: Process {
        id: recorderCheckProc
        command: ["bash", "-c", "command -v pw-record >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.recorderAvailable = text.trim() === "yes";
                root.recorderChecked = true;
            }
        }
    }

    property Process backendCheckProc: Process {
        id: backendCheckProc
        // Checked in the order the plan recommends: whisper.cpp's CLI first,
        // then the openai-whisper Python package, then faster-whisper, whose
        // presence is recorded but not yet driven (it ships no stable CLI).
        // whisper-cli only counts as found alongside its GGML model — the
        // binary alone cannot transcribe anything — so a second line carries
        // the model path the same run discovered it at.
        command: ["bash", "-c", "" +
            "model=\"$HOME/.local/share/whisper.cpp/models/ggml-base.bin\"; " +
            "if command -v whisper-cli >/dev/null 2>&1 && [ -f \"$model\" ]; then echo whisper-cli; echo \"$model\"; " +
            "elif command -v whisper >/dev/null 2>&1; then echo whisper; " +
            "elif command -v faster-whisper >/dev/null 2>&1; then echo faster-whisper; " +
            "else echo none; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const found = lines[0] ?? "none";
                root.backendName = found === "none" ? "" : found;
                root.modelPath = found === "whisper-cli" ? (lines[1] ?? "").trim() : "";
                // faster-whisper is detected but not driven yet: it has no
                // stable CLI to shell out to, only a Python API. Reporting it
                // as available would offer a tool that then fails every time.
                root.backendAvailable = found === "whisper-cli" || found === "whisper";
                root.backendChecked = true;
            }
        }
    }

    property Process recordProc: Process {
        id: recordProc
        onExited: (exitCode, exitStatus) => {
            if (root.state !== "recording")
                return; // Already cancelled.
            root.startTranscription();
        }
    }

    property Process transcribeProc: Process {
        id: transcribeProc
        property string outputPath: ""
        onExited: exitCode => {
            if (root.state !== "transcribing")
                return; // Cancelled mid-run.
            if (exitCode !== 0) {
                root.state = "error";
                root.errorText = Translation.tr("Transcription failed.");
                root.cleanupRecording();
                return;
            }
            transcriptFile.path = transcribeProc.outputPath;
            transcriptFile.reload();
        }
    }

    property FileView transcriptFile: FileView {
        id: transcriptFile
        printErrors: false
        onLoaded: {
            const text = String(transcriptFile.text() ?? "").trim();
            root.cleanupRecording();
            Quickshell.execDetached(["rm", "-f", transcribeProc.outputPath]);
            if (text.length === 0) {
                root.state = "error";
                root.errorText = Translation.tr("No speech was recognised.");
                return;
            }
            root.draftText = text;
            root.state = "review";
            root.transcribed(text);
        }
        onLoadFailed: {
            root.cleanupRecording();
            root.state = "error";
            root.errorText = Translation.tr("No speech was recognised.");
        }
    }
}
