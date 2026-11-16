pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import ".."
import qs
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Phone Microphone Service — bridges droidcam-cli (audio mode) into a reactive
 * QML state, with virtual null-sink routing so the phone's audio stream becomes
 * a usable *microphone source* in PipeWire/PulseAudio.
 *
 * Important droidcam-cli usage notes:
 *   • The PC connects TO the phone (not the other way around).
 *   • Used flags (verified with droidcam-cli 2.1.5):
 *       -a          enable audio (REQUIRED for mic mode)
 *       -nocontrols disable stdin controls
 *       -v          NOT used here (we only want audio)
 *   • The `-a` flag makes droidcam-cli stream audio from the phone's mic to
 *     the default PulseAudio sink. To use it as a microphone, we set
 *     `PULSE_SINK=DroidCam-Mic` env before launching so the audio lands in
 *     our null-sink instead of the speakers — the null-sink's `.monitor`
 *     source then becomes a recordable microphone.
 *
 * Architecture:
 *
 *   ┌────────────────────────────────────┐  PCM   ┌─────────────────────┐
 *   │ env PULSE_SINK=DroidCam-Mic scrcpy  │ ─────▶ │ null-sink "DroidCam-Mic"
 *   │ --audio-source=mic --no-video       │ writes │ (created via pactl   │
 *   │ --no-window                         │ to its │  module-null-sink)   │
 *   └────────────────────────────────────┘ target  └─────────┬───────────┘
 *                                                sink          │ .monitor
 *                                                              ▼
 *                                          ┌──────────────────────┐
 *                                          │ source "DroidCam-Mic │
 *                                          │ .monitor"            │
 *                                          │ (apps see this as    │
 *                                          │  a microphone)       │
 *                                          └──────────────────────┘
 *
 * scrcpy uses SDL2 for audio output. SDL2's PulseAudio backend (and PipeWire's
 * pulse-server replacement) respects the PULSE_SINK env variable on startup,
 * so the audio stream is created directly on DroidCam-Mic as a sink-input —
 * no pw-link post-routing needed. The null-sink's `.monitor` source becomes a
 * recordable microphone. This is far more reliable than the previous
 * pw-link-based approach (route_scrcpy_mic.sh), which suffered from race
 * conditions between null-sink creation, scrcpy launch and port discovery,
 * especially on PipeWire.
 *
 * 100% userspace — no kernel modules, robust across NVIDIA/AMD/Intel.
 */
