pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions

/**
 * Speech typed straight into whatever window has focus, through voxtype.
 *
 *     idle → recording → transcribing → (text typed into the focused app)
 *
 * Unlike `AiVoiceService`, which records into an editable draft the user still
 * has to send, nothing here comes back to the shell: voxtype types the finished
 * text where the cursor already is. The shell only presses the button and shows
 * what is happening — the notch and the bar indicator both read the state below.
 *
 * The daemon is owned by the shell rather than by systemd. voxtype's own unit is
 * `WantedBy=graphical-session.target`, a target plenty of Hyprland sessions never
 * reach, so enabling it there is a switch that silently does nothing at the next
 * login. A `Process` tied to `Config.options.dictation.enabled` starts with the
 * shell, dies with it, and means "off" is actually off. A voxtype.service that is
 * already running is left alone and simply used — see `externalDaemon`.
 *
 * State is read from the file the daemon rewrites on every transition
 * (`$XDG_RUNTIME_DIR/voxtype/state`), watched rather than polled, so the notch
 * reacts the moment recording starts instead of up to a second later.
 */
Singleton {
    id: root

    readonly property string runtimeDir: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        if (xdg && xdg.length > 0)
            return `${xdg}/voxtype`;
        return `/run/user/1000/voxtype`;
    }
    readonly property string statePath: `${root.runtimeDir}/state`
    readonly property string configScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/dictation/voxtype_config.py`)
    /** Download bookkeeping: an in-flight marker, its log, and a failure flag. */
    readonly property string stateDir: FileUtils.trimFileProtocol(`${Directories.state}/user/dictation`)

    // ── Options ───────────────────────────────────────────────────────────
    readonly property bool enabled: Config.options?.dictation?.enabled ?? false
    /** "fast" or "accurate" — a size/latency choice, not a language one. */
    readonly property string quality: Config.options?.dictation?.quality ?? "fast"
    /** "auto", a single code ("fr"), or several comma-separated ("en,fr"). */
    readonly property string language: Config.options?.dictation?.language ?? "en"
    readonly property bool translateToEnglish: Config.options?.dictation?.translateToEnglish ?? false
    readonly property string outputMode: Config.options?.dictation?.outputMode ?? "type"
    readonly property bool pauseMedia: Config.options?.dictation?.pauseMedia ?? true
    readonly property bool soundFeedback: Config.options?.dictation?.soundFeedback ?? false
    readonly property int maxDurationSecs: Config.options?.dictation?.maxDurationSecs ?? 60
    readonly property int typeDelayMs: Config.options?.dictation?.typeDelayMs ?? 5
    readonly property bool notifyOnTranscription: Config.options?.dictation?.notifyOnTranscription ?? true
    /** 0 asks for a sensible default; anything else is passed through as-is. */
    readonly property int threads: Config.options?.dictation?.threads ?? 0
    /** Overrides the built-in per-language punctuation sample when set. */
    readonly property string punctuationHint: Config.options?.dictation?.punctuationHint ?? ""

    // ── Models ────────────────────────────────────────────────────────────
    /**
     * Whisper ships an English-only variant of the small models and a
     * multilingual one under the same size, so the language picked above — not
     * a separate "multilingual" switch — decides which file the quality choice
     * actually needs. `large-v3-turbo` is multilingual to begin with, which is
     * why the accurate preset needs no such split.
     */
    readonly property bool englishOnly: root.language === "en"
    readonly property string requiredModel: {
        if (root.quality === "accurate")
            return "large-v3-turbo";
        return root.englishOnly ? "base.en" : "base";
    }
    readonly property string requiredModelSize: root.quality === "accurate" ? "1.6 GB" : "142 MB"
    readonly property string qualityLabel: root.quality === "accurate"
        ? Translation.tr("Whisper — Accurate")
        : Translation.tr("Whisper — Fast")

    property var installedModels: []
    /**
     * Models whose download was cut short. `voxtype setup --download` skips any
     * model file that merely exists — it prints "Model ready" and returns — so a
     * half-written file would never be re-fetched and would instead fail deep
     * inside the daemon at load time. These are therefore not installed.
     */
    property var incompleteModels: []
    readonly property bool modelReady: root.installedModels.indexOf(root.requiredModel) !== -1
    readonly property bool requiredModelIncomplete: root.incompleteModels.indexOf(root.requiredModel) !== -1

    function modelInstalled(model: string): bool {
        return root.installedModels.indexOf(model) !== -1;
    }

    // ── Performance ───────────────────────────────────────────────────────
    /** How voxtype is computing right now, e.g. "CPU (AVX2)" or "GPU (Vulkan)". */
    property string backend: ""
    /** A GPU build is installed and could be switched to, but is not active. */
    property bool gpuAvailable: false
    property int cpuCount: 4
    readonly property bool onGpu: root.backend.indexOf("GPU") === 0

    /**
     * Whisper leaves this at `min(cores, 4)`, which on an eight-core machine
     * spends half of it idling through a transcription the user is waiting on.
     * One core is kept back so the rest of the session stays responsive.
     */
    readonly property int effectiveThreads: root.threads > 0
        ? root.threads
        : Math.max(2, root.cpuCount - 1)

    /**
     * Whisper punctuates in the style of the text it is primed with, and its
     * multilingual models are noticeably worse at commas and accents outside
     * English without that nudge. Each sample is a short, ordinary sentence
     * carrying the punctuation the language actually uses — nothing topical,
     * so it cannot drag the transcription towards a subject.
     */
    readonly property var punctuationSamples: ({
        "fr": "Bonjour, voici un exemple : des virgules, des points, et des questions ?",
        "es": "Hola, aquí va un ejemplo: comas, puntos, y preguntas. ¿Verdad?",
        "de": "Guten Tag, hier ein Beispiel: Kommas, Punkte, und Fragen?",
        "it": "Buongiorno, ecco un esempio: virgole, punti, e domande?",
        "pt": "Olá, aqui está um exemplo: vírgulas, pontos, e perguntas?",
        "nl": "Goedendag, hier een voorbeeld: komma's, punten, en vragen?",
        "pl": "Dzień dobry, oto przykład: przecinki, kropki, i pytania?",
        "ru": "Здравствуйте, вот пример: запятые, точки и вопросы?",
        "ca": "Bon dia, aquí teniu un exemple: comes, punts, i preguntes?",
        "sv": "God dag, här är ett exempel: kommatecken, punkter, och frågor?",
        "en": "Hello, here is an example: commas, periods, and questions?"
    })

    readonly property string effectiveHint: {
        if (root.punctuationHint.length > 0)
            return root.punctuationHint;
        // Auto-detection has no language to prime for, and priming with the
        // wrong one costs accuracy, so it deliberately gets no sample.
        const primary = root.language.split(",")[0].trim();
        return root.punctuationSamples[primary] ?? "";
    }

    /**
     * Switches voxtype to its Vulkan build, which is a root-owned symlink swap —
     * hence pkexec, which the shell's own polkit agent answers. Worth offering
     * in the UI rather than leaving in the release notes: on an integrated Arc
     * GPU it took a five-second dictation from 45 s to under 2 s.
     */
    function enableGpu() {
        if (!root.gpuAvailable)
            return;
        gpuEnableProc.running = true;
    }

    // ── Capability ────────────────────────────────────────────────────────
    property bool installed: false
    property bool bridgeInstalled: false
    property bool binaryChecked: false
    /** A voxtype.service someone else already runs; the shell then stays out of the way. */
    property bool externalDaemon: false
    /**
     * True once the shell's settings have actually reached voxtype's config
     * file. The daemon waits for this: started against the stock config it
     * would grab Scroll Lock for its own hotkey and spawn its own on-screen
     * display, both of which this shell replaces, and the user would see a
     * flash of the wrong behaviour on the very first run before the restart
     * that fixes it.
     */
    property bool configApplied: false

    readonly property bool available: root.installed && root.enabled && root.modelReady

    /** Why dictation cannot run right now, empty when it can. */
    function unavailableReason(): string {
        if (!root.binaryChecked)
            return Translation.tr("Looking for voxtype…");
        if (!root.installed)
            return Translation.tr("Voxtype is not installed.");
        if (!root.enabled)
            return Translation.tr("Dictation is turned off.");
        if (root.requiredModelIncomplete)
            return Translation.tr("The %1 speech model is still downloading.").arg(root.requiredModel);
        if (!root.modelReady)
            return Translation.tr("The %1 speech model has not been downloaded yet.").arg(root.requiredModel);
        return "";
    }

    // ── Live state ────────────────────────────────────────────────────────
    /** stopped | idle | recording | streaming | transcribing */
    property string state: "stopped"
    readonly property bool recording: root.state === "recording" || root.state === "streaming"
    readonly property bool transcribing: root.state === "transcribing"
    readonly property bool busy: root.recording || root.transcribing
    readonly property bool daemonUp: root.state !== "stopped"

    property real recordingStartedAt: 0
    property int elapsedMs: 0

    /** Latest mic level, 0..1, smoothed for the notch's meter. */
    property real level: 0
    /** Recent levels, oldest first — the notch draws this as a waveform. */
    property var waveform: []
    readonly property int waveformLength: 40

    signal dictationStarted
    signal dictationFinished

    onRecordingChanged: {
        if (root.recording) {
            root.recordingStartedAt = Date.now();
            root.elapsedMs = 0;
            root.dictationStarted();
            return;
        }
        root.level = 0;
        root.waveform = [];
    }

    onStateChanged: {
        if (root.state === "idle" || root.state === "stopped")
            root.dictationFinished();
    }

    // ── Actions ───────────────────────────────────────────────────────────
    /**
     * The one thing the keybind does. Refuses loudly rather than silently when
     * something is missing — a dictation key that does nothing at all reads as
     * a broken shell, not as an unconfigured feature.
     */
    function toggle() {
        if (!root.available) {
            root.complain();
            return;
        }
        if (!root.daemonUp) {
            // The daemon is still coming up (first toggle right after the
            // shell started, or straight after a config change restarted it).
            // Waiting for it beats dropping the keypress.
            pendingToggleTimer.restart();
            return;
        }
        recordProc.exec(["voxtype", "record", "toggle"]);
    }

    function stop() {
        if (!root.busy)
            return;
        recordProc.exec(["voxtype", "record", "stop"]);
    }

    /** Throws the recording away: nothing is transcribed and nothing is typed. */
    function discard() {
        if (!root.busy)
            return;
        recordProc.exec(["voxtype", "record", "cancel"]);
    }

    /** Short label for the language in use, for the bar and the popup. */
    readonly property string languageBadge: root.language === "auto"
        ? Translation.tr("AUTO")
        : root.language.split(",")[0].trim().toUpperCase()

    function complain() {
        const reason = root.unavailableReason();
        if (reason.length === 0)
            return;
        Quickshell.execDetached(["notify-send", Translation.tr("Dictation"), reason, "-a", "Shell", "-i", "mic"]);
    }

    function redetect() {
        root.binaryChecked = false;
        binaryCheckProc.running = true;
        modelListProc.running = true;
        externalDaemonProc.running = true;
        backendCheckProc.running = true;
    }

    /**
     * Pushes the shell's settings into voxtype's own config file and restarts
     * the daemon so they take effect. Debounced by the caller: every switch on
     * the settings page lands here, and a restart per keystroke in the language
     * field would make the page feel like it was fighting back.
     */
    function applySettings() {
        if (!root.installed)
            return;
        configProc.command = ["python3", root.configScript, "set",
            "state_file=auto",
            "hotkey.enabled=false",
            "osd.enabled=false",
            `whisper.model=${root.requiredModel}`,
            `whisper.language=${root.language.indexOf(",") === -1 ? root.language : `[${root.language}]`}`,
            `whisper.threads=${root.effectiveThreads}`,
            `whisper.initial_prompt=${root.effectiveHint}`,
            `whisper.translate=${root.translateToEnglish ? "true" : "false"}`,
            `output.mode=${root.outputMode}`,
            `output.type_delay_ms=${root.typeDelayMs}`,
            // Paste mode puts the transcription on the clipboard to paste it.
            // Off by default in voxtype, which means dictating quietly destroys
            // whatever the user had copied.
            "output.restore_clipboard=true",
            `output.notification.on_transcription=${root.notifyOnTranscription ? "true" : "false"}`,
            // Start and stop already have the bar pill and the notch; a
            // notification for each as well would be three announcements of the
            // same thing.
            "output.notification.on_recording_start=false",
            "output.notification.on_recording_stop=false",
            `audio.max_duration_secs=${root.maxDurationSecs}`,
            `audio.pause_media=${root.pauseMedia ? "true" : "false"}`,
            `audio.feedback.enabled=${root.soundFeedback ? "true" : "false"}`];
        configProc.running = true;
    }

    function scheduleApply() {
        if (!root.installed || !Config.ready)
            return;
        applyTimer.restart();
    }

    /** Restarts our own daemon; a foreign systemd one is left for systemd to manage. */
    function restartDaemon() {
        if (root.externalDaemon) {
            Quickshell.execDetached(["systemctl", "--user", "restart", "voxtype.service"]);
            return;
        }
        if (!daemonProc.running)
            return;
        daemonProc.restarting = true;
        daemonProc.running = false;
    }

    // ── Model management ──────────────────────────────────────────────────
    property string downloadingModel: ""
    property real downloadProgress: 0
    property string lastError: ""

    /**
     * Runs the download outside the shell's process tree, on purpose. A model is
     * up to 1.6 GB, and a `Process` owned by the shell dies with the next config
     * reload — which used to abandon the download half-written. Detached, the
     * transfer finishes regardless, and the marker file it leaves behind is what
     * this service watches; a reload simply reconnects to the progress.
     */
    function downloadModel(model: string) {
        if (root.downloadingModel.length > 0)
            return;
        root.lastError = "";
        root.downloadProgress = 0;
        root.downloadingModel = model;
        Quickshell.execDetached(["bash", "-c", root.downloadScript, "--", root.stateDir, model]);
        downloadWatchTimer.restart();
    }

    readonly property string downloadScript: [
        "set -u",
        "state=\"$1\"; model=\"$2\"",
        "models=\"${XDG_DATA_HOME:-$HOME/.local/share}/voxtype/models\"",
        "mkdir -p \"$state\"",
        "rm -f \"$state/failed-$model\" \"$state/log-$model\"",
        ": > \"$state/incomplete-$model\"",
        // Any leftover file has to go first: voxtype reports an existing one as
        // "Model ready" and downloads nothing, so a retry after a failure would
        // otherwise keep the broken file forever.
        "rm -f \"$models/ggml-$model.bin\"",
        "if voxtype setup --download --model \"$model\" --no-post-install > \"$state/log-$model\" 2>&1; then",
        "    rm -f \"$state/incomplete-$model\"",
        "else",
        "    rm -f \"$models/ggml-$model.bin\" \"$state/incomplete-$model\"",
        "    : > \"$state/failed-$model\"",
        "fi"
    ].join("\n")

    function removeModel(model: string) {
        const dataHome = Quickshell.env("XDG_DATA_HOME");
        const base = (dataHome && dataHome.length > 0) ? dataHome : `${Quickshell.env("HOME")}/.local/share`;
        removeProc.command = ["bash", "-c",
            "rm -f \"$1/voxtype/models/ggml-$3.bin\" \"$2/incomplete-$3\" \"$2/log-$3\" \"$2/failed-$3\"",
            "--", base, root.stateDir, model];
        removeProc.running = true;
    }

    // ── Detection ─────────────────────────────────────────────────────────
    Component.onCompleted: root.redetect()

    Process {
        id: binaryCheckProc
        command: ["bash", "-c",
            "command -v voxtype >/dev/null 2>&1 && echo yes || echo no; " +
            "command -v voxtype-audio-bridge >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.installed = (lines[0] ?? "no").trim() === "yes";
                root.bridgeInstalled = (lines[1] ?? "no").trim() === "yes";
                root.binaryChecked = true;
                if (root.installed && root.enabled)
                    root.scheduleApply();
            }
        }
    }

    /**
     * Cores, the active compute backend, and whether a GPU build is sitting
     * there unused. `voxtype status` reports the backend even with no daemon
     * running, so this needs nothing to be up.
     */
    Process {
        id: backendCheckProc
        command: ["bash", "-c",
            "nproc; " +
            "voxtype status --format json --extended 2>/dev/null " +
            "| sed -n 's/.*\"backend\": *\"\\([^\"]*\\)\".*/\\1/p'; " +
            "voxtype setup gpu 2>/dev/null | grep -q 'GPU (Vulkan) - installed' && echo gpu-available || echo gpu-none"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").map(line => line.trim());
                const cores = parseInt(lines[0]);
                if (!isNaN(cores) && cores > 0)
                    root.cpuCount = cores;
                root.backend = lines[1] ?? "";
                root.gpuAvailable = lines.indexOf("gpu-available") !== -1;
            }
        }
    }

    Process {
        id: gpuEnableProc
        command: ["pkexec", "voxtype", "setup", "gpu", "--enable"]
        stderr: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line.length > 0)
                    root.lastError = line;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                // 126/127 is the user dismissing the polkit prompt, which is an
                // answer rather than a failure worth shouting about.
                if (exitCode !== 126 && exitCode !== 127)
                    root.lastError = Translation.tr("Switching to the GPU backend failed.");
                return;
            }
            root.lastError = "";
            backendCheckProc.running = true;
            root.restartDaemon();
        }
    }

    Process {
        id: externalDaemonProc
        command: ["systemctl", "--user", "is-active", "--quiet", "voxtype.service"]
        onExited: exitCode => root.externalDaemon = (exitCode === 0)
    }

    /**
     * Which models are on disk, and which are only partly there. `voxtype setup
     * model --list` prints a human table, so the file names are read directly
     * instead — one less output format to track across voxtype releases.
     */
    Process {
        id: modelListProc
        command: ["bash", "-c",
            "state=\"$1\"; dir=\"${XDG_DATA_HOME:-$HOME/.local/share}/voxtype/models\"; " +
            "if [ -d \"$dir\" ]; then for f in \"$dir\"/ggml-*.bin; do [ -e \"$f\" ] || continue; " +
            "b=$(basename \"$f\"); b=${b#ggml-}; echo \"ok:${b%.bin}\"; done; fi; " +
            "if [ -d \"$state\" ]; then for f in \"$state\"/incomplete-*; do [ -e \"$f\" ] || continue; " +
            "b=$(basename \"$f\"); echo \"partial:${b#incomplete-}\"; done; fi",
            "--", root.stateDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").map(line => line.trim()).filter(line => line.length > 0);
                const partial = lines.filter(line => line.indexOf("partial:") === 0).map(line => line.substring(8));
                root.incompleteModels = partial;
                root.installedModels = lines.filter(line => line.indexOf("ok:") === 0)
                    .map(line => line.substring(3))
                    .filter(model => partial.indexOf(model) === -1);
                // A download still running from before this shell reloaded:
                // pick it back up rather than leaving the page on "Download".
                if (partial.length > 0 && root.downloadingModel.length === 0) {
                    root.downloadingModel = partial[0];
                    downloadWatchTimer.restart();
                }
            }
        }
    }

    // ── The daemon ────────────────────────────────────────────────────────
    Process {
        id: daemonProc
        property bool restarting: false
        running: Config.ready && root.enabled && root.installed && root.modelReady
            && root.configApplied && !root.externalDaemon
        command: ProcUtils.pdeath(["voxtype", "daemon"])
        stderr: SplitParser {
            onRead: data => {
                // voxtype logs to stderr; only the failures are worth keeping.
                data.split("\n").forEach(line => {
                    if (line.indexOf("ERROR") !== -1)
                        root.lastError = line.trim();
                });
            }
        }
        onExited: {
            if (!daemonProc.restarting)
                return;
            daemonProc.restarting = false;
            daemonRestartTimer.restart();
        }
    }

    Timer {
        id: daemonRestartTimer
        interval: 250
        onTriggered: daemonProc.running = Qt.binding(() => Config.ready && root.enabled && root.installed
            && root.modelReady && root.configApplied && !root.externalDaemon)
    }

    // ── Live state file ───────────────────────────────────────────────────
    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const next = (text() || "").trim();
            root.state = next.length > 0 ? next : "idle";
        }
        // The daemon deletes the file on the way out, so a failed load is how
        // "not running" arrives — not an error worth reporting.
        onLoadFailed: root.state = "stopped"
    }

    /**
     * The state file only exists once a daemon has run, and FileView cannot
     * watch a path that was never there — so a shell that started before the
     * daemon would sit on "stopped" forever. Re-pointing the path is what makes
     * it pick the file up.
     */
    Timer {
        interval: 1000
        repeat: true
        running: root.enabled && root.installed && root.modelReady && root.state === "stopped"
        onTriggered: {
            stateFile.path = "";
            stateFile.path = root.statePath;
        }
    }

    Timer {
        id: pendingToggleTimer
        interval: 400
        onTriggered: {
            if (!root.daemonUp) {
                root.lastError = Translation.tr("The dictation daemon did not start.");
                return;
            }
            recordProc.exec(["voxtype", "record", "toggle"]);
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: root.recording
        onTriggered: root.elapsedMs = Date.now() - root.recordingStartedAt
    }

    Process {
        id: recordProc
        function exec(argv) {
            recordProc.running = false;
            recordProc.command = argv;
            recordProc.running = true;
        }
    }

    // ── Mic levels ────────────────────────────────────────────────────────
    /**
     * voxtype's own sidecar, reading the daemon's capture over its audio
     * socket. The alternative — pointing cava at the microphone — opens a
     * second capture stream on a device that is already being recorded, and
     * shows the room rather than what the daemon actually hears.
     */
    Process {
        id: bridgeProc
        running: root.recording && root.bridgeInstalled
        command: ProcUtils.pdeath(["voxtype-audio-bridge"])
        stdout: SplitParser {
            // One read can carry several frames at once, so never treat the
            // payload as a single line.
            onRead: data => data.split("\n").forEach(line => root.handleFrame(line))
        }
    }

    function handleFrame(line: string) {
        const trimmed = String(line ?? "").trim();
        if (trimmed.length === 0 || trimmed.charAt(0) !== "{")
            return;
        let frame;
        try {
            frame = JSON.parse(trimmed);
        } catch (e) {
            return;
        }
        if (frame.status !== undefined)
            return;
        const rms = Math.max(0, Math.min(1, Number(frame.rms ?? 0)));
        const peak = Math.max(0, Math.min(1, Number(frame.peak ?? 0)));
        // Speech sits low in a linear 0..1 scale; the curve is what makes a
        // normal speaking voice fill the meter instead of nudging it.
        const shaped = Math.min(1, Math.pow(Math.max(rms, peak * 0.6), 0.55) * 1.4);
        root.level = root.level * 0.55 + shaped * 0.45;
        const next = root.waveform.slice(-(root.waveformLength - 1));
        next.push(root.level);
        root.waveform = next;
    }

    // ── Settings → voxtype's config file ──────────────────────────────────
    Timer {
        id: applyTimer
        interval: 500
        onTriggered: root.applySettings()
    }

    Process {
        id: configProc
        stdout: StdioCollector {}
        stderr: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line.length > 0)
                    root.lastError = line;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                return;
            if (!root.configApplied) {
                // First write of the session: the binding above starts the
                // daemon on its own, so restarting here would only fight it.
                root.configApplied = true;
                return;
            }
            root.restartDaemon();
        }
    }

    Connections {
        target: Config.options?.dictation ?? null
        enabled: target !== null
        function onQualityChanged() { root.scheduleApply(); }
        function onLanguageChanged() { root.scheduleApply(); }
        function onTranslateToEnglishChanged() { root.scheduleApply(); }
        function onOutputModeChanged() { root.scheduleApply(); }
        function onPauseMediaChanged() { root.scheduleApply(); }
        function onSoundFeedbackChanged() { root.scheduleApply(); }
        function onMaxDurationSecsChanged() { root.scheduleApply(); }
        function onThreadsChanged() { root.scheduleApply(); }
        function onTypeDelayMsChanged() { root.scheduleApply(); }
        function onNotifyOnTranscriptionChanged() { root.scheduleApply(); }
        function onPunctuationHintChanged() { root.scheduleApply(); }
        function onEnabledChanged() {
            if (Config.options.dictation.enabled)
                root.scheduleApply();
        }
    }

    // ── Downloads ─────────────────────────────────────────────────────────
    Timer {
        id: downloadWatchTimer
        interval: 900
        repeat: true
        running: false
        triggeredOnStart: true
        onTriggered: {
            if (root.downloadingModel.length === 0) {
                stop();
                return;
            }
            if (downloadWatchProc.running)
                return;
            downloadWatchProc.command = ["bash", "-c", root.downloadWatchScript,
                "--", root.stateDir, root.downloadingModel];
            downloadWatchProc.running = true;
        }
    }

    /**
     * Prints the download's state on the first line and its latest percentage on
     * the second. The percentage comes out of the log the download writes: curl
     * puts its progress bar on stderr, carriage-returned rather than newlined,
     * which is why the log is folded before the last reading is picked out.
     */
    readonly property string downloadWatchScript: [
        "set -u",
        "state=\"$1\"; model=\"$2\"",
        "if [ -f \"$state/failed-$model\" ]; then echo failed",
        "elif [ -f \"$state/incomplete-$model\" ]; then echo running",
        "else echo done; fi",
        "tr '\\r' '\\n' < \"$state/log-$model\" 2>/dev/null | grep -o '[0-9][0-9.]*%' | tail -1"
    ].join("\n")

    Process {
        id: downloadWatchProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const status = (lines[0] ?? "").trim();
                const percent = parseFloat((lines[1] ?? "").replace("%", ""));
                if (!isNaN(percent))
                    root.downloadProgress = Math.max(0, Math.min(100, percent)) / 100;
                if (status === "running")
                    return;
                const model = root.downloadingModel;
                downloadWatchTimer.stop();
                root.downloadingModel = "";
                root.downloadProgress = 0;
                if (status === "failed")
                    root.lastError = Translation.tr("Downloading the %1 model failed. See the log for what voxtype said.").arg(model);
                Quickshell.execDetached(["rm", "-f", `${root.stateDir}/failed-${model}`, `${root.stateDir}/log-${model}`]);
                modelListProc.running = true;
                // A finished download also repoints voxtype's config at whatever
                // was fetched, so the shell's own choice is written back over it.
                root.scheduleApply();
            }
        }
    }

    Process {
        id: removeProc
        onExited: modelListProc.running = true
    }

    // ── Keybind ───────────────────────────────────────────────────────────
    GlobalShortcut {
        name: "dictationToggle"
        description: "Start or stop dictation"
        onPressed: root.toggle()
    }

    GlobalShortcut {
        name: "dictationStop"
        description: "Stop dictation without transcribing further speech"
        onPressed: root.stop()
    }
}
