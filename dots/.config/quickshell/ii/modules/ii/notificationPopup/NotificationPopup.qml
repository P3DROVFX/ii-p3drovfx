import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        property bool active: (Notifications.popupList.length > 0)
        property bool keepVisible: false

        visible: keepVisible && !GlobalStates.screenLocked

        Component.onCompleted: {
            keepVisible = active;
        }

        onActiveChanged: {
            if (active) {
                hideTimer.stop();
                keepVisible = true;
            } else {
                hideTimer.start();
            }
        }

        Timer {
            id: hideTimer
            interval: (Appearance?.animation?.elementMove?.duration ?? 500) + 50
            running: false
            onTriggered: root.keepVisible = false
        }

        screen: Quickshell.screens.find(s => Config.options.notifications.monitor.enable ? s.name === Config.options.notifications.monitor.name : s.name === Hyprland.focusedMonitor?.name) ?? null

        property string position: {
            const raw = Config.options.notifications.position ?? "top_right"
            if (raw === "top") return "top_right"
            if (raw === "bottom") return "bottom_right"
            return raw
        }
        property bool isTop: position.startsWith("top")
        property bool isBottom: position.startsWith("bottom")
        property bool isLeft: position.endsWith("left")
        property bool isRight: position.endsWith("right")

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: listview
        }

        color: "transparent"

        NotificationListView {
            id: listview
            anchors.leftMargin: root.isLeft ? Math.max(Appearance.sizes.hyprlandGapsOut, Appearance.rounding.windowRounding * 0.5) : 0
            anchors.rightMargin: root.isRight ? Math.max(Appearance.sizes.hyprlandGapsOut, Appearance.rounding.windowRounding * 0.5) : 0
            anchors.topMargin: Math.max(Appearance.sizes.hyprlandGapsOut, Appearance.rounding.windowRounding * 0.5)
            anchors.bottomMargin: Math.max(Appearance.sizes.hyprlandGapsOut, Appearance.rounding.windowRounding * 0.5)
            width: Appearance.sizes.notificationPopupWidth * (Config.options.notifications.zoomPercent / 100)
            popup: true
            height: Math.min(contentItem.height + anchors.topMargin + anchors.bottomMargin, parent.height)
            verticalLayoutDirection: root.isBottom ? ListView.BottomToTop : ListView.TopToBottom

            states: [
                State {
                    name: "top_left"
                    when: root.position === "top_left"
                    AnchorChanges {
                        target: listview
                        anchors.left: parent.left
                        anchors.right: undefined
                        anchors.horizontalCenter: undefined
                        anchors.top: parent.top
                        anchors.bottom: undefined
                    }
                },
                State {
                    name: "top_right"
                    when: root.position === "top_right"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: parent.right
                        anchors.horizontalCenter: undefined
                        anchors.top: parent.top
                        anchors.bottom: undefined
                    }
                },
                State {
                    name: "bottom_left"
                    when: root.position === "bottom_left"
                    AnchorChanges {
                        target: listview
                        anchors.left: parent.left
                        anchors.right: undefined
                        anchors.horizontalCenter: undefined
                        anchors.top: undefined
                        anchors.bottom: parent.bottom
                    }
                },
                State {
                    name: "bottom_right"
                    when: root.position === "bottom_right"
                    AnchorChanges {
                        target: listview
                        anchors.left: undefined
                        anchors.right: parent.right
                        anchors.horizontalCenter: undefined
                        anchors.top: undefined
                        anchors.bottom: parent.bottom
                    }
                }
            ]
        }
    }
}
