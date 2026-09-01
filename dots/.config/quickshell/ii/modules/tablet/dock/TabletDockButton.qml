import QtQuick
import Quickshell
import Quickshell.Widgets

import qs.services
import qs.modules.common

/**
 * One app in the tablet dock: an icon with a running dot under it.
 *
 * No hover growth and no tooltip — there is no cursor to read intent from, so the only
 * feedback available is the press itself.
 */
Item {
    id: root

    property string appId: ""
    property string iconSource: ""
    property bool running: false
    property real iconSize: 44

    signal activated

    implicitWidth: root.iconSize + 16
    implicitHeight: root.iconSize + 16

    IconImage {
        id: icon
        anchors.centerIn: parent
        implicitSize: root.iconSize
        source: root.iconSource
        scale: tapArea.pressed ? 0.86 : 1

        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // Android marks a running app with a dot under the icon rather than a highlight
    // behind it, which keeps the icon itself the only thing competing for attention.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        width: root.running ? 5 : 0
        height: 5
        radius: height / 2
        color: Appearance.colors.colOnLayer1
        opacity: root.running ? 0.85 : 0

        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        onClicked: root.activated()
    }
}
