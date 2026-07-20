import QtQuick
import Quickshell
import qs.modules.common

/*
 * Widget to be placed on a WidgetCanvas
 */
MouseArea {
    id: root

    property bool allowMiddleClick: false
    property alias animateXPos: xBehavior.enabled
    property alias animateYPos: yBehavior.enabled
    property int animDuration: Appearance.animation.elementMove.duration
    property bool draggable: true
    drag.target: draggable ? root : undefined
    cursorShape: (draggable && containsPress) ? Qt.ClosedHandCursor : draggable ? Qt.OpenHandCursor : Qt.ArrowCursor
    acceptedButtons: allowMiddleClick ? Qt.MiddleButton | Qt.LeftButton : Qt.LeftButton

    function center() {
        root.x = (root.parent.width - root.width) / 2
        root.y = (root.parent.height - root.height) / 2
    }

    NumberAnimation {
        id: sharedXAnim
        duration: root.animDuration
        easing.type: (root.animDuration == Math.round(450 * Appearance.animMultiplier) || root.animDuration > 500) ? Easing.OutCubic : Appearance.animation.elementMove.type
        easing.bezierCurve: (root.animDuration == Math.round(450 * Appearance.animMultiplier) || root.animDuration > 500) ? [] : Appearance.animation.elementMove.bezierCurve
    }
    Behavior on x {
        id: xBehavior
        animation: sharedXAnim
    }
    NumberAnimation {
        id: sharedYAnim
        duration: root.animDuration
        easing.type: (root.animDuration == Math.round(450 * Appearance.animMultiplier) || root.animDuration > 500) ? Easing.OutCubic : Appearance.animation.elementMove.type
        easing.bezierCurve: (root.animDuration == Math.round(450 * Appearance.animMultiplier) || root.animDuration > 500) ? [] : Appearance.animation.elementMove.bezierCurve
    }
    Behavior on y {
        id: yBehavior
        animation: sharedYAnim
    }
}
