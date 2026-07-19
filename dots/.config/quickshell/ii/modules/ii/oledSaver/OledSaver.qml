pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    function toggle() {
        const name = Hyprland.focusedMonitor?.name;
        if (!name) return;
        const monitors = GlobalStates.oledSaverMonitors;
        GlobalStates.oledSaverMonitors = monitors.includes(name) ? monitors.filter(n => n !== name) : [...monitors, name];
    }

    function close(name) {
        GlobalStates.oledSaverMonitors = GlobalStates.oledSaverMonitors.filter(n => n !== name);
    }

    // Inhibits sleep/lock/DPMS while at least one monitor is blacked out.
    // Kept independent from the shared Idle.inhibit toggle so this feature
    // never clobbers the user's own manual idle-inhibit preference.
    IdleInhibitor {
        enabled: GlobalStates.oledSaverMonitors.length > 0
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            anchors {
                right: true
                bottom: true
            }
            mask: Region {
                item: null
            }
        }
    }

    IpcHandler {
        target: "oledSaver"

        function toggle() {
            root.toggle();
        }
    }

    GlobalShortcut {
        name: "oledSaverToggle"
        description: "Toggles the OLED saver (blackout) on the focused monitor"
        onPressed: root.toggle()
    }

    component OledSaverWindow: PanelWindow {
        id: window
        signal dismiss

        color: "black"
        WlrLayershell.namespace: "quickshell:oledSaver"
        // Top (not Overlay) so OSD, notifications, polkit prompts, etc. still
        // render above the blackout instead of being hidden by it.
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        property bool cursorVisible: false
        property bool hintVisible: false

        Item {
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape)
                    window.dismiss();
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: window.cursorVisible ? Qt.ArrowCursor : Qt.BlankCursor

                onPositionChanged: {
                    window.cursorVisible = true;
                    window.hintVisible = true;
                    cursorHideTimer.restart();
                    hintHideTimer.restart();
                }
                onClicked: window.dismiss()
            }

            StyledText {
                anchors.centerIn: parent
                text: Translation.tr("Press Esc or click to exit")
                color: "white"
                font.pixelSize: Appearance.font.pixelSize.large
                opacity: window.hintVisible ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
            }

            Timer {
                id: cursorHideTimer
                interval: Config.options.oledSaver.cursorHideDelay * 1000
                onTriggered: window.cursorVisible = false
            }

            Timer {
                id: hintHideTimer
                interval: (Config.options.oledSaver.cursorHideDelay + Config.options.oledSaver.hintExtraDelay) * 1000
                onTriggered: window.hintVisible = false
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Loader {
            id: oledSaverLoader
            required property var modelData
            active: GlobalStates.oledSaverMonitors.includes(modelData.name)

            sourceComponent: OledSaverWindow {
                screen: oledSaverLoader.modelData
                onDismiss: root.close(oledSaverLoader.modelData.name)
            }
        }
    }
}
