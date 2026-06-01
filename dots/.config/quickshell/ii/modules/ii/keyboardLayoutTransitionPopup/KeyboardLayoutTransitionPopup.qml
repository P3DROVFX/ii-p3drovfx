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

    property bool isOpen: false
    property bool isInitialized: false

    Component.onCompleted: Qt.callLater(() => {
        isInitialized = true;
    })

    // Listen for keyboard layout changes to show the popup
    Connections {
        target: HyprlandXkb
        function onCurrentLayoutNameChanged() {
            if (root.isInitialized && HyprlandXkb.layoutCodes.length > 1 && Config.options.bar.tooltips.enableKeyboardLayoutTransitionPopup) {
                root.isOpen = true;
                hideTimer.restart();
            }
        }
    }

    // Auto-dismiss popup 1 second after the last layout switch
    Timer {
        id: hideTimer
        interval: 1000
        repeat: false
        onTriggered: {
            root.isOpen = false;
        }
    }

    PanelWindow {
        id: popupWindow
        color: "transparent"
        visible: root.isOpen || (popupContent ? popupContent.isExitAnimRunning : false)
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:keyboardLayoutTransitionPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
            top: true
            bottom: false
            left: false
            right: false
        }

        // Responsive top margin - offset from top bar (if active at the top) to avoid overlaps
        readonly property int topMarginValue: {
            if (!Config.options.bar.vertical && !Config.options.bar.bottom) {
                // Bar is active at the top
                return Appearance.sizes.barHeight + 12;
            }
            return 24; // Standard sleek top margin if bar is on the bottom or side
        }

        margins {
            top: 0
        }

        implicitWidth: popupContent.implicitWidth
        implicitHeight: popupContent.implicitHeight + topMarginValue

        mask: Region {
            item: popupContent.staticMaskTarget
        }

        KeyboardLayoutTransitionPopupContent {
            id: popupContent
            isOpen: root.isOpen
            topMarginValue: popupWindow.topMarginValue
        }
    }
}
