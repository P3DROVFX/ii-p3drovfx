import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * A call on the phone, as a card in the corner: the caller, and Answer / Silence /
 * Decline while it rings, the length and End once answered. Shown when the dynamic
 * island is not the one showing calls (IllogicalImpulseFamily loads it only then);
 * it leaves when the call is over, or for the rest of the call when closed.
 *
 * Placed exactly like the Bluetooth connection popup, which it is modelled on.
 */
Scope {
    id: root

    /** Closed by hand: stays closed until this call is over. */
    property bool hiddenForThisCall: false
    Connections {
        target: PhoneCallService
        function onActiveChanged() {
            if (!PhoneCallService.active)
                root.hiddenForThisCall = false;
        }
    }

    // The popup anchors like the bar popups (right side for horizontal bars,
    // or the bar's own edge for vertical bars). When the sidebar on that same
    // edge opens, the popup follows the sidebar's animated width so both
    // surfaces remain visible instead of dismissing the connection notice.
    readonly property bool popupOnLeftSide: BarPlacement.vertical && !BarPlacement.bottom
    readonly property bool popupOnRightSide: !BarPlacement.vertical || BarPlacement.bottom

    LazyLoader {
        id: popupLoader
        active: PhoneCallService.active && !root.hiddenForThisCall

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

            WlrLayershell.namespace: "quickshell:phoneCallPopup"
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
            readonly property int barGaps: (BarInteraction.cornerStyle !== 0) ? Appearance.sizes.hyprlandGapsOut : 0
            readonly property real liveBarHeight: GlobalStates.horizontalBarVisibleHeightFor(popupWindow.screen?.name ?? "")
            readonly property real liveVerticalBarWidth: GlobalStates.verticalBarVisibleWidthFor(popupWindow.screen?.name ?? "")

            margins {
                top: {
                    if (BarPlacement.vertical) {
                        return topFrameThickness;
                    }
                    return BarPlacement.bottom ? 0 : popupWindow.liveBarHeight + topFrameThickness;
                }
                bottom: {
                    if (BarPlacement.vertical) {
                        return bottomFrameThickness;
                    }
                    return BarPlacement.bottom ? popupWindow.liveBarHeight + bottomFrameThickness : 0;
                }
                left: {
                    if (BarPlacement.vertical) {
                        return (BarPlacement.bottom ? leftFrameThickness : popupWindow.liveVerticalBarWidth + leftFrameThickness) + popupWindow.sidebarPush;
                    }
                    return leftFrameThickness + popupWindow.sidebarPush;
                }
                right: {
                    if (BarPlacement.vertical) {
                        return (BarPlacement.bottom ? popupWindow.liveVerticalBarWidth + rightFrameThickness : rightFrameThickness) + popupWindow.sidebarPush;
                    }
                    return barGaps + 4 + rightFrameThickness + popupWindow.sidebarPush;
                }
            }

            implicitWidth: popupContent.implicitWidth
            implicitHeight: popupContent.implicitHeight

            mask: Region {
                item: popupContent.staticMaskTarget
            }

            PhoneCallPopupContent {
                id: popupContent
                onHideRequested: root.hiddenForThisCall = true
            }
        }
    }
}
