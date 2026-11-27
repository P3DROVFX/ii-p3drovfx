import QtQuick
import qs.modules.common

/**
 * A grab bar on the top or bottom edge of a timed block. Dragging it moves the
 * block's start or end; the bar itself is the only visible affordance and
 * appears on hover, or always when the block is the one being built.
 */
MouseArea {
    id: grab

    required property var gesture
    required property Item coordinateRoot
    // "resizeStart" / "draftResizeStart" grab the top edge, the "End" kinds the bottom.
    property string kind: "resizeEnd"
    property bool atTop: false
    property var target: null
    property int day: -1
    property int start: 0
    property int end: 0
    property color barColor: Appearance.colors.colPrimary
    property bool alwaysShown: false

    signal finished(var result)

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: grab.atTop ? parent.top : undefined
    anchors.bottom: grab.atTop ? undefined : parent.bottom
    width: Math.min(parent.width - 20, 44)
    height: 14
    hoverEnabled: true
    preventStealing: true
    cursorShape: Qt.SizeVerCursor
    z: 12

    function gridPoint(mouse) {
        return grab.mapToItem(grab.coordinateRoot, mouse.x, mouse.y);
    }

    onPressed: mouse => {
        const point = grab.gridPoint(mouse);
        grab.gesture.press(grab.kind, grab.target, grab.day, point.x, point.y, grab.start, grab.end);
    }

    onPositionChanged: mouse => {
        if (!grab.pressed)
            return;
        const point = grab.gridPoint(mouse);
        grab.gesture.move(point.x, point.y);
    }

    onReleased: mouse => {
        const point = grab.gridPoint(mouse);
        const result = grab.gesture.release(point.x, point.y);
        if (result)
            grab.finished(result);
    }

    onCanceled: grab.gesture.cancel()

    // A HoverHandler, not containsMouse: the bar must not vanish as the
    // pointer arrives at it.
    HoverHandler {
        id: barHover
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, 28)
        height: 4
        radius: Appearance.rounding.full
        color: grab.barColor
        opacity: grab.alwaysShown || barHover.hovered || grab.pressed ? 0.9 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }
}
