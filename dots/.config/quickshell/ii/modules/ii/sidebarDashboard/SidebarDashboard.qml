import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth

    readonly property bool isOnRight: {
        const pos = Config.options.sidebar.position;
        return pos === "default" || pos === "right"; 
    }

    // Loader guard: PanelWindow (Wayland surface) is never created in connect mode,
    // except in Float+Connect mode (cornerStyle 1) where sidebars remain separate.
    Loader {
        id: panelLoader
        active: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        sourceComponent: panelWindowComponent
    }

    Component {
        id: panelWindowComponent

        PanelWindow {
            id: panelWindow

            function hide() {
                GlobalStates.sidebarRightOpen = false;
            }

            visible: GlobalStates.sidebarRightOpen
            exclusiveZone: 0
            implicitWidth: sidebarWidth
            WlrLayershell.namespace: root.isOnRight ? "quickshell:sidebarRight" : "quickshell:sidebarLeft"
            WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                left: !root.isOnRight
                right: root.isOnRight
                bottom: true
            }

            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(panelWindow);
                } else {
                    GlobalFocusGrab.removeDismissable(panelWindow);
                }
            }

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    panelWindow.hide();
                }
            }

            Loader {
                id: sidebarContentLoader

                active: GlobalStates.sidebarRightOpen || Config?.options.sidebar.keepRightSidebarLoaded
                sourceComponent: SidebarDashboardContent {}
                
                width: root.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: parent.height - (Appearance.sizes.hyprlandGapsOut * 2)
                y: Appearance.sizes.hyprlandGapsOut

                focus: GlobalStates.sidebarRightOpen
                
                state: root.isOnRight ? "right" : "left"
                states: [
                    State {
                        name: "right"
                        AnchorChanges {
                            target: sidebarContentLoader
                            anchors.right: parent.right
                            anchors.left: undefined
                        }
                        PropertyChanges {
                            target: sidebarContentLoader
                            anchors.rightMargin: Appearance.sizes.hyprlandGapsOut
                            anchors.leftMargin: 0
                        }
                    },
                    State {
                        name: "left"
                        AnchorChanges {
                            target: sidebarContentLoader
                            anchors.left: parent.left
                            anchors.right: undefined
                        }
                        PropertyChanges {
                            target: sidebarContentLoader
                            anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
                            anchors.rightMargin: 0
                        }
                    }
                ]

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                }
            }
        }
    }
}