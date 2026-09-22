pragma ComponentBehavior: Bound
import qs
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Scope {
    id: rootScope

    RecordingCountdownOverlay {
        id: countdownOverlay
    }

    PanelWindow {
        id: root
        visible: GlobalStates.recordingToolbarOpen
        color: "transparent"

        screen: {
            const focused = Quickshell.Hyprland?.focusedMonitor?.name
            if (focused) {
                const s = Quickshell.screens.find(s => s.name === focused)
                if (s) return s
            }
            return Quickshell.screens[0]
        }

        WlrLayershell.namespace: "quickshell:recordingToolbar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Only the toolbar itself accepts input; the rest of the screen is click-through
        mask: Region {
            item: toolbarContent
        }

        function hide() {
            GlobalStates.closeRecordingToolbar();
        }

        Timer {
            id: registerGrabTimer
            interval: 0
            onTriggered: GlobalFocusGrab.addDismissable(root)
        }

        onVisibleChanged: {
            if (visible) {
                registerGrabTimer.restart();
            } else {
                GlobalFocusGrab.removeDismissable(root);
            }
        }

        Component.onDestruction: GlobalFocusGrab.removeDismissable(root)

        // ── Keyboard Shortcuts ────────────────────────────────────────────────
        Shortcut {
            sequence: "Escape"
            enabled: GlobalStates.recordingToolbarOpen
            onActivated: {
                if (toolbarContent.activeSection !== "") {
                    toolbarContent.collapseSection();
                } else {
                    GlobalStates.closeRecordingToolbar();
                }
            }
        }

        Shortcut {
            sequence: "Return"
            enabled: GlobalStates.recordingToolbarOpen
            onActivated: root.triggerRecord()
        }

        // ── Main Content with Entry / Exit Animation ──────────────────────────
        RecordingToolbarContent {
            id: toolbarContent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round((root.screen?.height ?? 1080) * 0.10)

            expandedSection: GlobalStates.recordingToolbarSection
            onExpandedSectionChanged: {
                if (GlobalStates.recordingToolbarSection !== expandedSection) {
                    GlobalStates.recordingToolbarSection = expandedSection;
                }
            }

            opacity: GlobalStates.recordingToolbarOpen ? 1.0 : 0.0
            scale: GlobalStates.recordingToolbarOpen ? 1.0 : 0.94
            transformOrigin: Item.Bottom

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                }
            }

            onCloseRequested: GlobalStates.closeRecordingToolbar()
            onRecordRequested: root.triggerRecord()
        }

        // ── Recording Trigger Functions ──────────────────────────────────────
        function triggerRecord() {
            const countdown = Config.options.screenRecord.countdown ?? 0;
            GlobalStates.closeRecordingToolbar();

            if (countdown > 0) {
                countdownOverlay.start(countdown, () => {
                    root.executeRecording();
                });
            } else {
                root.executeRecording();
            }
        }

        function executeRecording() {
            const mode = toolbarContent.selectedMode || Config.options.screenRecord.mode || "fullscreen";
            const soundFlag = (Config.options.screenRecord.recordAudio || Config.options.screenRecord.recordMic);

            if (mode === "fullscreen") {
                const args = [Directories.recordScriptPath, "--force-record", "--fullscreen"];
                if (soundFlag) args.push("--sound");
                Quickshell.execDetached(args);
            } else if (mode === "region") {
                const args = [Directories.recordScriptPath, "--force-record", "--region"];
                if (soundFlag) args.push("--sound");
                Quickshell.execDetached(args);
            } else if (mode === "window") {
                const args = [Directories.recordScriptPath, "--force-record", "--window"];
                if (soundFlag) args.push("--sound");
                Quickshell.execDetached(args);
            }
        }
    }
}
