pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The island's teleprompter, live, shrunk onto the Settings page.
 *
 * Not a stand-in: the two real faces — the contracted strip and the card the
 * hover grows — loaded from their own files and drawn at their real pixel
 * size inside a mock of the island's body, the whole stage scaled to fit the
 * page (the lock screen preview's trick). The demo session reads a sample
 * until a real one starts, which then takes the stage; hovering the preview
 * does what hovering the island does, crossfading strip into card.
 */
ClippingRectangle {
    id: root

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer2

    implicitHeight: Math.round(Math.min(260, Math.max(170, root.width / 3.4)))

    /** A real session takes the stage; otherwise the demo reads a sample. */
    readonly property var prompter: Teleprompter.running ? Teleprompter : demo
    readonly property bool engaged: previewHover.hovered
    readonly property real scaleFactor: Math.min(1.2, Math.max(0.5, (root.width - 96) / Teleprompter.boxWidth))
    readonly property real compactHeight: root.prompter.compactBoxHeight
    readonly property real expandedHeight: expandedLoader.item && expandedLoader.item.implicitHeight > 0
        ? expandedLoader.item.implicitHeight : root.compactHeight
    readonly property real bodyHeight: Math.round(root.scaleFactor
        * (root.engaged ? root.expandedHeight : root.compactHeight))
    /** The card is wider than the strip — and wider than the hold's swell. */
    property real boxWidthNow: root.engaged ? Teleprompter.expandedBoxWidth : Teleprompter.boxWidth

    Behavior on boxWidthNow {
        enabled: !Appearance.reducedMotion
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    property real reveal: root.engaged ? 1 : 0

    Behavior on reveal {
        enabled: !Appearance.reducedMotion
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    PreviewPrompter {
        id: demo
        visible: root.visible && !Teleprompter.running
    }

    HoverHandler {
        id: previewHover
    }

    function syncPrompter() {
        if (compactLoader.item)
            compactLoader.item.prompter = root.prompter;
        if (expandedLoader.item)
            expandedLoader.item.prompter = root.prompter;
    }
    onPrompterChanged: root.syncPrompter()

    // The mock body: the island's own silhouette language — flat against the
    // screen's top edge, round underneath.
    Item {
        id: stage
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(root.boxWidthNow * root.scaleFactor)
        height: root.bodyHeight

        Behavior on height {
            enabled: !Appearance.reducedMotion
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            bottomLeftRadius: Appearance.rounding.large
            bottomRightRadius: Appearance.rounding.large
        }

        Item {
            id: faceHost
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.boxWidthNow
            height: Math.max(1, root.bodyHeight / root.scaleFactor)
            scale: root.scaleFactor
            transformOrigin: Item.Top
            clip: true

            Loader {
                id: compactLoader
                anchors.fill: parent
                opacity: 1 - root.reveal
                source: Quickshell.shellPath("modules/ii/dynamicIsland/widgets/FloatingNotchTeleprompter.qml")
                onLoaded: root.syncPrompter()
            }

            Loader {
                id: expandedLoader
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.boxWidthNow
                opacity: root.reveal
                visible: root.reveal > 0.01
                active: root.engaged || root.reveal > 0.01
                source: Quickshell.shellPath("modules/ii/dynamicIsland/activities/teleprompter/TeleprompterExpanded.qml")
                onLoaded: root.syncPrompter()
            }
        }
    }

    StyledText {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 14
        text: root.engaged ? Translation.tr("The card the hover opens on the island")
            : Translation.tr("Hover to preview the control card")
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
}
