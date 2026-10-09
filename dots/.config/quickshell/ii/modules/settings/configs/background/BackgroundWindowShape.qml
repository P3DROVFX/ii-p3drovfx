import QtQuick
import qs.modules.common

/**
 * A stand-in window for the blur demo: a rounded body under a title bar with three dots.
 * Abstract on purpose, so it reads as "a window" without pretending to be an app.
 */
Rectangle {
    id: root

    readonly property real barHeight: 22
    readonly property real dotSize: 7
    readonly property real dotGap: 5
    readonly property real barInset: 10
    readonly property real bodyLineHeight: 7
    readonly property real bodyLineAlpha: 0.5

    radius: Appearance.rounding.normal
    color: Appearance.m3colors.m3surfaceContainerHigh

    Row {
        anchors {
            left: parent.left
            leftMargin: root.barInset
            top: parent.top
        }
        height: root.barHeight
        spacing: root.dotGap

        Repeater {
            model: 3

            delegate: Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: root.dotSize
                height: root.dotSize
                radius: width / 2
                color: Appearance.colors.colOutline
            }
        }
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: root.barHeight + root.barInset
            margins: root.barInset
        }
        spacing: root.dotGap

        Repeater {
            model: [1, 0.8, 0.55]

            delegate: Rectangle {
                required property real modelData

                width: (root.width - root.barInset * 2) * modelData
                height: root.bodyLineHeight
                radius: height / 2
                color: Appearance.m3colors.m3surfaceContainerHighest
                opacity: root.bodyLineAlpha + 0.5
            }
        }
    }
}
