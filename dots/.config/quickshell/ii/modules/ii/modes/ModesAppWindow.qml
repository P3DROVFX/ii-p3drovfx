pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * Modes & Routines as an ordinary floating window (see hyprland/rules.lua), at the size
 * the clock and EasyEffects open at, so the whole-app windows read as one family.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080
    readonly property real familyWidth: Math.min(1500, Math.max(900, root.screenWidth * 0.92)) + 40
    readonly property real familyHeight: Math.min(700, Math.max(460, root.screenHeight * 0.62)) + 100

    title: "ii Modes"
    implicitWidth: Math.round(Math.min(root.familyWidth, root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(root.familyHeight, root.screenHeight * 0.85))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.modesOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.modesOpen)
            GlobalStates.modesOpen = false;
    }

    ModesAppContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
