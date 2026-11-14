pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import ".."
import qs
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Phone Camera Service — bridges droidcam-cli (video mode) into a reactive QML
 * state for the Phone sidebar panel.
 *
 * Important droidcam-cli usage notes:
 *   • The PC connects TO the phone (not the other way around). The phone just
 *     listens on port 4747 waiting for connections from the droidcam-cli.
 *   • Used flags (verified with droidcam-cli 2.1.5):
 *       -v          enable video (default, but explicit)
 *       -a          enable audio (used by PhoneMicService, not here)
 *       -hflip      horizontal mirror
 *       -vflip      vertical flip
 *       -nocontrols disable stdin controls (clean process exit on SIGTERM)
 *       -size=WxH   resolution (no -- prefix, no --fps exists)
 *       -dev=PATH   choose v4l2 device explicitly
 *   • Camera facing (front/back) is NOT a CLI flag — it must be changed in the
 *     Android app's settings UI before connecting. We expose it in config for
 *     future Android-side automation.
 *
 * State:
 *   • `available` — droidcam-cli is installed (periodic re-check every 10s).
 *   • `running` — process is alive AND /dev/videoN has been detected.
 *   • `connecting` — startCamera() has fired, awaiting handshake.
 *   • `lastError` — last failure reason (surfaced via errorOccurred).
 *
 * IP resolution priority:
 *   1. Config.options.phone.webcam.wifiIp (user override)
 *   2. KDE Connect DBus property `org.kde.kdeconnect.device.reachableAddresses`
 *      (returns the IPs KDE Connect is currently using for the active device).
 */
