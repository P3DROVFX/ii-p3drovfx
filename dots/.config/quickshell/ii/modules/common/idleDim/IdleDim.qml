pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common

/**
 * Idle dim: a click-through 50 % black scrim over every output, driven by
 * hypridle's first listener (`qs ipc -c ii call idleDim dim` / `restore`).
 *
 * It darkens the composited image instead of the backlight, so it reaches
 * external monitors, works at any backlight level and never reads as a
 * brightness key press to the OSDs. The `above_lock` layer rule for
 * quickshell:idleDim in Hyprland's rules.lua keeps it over the lock screen too.
 */
Scope {
    id: root

    readonly property real dimOpacity: 0.5
    readonly property int fadeInDuration: 1000
    readonly property int fadeOutDuration: 200

    property bool dimmed: false
    // Keeps the surfaces mapped until the fade-out has finished
    readonly property bool surfacesWanted: root.dimmed || fadeOutTimer.running

    function dim(): void {
        root.dimmed = true;
    }

    function restore(): void {
        if (!root.dimmed)
            return;
        root.dimmed = false;
        fadeOutTimer.restart();
    }

    Timer {
        id: fadeOutTimer
        interval: root.fadeOutDuration + 50
    }

    IpcHandler {
        target: "idleDim"

        function dim(): void {
            root.dim();
        }

        function restore(): void {
            root.restore();
        }
    }

    // Safety net for a missed on-resume (hypridle restarted while dimmed, the
    // ipc call landing mid-reload): the scrim only goes up after 120 s without
    // input, so this monitor is already idle by then and any input lifts it.
    // Always enabled, because cycling `enabled` is what re-arms an IdleMonitor.
    IdleMonitor {
        enabled: Config.ready
        timeout: 10
        respectInhibitors: false
        onIsIdleChanged: {
            if (!isIdle)
                root.restore();
        }
    }

    LazyLoader {
        active: root.surfacesWanted

        component: Variants {
            model: Quickshell.screens

            PanelWindow {
                id: scrimWindow

                required property var modelData
                // Starts at 0 so the first frame fades in rather than popping
                property bool revealed: false

                screen: scrimWindow.modelData
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:idleDim"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                Component.onCompleted: scrimWindow.revealed = true

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: root.dimmed && scrimWindow.revealed ? root.dimOpacity : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.dimmed ? root.fadeInDuration : root.fadeOutDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }
}
