import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    readonly property bool notifIsLeft: (Config.options.notifications.position ?? "top_right").endsWith("left")
    readonly property bool notifIsRight: (Config.options.notifications.position ?? "top_right").endsWith("right")

    LazyLoader {
        id: popupLoader
        active: GlobalStates.videoEditorPopupOpen

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: true
            screen: {
                const focused = Quickshell.Hyprland?.focusedMonitor?.name
                if (focused) {
                    const s = Quickshell.screens.find(s => s.name === focused)
                    if (s) return s
                }
                return Quickshell.screens[0]
            }

            WlrLayershell.namespace: "quickshell:videoEditorPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                top: !BarPlacement.vertical && !BarPlacement.bottom
                bottom: !BarPlacement.vertical && BarPlacement.bottom
                left: BarPlacement.vertical ? (BarPlacement.bottom ? false : true) : root.notifIsRight
                right: BarPlacement.vertical ? (BarPlacement.bottom ? true : false) : root.notifIsLeft
            }

            margins {
                top: BarPlacement.vertical ? 0 : Appearance.sizes.barHeight
                bottom: BarPlacement.vertical ? 0 : Appearance.sizes.barHeight
                left: BarPlacement.vertical ? Appearance.sizes.verticalBarWidth : (root.notifIsRight ? Appearance.sizes.hyprlandGapsOut + 4 : 0)
                right: BarPlacement.vertical ? Appearance.sizes.verticalBarWidth : (root.notifIsLeft ? Appearance.sizes.hyprlandGapsOut + 4 : 0)
            }

            implicitWidth: popupContent.implicitWidth
            implicitHeight: popupContent.implicitHeight

            mask: Region {
                item: popupContent.contentBackground
            }

            VideoEditorPopupContent {
                id: popupContent
                onDismissed: GlobalStates.videoEditorPopupOpen = false
                onEditRequested: {
                    GlobalStates.videoEditorPopupOpen = false
                    if (Config.options.screenRecord.openInLosslessCut) {
                        GlobalStates.launchLosslessCut(GlobalStates.videoEditorPath)
                    } else {
                        GlobalStates.videoEditorOpen = true
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onDashboardPanelOpenChanged() {
            if (GlobalStates.dashboardPanelOpen) {
                GlobalStates.videoEditorPopupOpen = false;
            }
        }
        function onPoliciesPanelOpenChanged() {
            if (GlobalStates.policiesPanelOpen) {
                GlobalStates.videoEditorPopupOpen = false;
            }
        }
    }
}
