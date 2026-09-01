import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.common.widgets

/**
 * One Android navigation button: back, home or recents.
 *
 * Plain symbol on transparent ground, like Android's three-button navigation. The press
 * plate is the only feedback, since there is no cursor to hover with.
 */
Item {
    id: root

    property string symbol: ""
    property real symbolSize: 22
    property real symbolRotation: 0
    property real buttonSize: Appearance.sizes.minimumTouchTarget

    signal activated

    implicitWidth: root.buttonSize
    implicitHeight: root.buttonSize

    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        radius: height / 2
        color: Appearance.colors.colOnLayer0
        opacity: tapArea.pressed ? 0.16 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: root.symbolSize
        rotation: root.symbolRotation
        fill: 0
        color: Appearance.colors.colOnLayer0
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        onClicked: root.activated()
    }
}
