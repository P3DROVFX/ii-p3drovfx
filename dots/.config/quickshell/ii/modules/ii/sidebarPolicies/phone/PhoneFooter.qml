// PhoneFooter.qml
// Render the 3 hero cards (scrcpy/webcam/mic) at the bottom of the Phone tab.
// Each card has a state machine: unavailable | offline | ready | connecting | active.
// The detailLine binding shows elapsed time and connection info when active.
// Backed by KdeConnectService, PhoneCameraService and PhoneMicService singletons.

pragma ComponentBehavior: Bound

// Performance fix: multi-arg .arg() doesn't work in this Qt/Quickshell version
// Use chained .arg(x).arg(y) instead.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Footer of the Phone tab — renders a stacked set of hero cards for the
 * three phone-as-a-peripheral features: Scrcpy Mirror, Phone Webcam, and
 * Phone Microphone.
 *
 * When any card is in the "active" state, it expands in height and reveals
 * inline status (elapsed time, IP, /dev/videoN), a big Stop button and
 * contextual quick-action chips (flip/mirror/preview for webcam, mute/gain
 * for mic, focus/kill/screenshot for scrcpy). The notifications panel
 * above contracts automatically because the Phone panel uses
 * `Layout.fillHeight` on it.
 *
 * Click behaviour on each card:
 *   • Idle → start the feature.
 *   • Active → main click is a secondary action (focus scrcpy window, mute
 *     mic toggle, focus preview window). Use the explicit Stop button to
 *     actually stop the feature.
 *   • Settings gear (top-right) → opens the sub-page with detailed options.
 */
