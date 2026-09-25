pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The clock as an ordinary application window: an xdg toplevel the compositor moves,
 * tiles and closes like any other program, sized to fit whatever monitor it opens on.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property var state: Persistent.states.clockApp
    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    title: "ii Clock"
    implicitWidth: Math.max(ClockStyle.windowMinWidth, Math.min(root.state.width, Math.round(root.screenWidth * 0.9)))
    implicitHeight: Math.max(ClockStyle.windowMinHeight, Math.min(root.state.height, Math.round(root.screenHeight * 0.88)))
    minimumSize: Qt.size(ClockStyle.windowMinWidth, ClockStyle.windowMinHeight)

    color: ClockStyle.colBackground
    visible: GlobalStates.clockAppOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.clockAppOpen)
            GlobalStates.clockAppOpen = false;
    }

    Component.onDestruction: {
        if (root.width >= ClockStyle.windowMinWidth && root.height >= ClockStyle.windowMinHeight) {
            root.state.width = Math.round(root.width);
            root.state.height = Math.round(root.height);
        }
    }

    ClockAppContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}
