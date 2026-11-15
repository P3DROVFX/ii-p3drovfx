import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * The phone's laser pointer: a glowing dot over the focused screen while a finger is on
 * the presenter's laser pad (IiLinkService.presentLaser). The surface takes no input,
 * so the slides under it keep the keyboard, and it is mapped only while the dot shows
 * (plus its fade), so a fullscreen presentation keeps direct scanout the rest of the time.
 */
Scope {
    id: root

    readonly property bool pointing: IiLinkService.presentLaser !== null
    // Kept for the fade after the finger lifts.
    property bool mapped: false
    onPointingChanged: {
        if (root.pointing) {
            unmapLater.stop();
            root.mapped = true;
        } else {
            unmapLater.restart();
        }
    }
    Timer {
        id: unmapLater
        interval: 260
        onTriggered: root.mapped = false
    }

    LazyLoader {
        active: root.mapped

        component: PanelWindow {
            id: win
            color: "transparent"
            screen: Quickshell.screens.find(s => s.name === IiLinkService.presentScreen) ?? null
            WlrLayershell.namespace: "quickshell:presenterLaser"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {}

            // The last spot, held through the fade.
            property real px: 0.5
            property real py: 0.5
            Connections {
                target: IiLinkService
                function onPresentLaserChanged() {
                    const p = IiLinkService.presentLaser;
                    if (p) {
                        win.px = p.x;
                        win.py = p.y;
                    }
                }
            }
            Component.onCompleted: {
                const p = IiLinkService.presentLaser;
                if (p) {
                    win.px = p.x;
                    win.py = p.y;
                }
            }

            Item {
                id: dot
                readonly property real size: Math.max(18, Math.min(win.width, win.height) * 0.018)
                width: size
                height: size
                x: win.px * win.width - size / 2
                y: win.py * win.height - size / 2
                opacity: root.pointing ? 1 : 0
                scale: root.pointing ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // The glow: seen across a room, on light and dark slides alike.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 2.6
                    height: width
                    radius: width / 2
                    color: Appearance.m3colors.m3error
                    opacity: 0.22
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 1.6
                    height: width
                    radius: width / 2
                    color: Appearance.m3colors.m3error
                    opacity: 0.4
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.m3colors.m3error
                    border.width: 2
                    border.color: Qt.rgba(1, 1, 1, 0.85)
                }
            }
        }
    }
}
