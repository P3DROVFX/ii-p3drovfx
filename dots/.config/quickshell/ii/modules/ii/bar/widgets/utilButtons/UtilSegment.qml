pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * One segment of the Segments utility buttons.
 *
 * The segments are joined into a track, so the corner radii are what says where
 * one button ends and the next begins — and what says which one you are about
 * to press. Both readings come off a single number:
 *
 *   pop = 0     square inner corners: part of the track
 *   pop ≈ 0.55  hover — the corners lift, the segment starts to detach
 *   pop = 1     active — fully round: the button has popped out of the track
 *
 * Nothing here changes length. A row where the hovered item grows has to take
 * that width from somewhere, and taking it from the neighbours puts the pointer
 * over a segment that is moving away from it.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property bool first: false
    property bool last: false
    property bool active: false
    property string iconText: ""
    property var altAction: null

    signal triggered(var event)

    readonly property bool hovered: mouseArea.containsMouse

    implicitWidth: root.thickness
    implicitHeight: root.thickness

    // Active outranks hover: a button that is on stays popped out while the
    // pointer is over it, rather than dropping back into the track.
    readonly property real popTarget: root.active ? 1.0 : (root.hovered ? 0.55 : 0.0)
    property real pop: root.popTarget

    Behavior on pop {
        enabled: !Appearance.reducedMotion
        NumberAnimation {
            duration: Math.round(200 * Appearance.animMultiplier)
            easing.type: Easing.OutQuad
        }
    }

    readonly property real seamRadius: Appearance.rounding.verysmall
    readonly property real fullRadius: root.thickness / 2
    readonly property real innerRadius: root.seamRadius + (root.fullRadius - root.seamRadius) * root.pop

    // The two ends of the group are round no matter what: they are the outline
    // of the track itself, not a seam between two buttons.
    readonly property real leadingRadius: root.first ? root.fullRadius : root.innerRadius
    readonly property real trailingRadius: root.last ? root.fullRadius : root.innerRadius

    readonly property color colSurface: root.active
        ? (root.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
        : (root.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
    readonly property color colInk: root.active
        ? Appearance.colors.colOnPrimary
        : Appearance.colors.colOnSecondaryContainer

    Rectangle {
        id: plate
        anchors.fill: parent
        color: root.colSurface

        topLeftRadius: root.vertical ? root.leadingRadius : root.leadingRadius
        topRightRadius: root.vertical ? root.leadingRadius : root.trailingRadius
        bottomLeftRadius: root.vertical ? root.trailingRadius : root.leadingRadius
        bottomRightRadius: root.vertical ? root.trailingRadius : root.trailingRadius

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(plate)
        }

        MaterialSymbol {
            id: symbol
            anchors.centerIn: parent
            text: root.iconText
            iconSize: Appearance.font.pixelSize.large
            fill: root.active ? 1 : 0
            color: root.colInk

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(symbol)
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | (root.altAction ? Qt.RightButton : Qt.NoButton)
        onClicked: event => {
            if (event.button === Qt.RightButton) {
                if (root.altAction)
                    root.altAction();
                return;
            }
            root.triggered(event);
        }
    }
}
