pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * Real Gnome on every monitor: the input half for the monitors that do not hold
 * the search.
 *
 * The focused monitor's picker and workspace indicator live in the search's own
 * window (the island, or the overview); the other monitors have no such window,
 * so each gets this resident, click-through layer that takes the pointer only
 * while the overview is open there. It hosts the same picker and indicator, so a
 * window can be picked, closed or dragged on any monitor, and dragged across.
 * Which monitor holds the search follows the pointer, so the roles swap as it
 * moves; the pickers share their state through GlobalStates.
 */
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData

            screen: modelData
            readonly property string screenName: modelData ? modelData.name : ""
            readonly property string focusedName: GlobalStates.overviewMonitor
            readonly property var controller: GlobalStates.overviewBackgroundControllerFor(win.screenName)
            // Not the monitor holding the search.
            readonly property bool hosting: GlobalStates.realGnomeMirrored && GlobalStates.overviewOpen
                && win.screenName !== win.focusedName
            readonly property bool zoomed: !!win.controller && win.controller.progress > 0.9
            readonly property var reserved: HyprlandData.monitors.find(m => m.name === win.screenName)?.reserved ?? [0, 0, 0, 0]

            // Kept mapped (mapping a full-screen layer costs tens of ms); input only
            // while there is something to pick.
            WlrLayershell.namespace: "quickshell:overviewMirror"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {
                item: win.hosting ? content : noInput
            }
            Item {
                id: noInput
                width: 0
                height: 0
            }

            Item {
                id: content
                anchors.fill: parent

                // Clicking away from the windows leaves the overview, as on the main one.
                MouseArea {
                    anchors.fill: parent
                    enabled: win.hosting
                    onClicked: GlobalStates.overviewOpen = false
                }

                RealGnomeWindowPicker {
                    anchors.fill: parent
                    screenName: win.screenName
                    shown: win.hosting && win.zoomed
                }

                Loader {
                    active: GlobalStates.realGnomeMirrored
                    x: (win.width - (item ? item.width : 0)) / 2
                    y: win.height - win.reserved[3] - 20 - (item ? item.height / 2 : 0)
                    sourceComponent: RealGnomeWorkspaceIndicator {
                        screenName: win.screenName
                        shown: win.hosting && !!win.controller && win.controller.progress > 0.6
                    }
                }
            }
        }
    }
}
