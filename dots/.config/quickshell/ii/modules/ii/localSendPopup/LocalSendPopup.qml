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

    // Keep the transfer popup visible while moving it away from a sidebar on
    // the same edge. The opposite-side sidebar must not affect its position.
    readonly property bool popupOnLeftSide: Config.options.bar.vertical && !Config.options.bar.bottom
    readonly property bool popupOnRightSide: !Config.options.bar.vertical || Config.options.bar.bottom

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
            readonly property real sidebarPush: {
                const screenName = popupWindow.screen?.name ?? "";
                if (root.popupOnLeftSide && screenName === GlobalStates.effectiveLeftMonitor)
                    return GlobalStates.animatedLeftSidebarWidth;
                if (root.popupOnRightSide && screenName === GlobalStates.effectiveRightMonitor)
                    return GlobalStates.animatedRightSidebarWidth;
                return 0;
            }

            WlrLayershell.namespace: "quickshell:localSendPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            // Position: anchored to top+right for horizontal bar (like other bar popups)
            anchors {
                top: BarPlacement.vertical || (!BarPlacement.vertical && !BarPlacement.bottom)
                bottom: !BarPlacement.vertical && BarPlacement.bottom
                left: BarPlacement.vertical && !BarPlacement.bottom
                right: (!BarPlacement.vertical) || (BarPlacement.vertical && BarPlacement.bottom)
            }

            readonly property int frameThickness: Config.options.appearance.fakeScreenRounding === 3 ? Config.options.appearance.wrappedFrameThickness : 0
            readonly property int topFrameThickness: (BarPlacement.vertical || BarPlacement.bottom) ? frameThickness : 0
            readonly property int bottomFrameThickness: (BarPlacement.vertical || !BarPlacement.bottom) ? frameThickness : 0
            readonly property int leftFrameThickness: (!BarPlacement.vertical || BarPlacement.bottom) ? frameThickness : 0
            readonly property int rightFrameThickness: (!BarPlacement.vertical || !BarPlacement.bottom) ? frameThickness : 0
            readonly property int barGaps: (Config.options.bar.cornerStyle !== 0) ? Appearance.sizes.hyprlandGapsOut : 0

            margins {
                top: {
                    if (BarPlacement.vertical) {
                        return topFrameThickness;
                    }
                    return BarPlacement.bottom ? 0 : Appearance.sizes.barHeight + topFrameThickness;
                }
                bottom: {
                    if (BarPlacement.vertical) {
                        return bottomFrameThickness;
                    }
                    return BarPlacement.bottom ? Appearance.sizes.barHeight + bottomFrameThickness : 0;
                }
                left: {
                    if (BarPlacement.vertical) {
                        return (BarPlacement.bottom ? leftFrameThickness : Appearance.sizes.verticalBarWindowWidth + leftFrameThickness) + popupWindow.sidebarPush;
                    }
                    return leftFrameThickness + popupWindow.sidebarPush;
                }
                right: {
                    if (BarPlacement.vertical) {
                        return (BarPlacement.bottom ? Appearance.sizes.verticalBarWindowWidth + rightFrameThickness : rightFrameThickness) + popupWindow.sidebarPush;
                    }
                    return barGaps + 4 + rightFrameThickness + popupWindow.sidebarPush;
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
