import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * What the animation multiplier does, run with the shell's own spatial curve: while the
 * card is under the pointer (`active`) a dot crosses the track and comes back, over and
 * over, at the duration the slider sets; it settles at the start when the pointer leaves.
 */
Rectangle {
    id: root

    readonly property real stageHeight: 120
    readonly property real stagePadding: 24
    readonly property real dotSize: 32
    readonly property real trackHeight: 6
    readonly property int restDuration: 350
    readonly property var move: Appearance.animation.elementMove

    property bool active: false

    Layout.fillWidth: true
    implicitHeight: root.stageHeight
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    onActiveChanged: {
        if (!root.active)
            home.restart();
    }

    Item {
        id: lane
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.stagePadding
            rightMargin: root.stagePadding
        }
        height: root.dotSize

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            height: root.trackHeight
            radius: height / 2
            color: Appearance.colors.colSecondaryContainer
        }
        Rectangle {
            id: dot
            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            color: Appearance.colors.colPrimary
        }
    }

    SequentialAnimation {
        id: loop
        running: root.active
        loops: Animation.Infinite

        NumberAnimation {
            target: dot
            property: "x"
            to: lane.width - dot.width
            duration: root.move.duration
            easing.type: root.move.type
            easing.bezierCurve: root.move.bezierCurve
        }
        PauseAnimation {
            duration: root.restDuration
        }
        NumberAnimation {
            target: dot
            property: "x"
            to: 0
            duration: root.move.duration
            easing.type: root.move.type
            easing.bezierCurve: root.move.bezierCurve
        }
        PauseAnimation {
            duration: root.restDuration
        }
    }

    NumberAnimation {
        id: home
        target: dot
        property: "x"
        to: 0
        duration: root.move.duration
        easing.type: root.move.type
        easing.bezierCurve: root.move.bezierCurve
    }
}
