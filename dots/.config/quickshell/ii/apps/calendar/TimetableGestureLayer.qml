import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import "."
import "TimetableHelpers.js" as H

/**
 * What the pointer is doing on the timed grid, drawn once above every column.
 *
 * A moved or resized event is lifted as one card at the snapped range: its
 * source block is hidden while the gesture is active, so the event reads as
 * moving rather than duplicated. A new event (or the draft the editor is
 * building) is a tonal card with grab bars on both edges. The target column
 * gets a faint tint instead of a border.
 */
Item {
    id: layer

    required property var gesture
    property real dayColumnWidth: 0
    property real dayStride: 0
    property real pixelsPerMinute: 1
    property real blockGap: 0
    property int startHour: 0
    property int startMinute: 0

    signal finished(var result)

    readonly property bool creating: layer.gesture.active && layer.gesture.kind === "create"
    readonly property bool draftMoving: layer.gesture.active && layer.gesture.kind.indexOf("draft") === 0
    readonly property bool eventMoving: layer.gesture.active && (layer.gesture.kind === "move" || layer.gesture.kind.indexOf("resize") === 0)
    readonly property bool showDraft: layer.creating || layer.draftMoving || layer.gesture.hasDraft
    readonly property bool showTint: layer.creating || layer.draftMoving || (layer.gesture.active && layer.gesture.kind === "move")
    readonly property int draftDay: (layer.creating || layer.draftMoving) ? layer.gesture.previewDay : layer.gesture.draftDay
    readonly property int draftStart: (layer.creating || layer.draftMoving) ? layer.gesture.previewStart : layer.gesture.draftStart
    readonly property int draftEnd: (layer.creating || layer.draftMoving) ? layer.gesture.previewEnd : layer.gesture.draftEnd

    function cardX(day) {
        return Math.max(0, day) * layer.dayStride + 5;
    }

    function cardY(minutes) {
        return H.minutesToY(minutes, layer.startHour, layer.startMinute, layer.pixelsPerMinute);
    }

    function cardHeight(startMinutes, endMinutes) {
        return H.timedBlockHeight(startMinutes, endMinutes, layer.pixelsPerMinute, layer.blockGap);
    }

    function rangeText(startMinutes, endMinutes) {
        const format = Config.options?.time.format;
        return H.minutesToTimeStr(startMinutes, format) + " — " + H.minutesToTimeStr(endMinutes, format);
    }

    // Target column tint: a surface, not an outline.
    Rectangle {
        id: targetTint
        x: layer.cardX(layer.gesture.previewDay) - 5
        y: 0
        width: layer.dayColumnWidth
        height: layer.height
        radius: Appearance.rounding.windowRounding
        color: H.withOpacity(Appearance.colors.colPrimary, 0.06)
        opacity: layer.showTint ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    // ─── Moved or resized event ───────────────
    // Shadows sit beneath their card, so they are declared first.
    StyledRectangularShadow {
        target: movedCard
    }

    Rectangle {
        id: movedCard
        readonly property color fill: layer.gesture.target ? H.chipColor(layer.gesture.target, Appearance.colors, GoogleCalendarService.colorForEvent(layer.gesture.target)) : Appearance.colors.colPrimaryContainer

        x: layer.cardX(layer.gesture.previewDay)
        y: layer.cardY(layer.gesture.previewStart)
        width: layer.dayColumnWidth - 12
        height: layer.cardHeight(layer.gesture.previewStart, layer.gesture.previewEnd)
        radius: Appearance.rounding.normal
        color: movedCard.fill
        opacity: layer.eventMoving ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2
            clip: true

            StyledText {
                width: parent.width
                text: layer.gesture.target?.content ?? Translation.tr("Event")
                font.weight: Font.DemiBold
                font.pixelSize: Appearance.font.pixelSize.small
                elide: Text.ElideRight
                color: ColorUtils.getContrastingTextColor(movedCard.fill)
            }

            StyledText {
                width: parent.width
                visible: movedCard.height >= 40
                text: layer.rangeText(layer.gesture.previewStart, layer.gesture.previewEnd)
                font.weight: Font.Medium
                font.pixelSize: Appearance.font.pixelSize.smallest
                elide: Text.ElideRight
                color: ColorUtils.getContrastingTextColor(movedCard.fill)
            }
        }
    }

    // ─── Draft: a new event, or the one being resized or moved ───────────
    StyledRectangularShadow {
        target: draftCard
    }

    Rectangle {
        id: draftCard

        x: layer.cardX(layer.draftDay)
        y: layer.cardY(layer.draftStart)
        width: layer.dayColumnWidth - 12
        height: layer.cardHeight(layer.draftStart, layer.draftEnd)
        radius: Appearance.rounding.normal
        color: Appearance.colors.colPrimaryContainer
        opacity: layer.showDraft && layer.draftDay >= 0 ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        // Body: drags the whole draft to another slot or column.
        TimetableBlockGrab {
            gesture: layer.gesture
            coordinateRoot: layer
            kind: "draftMove"
            day: layer.gesture.draftDay
            start: layer.gesture.draftStart
            end: layer.gesture.draftEnd
            enabled: draftCard.visible
            onFinished: result => layer.finished(result)
        }

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2
            clip: true

            StyledText {
                width: parent.width
                text: Translation.tr("New event")
                font.weight: Font.DemiBold
                font.pixelSize: Appearance.font.pixelSize.small
                elide: Text.ElideRight
                color: Appearance.colors.colOnPrimaryContainer
            }

            StyledText {
                width: parent.width
                visible: draftCard.height >= 40
                text: layer.rangeText(layer.draftStart, layer.draftEnd)
                font.weight: Font.Medium
                font.pixelSize: Appearance.font.pixelSize.smallest
                elide: Text.ElideRight
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        TimetableEdgeGrab {
            gesture: layer.gesture
            coordinateRoot: layer
            kind: "draftResizeStart"
            atTop: true
            day: layer.gesture.draftDay
            start: layer.gesture.draftStart
            end: layer.gesture.draftEnd
            barColor: Appearance.colors.colPrimary
            alwaysShown: true
            enabled: draftCard.visible
            onFinished: result => layer.finished(result)
        }

        TimetableEdgeGrab {
            gesture: layer.gesture
            coordinateRoot: layer
            kind: "draftResizeEnd"
            day: layer.gesture.draftDay
            start: layer.gesture.draftStart
            end: layer.gesture.draftEnd
            barColor: Appearance.colors.colPrimary
            alwaysShown: true
            enabled: draftCard.visible
            onFinished: result => layer.finished(result)
        }
    }
}
