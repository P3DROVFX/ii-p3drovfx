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

    LazyLoader {
        id: popupLoader
        active: GlobalStates.screenshotOverlayOpen

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: true
            screen: {
                const target = GlobalStates.screenshotOverlayMonitor;
                if (target) {
                    const captured = Quickshell.screens.find(s => s.name === target);
                    if (captured) return captured;
                }
                const focused = Quickshell.Hyprland?.focusedMonitor?.name;
                if (focused) {
                    const s = Quickshell.screens.find(s => s.name === focused);
                    if (s) return s;
                }
                return Quickshell.screens[0];
            }

            WlrLayershell.namespace: "quickshell:screenshotOverlay"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                bottom: true
                left: BarPlacement.vertical ? (BarPlacement.bottom ? false : true) : true
                right: false
                top: false
            }

            margins {
                bottom: BarPlacement.vertical ? Appearance.sizes.hyprlandGapsOut : (BarPlacement.bottom ? Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut : Appearance.sizes.hyprlandGapsOut)
                left: BarPlacement.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.hyprlandGapsOut
                top: 0
                right: 0
            }

            implicitWidth: popupContent.implicitWidth
            implicitHeight: popupContent.implicitHeight

            ScreenshotOverlayContent {
                id: popupContent
                onDismissed: {
                    var path = GlobalStates.screenshotOverlayImagePath;
                    if (path.startsWith("/tmp/quickshell-snip-")) {
                        Quickshell.execDetached(["rm", "-f", path]);
                    }
                    GlobalStates.screenshotOverlayOpen = false
                    GlobalStates.screenshotOverlayImagePath = ""
                    GlobalStates.screenshotOverlayMonitor = ""
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onDashboardPanelOpenChanged() {
            if (GlobalStates.dashboardPanelOpen) {
                GlobalStates.screenshotOverlayOpen = false;
                GlobalStates.screenshotOverlayImagePath = "";
            }
        }
        function onPoliciesPanelOpenChanged() {
            if (GlobalStates.policiesPanelOpen) {
                GlobalStates.screenshotOverlayOpen = false;
                GlobalStates.screenshotOverlayImagePath = "";
            }
        }
    }
}