Item {
    id: root

    implicitHeight: visible ? footerColumn.implicitHeight : 0
    height: visible ? implicitHeight : 0
    visible: Config.options.phone.showPeripheralCards

    signal requestOpenSubPage(url target)

    readonly property bool _scrcpyPresent: KdeConnectService.scrcpyAvailable
    readonly property bool _droidcamPresent: PhoneCameraService.available
    readonly property bool _micPresent: PhoneMicService.available

    readonly property bool _deviceOnline: KdeConnectService.activeReachable

    // ─── Install guide popup state ─────────────────────────
    // When visible, shows a floating overlay listing missing dependencies
    // with copyable install commands per distro.
    property bool _installGuideVisible: false
    property var _installGuideDeps: []
    property string _installGuideTitle: Translation.tr("Missing Dependencies")

    function _openInstallGuide(deps, title) {
        root._installGuideDeps = deps || []
        root._installGuideTitle = title || Translation.tr("Missing Dependencies")
        root._installGuideVisible = true
    }

    /** Helper — formats milliseconds as "Xm Ys" or "Xs" for inline display. */
    function _fmtElapsed(ms): string {
        const s = Math.floor(ms / 1000)
        if (s < 60) return s + "s"
        const m = Math.floor(s / 60)
        const rem = s % 60
        if (m < 60) return m + "m " + (rem < 10 ? "0" : "") + rem + "s"
        const h = Math.floor(m / 60)
        const rm = m % 60
        return h + "h " + (rm < 10 ? "0" : "") + rm + "m"
    }

    property int entranceTrigger: -1
    onEntranceTriggerChanged: {
        if (entranceTrigger >= 0) {
            card1.opacity = 0; card1Transform.y = 25; card1.scale = 0.88
            card2.opacity = 0; card2Transform.y = 25; card2.scale = 0.88
            card3.opacity = 0; card3Transform.y = 25; card3.scale = 0.88

            Qt.callLater(function() {
                footerEntranceAnim.stop()
                footerEntranceAnim.start()
            })
        }
    }

    ParallelAnimation {
        id: footerEntranceAnim

        SequentialAnimation {
            PauseAnimation { duration: 150 }
            ParallelAnimation {
                ScriptAction { script: card1.triggerEntrance() }
                NumberAnimation { target: card1; property: "opacity"; to: (card1.enabled ? 1.0 : 0.55); duration: 340; easing.type: Easing.OutCubic }
                NumberAnimation { target: card1Transform; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                NumberAnimation { target: card1; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 210 }
            ParallelAnimation {
                ScriptAction { script: card2.triggerEntrance() }
                NumberAnimation { target: card2; property: "opacity"; to: (card2.enabled ? 1.0 : 0.55); duration: 340; easing.type: Easing.OutCubic }
                NumberAnimation { target: card2Transform; property: "y"; to: 0; duration: 400; easing.type: Easing.OutExpo }
                NumberAnimation { target: card2; property: "scale"; to: 1.0; duration: 400; easing.type: Easing.OutExpo }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 270 }
            ParallelAnimation {
                ScriptAction { script: card3.triggerEntrance() }
                NumberAnimation { target: card3; property: "opacity"; to: (card3.enabled ? 1.0 : 0.55); duration: 340; easing.type: Easing.OutCubic }
                NumberAnimation { target: card3Transform; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                NumberAnimation { target: card3; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            }
        }
    }

    ColumnLayout {
        id: footerColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        // ─── 1. Scrcpy Mirror ──────────────────────────────
        PhoneFeatureCard {
            id: card1
            Layout.fillWidth: true
            transform: Translate { id: card1Transform; y: 0 }
            iconName: "smart_display"
            iconShape: MaterialShape.Shape.Cookie9Sided
            title: root._scrcpyPresent
                ? (KdeConnectService.scrcpyRunning
                    ? Translation.tr("scrcpy Mirror")
                    : Translation.tr("Open scrcpy Mirror"))
                : Translation.tr("Install scrcpy")
            subtitle: {
                if (!root._scrcpyPresent)
                    return Translation.tr("Click to see missing dependencies and install guide")
                if (!root._deviceOnline)
                    return Translation.tr("Pair a reachable device to mirror its screen")
                if (KdeConnectService.scrcpyLaunchError.length > 0)
                    return KdeConnectService.scrcpyLaunchError.split("\n")[0]
                if (!KdeConnectService.adbReachable && !KdeConnectService.scrcpyRunning)
                    return Translation.tr("Connect via USB (ADB debugging) or set wireless IP in settings")
                if (KdeConnectService.scrcpyRunning)
                    return Translation.tr("Mirror is running · click to focus window")
                if (KdeConnectService.scrcpyLaunching)
                    return Translation.tr("Launching scrcpy…")
                return Translation.tr("Launches a floating SDL window for the active phone")
            }
            state: !root._scrcpyPresent ? "unavailable"
                : !root._deviceOnline ? "offline"
                : KdeConnectService.scrcpyLaunchError.length > 0 ? "offline"
                : KdeConnectService.scrcpyRunning ? "active"
                : KdeConnectService.scrcpyLaunching ? "connecting"
                : "ready"
            detailLine: KdeConnectService.scrcpyRunning
                ? Translation.tr("Active for %1").arg(root._fmtElapsed(KdeConnectService.scrcpyElapsedMs))
                : ""
            dropEnabled: KdeConnectService.scrcpyRunning && root._deviceOnline
            onFilesDropped: urls => {
                urls.forEach(url => {
                    const file = String(url).replace(/^file:\/\//, "")
                    if (file.length > 0)
                        KdeConnectService.shareUrl(KdeConnectService.activeDeviceId, file)
                })
            }
            inlineActions: KdeConnectService.scrcpyRunning ? [
                {
                    icon: "center_focus_strong",
                    label: Translation.tr("Focus window"),
                    onClicked: () => KdeConnectService.focusScrcpyWindow()
                },
                {
                    icon: "screenshot_monitor",
                    label: Translation.tr("Phone screenshot"),
                    onClicked: () => KdeConnectService.adbScreenshot()
                },
                {
                    icon: "power_settings_new",
                    label: Translation.tr("Toggle phone power"),
                    onClicked: () => KdeConnectService.adbTogglePower()
                },
                {
                    icon: KdeConnectService.adbReachable ? "cast_connected" : "cast",
                    label: KdeConnectService.adbReachable
                        ? Translation.tr("ADB reachable")
                        : Translation.tr("ADB not connected"),
                    onClicked: () => KdeConnectService._probeAdb()
                }
            ] : []
            lastError: ""
            onClicked: {
                if (root._scrcpyPresent) {
                    if (KdeConnectService.scrcpyRunning) {
                        // Stop scrcpy — kill existing instance.
                        KdeConnectService.killScrcpy()
                    } else if (!KdeConnectService.scrcpyLaunching) {
                        KdeConnectService.launchScrcpy(KdeConnectService.activeDeviceId)
                    }
                } else {
                    // Open the install guide popup showing missing deps.
                    root._openInstallGuide(
                        KdeConnectService.scrcpyMissingDeps,
                        Translation.tr("scrcpy Mirror — Missing Dependencies"))
                }
            }
            onStopClicked: {
                if (KdeConnectService.scrcpyRunning)
                    KdeConnectService.killScrcpy()
            }
        }

        // ─── 2. Phone Webcam ────────────────────────────────
        PhoneFeatureCard {
            id: card2
            Layout.fillWidth: true
            transform: Translate { id: card2Transform; y: 0 }
            iconName: "videocam"
            iconShape: MaterialShape.Shape.Cookie7Sided
            title: root._droidcamPresent
                ? Translation.tr("Phone Webcam")
                : Translation.tr("Install DroidCam")
            subtitle: {
                if (!root._droidcamPresent)
                    return Translation.tr("Click to see missing dependencies and install guide")
                if (!root._deviceOnline)
                    return Translation.tr("Pair a reachable device to use its camera")
                if (PhoneCameraService.connecting)
                    return Translation.tr("Connecting to %1:%2…").arg(PhoneCameraService.activeIp || "?").arg(String(PhoneCameraService.activePort))
                if (PhoneCameraService.running)
                    return PhoneCameraService.videoDevice || "/dev/videoN"
                return Translation.tr("Tap to start · settings to configure")
            }
            state: !root._droidcamPresent ? "unavailable"
                : !root._deviceOnline ? "offline"
                : PhoneCameraService.connecting ? "connecting"
                : PhoneCameraService.running ? "active"
                : "ready"
            detailLine: {
                if (!PhoneCameraService.running) return ""
                const el = root._fmtElapsed(PhoneCameraService.elapsedMs)
                const ip = PhoneCameraService.activeIp || "(usb)"
                const port = String(PhoneCameraService.activePort)
                const dev = PhoneCameraService.videoDevice || "/dev/videoN"
                return "Active for " + el + " · " + ip + ":" + port + " · " + dev
            }
            lastError: PhoneCameraService.lastError
            inlineActions: PhoneCameraService.running ? [
                {
                    icon: "preview",
                    label: Translation.tr("Open preview window (mpv)"),
                    onClicked: () => PhoneCameraService.openExternalPreview()
                }
            ] : []
            onClicked: {
                if (!root._droidcamPresent) {
                    // Open the install guide popup showing missing deps
                    // (droidcam-cli, v4l2loopback, v4l-utils, mpv).
                    root._openInstallGuide(
                        PhoneCameraService.missingDeps,
                        Translation.tr("Phone Webcam — Missing Dependencies"))
                    return
                }
                if (PhoneCameraService.connecting || PhoneCameraService.running) {
                    PhoneCameraService.stopCamera()
                } else {
                    PhoneCameraService.startCamera()
                }
            }
            onStopClicked: {
                PhoneCameraService.stopCamera()
            }
        }

        // ─── 3. Phone Microphone ────────────────────────────
        PhoneFeatureCard {
            id: card3
            Layout.fillWidth: true
            transform: Translate { id: card3Transform; y: 0 }
            iconName: "mic"
            iconShape: MaterialShape.Shape.Sunny
            title: root._micPresent
                ? Translation.tr("Phone Microphone")
                : Translation.tr("Install scrcpy or DroidCam")
            subtitle: {
                if (!root._micPresent)
                    return Translation.tr("Click to see missing dependencies and install guide")
                if (!root._deviceOnline)
                    return Translation.tr("Pair a reachable device to use its microphone")
                if (PhoneMicService.connecting)
                    return Translation.tr("Set up audio routing…")
                if (PhoneMicService.running)
                    return PhoneMicService.muted
                        ? Translation.tr("Muted · click to unmute")
                        : Translation.tr("Active · click to mute")
                return Translation.tr("Tap to start · uses scrcpy or DroidCam")
            }
            state: !root._micPresent ? "unavailable"
                : !root._deviceOnline ? "offline"
                : PhoneMicService.connecting ? "connecting"
                : PhoneMicService.running ? "active"
                : "ready"
            detailLine: {
                if (!PhoneMicService.running) return ""
                const el = root._fmtElapsed(PhoneMicService.elapsedMs)
                const gain = String(PhoneMicService.micGain) + "%"
                const suffix = PhoneMicService.defaultOverridden
                    ? " · " + Translation.tr("default input")
                    : ""
                return "Active for " + el + " · " + gain + suffix
            }
            lastError: PhoneMicService.lastError
            inlineActions: PhoneMicService.running ? [
                {
                    icon: PhoneMicService.muted ? "mic_off" : "mic",
                    label: PhoneMicService.muted
                        ? Translation.tr("Unmute")
                        : Translation.tr("Mute"),
                    onClicked: () => PhoneMicService.toggleMute()
                },
                {
                    icon: PhoneMicService.monitorEnabled ? "hearing" : "hearing_disabled",
                    label: PhoneMicService.monitorEnabled
                        ? Translation.tr("Stop monitoring")
                        : Translation.tr("Hear yourself"),
                    onClicked: () => PhoneMicService.toggleMonitor()
                },
                {
                    icon: "tune",
                    label: Translation.tr("Gain: %1%").arg(String(PhoneMicService.micGain)),
                    onClicked: () => {
                        // Cycle gain: 100 → 150 → 200 → 50 → 100.
                        const g = PhoneMicService.micGain
                        const next = g < 100 ? 100
                                   : g < 150 ? 150
                                   : g < 200 ? 200
                                   : 50
                        PhoneMicService.setGain(next)
                    }
                },
                {
                    icon: PhoneMicService.defaultOverridden ? "star" : "star_border",
                    label: PhoneMicService.defaultOverridden
                        ? Translation.tr("Restore default source")
                        : Translation.tr("Set as default input"),
                    onClicked: () => {
                        if (PhoneMicService.defaultOverridden)
                            PhoneMicService.restoreDefaultSource()
                        else
                            PhoneMicService.overrideDefaultSource()
                    }
                }
            ] : []
            onClicked: {
                if (!root._micPresent) {
                    // Open the install guide popup showing missing deps
                    // (pactl, scrcpy or droidcam-cli).
                    root._openInstallGuide(
                        PhoneMicService.missingDeps,
                        Translation.tr("Phone Microphone — Missing Dependencies"))
                    return
                }
                // If running, primary click toggles mute. The Stop button
                // (via stopClicked) handles the actual stop.
                if (PhoneMicService.running && !PhoneMicService.connecting) {
                    PhoneMicService.toggleMute()
                    return
                }
                if (PhoneMicService.connecting) {
                    PhoneMicService.stopMic()
                } else {
                    PhoneMicService.startMic()
                }
            }
            onStopClicked: {
                PhoneMicService.stopMic()
            }
        }
    }

    // ─── Install guide popup overlay ───────────────────────
    // Shows when _installGuideVisible is true. Centers over the panel.
    InstallGuidePopup {
        id: installGuidePopup
        anchors.fill: parent
        visible: root._installGuideVisible
        missingDeps: root._installGuideDeps
        detectedDistro: {
            // Prefer PhoneCameraService's detection, fall back to others.
            if (PhoneCameraService.detectedDistro && PhoneCameraService.detectedDistro !== "unknown")
                return PhoneCameraService.detectedDistro
            if (PhoneMicService.detectedDistro && PhoneMicService.detectedDistro !== "unknown")
                return PhoneMicService.detectedDistro
            if (KdeConnectService.detectedDistro && KdeConnectService.detectedDistro !== "unknown")
                return KdeConnectService.detectedDistro
            return "unknown"
        }
        headerTitle: root._installGuideTitle
        onCloseRequested: {
            root._installGuideVisible = false
        }
        onRefreshRequested: {
            // Re-check all 3 services — the user may have installed deps
            // for any of the features.
            PhoneCameraService.refresh()
            PhoneMicService.refresh()
            KdeConnectService.checkScrcpyProc.running = true
            KdeConnectService.checkAdbProc.running = true
            KdeConnectService.checkPythonDbusProc.running = true
        }
    }
}
