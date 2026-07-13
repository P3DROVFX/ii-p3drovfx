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

    // Dismiss popup when sidebar opens (avoids input conflicts)
    Connections {
        target: GlobalStates
        function onDashboardPanelOpenChanged() {
            if (GlobalStates.dashboardPanelOpen) {
                GlobalStates.localSendPopupOpen = false;
            }
        }
        function onPoliciesPanelOpenChanged() {
            if (GlobalStates.policiesPanelOpen) {
                GlobalStates.localSendPopupOpen = false;
            }
        }
    }

    LazyLoader {
        id: popupLoader
        active: GlobalStates.localSendPopupOpen

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: true
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

            readonly property real screenWidth: popupWindow.screen?.width ?? 0
            readonly property real screenHeight: popupWindow.screen?.height ?? 0

            WlrLayershell.namespace: "quickshell:localSendPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            // Position: anchored to top+right for horizontal bar (like other bar popups)
            anchors {
                top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
                bottom: !Config.options.bar.vertical && Config.options.bar.bottom
                left: Config.options.bar.vertical && !Config.options.bar.bottom
                right: (!Config.options.bar.vertical) || (Config.options.bar.vertical && Config.options.bar.bottom)
            }

            readonly property int frameThickness: Config.options.appearance.fakeScreenRounding === 3 ? Config.options.appearance.wrappedFrameThickness : 0
            readonly property int topFrameThickness: (Config.options.bar.vertical || Config.options.bar.bottom) ? frameThickness : 0
            readonly property int bottomFrameThickness: (Config.options.bar.vertical || !Config.options.bar.bottom) ? frameThickness : 0
            readonly property int leftFrameThickness: (!Config.options.bar.vertical || Config.options.bar.bottom) ? frameThickness : 0
            readonly property int rightFrameThickness: (!Config.options.bar.vertical || !Config.options.bar.bottom) ? frameThickness : 0
            readonly property int barGaps: (Config.options.bar.cornerStyle !== 0) ? Appearance.sizes.hyprlandGapsOut : 0

            margins {
                top: {
                    if (Config.options.bar.vertical) {
                        return topFrameThickness;
                    }
                    return Config.options.bar.bottom ? 0 : Appearance.sizes.barHeight + topFrameThickness;
                }
                bottom: {
                    if (Config.options.bar.vertical) {
                        return bottomFrameThickness;
                    }
                    return Config.options.bar.bottom ? Appearance.sizes.barHeight + bottomFrameThickness : 0;
                }
                left: {
                    if (Config.options.bar.vertical) {
                        return Config.options.bar.bottom ? leftFrameThickness : Appearance.sizes.verticalBarWindowWidth + leftFrameThickness;
                    }
                    return leftFrameThickness;
                }
                right: {
                    if (Config.options.bar.vertical) {
                        return Config.options.bar.bottom ? Appearance.sizes.verticalBarWindowWidth + rightFrameThickness : rightFrameThickness;
                    }
                    return barGaps + 4 + rightFrameThickness;
                }
            }

            implicitWidth: popupContent.implicitWidth
            implicitHeight: popupContent.implicitHeight

            mask: Region {
                item: popupContent.staticMaskTarget
            }

            LocalSendPopupContent {
                id: popupContent
                transfer: GlobalStates.localSendPopupTransfer

                onDismissed: {
                    GlobalStates.localSendPopupOpen = false;
                }
                onAcceptRequested: {
                    LocalSend.acceptTransfer();
                }
                onRejectRequested: {
                    LocalSend.denyTransfer();
                }
            }
        }
    }
}
