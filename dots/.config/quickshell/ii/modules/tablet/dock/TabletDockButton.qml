import QtQuick

import qs.modules.common
import qs.modules.common.dock

/**
 * One touch-sized item in the tablet dock: an adaptive app icon with a running dot.
 *
 * No hover growth and no tooltip — there is no cursor to read intent from, so the only
 * feedback available is the press itself.
 */
Item {
    id: root

    property string appId: ""
    property bool running: false
    property real iconSize: 44
    property real buttonSize: root.iconSize + Appearance.sizes.elevationMargin * 2

    signal activated

    implicitWidth: root.buttonSize
    implicitHeight: root.buttonSize

    DockIcon {
        id: icon
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        appId: root.appId
        isRunning: root.running
        visible: root.appId.length > 0
        scale: tapArea.pressed ? 0.86 : 1

        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // Android marks a running app with a dot under the icon rather than a highlight behind
    // it, which keeps the adaptive icon itself as the visual focus.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Appearance.sizes.elevationMargin / 8
        width: root.running && root.appId.length > 0 ? Appearance.sizes.elevationMargin * 0.625 : 0
        height: Appearance.sizes.elevationMargin * 0.625
        radius: height / 2
        color: Appearance.colors.colOnLayer1
        opacity: root.running && root.appId.length > 0 ? 0.85 : 0

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