Singleton {
    id: root

    // ─── Public state ───────────────────────────────────────
    // `available` is a readonly composite defined in the dependency section
    // below (pactlPresent && (scrcpyPresent || droidcamCliPresent)).
    property bool running: false
    onRunningChanged: GlobalStates.phoneMicRunning = running
    property bool connecting: false
    property bool muted: false
    property bool monitorEnabled: false  // When true, user hears their own mic through speakers
    property string pulseSource: ""
    property string activeIp: ""
    property int activePort: 4748
    property int micGain: 100
    property string lastError: ""
    property bool defaultOverridden: false

    /** Live peak meter for the phone microphone source. `peakVolumePercent`
     *  is a 0-100 estimate read from `pactl list sources` for the active
     *  DroidCam-Mic.monitor source. `peakVolumeDb` converts it to decibels
     *  for visualizer widgets. */
    property real peakVolumePercent: 0.0
    property real peakVolumeDb: -96.0
    property string previousDefaultSource: ""

    /** Milliseconds since startMic() reached the `running` state.
     *  Updates every 1 second while running — used by the card to render
     *  "active for Xm Ys" inline. Zero when not running. */
    property int elapsedMs: 0

    signal stateChanged()
    signal errorOccurred(string message)
    signal criticalDepMissing(string depName, string message)

    // Internal — port to use when startMic falls through to the USB probe
    // path. The probe's onExited reads this value.
    property int _pendingPort: 4748

    // Internal — set to true when stopMic() is called intentionally.
    // Suppresses the "connection lost" path in the watchdog.
    property bool _userStopped: false

    /** PID of the detached audio session (0 when not running). */
    property int sessionPid: 0
    /** Unix timestamp when the current session started (from state file). */
    property int sessionStartedAt: 0

    readonly property string _sessionScript: Directories.scriptPath + "/phone/droidcam_session.sh"
    readonly property string _statusScript: Directories.scriptPath + "/phone/droidcam_status.sh"

    function _storeOriginalSink(name: string): void {
        Persistent.states.phoneMic.originalDefaultSink = name
    }

    function _clearOriginalSink(): void {
        Persistent.states.phoneMic.originalDefaultSink = ""
    }

    // 1s tick for the elapsed time counter.
    Timer {
        id: elapsedTicker
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.elapsedMs += 1000
    }

    readonly property string _setupScriptPath: Directories.scriptPath + "/phone/setup_droidcam_input.sh"
    readonly property string _teardownScriptPath: Directories.scriptPath + "/phone/teardown_droidcam_input.sh"

    // Which backend is currently active: "scrcpy" or "droidcam".
    // scrcpy is preferred because it doesn't require a separate app on the
    // phone — it uses ADB to capture the mic directly via the scrcpy server.
    property string _backend: ""

    Component.onCompleted: {
        // Respect the Phone tab toggle. If Phone integration is disabled in
        // config, we don't probe for droidcam-cli / pactl, and we skip the
        // swapped-sink safety check (nothing to restore — no mic was ever
        // started this session).
        if (!root._enabled) return
        detectDistroProc.running = true
        checkAvailProc.running = true
        // Defer the swapped-sink check to the next event loop tick so the
        // `_checkSwappedSinkProc` Process (declared later in the file) is
        // fully constructed before we touch it.
        Qt.callLater(() => {
            // If the shell reloaded while the default sink was swapped to
            // DroidCam-Mic but no phone-mic process is running anymore, the
            // user's audio would be stuck on the null-sink forever. Detect and
            // restore the saved original sink on startup.
            _checkSwappedSinkProc.running = true
        })
        // Re-adopt a previously running audio session after a shell restart.
        Qt.callLater(root._tryAdoptSession)
    }

    // Mirror KdeConnectService._enabled: stays dormant when Phone tab is off.
    readonly property bool _enabled: Config.options.policies.phone !== 0

    on_EnabledChanged: {
        if (root._enabled) {
            detectDistroProc.running = true
            checkAvailProc.running = true
            Qt.callLater(() => { _checkSwappedSinkProc.running = true })
            Qt.callLater(root._tryAdoptSession)
        } else {
            // Stop all background work. If a mic session is active, stop it
            // so we don't leave a null-sink / scrcpy process running.
            checkAvailProc.running = false
            peakMeterTimer.stop()
            micVerifyTimer.stop()
            monitorProc.running = false
            // stopMic() also unloads the null-sink and restores the default
            // sink, which is the safe thing to do when disabling the tab.
            if (root.running) root.stopMic()
        }
    }

    /** Re-checks if droidcam-cli + pactl are installed. Call after user runs the installer. */
    function refresh(): void {
        checkAvailProc.running = true
    }

    // Periodic re-check — picks up installs done outside the shell.
    Timer {
        interval: 30000
        repeat: true
        running: root._enabled && (GlobalStates.policiesPanelOpen || GlobalStates.dashboardPanelOpen || root.running)
        onTriggered: checkAvailProc.running = true
    }

    // Startup safety net: if the default sink is DroidCam-Mic (leftover from
    // a shell reload mid-launch) and no phone-mic scrcpy/droidcam process is
    // alive, restore the original default sink recorded in Persistent.
    Process {
        id: _checkSwappedSinkProc
        running: false
        command: ["bash", "-c",
            "DEFAULT=$(pactl get-default-sink 2>/dev/null); " +
            "echo \"$DEFAULT\"; " +
            "if [ \"$DEFAULT\" = \"DroidCam-Mic\" ]; then " +
            "  HAS_PROC=0; " +
            "  for pid in $(pgrep -x scrcpy 2>/dev/null); do " +
            "    if tr '\\0' ' ' < /proc/$pid/cmdline 2>/dev/null | grep -q -- '--audio-source=mic'; then " +
            "      HAS_PROC=1; break; " +
            "    fi; " +
            "  done; " +
            "  for pid in $(pgrep -x droidcam-cli 2>/dev/null); do " +
            "    if tr '\\0' ' ' < /proc/$pid/cmdline 2>/dev/null | grep -q -- '-a'; then " +
            "      HAS_PROC=1; break; " +
            "    fi; " +
            "  done; " +
            "  echo \"HAS_PROC=$HAS_PROC\"; " +
            "else " +
            "  echo \"HAS_PROC=1\"; " +
            "fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const text = String(this.text).trim()
                const isDroidCamDefault = text.indexOf("DroidCam-Mic") >= 0
                const hasProc = text.indexOf("HAS_PROC=1") >= 0
                if (isDroidCamDefault && !hasProc) {
                    const saved = root._originalDefaultSink
                    if (saved.length > 0 && saved !== "DroidCam-Mic") {
                        Quickshell.execDetached(["bash", "-c",
                            "pactl set-default-sink " + saved + " 2>/dev/null || true"])
                        root._clearOriginalSink()
                        console.log("[PhoneMicService] Restored leftover default sink swap to:", saved)
                    } else {
                        // No saved sink — dump DroidCam-Mic to avoid a muted
                        // system. The user can re-select their output manually.
                        Quickshell.execDetached(["bash", "-c",
                            "pactl set-default-sink @DEFAULT_SINK@ 2>/dev/null || true"])
                        console.warn("[PhoneMicService] DroidCam-Mic was default without saved sink; reset to @DEFAULT_SINK@")
                    }
                }
            }
        }
    }

    // ─── Session state probe (droidcam_session.sh status) ───
    // Probes both audio sessions (droidcam audio + scrcpy mic) and picks the
    // alive one. Used for boot adopt and watchdog.
    Process {
        id: statusProc
        running: false
        property string _target: "droidcam" // "droidcam" | "scrcpy-mic"
        command: ["bash", root._sessionScript, "status", "droidcam"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text).trim()
                let json = null
                try { json = JSON.parse(out) } catch (e) { json = null }
                if (!json) return
                root._onAudioSessionStatus(json)
            }
        }
    }

    function _probeStatus(target: string): void {
        statusProc._target = target
        statusProc.command = ["bash", root._sessionScript, "status", target]
        statusProc.running = false
        statusProc.running = true
    }

    // Boot adopt — if a live audio session exists, claim it.
    function _tryAdoptSession(): void {
        if (!root._enabled) return
        if (root.running || root.connecting) return
        root._probeStatus("droidcam")
    }

    function _onAudioSessionStatus(json): void {
        const alive = json.alive === "true" || json.alive === true
        const pid = parseInt(json.pid || "0") || 0
        const session = json.session || ""

        // Watchdog path — we were already running and the session died.
        if (root.running && !alive) {
            micWatchdogTimer.stop()
            if (!root._userStopped) {
                root._reportLaunchFailure("Microphone connection lost — the audio process exited. "
                    + "Check the phone (DroidCam/scrcpy) and reconnection.")
            } else {
                root.running = false
                root.connecting = false
                root.pulseSource = ""
                root.sessionPid = 0
                root.sessionStartedAt = 0
                root.stateChanged()
            }
            return
        }

        if (alive && pid > 0) {
            // Live session found.
            root.sessionPid = pid
            root.sessionStartedAt = parseInt(json.started || "0") || 0
            root.activePort = parseInt(json.port || "4748") || 4748
            root.activeIp = json.ip || ""
            root._backend = (session === "scrcpy-mic") ? "scrcpy" : "droidcam"

            if (root.sessionStartedAt > 0) {
                root.elapsedMs = Math.max(0, (Date.now() / 1000 | 0) - root.sessionStartedAt) * 1000
            }

            if (!root.running && !root.connecting) {
                // Ensure the null-sink exists (idempotent) and resolve the
                // monitor source, then claim running.
                setupProc.running = true
                root._pendingAdopt = true
            }
            return
        }

        // Not alive — if we were probing scrcpy as fallback, try that.
        if (statusProc._target === "droidcam") {
            root._probeStatus("scrcpy-mic")
            return
        }

        // No live session. Auto-restart if the user had the mic enabled.
        if (!root.running && !root.connecting) {
            const conf = Config.options.phone.microphone
            if (conf.enabled) {
                Qt.callLater(root.startMic)
            }
        }
    }

    property bool _pendingAdopt: false

    /** Completes a boot adoption — claims running without re-launching. */
    function _completeAdopt(): void {
        root.running = true
        root.connecting = false
        root.lastError = ""
        root.stateChanged()
        root._applyInitialState()
        micVerifyTimer.stop()
        failTimer.stop()
        // Watchdog keeps the session honest.
        micWatchdogTimer.restart()
    }

    // ─── Watchdog — drops running if the audio session/process dies ─────
    Timer {
        id: micWatchdogTimer
        interval: 5000
        repeat: true
        running: false
        onTriggered: {
            if (!root.running && !root.connecting) {
                micWatchdogTimer.stop()
                return
            }
            statusProc.running = false
            statusProc.running = true
        }
    }

    // ─── Granular dependency flags (for the install guide UI) ───
    property bool pactlPresent: false
    property bool scrcpyPresent: false
    property bool droidcamCliPresent: false
    property string detectedDistro: "unknown"

    // Composite: pactl is required AND (scrcpy OR droidcam-cli).
    // The ii tools phone as the microphone (IiMicService, PipeWire source `ii-tools-mic`) needs
    // none of the above: it is the first choice whenever the connected phone offers it.
    readonly property bool iiBackend: IiMicService.usable
    readonly property bool waitingForPhoneTap: root._backend === "iilink" && IiMicService.state === "asking"
    readonly property bool available: root.iiBackend
        || (root.pactlPresent && (root.scrcpyPresent || root.droidcamCliPresent))

    readonly property var missingDeps: {
        const deps = []
        if (!root.pactlPresent)
            deps.push({
                key: "pactl",
                name: Translation.tr("pactl (PulseAudio/PipeWire CLI)"),
                description: Translation.tr("Required for audio routing — creates a virtual null-sink that turns the phone mic stream into a recordable source."),
                present: false,
                installCommands: ({
                    arch: "sudo pacman -S pulseaudio-utils",
                    fedora: "sudo dnf install pulseaudio-utils",
                    debian: "sudo apt install pulseaudio-utils",
                })
            })
        if (!root.scrcpyPresent && !root.droidcamCliPresent)
            deps.push({
                key: "audio-backend",
                name: Translation.tr("scrcpy or DroidCam CLI"),
                description: Translation.tr("At least one audio backend is needed. scrcpy is preferred (no extra app on phone). DroidCam CLI is the fallback."),
                present: false,
                installCommands: ({
                    arch: "# Option 1 (preferred):\nsudo pacman -S scrcpy\n# Option 2:\nyay -S droidcam",
                    fedora: "# Option 1 (preferred):\nsudo dnf install scrcpy\n# Option 2: install from https://www.dev47apps.com/droidcam/linux/",
                    debian: "# Option 1 (preferred):\nsudo apt install scrcpy\n# Option 2:\nsudo apt install droidcam",
                })
            })
        return deps
    }

    Process {
        id: detectDistroProc
        running: false
        command: ["bash", "-c",
            "if [ -f /etc/arch-release ]; then echo arch; " +
            "elif [ -f /etc/fedora-release ]; then echo fedora; " +
            "elif [ -f /etc/debian_version ]; then echo debian; " +
            "else echo unknown; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = String(this.text).trim()
                if (d.length > 0) root.detectedDistro = d
            }
        }
    }

    // ─── Availability: pactl is required. Backend is either droidcam-cli
    // OR scrcpy (scrcpy is preferred since it's more reliable — droidcam-cli
    // has connection issues on some devices).
    Process {
        id: checkAvailProc
        running: false
        command: ["bash", "-c",
            "command -v pactl >/dev/null 2>&1 && echo 'pactl=1' || echo 'pactl=0'; " +
            "command -v scrcpy >/dev/null 2>&1 && echo 'scrcpy=1' || echo 'scrcpy=0'; " +
            "command -v droidcam-cli >/dev/null 2>&1 && echo 'droidcam=1' || echo 'droidcam=0'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text)
                root.pactlPresent = out.indexOf("pactl=1") >= 0
                root.scrcpyPresent = out.indexOf("scrcpy=1") >= 0
                root.droidcamCliPresent = out.indexOf("droidcam=1") >= 0
                root.stateChanged()
            }
        }
    }

    // ─── Setup: create null-sink, capture source name ─────
    Process {
        id: setupProc
        running: false
        command: ["bash", root._setupScriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const src = String(this.text).trim()
                if (src.length > 0) {
                    root.pulseSource = src
                    if (root._pendingAdopt) {
                        // Adoption path — the audio process was already running
                        // before this shell session. Just claim it.
                        root._pendingAdopt = false
                        root._completeAdopt()
                        return
                    }
                    // apply persisted state to the new source
                    root._applyInitialState()
                } else {
                    root.lastError = "Failed to create DroidCam null-sink — pactl may not have permission"
                    root.errorOccurred(root.lastError)
                    root.connecting = false
                    if (root._pendingAdopt) {
                        root._pendingAdopt = false
                        root.running = false
                        root.stateChanged()
                    }
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = String(this.text).trim()
                if (err.length > 0) {
                    root.lastError = err.split("\n")[0]
                    root.errorOccurred(root.lastError)
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.connecting = false
                root.stateChanged()
            }
        }
    }

    // NOTE: The scrcpy/droidcam audio processes are now launched DETACHED via
    // `droidcam_session.sh launch {audio|scrcpy-mic}` (setsid + nohup) so they
    // survive Quickshell restarts. Their lifecycle (kill on error/stop) is
    // handled by the session script, not by a child Process.

    // ─── Teardown: unload null-sink ────────────────────────
    Process {
        id: teardownProc
        running: false
        command: ["bash", root._teardownScriptPath]
    }

    // ─── Mute / gain control ───────────────────────────────
    Process { id: muteProc; running: false }
    Process { id: gainProc; running: false }
    Process { id: defaultProc; running: false }

    // ─── Fail timer — surfaces a connection error if neither
    // setupProc nor the mic launch have set running=true within 10s.
    Timer {
        id: failTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root.connecting || root.running) return
            if (root._retryScrcpyMic()) return
            micEvidenceRetryTimer.stop()
            root._reportLaunchFailure(
                "Could not connect within 10s — verify the phone is reachable "
                + "and the DroidCam/scrcpy app is open")
        }
    }

    // ─── IPC ───────────────────────────────────────────────
    IpcHandler {
        target: "phoneMic"
        function status(): string {
            return JSON.stringify({
                available: root.available,
                running: root.running,
                connecting: root.connecting,
                muted: root.muted,
                pulseSource: root.pulseSource,
                micGain: root.micGain,
                lastError: root.lastError
            })
        }
        function toggle(): void { root.toggleMic() }
        function mute(): void { root.toggleMute() }
    }

    // ─── Public API ────────────────────────────────────────

    /**
     * Starts the droidcam-cli audio process using Config.options.phone.microphone.
     *
     * Connection selection priority (mirrors PhoneCameraService):
     *   1. If user set `connection: "usb"` → use ADB directly.
     *   2. If user set `connection: "wifi"` AND configured a Wi-Fi IP → use Wi-Fi.
     *   3. Otherwise (most common: `wifi` with empty IP), probe USB ADB
     *      first. Prefer USB when the cable is plugged in; fall back to
     *      the Wi-Fi IP auto-detected from KDE Connect only if no USB
     *      device is available.
     *
     * The mode decision happens AFTER the null-sink setup completes
     * (startDelayTimer), so we keep _pendingPort around for the async path.
     */
    function startMic(): void {
        if (!root.available || root.running || root.connecting) return
        if (root.iiBackend) {
            root.lastError = ""
            root._backend = "iilink"
            IiMicService.request()
            return
        }
        if (!KdeConnectService.activeReachable) {
            root.lastError = "No reachable KDE Connect device — pair a device first"
            root.errorOccurred(root.lastError)
            return
        }

        // Clean up any leftover module-loopback from a previous session.
        // If the shell crashed/reloaded while "Hear yourself" (monitoring)
        // was enabled, the loopback module persists in the PipeWire daemon
        // and `root.monitorEnabled` is reset to false on reload — so
        // stopMic() would never unload it. The user would then "always
        // hear their microphone" even without toggling monitor mode.
        // Unloading here is safe: module-loopback has no side effects
        // beyond stopping the monitor route.
        Quickshell.execDetached(["bash", "-c",
            "pactl unload-module module-loopback 2>/dev/null; true"])

        root.connecting = true
        root.lastError = ""
        root._userStopped = false
        root._scrcpyAttempts = 0
        root._audioHijacked = false
        root._hijackSink = ""
        root._lastScrcpyError = ""
        root._pendingFailureFallback = ""
        root.stateChanged()

        const conf = Config.options.phone.microphone
        root._pendingPort = conf.port || 4748

        // 1. Create null-sink & capture .monitor source name.
        setupProc.running = true

        // 2. Wait for setup before deciding connection mode.
        // The setup creates the null-sink which is REQUIRED because scrcpy
        // (with PULSE_SINK=DroidCam-Mic) needs the sink to exist before it
        // launches — otherwise SDL2 falls back to the default sink and the
        // audio ends up on the speakers instead of becoming a mic source.
        startDelayTimer.restart()
        // 3. Schedule fail timer in case setup/launch hangs.
        failTimer.restart()
    }

    Timer {
        id: startDelayTimer
        interval: 2000
        repeat: false
        onTriggered: {
            // Only proceed if the null-sink was created (pulseSource is set).
            // If not, retry once more — the setupProc may still be running.
            if (root.pulseSource.length === 0) {
                startDelayRetryTimer.restart()
                return
            }
            root._decideAndLaunchAudio()
        }
    }

    // Retry the start delay if the null-sink wasn't created in time.
    Timer {
        id: startDelayRetryTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.pulseSource.length === 0 && root.connecting) {
                // Still no null-sink — give up.
                root.connecting = false
                failTimer.stop()
                root.lastError = "Failed to create null-sink — pactl may not have permission"
                root.errorOccurred(root.lastError)
                root.stateChanged()
                return
            }
            root._decideAndLaunchAudio()
        }
    }

    /**
     * Decides between scrcpy and droidcam backends, then launches.
     * scrcpy is preferred (no app needed on phone). Falls back to droidcam
     * if scrcpy is not installed.
     */
    function _decideAndLaunchAudio(): void {
        // If null-sink setup failed, _launchDroidcamAudio will surface
        // the error from `pulseSource` being empty.
        const conf = Config.options.phone.microphone

        // Check if scrcpy is available — prefer it over droidcam.
        if (KdeConnectService.scrcpyAvailable) {
            root._backend = "scrcpy"
            root._launchScrcpyMic()
            return
        }

        // Fall back to droidcam-cli.
        root._backend = "droidcam"

        // Case 1: explicit USB preference — launch immediately.
        if (conf.connection === "usb") {
            root._launchDroidcamAudio("usb", root._pendingPort, "")
            return
        }

        // Case 2: Wi-Fi preference with explicit IP — launch immediately.
        const userIp = (conf.wifiIp || "").trim()
        if (userIp.length > 0) {
            root._launchDroidcamAudio("wifi", root._pendingPort, userIp)
            return
        }

        // Case 3: probe USB first.
        usbProbeForStartup._oneShot = true
        usbProbeForStartup.running = true
    }

    /**
     * Launches scrcpy in audio-only mode with `--audio-source=mic`.
     *
     * Routing strategy: **default sink swap**. Before launching scrcpy, we
     * capture the current default sink name, then set `DroidCam-Mic` as the
     * new default. This guarantees that scrcpy's SDL2 audio backend opens
     * its sink-input on DroidCam-Mic — regardless of whether `PULSE_SINK`
     * env var is respected (it's unreliable on PipeWire).
     *
     * After 3s (restoreDefaultSinkTimer), the original default sink is
     * restored. Existing sink-inputs don't move when the default changes,
     * so scrcpy's audio stays on DroidCam-Mic.
     *
     * Without the swap, scrcpy writes to the user's default output
     * (speakers/Bluetooth) — the user hears their own phone mic through
     * their speakers, mute doesn't work, and "Hear yourself" stays on
     * forever because the audio never touches the null-sink.
     */
    function _launchScrcpyMic(): void {
        if (root.pulseSource.length === 0) {
            root.connecting = false
            failTimer.stop()
            root.lastError = "Failed to create null-sink — pactl may not have permission"
            root.errorOccurred(root.lastError)
            root.stateChanged()
            return
        }

        // Step 1: capture the current default sink so we can restore it later.
        defaultSinkSwapProc.running = true
    }

    /** Captures the original default sink name. Once captured, swaps the
     *  default sink to DroidCam-Mic and launches scrcpy. */
    Process {
        id: defaultSinkSwapProc
        running: false
        command: ["bash", "-c", "pactl get-default-sink 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const orig = String(this.text).trim()
                if (orig.length === 0) {
                    // Could not read the current default sink. Abort so we
                    // don't lose track of the original device forever.
                    root.connecting = false
                    failTimer.stop()
                    root.lastError = "Could not read current default audio sink — audio routing aborted"
                    root.errorOccurred(root.lastError)
                    root.stateChanged()
                    return
                }
                root._originalDefaultSink = orig
                root._storeOriginalSink(orig)
                // Set DroidCam-Mic as the default sink. scrcpy's SDL2 audio
                // backend opens its sink-input on the default sink when no
                // PULSE_SINK is set (or when it's ignored on PipeWire).
                Quickshell.execDetached(["bash", "-c",
                    "pactl set-default-sink DroidCam-Mic 2>/dev/null || true"])
                // Now launch scrcpy (no PULSE_SINK env needed — the default
                // sink swap handles the routing).
                // The restore timer is armed inside the launch, not here:
                // resolving the ADB target is asynchronous, and starting the
                // 3s countdown before scrcpy is even spawned could restore
                // the default sink out from under it.
                root._launchScrcpyMicInner()
            }
        }
    }

    /** Inner scrcpy launch — called by defaultSinkSwapProc after the swap. */
    function _launchScrcpyMicInner(): void {
        // Resolve the ADB target on demand — the phone's wireless-debugging
        // port changes on every toggle/reboot, and a stale one leaves scrcpy
        // with no device and the mic silently dead.
        KdeConnectService.withAdbTarget(targetArgs => root._launchScrcpyMicWithTarget(targetArgs))
    }

    function _launchScrcpyMicWithTarget(targetArgs): void {
        // --no-video      : don't capture video (audio only)
        // --no-window     : don't open an SDL window
        // --audio-source=mic : capture the phone's microphone
        // --audio-buffer=50  : low latency (50ms)
        const args = ["scrcpy", "--no-video", "--no-window",
                      "--audio-source=mic", "--audio-buffer=50"]
            .concat(targetArgs || [])

        root.activeIp = "(scrcpy)"
        root.activePort = 0
        root._backend = "scrcpy"
        root._userStopped = false

        // Launch detached (survives Quickshell restarts).
        micLaunchProc.command = ["bash", root._sessionScript, "launch", "scrcpy-mic"].concat(args)
        micLaunchProc.running = true

        // Restore the user's default sink as soon as scrcpy's stream shows up.
        root._armSinkRestore()

        // Backup: after 2s, also try to move any stray scrcpy sink-input
        // onto DroidCam-Mic (in case the default sink swap failed and the
        // sink-input landed on the speakers). This is the routeMicProc.
        routeMicTimer.restart()
        // micVerifyTimer (5s) checks the stream evidence → success.
        micVerifyTimer.restart()
        failTimer.restart()
    }

    /**
     * Watches for scrcpy's audio stream and restores the user's default sink
     * the moment it appears.
     *
     * The swap only has to outlive the stream's creation — every millisecond
     * past that is dead air on the user's speakers. A blind 3 s wait made
     * every launch, successful or not, mute the desktop for three seconds.
     * The 3 s is now only a ceiling for when the stream never shows up.
     */
    Timer {
        id: restoreDefaultSinkTimer
        property int elapsedMs: 0
        interval: 250
        repeat: true
        onTriggered: {
            restoreDefaultSinkTimer.elapsedMs += restoreDefaultSinkTimer.interval
            if (restoreDefaultSinkTimer.elapsedMs >= 3000) {
                restoreDefaultSinkTimer.stop()
                root._restoreDefaultSink()
                return
            }
            sinkInputProbeProc.running = false
            sinkInputProbeProc.running = true
        }
    }

    function _armSinkRestore(): void {
        restoreDefaultSinkTimer.elapsedMs = 0
        restoreDefaultSinkTimer.restart()
    }

    /** Presence check only: once scrcpy has a stream, the swap has done its
     *  job and the user's sink can go back. Where the stream landed is not
     *  judged here — routeMicProc still has 2 s to move it. */
    Process {
        id: sinkInputProbeProc
        running: false
        command: ["bash", "-c",
            "pactl list sink-inputs 2>/dev/null | grep -qi scrcpy && echo PRESENT || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (String(this.text).indexOf("PRESENT") < 0) return
                restoreDefaultSinkTimer.stop()
                root._restoreDefaultSink()
            }
        }
    }

    // Stored original default sink — restored after 3s or on stopMic().
    // Persisted so a shell reload mid-launch can recover the user's real
    // default sink instead of leaving DroidCam-Mic as default forever.
    property string _originalDefaultSink: Persistent.states.phoneMic.originalDefaultSink

    // How many times scrcpy has been spawned for the current startMic().
    property int _scrcpyAttempts: 0
    // Set when scrcpy's stream was found on a sink that isn't DroidCam-Mic,
    // which means another audio processor grabbed it before we could.
    property bool _audioHijacked: false
    property string _hijackSink: ""
    // Last ERROR/WARN line scrcpy wrote, so failures name a cause.
    property string _lastScrcpyError: ""
    // Non-empty while a failure report is waiting on the log read.
    property string _pendingFailureFallback: ""

    /** Puts the user's default sink back, if we swapped it. */
    function _restoreDefaultSink(): void {
        if (root._originalDefaultSink.length === 0) return
        Quickshell.execDetached(["bash", "-c",
            "pactl set-default-sink " + root._originalDefaultSink + " 2>/dev/null || true"])
        root._originalDefaultSink = ""
        root._clearOriginalSink()
    }

    /** Turns a failure into something the user can act on. The generic
     *  fallback is the last resort — it used to be the only message, which
     *  pointed at DroidCam even when scrcpy was the backend. */
    function _micFailureMessage(fallback: string): string {
        if (root._audioHijacked) {
            return "Phone mic audio was captured by another audio processor"
                + (root._hijackSink.length > 0 ? " (" + root._hijackSink + ")" : "")
                + " instead of the DroidCam-Mic sink.\n\n"
                + "Exclude \"scrcpy\" in that app's settings (EasyEffects: Preferences → "
                + "Excluded apps) and try again."
        }
        if (root._lastScrcpyError.length > 0)
            return "Phone microphone failed — " + root._lastScrcpyError
        return fallback
    }

    /** Reads scrcpy's log first so the error names a cause, then reports. */
    function _reportLaunchFailure(fallback: string): void {
        root._pendingFailureFallback = fallback
        scrcpyLogProc.running = false
        scrcpyLogProc.running = true
    }

    /**
     * Relaunches scrcpy once with a freshly resolved ADB target.
     *
     * Android re-rolls the wireless-debugging port constantly (observed:
     * five different ports in one session), so it can change in the window
     * between resolving the target and scrcpy reaching the device — which
     * kills the launch outright with "Could not find ADB device" or an
     * `adb push` that dies mid-transfer. Returns true when a retry started.
     */
    function _retryScrcpyMic(): bool {
        if (root._backend !== "scrcpy") return false
        if (root._userStopped) return false
        // Two retries, not one: a cold wireless ADB transport fails the
        // first launch often enough that a single retry still leaves a
        // visible failure rate.
        if (root._scrcpyAttempts >= 2) return false
        root._scrcpyAttempts++

        // No stop here: the process being retried is already dead, the
        // launcher overwrites its stale state file, and a concurrent stop
        // scan would race the replacement and kill it.
        failTimer.restart()

        // A non-empty _originalDefaultSink means the swap is still in
        // effect, so re-capturing it would record DroidCam-Mic as the
        // user's "real" sink and strand them on a null-sink.
        if (root._originalDefaultSink.length > 0) root._launchScrcpyMicInner()
        else root._launchScrcpyMic()
        return true
    }

    /**
     * Gathers everything needed to explain a failure: the last error scrcpy
     * logged, and which sink its stream ended up on. A stream sitting on a
     * sink other than DroidCam-Mic this late means another audio processor
     * claimed it and moved it back after routeMicProc tried — EasyEffects
     * does exactly that to every new output stream unless scrcpy is in its
     * excluded-apps list, and no default-sink juggling can beat it.
     */
    Process {
        id: scrcpyLogProc
        running: false
        command: ["bash", "-c",
            "L=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/ii/phone/scrcpy-mic.log\"; " +
            "[ -f \"$L\" ] && echo \"ERR:$(grep -aE '^(ERROR|WARN):' \"$L\" | tail -n1 | sed 's/^[A-Z]*: *//')\"; " +
            "D=$(pactl list short sinks 2>/dev/null | awk '$2==\"DroidCam-Mic\"{print $1}'); " +
            "S=$(pactl list sink-inputs 2>/dev/null | awk '" +
            "  /^Sink Input #/ { if (m) { print s; exit } m=0; s=\"\" }" +
            "  /^[ \\t]*Sink:/ { s=$2 }" +
            "  /scrcpy/ { m=1 }" +
            "  END { if (m) print s }'); " +
            "if [ -n \"$S\" ] && [ \"$S\" != \"$D\" ]; then " +
            "  echo \"HIJACK:$(pactl list short sinks 2>/dev/null | awk -v i=\"$S\" '$1==i{print $2}')\"; " +
            "fi; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(this.text).split("\n")
                root._lastScrcpyError = ""
                root._audioHijacked = false
                root._hijackSink = ""
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim()
                    if (line.startsWith("ERR:")) root._lastScrcpyError = line.substring(4).trim()
                    else if (line.startsWith("HIJACK:")) {
                        root._audioHijacked = true
                        root._hijackSink = line.substring(7).trim()
                    }
                }
                if (root._pendingFailureFallback.length === 0) return
                const fallback = root._pendingFailureFallback
                root._pendingFailureFallback = ""
                root._reportMicError(root._micFailureMessage(fallback))
            }
        }
    }

    /** Helper — reports an error and cleans up mic state. */
    function _reportMicError(message): void {
        root.connecting = false
        root.running = false
        root.pulseSource = ""
        root.elapsedMs = 0
        root.sessionPid = 0
        root.sessionStartedAt = 0
        root.lastError = message
        root.errorOccurred(root.lastError)
        root.stateChanged()
        micVerifyTimer.stop()
        failTimer.stop()
        routeMicTimer.stop()
        restoreDefaultSinkTimer.stop()
        micWatchdogTimer.stop()
        micEvidenceRetryTimer.stop()
        root._restoreDefaultSink()
        // Kill any detached session still alive.
        micSessionStopProc.running = false
        micSessionStopProc.running = true
        teardownProc.running = true
    }

    // ── Sink-input router (backup) ────────────────────────
    // Finds any sink-input from scrcpy that's NOT on DroidCam-Mic (i.e. it
    // landed on the default speakers because the default sink swap failed)
    // and moves it to DroidCam-Mic. This is a BACKUP to the default sink
    // swap — the primary routing method.
    //
    // Previous bug: the awk script used `if (matched)` but `matched` was
    // never defined — it should be `if (prev_matched)`. This meant only
    // the LAST sink-input in the list would be checked/moved, and if
    // scrcpy wasn't the last one, its sink-input was silently skipped.
    Process {
        id: routeMicProc
        running: false
        // Re-running the (idempotent) setup first heals two failure modes:
        // a teardown from the previous stop cycle racing this start and
        // deleting the null-sink after setup reused it, and PipeWire's
        // stream-restore pinning scrcpy's stream to a remembered sink —
        // only an explicit move both overrides and re-learns the target,
        // and the move silently no-ops when the sink is missing.
        command: ["bash", "-c",
            "bash " + root._setupScriptPath + " >/dev/null 2>&1; " +
            // Parse `pactl list sink-inputs` to find sink-input IDs whose
            // properties contain "scrcpy" (application.name, media.name,
            // application.process.binary, etc). For each matching ID, move
            // it to DroidCam-Mic.
            "pactl list sink-inputs 2>/dev/null | awk '" +
            "  /^Sink Input #/ {" +
            "    if (prev_matched) print prev_id;" +
            "    prev_id = substr($3, 2);" +
            "    prev_matched = 0" +
            "  }" +
            "  /scrcpy/ { prev_matched = 1 }" +
            "  END { if (prev_matched) print prev_id }" +
            "' | while read id; do" +
            "  pactl move-sink-input \"$id\" DroidCam-Mic 2>/dev/null; " +
            "done"
        ]
        onExited: (code, status) => {
            // Check the evidence right after the repair, so a successful
            // move is noticed immediately instead of on the next timer.
            if (!root.connecting) return
            micEvidenceProc.running = false
            micEvidenceProc.running = true
        }
    }

    Timer {
        id: routeMicTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.connecting && root._backend === "scrcpy") {
                routeMicProc.running = true
            }
        }
    }

    function _launchDroidcamAudio(mode: string, port: int, ip: string): void {
        if (root.pulseSource.length === 0) {
            // Setup failed; lastError already set.
            root.connecting = false
            failTimer.stop()
            root.stateChanged()
            return
        }

        // Args: env PULSE_SINK=DroidCam-Mic droidcam-cli -a -nocontrols [ip] [port]
        // -a enables audio, -nocontrols avoids reading stdin.
        const args = ["env", "PULSE_SINK=DroidCam-Mic", "droidcam-cli", "-a", "-nocontrols"]
        let useAdbFallback = false
        if (mode === "usb") {
            args.push("adb", String(port))
            useAdbFallback = true
        } else {
            // Wi-Fi mode. Without a real IP we can't proceed.
            if (!ip) {
                root.connecting = false
                failTimer.stop()
                root.lastError = "Could not detect USB or Wi-Fi IP.\n\nEither:\n• Plug your phone via USB with ADB debugging enabled (Settings → Developer options), or\n• Open the DroidCam app on your phone and set its Wi-Fi IP in Connection → Phone IP below."
                root.errorOccurred(root.lastError)
                root.stateChanged()
                return
            }
            args.push(ip, String(port))
        }

        root.activeIp = ip || (useAdbFallback ? "(usb)" : "")
        root.activePort = port
        root._backend = "droidcam"
        root._userStopped = false

        // Launch detached (survives Quickshell restarts). The script prints
        // the new PID on stdout.
        micLaunchProc.command = ["bash", root._sessionScript, "launch", "audio"].concat(args)
        micLaunchProc.running = true

        // Don't set running=true immediately. Validation happens via
        // micVerifyTimer (process alive + sink-input evidence).
        micVerifyTimer.restart()
    }

    Timer {
        id: micVerifyTimer
        interval: 5000
        repeat: false
        onTriggered: {
            // Verify success for both backends (scrcpy and droidcam-cli).
            // Success requires the process to be alive AND evidence that audio
            // actually reaches the null-sink (a RUNNING sink-input on
            // DroidCam-Mic), which the status script reports.
            if (root.connecting) {
                micEvidenceProc.running = false
                micEvidenceProc.running = true
            }
        }
    }

    // ─── Mic launch probe (droidcam_session.sh launch audio/scrcpy-mic) ──
    Process {
        id: micLaunchProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const pid = parseInt(String(this.text).trim()) || 0
                // No PID is not the same as no session: the launcher can lose
                // track of a process that started perfectly well. Whether the
                // mic works is settled by the stream evidence check, so record
                // what came back and let that verdict stand on its own.
                root.sessionPid = pid
                root.sessionStartedAt = Date.now() / 1000 | 0
                root.stateChanged()
            }
        }
    }

    // ─── Mic stream evidence check (droidcam_status.sh) ───
    Process {
        id: micEvidenceProc
        running: false
        command: ["bash", root._statusScript]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text).trim()
                let json = null
                try { json = JSON.parse(out) } catch (e) { json = null }
                if (!json) return
                if (root.connecting) {
                    const procAlive = (root._backend === "scrcpy")
                        ? json.audio_running === true
                        : json.audio_running === true
                    if (procAlive && json.audio_has_sink_input === true) {
                        // Real audio path confirmed.
                        root.running = true
                        root.connecting = false
                        root.elapsedMs = 0
                        failTimer.stop()
                        root.stateChanged()
                        root._applyInitialState()
                        micWatchdogTimer.restart()
                    } else if (procAlive) {
                        // Process alive but no sink-input yet — retry once.
                        micEvidenceRetryTimer.restart()
                    } else if (!root._retryScrcpyMic()) {
                        failTimer.stop()
                        root._reportLaunchFailure(
                            "Phone microphone process exited — check the phone connection "
                            + "and that Wireless debugging / DroidCam is still on")
                    }
                }
            }
        }
    }

    Timer {
        id: micEvidenceRetryTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.connecting) {
                // Repair the routing before re-checking it, not just look
                // again at a stream that nothing has moved in the meantime.
                routeMicProc.running = false
                routeMicProc.running = true
            }
        }
    }

    function stopMic(): void {
        if (root._backend === "iilink") {
            // The phone's side ends the stream; IiMicService's state clears running.
            monitorProc.command = ["bash", "-c", "pactl unload-module module-loopback 2>/dev/null; true"]
            monitorProc.running = true
            root.monitorEnabled = false
            IiMicService.stop()
            return
        }
        if (!root.running && !root.connecting) return
        failTimer.stop()
        startDelayTimer.stop()
        startDelayRetryTimer.stop()
        micVerifyTimer.stop()
        routeMicTimer.stop()
        restoreDefaultSinkTimer.stop()
        // Restore the original default sink if we swapped it during launch.
        // This is critical — if we don't restore it, the user's audio output
        // stays on DroidCam-Mic (a null-sink that absorbs all audio), and
        // the user can't hear any system audio.
        if (root._originalDefaultSink.length > 0) {
            Quickshell.execDetached(["bash", "-c",
                "pactl set-default-sink " + root._originalDefaultSink +
                " 2>/dev/null || true"])
            root._originalDefaultSink = ""
            root._clearOriginalSink()
        }
        // Cancel any pending USB probe from startMic case 3.
        usbProbeForStartup._oneShot = false
        usbProbeForStartup.running = false
        // Kill the detached session(s) via the session script (PID tracked).
        root._userStopped = true
        micWatchdogTimer.stop()
        micEvidenceRetryTimer.stop()
        micSessionStopProc.running = false
        micSessionStopProc.running = true
        // ALWAYS unload any module-loopback — not just when monitorEnabled.
        // This catches leftover loopbacks from a previous shell session where
        // monitor was toggled but the flag was reset on reload.
        monitorProc.command = ["bash", "-c",
            "pactl unload-module module-loopback 2>/dev/null; " +
            "rm -f /tmp/ii-monitor-loopback-pid 2>/dev/null; " +
            "true"]
        monitorProc.running = true
        root.monitorEnabled = false
        root.running = false
        root.connecting = false
        root.pulseSource = ""
        root.elapsedMs = 0
        root.sessionPid = 0
        root.sessionStartedAt = 0
        root.stateChanged()
        // Tear down the null-sink for both backends.
        teardownProc.running = true
    }

    // ─── Session stop (droidcam_session.sh stop <backend>) ──
    Process {
        id: micSessionStopProc
        running: false
        property string _target: "audio"
        command: ["bash", root._sessionScript, "stop", "audio"]
        onExited: (code, status) => {
            // Chain to the scrcpy-mic session exactly once, then reset for
            // the next caller. Re-arming unconditionally here turns one stop
            // into a permanent stop loop that kills every new scrcpy within
            // milliseconds of launch.
            if (micSessionStopProc._target === "scrcpy-mic") {
                micSessionStopProc._target = "audio"
                micSessionStopProc.command = ["bash", root._sessionScript, "stop", "audio"]
                return
            }
            micSessionStopProc._target = "scrcpy-mic"
            micSessionStopProc.command = ["bash", root._sessionScript, "stop", "scrcpy-mic"]
            micSessionStopProc.running = true
        }
    }

    function toggleMic(): void {
        if (root.running || root.connecting) stopMic()
        else startMic()
    }

    function toggleMute(): void {
        if (!root.running || root.pulseSource.length === 0) {
            root.muted = !root.muted
            return
        }
        root.muted = !root.muted
        muteProc.command = ["bash", "-c",
            "pactl set-source-mute '" + root.pulseSource + "' " +
            (root.muted ? "1" : "0") + " 2>/dev/null || true"]
        muteProc.running = true
        root.stateChanged()
    }

    function setGain(percent: int): void {
        root.micGain = Math.max(0, Math.min(200, percent))
        const conf = Config.options.phone.microphone
        conf.micGain = root.micGain
        if (root.running && root.pulseSource.length > 0) {
            gainProc.command = ["bash", "-c",
                "pactl set-source-volume '" + root.pulseSource + "' " +
                root.micGain + "% 2>/dev/null || true"]
            gainProc.running = true
        }
    }

    function overrideDefaultSource(): void {
        if (!root.running || root.pulseSource.length === 0) return
        if (root.defaultOverridden) return
        // Capture the current default source name first.
        defaultQueryProc.running = true
    }

    function restoreDefaultSource(): void {
        if (!root.defaultOverridden) return
        if (root.previousDefaultSource.length === 0) return
        defaultProc.command = ["bash", "-c",
            "pactl set-default-source " + root.previousDefaultSource + " 2>/dev/null || true"]
        defaultProc.running = true
        root.defaultOverridden = false
        root.stateChanged()
    }

    Process {
        id: defaultQueryProc
        running: false
        command: ["bash", "-c", "pactl get-default-source 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const src = String(this.text).trim()
                root.previousDefaultSource = src
                if (src.length > 0 && root.pulseSource.length > 0) {
                    defaultProc.command = ["bash", "-c",
                        "pactl set-default-source " + root.pulseSource + " 2>/dev/null || true"]
                    defaultProc.running = true
                    root.defaultOverridden = true
                    root.stateChanged()
                }
            }
        }
    }

    /**
     * Toggles monitor mode — when enabled, the user hears their own
     * microphone audio through the default speakers. Uses PipeWire
     * module-loopback to create a path from the null-sink's .monitor
     * source to the default audio output.
     */
    function toggleMonitor(): void {
        if (!root.running) return
        root.monitorEnabled = !root.monitorEnabled
        if (root.monitorEnabled) {
            // Create a loopback from DroidCam-Mic.monitor to default output.
            monitorProc.command = ["bash", "-c",
                "pactl load-module module-loopback source=" +
                (root._backend === "iilink" ? IiMicService.sourceName : "DroidCam-Mic.monitor") + " " +
                "sink=@DEFAULT_SINK@ 2>/dev/null && " +
                "echo $! > /tmp/ii-monitor-loopback-pid || true"]
            monitorProc.running = true
        } else {
            // Unload the loopback module.
            monitorProc.command = ["bash", "-c",
                "pactl unload-module module-loopback 2>/dev/null; " +
                "rm -f /tmp/ii-monitor-loopback-pid 2>/dev/null; " +
                "true"]
            monitorProc.running = true
        }
        root.stateChanged()
    }

    Process { id: monitorProc; running: false }

    // The ii tools phone's stream drives running/connecting while it is the backend, however it
    // started (this panel, or the phone's own Mic screen).
    Connections {
        target: IiMicService
        function onStateChanged(): void {
            const st = IiMicService.state
            if (st === "idle") {
                if (root._backend !== "iilink") return
                root.running = false
                root.connecting = false
                root.pulseSource = ""
                root.monitorEnabled = false
                root.elapsedMs = 0
                root._backend = ""
            } else if (root.running && root._backend !== "iilink") {
                return // a scrcpy/DroidCam session owns the mic
            } else {
                root._backend = "iilink"
                root.connecting = st !== "live"
                root.running = st === "live"
                root.pulseSource = st === "live" ? IiMicService.sourceName : ""
                if (st === "live") root.elapsedMs = 0
            }
            root.stateChanged()
        }
        function onErrorOccurred(message: string): void {
            root.lastError = message
            root.errorOccurred(message)
        }
    }

    // ─── Internals ─────────────────────────────────────────

    /**
     * Async USB ADB probe for startMic. When _oneShot is true, the onExited
     * handler picks up _pendingPort and continues the launch flow after
     * the probe finishes.
     *
     * Replaces the old synchronous adbProbeForFallback pattern — see
     * PhoneCameraService.qml for the rationale (race on first invocation).
     */
    Process {
        id: usbProbeForStartup
        running: false
        property bool _oneShot: false
        command: ["bash", "-c",
            "if command -v adb >/dev/null 2>&1; then " +
            "  STATE=$(adb get-state 2>/dev/null); " +
            "  [ \"$STATE\" = \"device\" ] && exit 0 || exit 1; " +
            "else exit 1; fi"]
        onExited: (code, status) => {
            const now = (code === 0)
            if (now !== KdeConnectService.adbReachable) {
                KdeConnectService.adbReachable = now
            }
            if (!usbProbeForStartup._oneShot) return
            usbProbeForStartup._oneShot = false

            if (now) {
                // USB available — prefer it over the stale Wi-Fi IP from
                // KDE Connect.
                root._launchDroidcamAudio("usb", root._pendingPort, "")
            } else {
                // USB not available — try the auto-detected Wi-Fi IP.
                const conf = Config.options.phone.microphone
                const ip = root._resolveIp(conf)
                if (!ip) {
                    root.connecting = false
                    failTimer.stop()
                    root.lastError = "Could not detect USB (no device plugged / ADB debugging off) and no Wi-Fi IP configured.\n\nEither:\n• Plug your phone via USB with ADB debugging enabled, or\n• Open the DroidCam app on your phone and set its Wi-Fi IP in Connection → Phone IP below."
                    root.errorOccurred(root.lastError)
                    root.stateChanged()
                    return
                }
                root._launchDroidcamAudio("wifi", root._pendingPort, ip)
            }
        }
    }

    function _applyInitialState(): void {
        const conf = Config.options.phone.microphone
        // Mute
        root.muted = false // always start unmuted; user can toggle
        // Gain
        if (conf.micGain !== 100) root.setGain(conf.micGain)
        // Default override
        if (conf.setAsDefault) root.overrideDefaultSource()
    }

    function _resolveIp(conf): string {
        if (conf.connection === "usb") return ""
        const configuredIp = (conf.wifiIp || "").trim()
        if (configuredIp.length > 0) return configuredIp
        return root._lastKnownIp
    }

    property string _lastKnownIp: ""

    Process {
        id: ipFetcher
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text).trim()
                const lines = out.split("\n")
                for (const line of lines) {
                    const trimmed = line.trim()
                    const m = /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/.exec(trimmed)
                    if (m) {
                        root._lastKnownIp = m[1]
                        root.stateChanged()
                        return
                    }
                }
            }
        }
    }

    function _fetchDeviceIp(): void {
        const devId = KdeConnectService.activeDeviceId
        if (!devId) {
            root._lastKnownIp = ""
            return
        }
        ipFetcher.command = ["bash", "-c",
            "QDBUS=$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus); " +
            "$QDBUS org.kde.kdeconnect " +
            "/modules/kdeconnect/devices/" + devId +
            " org.kde.kdeconnect.device.reachableAddresses 2>/dev/null"]
        ipFetcher.running = true
    }

    // If user switches device mid-stream, stop the mic.
    Connections {
        target: KdeConnectService
        ignoreUnknownSignals: true
        function onActiveDeviceIdChanged() {
            if (root.running || root.connecting) {
                root.stopMic()
            }
            root._lastKnownIp = ""
            root._fetchDeviceIp()
        }
        function onActiveReachableChanged() {
            if (KdeConnectService.activeReachable) {
                root._fetchDeviceIp()
            }
        }
    }

    // Peak meter polling. We sample the source volume reported by pactl
    // and convert it to a percentage/dB value for UI visualizers. This is
    // the source *gain* level, not the true audio signal, but it gives
    // immediate visual feedback that the mic source is alive.
    Timer {
        id: peakMeterTimer
        interval: 120
        repeat: true
        running: root.running && root.pulseSource.length > 0
        onTriggered: {
            peakMeterProc.running = false
            peakMeterProc.running = true
        }
    }

    Process {
        id: peakMeterProc
        running: false
        command: ["bash", "-c",
            "SRC='" + root.pulseSource + "'; " +
            "pactl list sources | awk " +
            "'BEGIN{found=0} /^Source /{found=0} " +
            "{if (found && /^[[:space:]]*Volume:/) " +
            "{match($0, /([0-9]+)%/); print substr($0, RSTART, RLENGTH-1); exit}} " +
            "$0 ~ SRC {found=1}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = String(this.text).trim()
                const pct = parseFloat(txt)
                if (!isNaN(pct) && pct >= 0) {
                    root.peakVolumePercent = pct
                    root.peakVolumeDb = pct > 0
                        ? (20 * Math.log10(Math.max(0.0001, pct / 100)))
                        : -96.0
                } else {
                    root.peakVolumePercent = 0
                    root.peakVolumeDb = -96.0
                }
            }
        }
    }

    // Initial fetch on completed — gives us the IP immediately if device is
    // already active when the shell boots.
    Timer {
        interval: 3000
        repeat: false
        running: true
        onTriggered: root._fetchDeviceIp()
    }
}
