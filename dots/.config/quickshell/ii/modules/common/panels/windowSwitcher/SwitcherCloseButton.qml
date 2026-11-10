import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The × on a switcher card or cover: shown while the pointer is over its window, closes it.
 * Shared by the floating panel and the island's cover flow.
 */
MouseArea {
    id: button

    /// The pointer is over the card this sits on (or over the button itself).
    property bool shown: false
    property real size: 26

    width: button.size
    height: button.size
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    enabled: button.opacity > 0.5

    opacity: button.shown ? 1 : 0
    scale: button.shown ? 1 : 0.8
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standard
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: button.containsMouse ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2
        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
            }
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: "close"
        iconSize: Math.round(button.size * 0.62)
        color: button.containsMouse ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
    }
}
