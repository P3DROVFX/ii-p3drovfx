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

    signal activated

    implicitWidth: Appearance.sizes.minimumTouchTarget
    implicitHeight: Appearance.sizes.minimumTouchTarget

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
        // The dock sits on the wallpaper with no plate behind it, so the glyph carries its
        // own contrast rather than trusting whatever image is underneath.
        color: "white"
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.45)
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        onClicked: root.activated()
    }
}
