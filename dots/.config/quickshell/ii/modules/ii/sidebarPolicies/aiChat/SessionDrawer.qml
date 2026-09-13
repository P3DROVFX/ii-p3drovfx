pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The chat list on a narrow sidebar: it slides over the conversation instead
 * of squeezing it, and anything outside it puts it away.
 *
 * Above 640 px the same list is a pane beside the chat, so this is only ever
 * one of the two hosts — never both.
 */
Item {
    id: root

    property bool shown: false
    signal closed

    /**
     * Inset on every side, so the sheet reads as something laid over the chat
     * rather than as a second half of it. The gap on the right is what says
     * the conversation is still there behind it.
     */
    readonly property real inset: 6
    readonly property real panelWidth: Math.min(300, root.width - 56)

    opacity: root.shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim

        MouseArea {
            anchors.fill: parent
            enabled: root.shown
            onClicked: root.closed()
            onWheel: wheel => wheel.accepted = true
        }
    }

    StyledRectangularShadow {
        target: panel
    }

    Rectangle {
        id: panel
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.inset
        anchors.topMargin: root.inset
        anchors.bottomMargin: root.inset
        width: root.panelWidth
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainerHigh
        clip: true

        transform: Translate {
            x: root.shown ? 0 : -panel.width - root.inset - 8

            Behavior on x {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        MouseArea {
            // Keeps clicks on the list from reaching the scrim behind it.
            anchors.fill: parent
        }

        Loader {
            anchors.fill: parent
            anchors.margins: 10
            // Kept alive through the slide out, so the list does not vanish
            // before the panel carrying it has left.
            active: root.opacity > 0

            sourceComponent: SessionList {
                showCloseButton: true
                onCloseRequested: root.closed()
            }
        }
    }
}
