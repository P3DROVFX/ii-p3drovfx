import QtQuick

/**
 * The body of a timed block. A press starts a move, or a click when the block
 * cannot move; the gesture decides whether it became a drag. Positions are
 * translated into the events row's coordinates, so the pointer keeps working
 * when it leaves this block or the grid scrolls.
 */
MouseArea {
    id: grab

    required property var gesture
    required property Item coordinateRoot
    property string kind: "move"
    property var target: null
    property int day: -1
    property int start: 0
    property int end: 0

    signal finished(var result)

    anchors.fill: parent
    hoverEnabled: true
    preventStealing: true
    cursorShape: grab.gesture.active && grab.gesture.target === grab.target ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    z: 2

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
}
