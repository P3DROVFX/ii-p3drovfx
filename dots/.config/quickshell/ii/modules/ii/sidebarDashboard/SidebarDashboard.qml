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

    // Keep the lightweight panel controller alive, but make the expensive dashboard
    // tree obey the user's keep-alive preference.
    readonly property bool keepContentLoaded: Config.ready && Config.options.sidebar.keepRightSidebarLoaded
    readonly property bool contentWanted: GlobalStates.sidebarRightOpen || root.keepContentLoaded

    readonly property bool isOnRight: {
        const pos = Config.options.sidebar.position;
        return pos === "default" || pos === "right";
    }

    /// Width of a vertical bar on the dashboard's edge. The surface ignores that bar's
    /// exclusive zone so the slide passes over the bar instead of being clipped at its inner
    /// edge, and carries this as margin so the dashboard still rests beside the bar.
    readonly property real sideBarOffset: BarPlacement.vertical && GlobalStates.barOpen && (BarPlacement.bottom === root.isOnRight)
        ? Appearance.sizes.verticalBarWindowWidth : 0

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

            // Mapped until the slide out has finished, or there is nothing to animate.
            visible: GlobalStates.sidebarRightOpen || GlobalStates.dashboardSlideProgress > 0
            exclusiveZone: 0
            exclusionMode: root.sideBarOffset > 0 ? ExclusionMode.Ignore : ExclusionMode.Normal
            implicitWidth: sidebarWidth + root.sideBarOffset
            // The strip over the bar only draws the slide; clicks there still belong to the bar.
            mask: Region {
                x: root.isOnRight ? 0 : root.sideBarOffset
                y: 0
                width: panelWindow.width - root.sideBarOffset
                height: panelWindow.height
            }
            WlrLayershell.namespace: root.isOnRight ? "quickshell:sidebarRight" : "quickshell:sidebarLeft"
            // Hyprland hands pointer focus to any layer surface that maps asking for keyboard
            // interactivity, no matter where the cursor really is, and only re-evaluates it on the
            // next pointer event — so the click meant to close the sidebar again gets spent
            // restoring focus instead. Mapping exclusive and downgrading to on-demand right after
            // makes Hyprland re-evaluate pointer focus itself, handing it back to whatever is
            // actually under the cursor, while the sidebar keeps its keyboard focus.
            // The downgrade has to happen after the surface is mapped, so it's driven by
            // Hyprland's own openlayer event; the timer is only a fallback if that never arrives.
            property bool keyboardExclusive: true
            WlrLayershell.keyboardFocus: panelWindow.keyboardExclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    if (!panelWindow.keyboardExclusive) return;
                    if (event.name !== "openlayer") return;
                    if (event.data !== panelWindow.WlrLayershell.namespace) return;
                    panelWindow.keyboardExclusive = false;
                }
            }

            Timer {
                id: keyboardFocusDowngrade
                interval: 200
                onTriggered: panelWindow.keyboardExclusive = false
            }
            color: "transparent"

            anchors {
                top: true
                left: !root.isOnRight
                right: root.isOnRight
                bottom: true
            }

            onVisibleChanged: {
                if (visible) {
                    keyboardFocusDowngrade.restart();
                    GlobalFocusGrab.addDismissable(panelWindow);
                } else {
                    keyboardFocusDowngrade.stop();
                    panelWindow.keyboardExclusive = true;
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

                active: root.contentWanted
                sourceComponent: SidebarDashboardContent {
                    keepWarm: root.keepContentLoaded
                }
                
                width: root.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: Math.max(0, parent.height - (Appearance.sizes.hyprlandGapsOut * 2))
                y: Appearance.sizes.hyprlandGapsOut

                // The slide lives here rather than in a Hyprland layer rule: the compositor's
                // layer curve is shared by every popup and dock, and the wallpaper parallax
                // has to follow this exact motion. A full sidebar width clears the shadow too.
                transform: Translate {
                    x: (1 - GlobalStates.dashboardSlideProgress) * (root.isOnRight ? 1 : -1) * (root.sidebarWidth + root.sideBarOffset)
                }

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
                            anchors.rightMargin: Appearance.sizes.hyprlandGapsOut + root.sideBarOffset
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
                            anchors.leftMargin: Appearance.sizes.hyprlandGapsOut + root.sideBarOffset
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
