import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    readonly property bool notifIsLeft: (Config.options.notifications.position ?? "top_right").endsWith("left")
    readonly property bool notifIsRight: (Config.options.notifications.position ?? "top_right").endsWith("right")
    readonly property bool popupOnLeftSide: Config.options.bar.vertical ? !Config.options.bar.bottom : root.notifIsLeft
    readonly property bool popupOnRightSide: Config.options.bar.vertical ? Config.options.bar.bottom : root.notifIsRight

    // Native Process avoids qs ipc call round-trip from external shell
    Process {
        id: hyprpickerProcess
        command: ["bash", "-c", "sleep 0.2; hyprpicker -a -f hex"]
        stdout: SplitParser {
            onRead: data => {
                let hex = data.trim();
                if (hex.startsWith("#") && hex.length >= 7) {
                    GlobalStates.pickColor(hex);
                }
            }
        }
    }

    GlobalShortcut {
        name: "colorPickerLaunch"
        description: "Launch color picker (hyprpicker) and show popup with palette"
        onPressed: {
            hyprpickerProcess.running = false;
            Qt.callLater(() => {
                hyprpickerProcess.running = true;
            });
        }
    }

    IpcHandler {
        target: "colorPickerLaunch"
        function trigger(): void {
            hyprpickerProcess.running = false;
            Qt.callLater(() => {
                hyprpickerProcess.running = true;
            });
        }
    }

    Connections {
        target: Config.options.bar.tooltips
        function onEnablePopupsChanged() {
            if (!Config.options.bar.tooltips.enablePopups)
                GlobalStates.colorPickerPopupOpen = false;
        }
        function onEnableColorPickerPopupChanged() {
            if (!Config.options.bar.tooltips.enableColorPickerPopup)
                GlobalStates.colorPickerPopupOpen = false;
        }
    }


    LazyLoader {
        id: popupLoader
        active: GlobalStates.colorPickerPopupOpen
            && Config.options.bar.tooltips.enablePopups
            && Config.options.bar.tooltips.enableColorPickerPopup

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: Quickshell.screens.length > 0
                && Config.options.bar.tooltips.enablePopups
                && Config.options.bar.tooltips.enableColorPickerPopup
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

            readonly property real sidebarPush: {
                const screenName = popupWindow.screen?.name ?? "";
                if (root.popupOnLeftSide && screenName === GlobalStates.effectiveLeftMonitor)
                    return GlobalStates.animatedLeftSidebarWidth;
                if (root.popupOnRightSide && screenName === GlobalStates.effectiveRightMonitor)
                    return GlobalStates.animatedRightSidebarWidth;
                return 0;
            }

            WlrLayershell.namespace: "quickshell:colorPickerPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
                bottom: !Config.options.bar.vertical && Config.options.bar.bottom
                left: Config.options.bar.vertical ? (Config.options.bar.bottom ? false : true) : root.notifIsRight
                right: Config.options.bar.vertical ? (Config.options.bar.bottom ? true : false) : root.notifIsLeft
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
                        return (Config.options.bar.bottom ? leftFrameThickness : Appearance.sizes.verticalBarWindowWidth + leftFrameThickness) + popupWindow.sidebarPush;
                    }
                    if (root.notifIsRight) {
                        return barGaps + 4 + leftFrameThickness + popupWindow.sidebarPush;
                    }
                    return leftFrameThickness + popupWindow.sidebarPush;
                }
                right: {
                    if (Config.options.bar.vertical) {
                        return (Config.options.bar.bottom ? Appearance.sizes.verticalBarWindowWidth + rightFrameThickness : rightFrameThickness) + popupWindow.sidebarPush;
                    }
                    if (root.notifIsLeft) {
                        return barGaps + 4 + rightFrameThickness + popupWindow.sidebarPush;
                    }
                    return rightFrameThickness + popupWindow.sidebarPush;
                }
            }

            implicitWidth: popupContent.implicitWidth
            implicitHeight: popupContent.implicitHeight

            mask: Region {
                item: popupContent.staticMaskTarget
            }

            ColorPickerPopupContent {
                id: popupContent
                colorHex: GlobalStates.colorPickerPopupColor

                onDismissed: {
                    GlobalStates.colorPickerPopupOpen = false;
                }
            }
        }
    }
}
