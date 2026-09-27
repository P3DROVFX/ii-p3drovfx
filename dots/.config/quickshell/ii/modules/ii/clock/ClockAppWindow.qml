pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The clock as an ordinary application window: an xdg toplevel the compositor moves,
 * floats (see hyprland/rules.lua) and opens at the size Usage and Modes use.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    // Usage and Modes' footprint: their page (92% of the width, 62% of the height, clamped
    // to 900–1500 by 460–700), their tab row and their 20 px frame. The three whole-app
    // surfaces open at one size, so moving between them never resizes the thing you look at.
    readonly property real familyWidth: Math.min(1500, Math.max(900, root.screenWidth * 0.92)) + 40
    readonly property real familyHeight: Math.min(700, Math.max(460, root.screenHeight * 0.62)) + 100

    title: "ii Clock"
    implicitWidth: Math.round(Math.min(root.familyWidth, root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(root.familyHeight, root.screenHeight * 0.85))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.clockAppOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.clockAppOpen)
            GlobalStates.clockAppOpen = false;
    }

    ClockAppContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
