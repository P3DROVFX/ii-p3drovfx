import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import qs.modules.common.functions
import "."
import "TimetableHelpers.js" as H

Item {
    id: dayColumn

    property int dayIdx
    property var dayData
    property bool isToday
    property bool keyboardSelected: false
    property real dayColumnWidth
    property real contentHeight
    property real pixelsPerMinute
    property real eventSpacing
    property int startHour
    property int startMinute
    property Item coordinateRoot: null
    // The one TimetableGesture of the grid; every press in this column goes to it.
    property var gesture: null
    // True while a gesture is running. The event blocks keep their layout
    // until it ends, because rebuilding them would drop the grab driving it.
    property bool frozen: false

    // For events
    property var nextEventData
    property real maxLogicalDistance: 1.0

    // Colors
    property color todayHighlightFill
    property color dayBackgroundFill
    property color dayBackgroundFillVariant

    signal gestureFinished(var result)
    signal deleteRequested(var event, int dayIndex)

    // Blocks for the day, as { event, colIndex, totalCols } rows.
    property var layout: []

    function refreshLayout() {
        if (dayColumn.frozen)
            return;
        dayColumn.layout = H.computeEventLayout(dayColumn.dayData?.events ?? [], event => CalendarService.isAllDayEvent(event));
    }

    onDayDataChanged: dayColumn.refreshLayout()
    onFrozenChanged: dayColumn.refreshLayout()
    Component.onCompleted: dayColumn.refreshLayout()

    width: dayColumnWidth
    height: contentHeight
    clip: true

    // Same weekend marker as the month grid: a texture, so it survives the
    // today fill without changing the timed background through the day.
    readonly property bool isWeekend: {
        const date = dayColumn.dayData?.date;
        if (!(date instanceof Date))
            return false;
        const weekday = date.getDay();
        return weekday === 0 || weekday === 6;
    }
    readonly property color weekendHatchColor: {
        const tertiary = Qt.color(Appearance.colors.colTertiary);
        return Qt.hsla(tertiary.hslHue, tertiary.hslSaturation * 0.3, tertiary.hslLightness, 0.13);
    }

    Rectangle {
        id: columnBackground
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: isToday ? todayHighlightFill : (dayColumn.keyboardSelected ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, (dayIdx % 2 === 0 ? dayBackgroundFill : dayBackgroundFillVariant), 0.35) : (dayIdx % 2 === 0 ? dayBackgroundFill : dayBackgroundFillVariant))

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(columnBackground)
        }
    }

    DiagonalHatch {
        anchors.fill: parent
        visible: dayColumn.isWeekend
        lineColor: dayColumn.weekendHatchColor
        lineSpacing: 9
        plateRadius: Appearance.rounding.windowRounding
    }

    // Press on an empty slot: drag to create a range, or click for an hour.
    MouseArea {
        id: createArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: Qt.CrossCursor
        z: 0

        onPressed: mouse => {
            const point = createArea.mapToItem(dayColumn.coordinateRoot, mouse.x, mouse.y);
            dayColumn.gesture.press("create", null, dayColumn.dayIdx, point.x, point.y, 0, 0);
        }

        onPositionChanged: mouse => {
            if (!createArea.pressed)
                return;
            const point = createArea.mapToItem(dayColumn.coordinateRoot, mouse.x, mouse.y);
            dayColumn.gesture.move(point.x, point.y);
        }

        onReleased: mouse => {
            const point = createArea.mapToItem(dayColumn.coordinateRoot, mouse.x, mouse.y);
            const result = dayColumn.gesture.release(point.x, point.y);
            if (result)
                dayColumn.gestureFinished(result);
        }

        onCanceled: dayColumn.gesture.cancel()
    }

    // ─── Existing event blocks ────────────────
    // Blocks are keyed by position: a refreshed layout rebinds their data in
    // place and never destroys a block, so a commit can run inside the handler
    // of the very grab that started it.
    Repeater {
        model: dayColumn.layout.length
        delegate: EventBlock {
            readonly property var slot: dayColumn.layout[index] ?? null
            eventData: slot?.event ?? null
            colIndex: slot?.colIndex ?? 0
            totalCols: slot?.totalCols ?? 1
            dayIdx: dayColumn.dayIdx
            nextEventData: dayColumn.nextEventData
            maxLogicalDistance: dayColumn.maxLogicalDistance
            pixelsPerMinute: dayColumn.pixelsPerMinute
            eventSpacing: dayColumn.eventSpacing
            startHour: dayColumn.startHour
            startMinute: dayColumn.startMinute
            coordinateRoot: dayColumn.coordinateRoot
            gesture: dayColumn.gesture
            manipulating: dayColumn.gesture !== null && dayColumn.gesture.active && eventData !== null && dayColumn.gesture.target === eventData
            onDeleteRequested: (evt, dIdx) => dayColumn.deleteRequested(evt, dIdx)
            onGestureFinished: result => dayColumn.gestureFinished(result)
        }
    }
}
