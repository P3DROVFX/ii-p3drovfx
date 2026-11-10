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
        property bool active: (Notifications.popupList.length > 0) && !Notifications.effectiveSilent
        property bool keepVisible: false

        visible: keepVisible && !GlobalStates.screenLocked && !Notifications.effectiveSilent

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
        // A full-output surface: the dock, bar and corners reserve space, and with the
        // default ExclusionMode the popup was laid out inside that reserved area, so its
        // right edge stopped short of the dock and the slide came out from behind it.
        // The edges are handled below instead, so the card still slides above the panels
        // but settles clear of whatever a pinned dock, the bar and an open sidebar cover.
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        readonly property real baseMargin: Math.max(Appearance.sizes.hyprlandGapsOut, Appearance.rounding.windowRounding * 0.5)
        readonly property string screenName: root.screen?.name ?? ""
        readonly property var dockInset: (Config.options.dock?.enable ?? true) ? (GlobalStates.dockInsets[root.screenName] ?? null) : null
        readonly property string dockSide: root.dockInset?.side ?? ""
        // The dock's exclusive zone: its thickness while pinned and revealed, 0 otherwise.
        readonly property real dockReserve: root.dockInset?.reserved ?? 0
        readonly property bool barVertical: Config.options.bar.vertical ?? false
        readonly property string barSide: root.barVertical
            ? (Config.options.bar.bottom ? "right" : "left")
            : (Config.options.bar.bottom ? "bottom" : "top")
        readonly property real barThickness: root.barVertical
            ? (Config.options.bar.sizes.width ?? Appearance.sizes.verticalBarWidth)
            : (Config.options.bar.sizes.height ?? Appearance.sizes.barHeight)
        // Read the animated widths, not only the open flags: an opening sidebar clears the
        // card immediately and a closing one only releases it once it is actually gone.
        readonly property real leftSidebarInset: (GlobalStates.effectiveLeftMonitor === root.screenName && root.screenName !== "")
            ? Math.max(GlobalStates.animatedLeftSidebarWidth, GlobalStates.leftSidebarTargetWidth) : 0
        readonly property real rightSidebarInset: (GlobalStates.effectiveRightMonitor === root.screenName && root.screenName !== "")
            ? Math.max(GlobalStates.animatedRightSidebarWidth, GlobalStates.rightSidebarTargetWidth) : 0

        function edgeMargin(side) {
            let margin = root.baseMargin;
            if (GlobalStates.barOpen && side === root.barSide)
                margin += root.barThickness;
            if (side === root.dockSide)
                margin += root.dockReserve;
            if (side === "left")
                margin += root.leftSidebarInset;
            else if (side === "right")
                margin += root.rightSidebarInset;
            return margin;
        }

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

            ShellRegionTarget {
                target: listview.contentItem
                label: Translation.tr("Notifications")
                namespace: "quickshell:notificationPopup"
            }
            anchors.leftMargin: root.isLeft ? root.edgeMargin("left") : 0
            anchors.rightMargin: root.isRight ? root.edgeMargin("right") : 0
            anchors.topMargin: root.edgeMargin("top")
            anchors.bottomMargin: root.edgeMargin("bottom")
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
