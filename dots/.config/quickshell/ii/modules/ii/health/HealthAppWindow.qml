pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * System Health as an ordinary application window: an xdg toplevel Hyprland floats and
 * centres by its title (see hyprland/rules.lua), at the size the clock family shares.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080
    readonly property real familyWidth: Math.min(1500, Math.max(900, root.screenWidth * 0.92)) + 40
    readonly property real familyHeight: Math.min(700, Math.max(460, root.screenHeight * 0.62)) + 100

    title: "ii System Health"
    implicitWidth: Math.round(Math.min(root.familyWidth, root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(root.familyHeight, root.screenHeight * 0.85))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.healthAppOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        HealthService.appVisible = root.visible;
        if (!visible && !GlobalStates.screenLocked && GlobalStates.healthAppOpen)
            GlobalStates.healthAppOpen = false;
    }
    Component.onCompleted: HealthService.appVisible = root.visible
    Component.onDestruction: HealthService.appVisible = false

    HealthAppContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
