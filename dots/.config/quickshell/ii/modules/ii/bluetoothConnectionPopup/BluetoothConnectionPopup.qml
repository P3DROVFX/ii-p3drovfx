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

    // Listen for new connections
    Connections {
        target: BluetoothStatus
        function onDeviceConnected(device) {
            if (Config.options.bar.tooltips.enablePopups && Config.options.bar.tooltips.enableBluetoothConnectionPopup) {
                GlobalStates.bluetoothConnectionPopupDevice = device;
                GlobalStates.bluetoothConnectionPopupOpen = true;
            }
        }
    }

    // Listen for disconnections to close the popup if the shown device disconnects
    Connections {
        target: BluetoothStatus
        function onDeviceDisconnected(device) {
            if (GlobalStates.bluetoothConnectionPopupDevice &&
                GlobalStates.bluetoothConnectionPopupDevice.address === device.address) {
                GlobalStates.bluetoothConnectionPopupOpen = false;
            }
        }
    }

    Connections {
        target: Config.options.bar.tooltips
        function onEnablePopupsChanged() {
            if (!Config.options.bar.tooltips.enablePopups)
                GlobalStates.bluetoothConnectionPopupOpen = false;
        }
        function onEnableBluetoothConnectionPopupChanged() {
            if (!Config.options.bar.tooltips.enableBluetoothConnectionPopup)
                GlobalStates.bluetoothConnectionPopupOpen = false;
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
        active: GlobalStates.bluetoothConnectionPopupOpen
            && Config.options.bar.tooltips.enablePopups
            && Config.options.bar.tooltips.enableBluetoothConnectionPopup

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: Config.options.bar.tooltips.enablePopups
                && Config.options.bar.tooltips.enableBluetoothConnectionPopup
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

            WlrLayershell.namespace: "quickshell:bluetoothConnectionPopup"
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

            BluetoothConnectionPopupContent {
                id: popupContent
                device: GlobalStates.bluetoothConnectionPopupDevice

                onDismissed: {
                    GlobalStates.bluetoothConnectionPopupOpen = false;
                }
                onDisconnectRequested: {
                    if (GlobalStates.bluetoothConnectionPopupDevice) {
                        GlobalStates.bluetoothConnectionPopupDevice.connecting = false;
                        GlobalStates.bluetoothConnectionPopupDevice.connected = false;
                    }
                    GlobalStates.bluetoothConnectionPopupOpen = false;
                }
            }
        }
    }
}