Singleton {
    id: root

    // ─── Public state ───────────────────────────────────────
    // "ii" whenever ii tools is the active phone service (connected or not: an
    // offline phone says so instead of offering DroidCam), unless Settings → ii tools
    // turned the webcam off or asks for DroidCam; otherwise "droidcam".
    readonly property string backend: (KdeConnectService.activeIsIi
        && IiCameraService.enabled
        && !IiCameraService.useDroidcam) ? "ii" : "droidcam"

    readonly property bool running: root.backend === "ii"
        ? IiCameraService.state === "live"
        : root._droidcamRunning
    onRunningChanged: GlobalStates.phoneCameraRunning = running
    readonly property bool connecting: root.backend === "ii"
        ? (IiCameraService.state === "asking" || IiCameraService.state === "starting")
        : root._droidcamConnecting
    readonly property string videoDevice: root.backend === "ii"
        ? IiCameraService.videoDevice
        : root._droidcamVideoDevice
    property string activeIp: ""
    property int activePort: 4747
    readonly property string lastError: root.backend === "ii"
        ? IiCameraService.lastError
        : root._droidcamLastError

    /** Milliseconds since startCamera() successfully detected /dev/videoN.
     *  Updates every 1 second while running — used by the card to render
     *  "active for Xm Ys" inline. Zero when not running. */
    readonly property int elapsedMs: root.backend === "ii"
        ? IiCameraService.elapsedMs
        : root._droidcamElapsedMs

    // DroidCam backing state (kept separate so public properties stay bound).
    property bool _droidcamRunning: false
    property bool _droidcamConnecting: false
    property string _droidcamVideoDevice: ""
    property string _droidcamLastError: ""
    property int _droidcamElapsedMs: 0
    property string _droidcamDistro: "unknown"

    signal stateChanged()
    signal errorOccurred(string message)
    signal criticalDepMissing(string depName, string message)

    onBackendChanged: {
        if (root.backend === "ii") {
            checkAvailProc.running = false
            detectDistroProc.running = false
            ipFetcher.running = false
            if (root._droidcamRunning || root._droidcamConnecting)
                root._stopDroidcam()
        } else if (root._enabled) {
            if (root._droidcamDistro === "unknown")
                detectDistroProc.running = true
            checkAvailProc.running = true
            root._fetchDeviceIp()
        }
        root.stateChanged()
    }

    Connections {
        target: IiCameraService
        function onStateChanged() {
            if (root.backend === "ii")
                root.stateChanged()
        }
        function onErrorOccurred(message) {
            if (root.backend === "ii")
                root.errorOccurred(message)
        }
    }

    // Internal — port to use when startCamera falls through to the USB
    // probe path. The probe's onExited reads this value.
    property int _pendingPort: 4747

    // Internal — set to true when stopCamera() is called intentionally.
    // Suppresses the "Connection failed" error in droidcamProc.onExited,
    // which fires with a non-zero exit code because SIGTERM = non-zero.
    // Without this, every stop (including from flipCamera/toggleMirror
    // restarts) would surface a spurious error toast.
    property bool _userStopped: false

    // Internal — droidcam-cli found the loopback device already claimed by
    // another producer. We then create a dedicated one (once per start
    // attempt) and relaunch with the same arguments.
    property bool _deviceBusy: false
    property bool _deviceCreateTried: false
    property var _lastLaunch: null // { mode, port, ip }

    // 1s tick for the elapsed time counter. Cheap — just an integer bump.
    Timer {
        id: elapsedTicker
        interval: 1000
        repeat: true
        running: root.backend === "droidcam" && root._droidcamRunning
        onTriggered: root._droidcamElapsedMs += 1000
    }

    Component.onCompleted: {
        GlobalStates.phoneCameraRunning = root.running
        // Respect the Phone tab toggle and ii backend.
        if (!root._enabled || root.backend === "ii") return
        detectDistroProc.running = true
        checkAvailProc.running = true
    }

    // Mirror KdeConnectService._enabled: stays dormant when Phone tab is off.
    readonly property bool _enabled: Config.options.policies.phone !== 0

    on_EnabledChanged: {
        if (root._enabled) {
            if (root.backend === "droidcam") {
                detectDistroProc.running = true
                checkAvailProc.running = true
            }
        } else {
            // Stop all background work and reset state.
            checkAvailProc.running = false
            root._stopDroidcam()
            if (IiCameraService.state !== "idle")
                IiCameraService.stop()
        }
    }

    /** Re-checks if camera dependencies are installed. Call after user runs the installer. */
    function refresh(): void {
        if (root.backend === "ii") {
            IiCameraService.refresh()
            return
        }
        checkAvailProc.running = true
    }

    // Periodic re-check — picks up installs done outside the shell.
    Timer {
        interval: 30000
        repeat: true
        running: root._enabled && root.backend === "droidcam"
            && (GlobalStates.policiesPanelOpen || GlobalStates.dashboardPanelOpen || root._droidcamRunning)
        onTriggered: checkAvailProc.running = true
    }

    // ─── Granular dependency flags (for the install guide UI) ───
    property bool droidcamCliPresent: false
    property bool v4l2loopbackLoaded: false
    property bool v4l2loopbackInstalled: false
    property bool v4lUtilsPresent: false
    property bool mpvPresent: false

    // Composite: droidcam-cli + v4l2loopback module (loaded or installed on system) are the hard requirements.
    // v4l-utils and mpv are recommended (device detection + preview window).
    readonly property bool available: root.backend === "ii"
        ? IiCameraService.available
        : (root.droidcamCliPresent && (root.v4l2loopbackLoaded || root.v4l2loopbackInstalled))

    /** Array of missing dependency descriptors for the install guide popup.
     *  Each entry: { key, name, description, present, installCommands: {distro: cmd} } */
    readonly property var missingDeps: root.backend === "ii"
        ? IiCameraService.missingDeps
        : root._droidcamMissingDeps

    readonly property var _droidcamMissingDeps: {
        const deps = []
        if (!root.droidcamCliPresent)
            deps.push({
                key: "droidcam-cli",
                name: Translation.tr("DroidCam CLI"),
                description: Translation.tr("Connects to the DroidCam app on your phone and streams video to /dev/videoN"),
                present: false,
                installCommands: _droidcamInstallCommands
            })
        if (!root.v4l2loopbackLoaded && !root.v4l2loopbackInstalled)
            deps.push({
                key: "v4l2loopback",
                name: Translation.tr("v4l2loopback kernel module"),
                description: Translation.tr("Creates virtual /dev/videoN devices that DroidCam writes to. Without it, droidcam-cli has nowhere to stream."),
                present: false,
                installCommands: _v4l2loopbackInstallCommands
            })
        if (!root.v4lUtilsPresent)
            deps.push({
                key: "v4l-utils",
                name: Translation.tr("v4l-utils (v4l2-ctl)"),
                description: Translation.tr("Recommended for device detection and live mirror/flip controls"),
                present: false,
                installCommands: _v4lUtilsInstallCommands
            })
        if (!root.mpvPresent)
            deps.push({
                key: "mpv",
                name: Translation.tr("mpv (optional)"),
                description: Translation.tr("Recommended for the webcam preview window. Falls back to ffplay/vlc if absent."),
                present: false,
                installCommands: _mpvInstallCommands
            })
        return deps
    }

    readonly property var _droidcamInstallCommands: ({
        arch: "yay -S droidcam",
        fedora: "# Enable RPM Fusion first, then:\nsudo dnf install android-tools\n# Download from https://www.dev47apps.com/droidcam/linux/",
        debian: "# Download from https://www.dev47apps.com/droidcam/linux/\n# Or: sudo apt install droidcam",
        opensuse: "# Download from https://www.dev47apps.com/droidcam/linux/\nsudo zypper install android-tools"
    })
    readonly property var _v4l2loopbackInstallCommands: ({
        arch: "yay -S v4l2loopback-dkms\nsudo modprobe v4l2loopback\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf",
        fedora: "sudo dnf install akmod-v4l2loopback\nsudo modprobe v4l2loopback\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf",
        debian: "sudo apt install v4l2loopback-dkms\nsudo modprobe v4l2loopback\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf",
        opensuse: "sudo zypper install v4l2loopback-kmp-default\nsudo modprobe v4l2loopback\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf"
    })
    readonly property var _v4lUtilsInstallCommands: ({
        arch: "sudo pacman -S v4l-utils",
        fedora: "sudo dnf install v4l-utils",
        debian: "sudo apt install v4l-utils",
        opensuse: "sudo zypper install v4l-utils"
    })
    readonly property var _mpvInstallCommands: ({
        arch: "sudo pacman -S mpv",
        fedora: "sudo dnf install mpv",
        debian: "sudo apt install mpv",
        opensuse: "sudo zypper install mpv"
    })

    /** Auto-detected distro id: "arch" | "fedora" | "debian" | "opensuse" | "unknown".
     *  Used by the install guide to show the right commands. */
    readonly property string detectedDistro: root.backend === "ii"
        ? IiCameraService.detectedDistro
        : root._droidcamDistro

    // ─── Distro detection (runs once on startup) ──────────
    Process {
        id: detectDistroProc
        running: false
        command: ["bash", "-c",
            "distro=unknown; " +
            "if [ -r /etc/os-release ]; then " +
            "  os_info=$(ID=\"\"; ID_LIKE=\"\"; . /etc/os-release 2>/dev/null; printf '%s %s' \"$ID\" \"$ID_LIKE\" | tr '[:upper:]' '[:lower:]'); " +
            "  for tok in $os_info; do " +
            "    case \"$tok\" in " +
            "      arch|manjaro|endeavouros|cachyos|garuda|artix|arcolinux) distro=arch; break;; " +
            "      fedora|nobara|bazzite|ultramarine) distro=fedora; break;; " +
            "      debian|ubuntu|linuxmint|pop|neon|elementary|zorin) distro=debian; break;; " +
            "      opensuse*|suse|sles|sled) distro=opensuse; break;; " +
            "    esac; " +
            "  done; " +
            "fi; " +
            "echo \"$distro\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = String(this.text).trim()
                if (d.length > 0) root._droidcamDistro = d
            }
        }
    }

    // ─── Granular dependency check ────────────────────────
    // Checks all 4 deps in a single bash invocation and parses the results.
    // Checks both loaded (lsmod) and installed on kernel (modinfo).
    Process {
        id: checkAvailProc
        running: false
        command: ["bash", "-c",
            // Each line: "dep=0" or "dep=1"
            "command -v droidcam-cli >/dev/null 2>&1 && echo 'droidcam=1' || echo 'droidcam=0'; " +
            "lsmod 2>/dev/null | grep -q '^v4l2loopback' && echo 'v4l2loopback_loaded=1' || echo 'v4l2loopback_loaded=0'; " +
            "modinfo v4l2loopback >/dev/null 2>&1 && echo 'v4l2loopback_installed=1' || echo 'v4l2loopback_installed=0'; " +
            "command -v v4l2-ctl >/dev/null 2>&1 && echo 'v4lutils=1' || echo 'v4lutils=0'; " +
            "command -v mpv >/dev/null 2>&1 && echo 'mpv=1' || echo 'mpv=0'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text)
                root.droidcamCliPresent = out.indexOf("droidcam=1") >= 0
                root.v4l2loopbackLoaded = out.indexOf("v4l2loopback_loaded=1") >= 0
                root.v4l2loopbackInstalled = out.indexOf("v4l2loopback_installed=1") >= 0
                root.v4lUtilsPresent = out.indexOf("v4lutils=1") >= 0
                root.mpvPresent = out.indexOf("mpv=1") >= 0
                root.stateChanged()
            }
        }
    }

    // Process to auto-load v4l2loopback kernel module if installed but not loaded
    Process {
        id: loadModuleProc
        running: false
        command: ["bash", "-c", "sudo -n modprobe v4l2loopback 2>/dev/null || pkexec modprobe v4l2loopback 2>/dev/null || modprobe v4l2loopback 2>/dev/null"]
        onExited: (code, status) => {
            checkAvailProc.running = true
            if (root._droidcamConnecting && !root._droidcamRunning) {
                root._doStartCamera()
            }
        }
    }

    // ─── /dev/videoN detector (runs after droidcam-cli starts) ───
    // BUG FIX (2026-06-21): The v4l2loopback_dc kernel module creates
    // /dev/video0 at BOOT TIME — the device node ALWAYS EXISTS, even when
    // droidcam-cli is not running and the phone is disconnected. The old
    // detection logic found the device and falsely reported "running".
    //
    // New approach: we don't detect the device at all. Instead we:
    //   1. Use SplitParser on stderr to catch "recv error" / "Error:" in
    //      real-time (droidcam-cli prints these when connection fails but
    //      stays alive).
    //   2. Set a 4s success timer — if no error after 4s AND the process
    //      is still alive, assume the connection succeeded.
    //   3. Look up the /dev/videoN path for display purposes only (after
    //      we already know the connection is good).
    Process {
        id: detectDeviceProc
        running: false
        property int attempt: 0
        command: ["bash", "-c",
            "v4l2-ctl --list-devices 2>/dev/null | " +
            "awk '/[Dd]roid[Cc]am/{flag=1;next} flag&&/\\/dev\\/video/{print $1;exit}'; " +
            // Fallback: look for a v4l2loopback / dummy device
            "v4l2-ctl --list-devices 2>/dev/null | " +
            "awk '/[Dd]ummy|loopback|v4l2loopback|platform:/{flag=1;next} flag&&/\\/dev\\/video/{print $1;exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text).trim().split("\n")[0].trim()
                if (out.length > 0 && out.startsWith("/dev/video")) {
                    // Only update the device path for display — we don't
                    // set running=true here (that's done by successTimer).
                    root._droidcamVideoDevice = out
                }
                // If no device found, retry up to 4 times for display only.
                if (out.length === 0 && detectDeviceProc.attempt < 4) {
                    detectDeviceProc.attempt++
                    detectRetryTimer.restart()
                }
            }
        }
    }

    Timer {
        id: detectRetryTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (root._droidcamConnecting && !root._droidcamRunning) {
                detectDeviceProc.running = false
                detectDeviceProc.running = true
            }
        }
    }

    // ─── Main droidcam-cli process (kept alive while running) ───
    // stderr uses SplitParser. droidcam-cli prints "recv error" and
    // "Connection reset" during connection negotiation — these are NOT
    // always fatal. The process stays alive and may eventually connect.
    // We only treat "Is the app running?" as a clear fatal signal.
    Process {
        id: droidcamProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: { /* informational only */ }
        }
        stderr: SplitParser {
            onRead: line => {
                const s = String(line)
                // The loopback device is held by another producer with a
                // different pixel format — not a connection problem.
                // onExited reacts by creating a dedicated device.
                if (s.indexOf("video device reported pixel format") >= 0) root._deviceBusy = true
                // "Is the app running?" is the definitive fatal error —
                // the DroidCam app is not running on the phone.
                // "recv error" and "Connection reset" may be transient.
                if (s.indexOf("Is the app running") >= 0) {
                    if (root._droidcamConnecting || root._droidcamRunning) {
                        root._droidcamConnecting = false
                        root._droidcamRunning = false
                        root._droidcamVideoDevice = ""
                        root._droidcamElapsedMs = 0
                        root._droidcamLastError = "DroidCam app is not running on your phone — open it and press Start"
                        root.errorOccurred(root._droidcamLastError)
                        root.stateChanged()
                        successTimer.stop()
                        droidcamProc.running = false
                    }
                }
            }
        }
        onExited: (code, status) => {
            successTimer.stop()
            failTimer.stop()
            if (root._deviceBusy && root._droidcamConnecting && !root._userStopped) {
                root._deviceBusy = false
                if (!root._deviceCreateTried) {
                    root._deviceCreateTried = true
                    createDeviceProc.running = true
                    return
                }
                root._droidcamLastError = "The DroidCam loopback device is in use by another app"
            }
            // If the user intentionally stopped (or we're restarting for
            // flip/mirror), suppress the error — SIGTERM = non-zero exit.
            if (code !== 0 && !root._droidcamRunning && !root._userStopped) {
                root._droidcamLastError = root._droidcamLastError || "Connection failed — check that the DroidCam app is open on your phone and listening on port " + root.activePort
                root.errorOccurred(root._droidcamLastError)
            }
            root._userStopped = false
            root._droidcamRunning = false
            root._droidcamConnecting = false
            root._droidcamVideoDevice = ""
            root._droidcamElapsedMs = 0
            root.stateChanged()
        }
    }

    // ─── Dedicated loopback device (created on demand) ─────
    // droidcam-cli takes the first v4l2loopback device. When another producer
    // already owns it (e.g. a libcamera relay), add one labelled "DroidCam",
    // which _launchCameraProcess then picks. Needs root, hence pkexec, which
    // the shell's own polkit agent answers. The device lasts until reboot.
    // Exit 3 = v4l2loopback-ctl missing, 1 = prompt dismissed or add failed.
    Process {
        id: createDeviceProc
        running: false
        command: ["bash", "-c",
            "command -v v4l2loopback-ctl >/dev/null 2>&1 || exit 3; " +
            "out=$(pkexec v4l2loopback-ctl add -n DroidCam -x 1) || exit 1; " +
            // udev fixes the node's group/mode a moment after it appears.
            "dev=${out%%$'\\n'*}; " +
            "for i in $(seq 30); do [ -w \"$dev\" ] && exit 0; sleep 0.1; done; exit 0"]
        onExited: (code, status) => {
            if (!root._droidcamConnecting) return
            if (code === 0 && root._lastLaunch) {
                root._launchCameraProcess(root._lastLaunch.mode, root._lastLaunch.port, root._lastLaunch.ip)
                return
            }
            root._droidcamConnecting = false
            root._droidcamLastError = "The v4l2loopback device is in use by another app, and " + (code === 3
                ? "v4l2loopback-utils is needed to create a dedicated one for DroidCam"
                : "a dedicated one for DroidCam could not be created")
            root.errorOccurred(root._droidcamLastError)
            root.stateChanged()
        }
    }

    // Success timer — if droidcam-cli is still alive after 6s and no fatal
    // error ("Is the app running?") has been seen on stderr, assume the
    // connection succeeded. droidcam-cli may print transient "recv error"
    // and "Connection reset" messages during connection negotiation —
    // these are NOT treated as fatal. Only "Is the app running?" kills
    // the process early.
    Timer {
        id: successTimer
        interval: 6000
        repeat: false
        onTriggered: {
            if (root._droidcamConnecting && droidcamProc.running) {
                // Process is still alive after 6s with no fatal stderr
                // errors — the connection likely succeeded (or is close
                // enough that the device node exists).
                failTimer.stop()
                root._droidcamRunning = true
                root._droidcamConnecting = false
                root._droidcamElapsedMs = 0
                root.stateChanged()
                // Look up the device path for display purposes only.
                detectDeviceProc.attempt = 0
                detectDeviceProc.running = true
            } else if (root._droidcamConnecting) {
                // Process exited before the timer fired — connection failed.
                // onExited should have already handled the error.
                root._droidcamConnecting = false
                root.stateChanged()
            }
        }
    }

    // Legacy detect timer — now only triggers the device path lookup for
    // display. Kept for compatibility with the detectRetryTimer.
    Timer {
        id: detectTimer
        interval: 2500
        repeat: false
        onTriggered: {
            detectDeviceProc.attempt = 0
            detectDeviceProc.running = true
            failTimer.restart()
        }
    }

    Timer {
        id: failTimer
        interval: 9000
        repeat: false
        onTriggered: {
            if (root._droidcamConnecting && !root._droidcamRunning) {
                root._droidcamConnecting = false
                root._droidcamLastError = "Could not connect within 9s — verify the DroidCam app is open on your phone and in Start mode"
                root.errorOccurred(root._droidcamLastError)
                root.stateChanged()
                successTimer.stop()
                droidcamProc.running = false
            }
        }
    }

    // ─── IPC (debugging / external scripts) ────────────────
    IpcHandler {
        target: "phoneCamera"
        function status(): string {
            return JSON.stringify({
                backend: root.backend,
                available: root.available,
                running: root.running,
                connecting: root.connecting,
                videoDevice: root.videoDevice,
                activeIp: root.activeIp,
                activePort: root.activePort,
                lastError: root.lastError
            })
        }
        function toggle(): void { root.toggleCamera() }
        function flip(): void { root.flipCamera() }
    }

    // ─── Public API ────────────────────────────────────────

    /**
     * Starts the droidcam-cli video process using Config.options.phone.webcam.
     * Idempotent — calling while already running/connecting is a no-op.
     *
     * Connection selection priority:
     *   1. If user explicitly set `connection: "usb"` → use ADB directly.
     *   2. If user explicitly set `connection: "wifi"` AND configured a Wi-Fi
     *      IP manually → use Wi-Fi directly (respect the user's choice).
     *   3. Otherwise (most common case: `connection: "wifi"` with empty IP),
     *      probe USB ADB first. If the phone is plugged in with debugging
     *      enabled, prefer USB (much more reliable than the KDE Connect-
     *      discovered Wi-Fi IP, which may be stale, firewalled, or on a
     *      different subnet). Only fall back to Wi-Fi via the KDE Connect
     *      `reachableAddresses` lookup if USB is not available.
     */
    function startCamera(): void {
        if (root.backend === "ii") {
            IiCameraService.start()
            return
        }
        if (!root.available || root._droidcamRunning || root._droidcamConnecting) return
        if (!KdeConnectService.activeReachable) {
            root._droidcamLastError = "No reachable KDE Connect device — pair a device first"
            root.errorOccurred(root._droidcamLastError)
            return
        }

        root._droidcamConnecting = true
        root._droidcamLastError = ""
        root._userStopped = false
        root._deviceBusy = false
        root._deviceCreateTried = false
        root.stateChanged()

        if (root.v4l2loopbackInstalled && !root.v4l2loopbackLoaded) {
            loadModuleProc.running = true
            return
        }

        root._doStartCamera()
    }

    function _doStartCamera(): void {
        const conf = Config.options.phone.webcam
        const port = conf.port || 4747

        // Case 1: explicit USB preference — launch immediately.
        if (conf.connection === "usb") {
            root._launchCameraProcess("usb", port, "")
            return
        }

        // Case 2: Wi-Fi preference with explicit IP — launch immediately.
        const userIp = (conf.wifiIp || "").trim()
        if (userIp.length > 0) {
            root._launchCameraProcess("wifi", port, userIp)
            return
        }

        // Case 3: Wi-Fi preference but no IP configured. Probe USB first.
        // The probe callback will decide between USB (if available) and
        // the auto-detected Wi-Fi IP from KDE Connect.
        root._pendingPort = port
        usbProbeForStartup._oneShot = true
        usbProbeForStartup.running = true
    }

    /**
     * Actually launches `droidcam-cli` with the chosen connection mode.
     * Called from startCamera (cases 1 & 2) or from usbProbeForStartup's
     * onExited (case 3).
     */
    function _launchCameraProcess(mode: string, port: int, ip: string): void {
        const conf = Config.options.phone.webcam

        // Build args using the CORRECT droidcam-cli 2.1.5 syntax (single-dash, =).
        const args = ["droidcam-cli", "-nocontrols"]
        // Size — droidcam-cli uses `-size=WxH` (e.g. 1280x720), NOT `--size=`.
        if (conf.resolution && conf.resolution.length > 0) {
            args.push("-size=" + conf.resolution)
        }
        // Horizontal flip (matches the "mirror horizontally" config).
        if (conf.mirrorHorizontally) {
            args.push("-hflip")
        }
        // Rotation maps to vertical/horizontal flip combos (droidcam-cli has no
        // `--rotate`, but 180° = hflip+vflip and 90°/270° require app-side
        // rotation).
        if (conf.rotateDegrees === 180) {
            args.push("-vflip")
            // hflip already pushed above for mirrorHorizontally
            if (!conf.mirrorHorizontally) args.push("-hflip")
        }

        let useAdbFallback = false
        if (mode === "usb") {
            args.push("adb", String(port))
            useAdbFallback = true
        } else {
            // Wi-Fi mode. Without a real IP we can't proceed.
            if (!ip) {
                root._droidcamConnecting = false
                root._droidcamLastError = "Could not detect USB or Wi-Fi IP.\n\nEither:\n• Plug your phone via USB with ADB debugging enabled (Settings → Developer options), or\n• Open the DroidCam app on your phone — it shows the Wi-Fi IP at the bottom. Set it in Connection → Phone IP below."
                root.errorOccurred(root._droidcamLastError)
                root.stateChanged()
                return
            }
            args.push(ip, String(port))
        }

        // droidcam-cli takes the first v4l2loopback device it finds, which may
        // belong to another producer (e.g. a libcamera relay). Prefer a device
        // labelled "DroidCam" when one exists; `exec` keeps SIGTERM reaching
        // droidcam-cli itself.
        droidcamProc.command = ["bash", "-c",
            "for n in /sys/devices/virtual/video4linux/video*/name; do " +
            "  case \"$(cat \"$n\" 2>/dev/null)\" in *[Dd]roid[Cc]am*) " +
            "    d=${n%/name}; exec \"$0\" \"-dev=/dev/${d##*/}\" \"$@\";; esac; " +
            "done; exec \"$0\" \"$@\""].concat(args)
        root._lastLaunch = { mode: mode, port: port, ip: ip }
        root.activeIp = ip || (useAdbFallback ? "(usb)" : "")
        root.activePort = port
        droidcamProc.running = true

        // Start both timers:
        //   • successTimer (6s) — declare success if droidcam-cli stays alive
        //     with no fatal stderr error.
        //   • failTimer (9s) — absolute timeout fallback. If neither success
        //     nor a fatal error fires, surface a clear timeout error.
        // The old detectTimer/failTimer wiring was dead code (detectTimer was
        // never restarted), so connections could hang indefinitely.
        successTimer.restart()
        failTimer.restart()
    }

    /** Stops the camera process gracefully. */
    function stopCamera(): void {
        if (root.backend === "ii") {
            IiCameraService.stop()
            return
        }
        root._stopDroidcam()
    }

    function _stopDroidcam(): void {
        detectTimer.stop()
        detectRetryTimer.stop()
        failTimer.stop()
        successTimer.stop()
        // Cancel any pending USB probe from startCamera case 3.
        usbProbeForStartup._oneShot = false
        usbProbeForStartup.running = false
        detectDeviceProc.running = false
        createDeviceProc.running = false
        if (!root._droidcamRunning && !root._droidcamConnecting) return
        // Mark as intentionally stopped so onExited doesn't show an error.
        root._userStopped = true
        droidcamProc.running = false  // SIGTERM
        root._droidcamRunning = false
        root._droidcamConnecting = false
        root._droidcamVideoDevice = ""
        root._droidcamElapsedMs = 0
        root.stateChanged()
    }

    function toggleCamera(): void {
        if (root.running || root.connecting) stopCamera()
        else startCamera()
    }

    /**
     * Toggles horizontal mirror. If running, applies via v4l2-ctl live on
     * DroidCam (the ii backend watches Config.options.phone.webcam.mirrorHorizontally
     * directly).
     */
    /** The picture flipped left to right: the phone's own switch with ii tools (so the
     *  app and the PC show one setting), the config with DroidCam. */
    readonly property bool mirrored: root.backend === "ii"
        ? (IiCameraService.phoneStatus?.mirror ?? false)
        : Config.options.phone.webcam.mirrorHorizontally

    function toggleMirror(): void {
        if (root.backend === "ii") {
            IiCameraService.set({ mirror: !root.mirrored })
            return
        }
        const conf = Config.options.phone.webcam
        conf.mirrorHorizontally = !conf.mirrorHorizontally
        if (root.backend === "droidcam" && root._droidcamRunning && root._droidcamVideoDevice.length > 0) {
            // Try v4l2-ctl first — works on some v4l2loopback configs.
            mirrorProc.command = ["bash", "-c",
                "v4l2-ctl -d " + root._droidcamVideoDevice +
                " --set-ctrl=horizontal_flip=" + (conf.mirrorHorizontally ? "1" : "0") +
                " 2>/dev/null || true"]
            mirrorProc.running = true
        }
    }

    /**
     * Sets rotation (0/90/180/270). Persists to config; restarts DroidCam if
     * running (the ii backend updates ffmpeg rotation live via Config binding).
     */
    function setRotation(degrees: int): void {
        const conf = Config.options.phone.webcam
        conf.rotateDegrees = degrees
        if (root.backend === "droidcam" && (root._droidcamRunning || root._droidcamConnecting)) {
            root.stopCamera()
            Qt.callLater(root.startCamera)
        }
    }

    /**
     * Flips between front and back cameras.
     */
    function flipCamera(): void {
        if (root.backend === "ii") {
            const st = IiCameraService.phoneStatus
            const lenses = (st && Array.isArray(st.lenses) && st.lenses.length > 0)
                ? st.lenses.map(l => String(l))
                : ["main", "front"]
            const cur = st && st.lens ? String(st.lens) : ""
            let next = cur === "front"
                ? (lenses.indexOf("main") >= 0 ? "main" : lenses[0])
                : (lenses.indexOf("front") >= 0 ? "front" : "")
            if (!next || next === cur) {
                for (let i = 0; i < lenses.length; i++) {
                    if (lenses[i] !== cur) {
                        next = lenses[i]
                        break
                    }
                }
            }
            if (next) IiCameraService.set({ lens: next })
            return
        }
        const conf = Config.options.phone.webcam
        conf.cameraFacing = (conf.cameraFacing === "front") ? "back" : "front"
        // Do NOT restart the connection — droidcam-cli can't toggle the
        // camera. The user needs to switch it in the DroidCam app on the
        // phone. Persist the setting for UI display only.
    }

    /**
     * Launches a `mpv` external window pinned to /dev/videoN for local
     * previewing of the active phone webcam. We deliberately do NOT embed
     * via Qt Multimedia — that approach crashed previously (race with
     * v4l2loopback, "Anti-Ghost" bug). `mpv` opens a low-latency SDL window
     * that the user can place wherever they want on the Hyprland desktop.
     *
     * Requires `mpv` (preferred). Falls back to `ffplay`, then `vlc`,
     * then `guvcview`, then `xdg-open` to a webcam test site.
     *
     * IMPORTANT (2026-06-22): Do NOT add `--no-config` here. The user's
     * `~/.config/mpv/mpv.conf` contains settings that are NECESSARY for
     * v4l2 playback to work (video driver, cache, HW decoder compatible
     * with v4l2loopback). Removing them via `--no-config` breaks playback,
     * resulting in a black window. The ONLY override we need is
     * `--no-fullscreen` to prevent the preview from opening in fullscreen
     * when the user's mpv.conf has `fullscreen=yes`.
     *
     * Do NOT add `--force-window=immediate`, `--untimed`, `--hwdec=no`,
     * `--cache=no`, or `--profile=low-latency` (low-latency is already
     * included). These aggressive flags interfere with v4l2 format
     * negotiation and cause black screens.
     */
    function openExternalPreview(): void {
        if (!root.running || root.videoDevice.length === 0) return
        Quickshell.execDetached(["bash", "-c",
            "DEV=" + root._shellQuote(root.videoDevice) + "; " +
            "if command -v mpv >/dev/null 2>&1; then " +
            "  mpv --profile=low-latency --no-fullscreen --no-osc " +
            "      --title='ii webcam preview' \"av://v4l2:${DEV}\" >/dev/null 2>&1 & " +
            "elif command -v ffplay >/dev/null 2>&1; then " +
            "  ffplay -fflags nobuffer -framedrop -window_title 'ii webcam preview' " +
            "         -f v4l2 -i \"${DEV}\" >/dev/null 2>&1 & " +
            "elif command -v vlc >/dev/null 2>&1; then " +
            "  vlc --no-video-title-show --no-fullscreen \"v4l2://${DEV}\" >/dev/null 2>&1 & " +
            "elif command -v guvcview >/dev/null 2>&1; then " +
            "  guvcview -d \"${DEV}\" >/dev/null 2>&1 & " +
            "else " +
            "  xdg-open 'https://webcamtests.com' >/dev/null 2>&1 & " +
            "fi"
        ])
    }

    function _shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    // ─── Internals ─────────────────────────────────────────

    /**
     * Async USB ADB probe for startCamera case 3. When _oneShot is true,
     * the onExited handler will pick up _pendingPort and continue the
     * launch flow after the probe finishes.
     *
     * This replaces the old synchronous adbProbeForFallback pattern, which
     * had a race: if KdeConnectService.adbReachable was stale (cached 30s),
     * the first invocation would fail and only the second one would work —
     * leaving the user stuck in "connecting" state.
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
                // KDE Connect. Much more reliable when the cable is plugged.
                root._launchCameraProcess("usb", root._pendingPort, "")
            } else {
                // USB not available — try the auto-detected Wi-Fi IP.
                const conf = Config.options.phone.webcam
                const ip = root._resolveIp(conf)
                if (!ip) {
                    root._droidcamConnecting = false
                    root._droidcamLastError = "Could not detect USB (no device plugged / ADB debugging off) and no Wi-Fi IP configured.\n\nEither:\n• Plug your phone via USB with ADB debugging enabled, or\n• Open the DroidCam app on your phone and set its Wi-Fi IP in Connection → Phone IP below."
                    root.errorOccurred(root._droidcamLastError)
                    root.stateChanged()
                    return
                }
                root._launchCameraProcess("wifi", root._pendingPort, ip)
            }
        }
    }

    Process {
        id: mirrorProc
        running: false
    }

    /**
     * Resolves the phone IP. Priority:
     *   1. Config.options.phone.webcam.wifiIp (user override)
     *   2. KDE Connect DBus property `reachableAddresses` (returns all IPs
     *      KDE Connect has seen for the device — first one wins).
     */
    function _resolveIp(conf): string {
        if (conf.connection === "usb") return ""
        const configuredIp = (conf.wifiIp || "").trim()
        if (configuredIp.length > 0) return configuredIp
        return root._lastKnownIp
    }

    property string _lastKnownIp: ""

    /**
     * Queries KDE Connect DBus for the active device's reachable addresses.
     * The `reachableAddresses` property returns a QStringList of IPs that KDE
     * Connect has seen for this device (typically the local Wi-Fi IP).
     * We pick the first valid IPv4 from the list.
     */
    Process {
        id: ipFetcher
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text).trim()
                // qdbus-qt6 returns each list item on its own line.
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

    /** Triggers async DBus fetch of the active device's IPs. */
    function _fetchDeviceIp(): void {
        if (!root._enabled || root.backend === "ii") return
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

    // Re-fetch IP whenever the active device changes (or first becomes available).
    Connections {
        target: KdeConnectService
        ignoreUnknownSignals: true
        function onActiveDeviceIdChanged() {
            if (root._droidcamRunning || root._droidcamConnecting) {
                root._stopDroidcam()
            }
            root._lastKnownIp = ""
            if (root.backend === "droidcam")
                root._fetchDeviceIp()
        }
        function onActiveReachableChanged() {
            if (KdeConnectService.activeReachable && root.backend === "droidcam") {
                root._fetchDeviceIp()
            }
        }
    }

    // Initial fetch on completed — gives us the IP immediately if device is
    // already active when the shell boots.
    Timer {
        interval: 3000
        repeat: false
        running: root._enabled && root.backend === "droidcam"
        onTriggered: root._fetchDeviceIp()
    }
}
