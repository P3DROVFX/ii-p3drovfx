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

Rectangle {
    id: eventBlock

    property var eventData
    property int colIndex: 0
    property int totalCols: 1
    property int dayIdx
    property var nextEventData
    property real maxLogicalDistance: 1.0
    property real pixelsPerMinute
    property real eventSpacing
    property int startHour
    property int startMinute
    property Item coordinateRoot: null
    property bool manipulating: false
    property var gesture: null

    signal deleteRequested(var event, int dayIndex)
    signal gestureFinished(var result)

    readonly property bool isNextEvent: nextEventData && nextEventData.dayIndex === dayIdx && nextEventData.startMinutes === eventStartMinutes
    readonly property bool sportEvent: eventData?.sportEvent === true
    readonly property bool readOnly: eventData?.readOnly === true
    readonly property string meetingUrl: {
        const url = String(eventData?.url ?? "").trim();
        if (url.length === 0)
            return "";
        return String(EmailDetections.detectAll(url).meetings[0]?.url ?? "");
    }
    readonly property color semanticColor: eventBlock.sportEvent
        ? Appearance.colors.colTertiaryContainer
        : H.chipColor(eventData, Appearance.colors, GoogleCalendarService.colorForEvent(eventData))

    readonly property int eventStartMinutes: H.eventStartMinutes(eventData) ?? 0
    readonly property int eventEndMinutes: H.eventEndMinutes(eventData) ?? eventStartMinutes
    readonly property bool isAtTop: eventStartMinutes <= startHour * 60 + startMinute
    readonly property bool isAtBottom: eventEndMinutes >= (startHour + 24) * 60 || eventEndMinutes >= 24 * 60
    readonly property bool isCompact: eventBlock.height <= 52
    // Only a single-day event with a real span can be dragged: a multi-day or
    // zero-length one would be truncated by the write-back.
    readonly property bool movable: !readOnly && !sportEvent
        && eventData?.startDate && eventData?.endDate
        && H.sameDate(eventData.startDate, eventData.endDate)
        && eventData.endDate.getTime() > eventData.startDate.getTime()

    // Overlap layout
    width: (parent.width - 10) / totalCols - 2
    x: colIndex * ((parent.width - 10) / totalCols) + 5
    
    radius: Appearance.rounding.normal
    topLeftRadius: isAtTop && colIndex === 0 ? Math.max(Appearance.rounding.normal, Appearance.rounding.windowRounding - 4) : Appearance.rounding.normal
    topRightRadius: isAtTop && colIndex === totalCols - 1 ? Math.max(Appearance.rounding.normal, Appearance.rounding.windowRounding - 4) : Appearance.rounding.normal
    bottomLeftRadius: isAtBottom && colIndex === 0 ? Math.max(Appearance.rounding.normal, Appearance.rounding.windowRounding - 4) : Appearance.rounding.normal
    bottomRightRadius: isAtBottom && colIndex === totalCols - 1 ? Math.max(Appearance.rounding.normal, Appearance.rounding.windowRounding - 4) : Appearance.rounding.normal
    clip: true
    z: isNextEvent ? 4 : 3
    color: H.eventColorWithProximity(
        eventBlock.semanticColor,
        Config.options.calendar.timetable.proximityColorGradient && !eventBlock.sportEvent,
        eventBlock.dayIdx,
        eventBlock.eventStartMinutes,
        eventBlock.nextEventData,
        eventBlock.maxLogicalDistance,
        Appearance.colors
    )
    y: Math.max(isAtTop ? 4 : 0, H.minutesToY(eventStartMinutes, startHour, startMinute, pixelsPerMinute))
    height: H.timedBlockHeight(eventStartMinutes, eventEndMinutes, pixelsPerMinute, eventSpacing)
    // The gesture layer draws the lifted copy; the source steps aside so the
    // event reads as moving, not duplicated.
    opacity: eventBlock.manipulating ? 0 : 1

    // Decorative watermark icon for the next event
    MaterialSymbol {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: -10
        text: eventBlock.sportEvent ? "sports_score" : "event_upcoming"
        font.pixelSize: Math.min(parent.height, parent.width) * 0.8
        color: ColorUtils.getContrastingTextColor(eventBlock.color)
        opacity: 0.15
        visible: (isNextEvent || eventBlock.sportEvent) && eventBlock.height > 44
        z: 0
        antialiasing: true
    }

    HoverHandler {
        id: eventHover
    }

    StyledToolTip {
        extraVisibleCondition: eventHover.hovered && !eventBlock.manipulating
        text: {
            let title = eventData.content || qsTr("Event");
            let description = eventData.description || "";
            let startStr = H.minutesToTimeStr(eventStartMinutes, Config.options?.time.format);
            let endStr = H.minutesToTimeStr(eventEndMinutes, Config.options?.time.format);
            let range = startStr && endStr ? startStr + " - " + endStr : startStr || endStr;
            return range ? description ? "•  " + title + "\n•  " + range + "\n•  " + description : "•  " + title + "\n•  " + range : "•  " + title;
        }
    }

    // Body: a press is a click (edit) or, past the threshold, a move. Edges:
    // resize. The gesture owns the thresholds and the result.
    TimetableBlockGrab {
        gesture: eventBlock.gesture
        coordinateRoot: eventBlock.coordinateRoot
        kind: eventBlock.movable ? "move" : "click"
        target: eventBlock.eventData
        day: eventBlock.dayIdx
        start: eventBlock.eventStartMinutes
        end: eventBlock.eventEndMinutes
        onFinished: result => eventBlock.gestureFinished(result)
    }

    TimetableEdgeGrab {
        gesture: eventBlock.gesture
        coordinateRoot: eventBlock.coordinateRoot
        kind: "resizeStart"
        atTop: true
        target: eventBlock.eventData
        day: eventBlock.dayIdx
        start: eventBlock.eventStartMinutes
        end: eventBlock.eventEndMinutes
        barColor: ColorUtils.getContrastingTextColor(eventBlock.color)
        enabled: eventBlock.movable
        onFinished: result => eventBlock.gestureFinished(result)
    }

    TimetableEdgeGrab {
        gesture: eventBlock.gesture
        coordinateRoot: eventBlock.coordinateRoot
        kind: "resizeEnd"
        target: eventBlock.eventData
        day: eventBlock.dayIdx
        start: eventBlock.eventStartMinutes
        end: eventBlock.eventEndMinutes
        barColor: ColorUtils.getContrastingTextColor(eventBlock.color)
        enabled: eventBlock.movable
        onFinished: result => eventBlock.gestureFinished(result)
    }

    // Delete button
    RippleButton {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: eventBlock.height <= 36 ? 2 : 4
        implicitWidth: eventBlock.height <= 36 ? 18 : 24
        implicitHeight: eventBlock.height <= 36 ? 18 : 24
        buttonRadius: Appearance.rounding.full
        buttonColor: H.withOpacity(Appearance.colors.colOnSurface, 0.15)
        opacity: eventHover.hovered ? 1 : 0
        visible: opacity > 0 && !eventBlock.readOnly && eventBlock.height >= 20
        z: 15

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onClicked: {
            if (eventData?.uid)
                eventBlock.deleteRequested(eventData, eventBlock.dayIdx);
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: eventBlock.height <= 36 ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.smallie
            text: "close"
            color: ColorUtils.getContrastingTextColor(eventBlock.color)
        }
    }

    // Frequent meeting action: keep it directly on blocks tall enough to
    // accommodate a secondary affordance without covering their title.
    RippleButton {
        id: joinButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 4
        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        buttonColor: H.withOpacity(Appearance.colors.colOnSurface, 0.15)
        visible: eventBlock.height > 60 && eventBlock.meetingUrl.length > 0 && !eventBlock.manipulating
        z: 15

        onClicked: Qt.openUrlExternally(eventBlock.meetingUrl)

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            text: "videocam"
            color: ColorUtils.getContrastingTextColor(eventBlock.color)
        }

        StyledToolTip {
            extraVisibleCondition: joinButton.hovered
            text: Translation.tr("Join meeting")
        }
    }

    // Compact single-line event content (15m - 30m short events)
    RowLayout {
        id: compactRow
        visible: eventBlock.isCompact
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: (eventHover.hovered && !eventBlock.readOnly && eventBlock.height >= 20) ? 22 : 6
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        spacing: 5
        z: 1

        Rectangle {
            visible: eventBlock.isNextEvent
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: nextTextCompact.implicitWidth + 8
            implicitHeight: Math.min(18, Math.max(14, eventBlock.height - 6))
            color: ColorUtils.getContrastingTextColor(eventBlock.color)
            radius: Appearance.rounding.full

            StyledText {
                id: nextTextCompact
                anchors.centerIn: parent
                text: "NEXT"
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: eventBlock.color
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: eventData.content ?? Translation.tr("Event")
            font.weight: Font.DemiBold
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
            color: ColorUtils.getContrastingTextColor(eventBlock.color)
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: eventBlock.width >= 180 && eventBlock.height >= 30
            text: H.minutesToTimeStr(eventBlock.eventStartMinutes, Config.options?.time.format) + " - " + H.minutesToTimeStr(eventBlock.eventEndMinutes, Config.options?.time.format)
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            color: ColorUtils.getContrastingTextColor(eventBlock.color)
            elide: Text.ElideRight
        }
    }

    // Standard multi-line event content (for normal height events)
    Column {
        id: standardColumn
        visible: !eventBlock.isCompact
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4
        z: 1

        StyledText {
            text: eventData.content ?? Translation.tr("Event")
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            width: parent.width - 28
            color: ColorUtils.getContrastingTextColor(eventBlock.color)
        }

        StyledText {
            width: parent.width
            visible: eventBlock.sportEvent && eventBlock.height > 82
            text: [eventData.status, eventData.lastPlay].filter(value => String(value ?? "").length > 0).join(" · ")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            color: ColorUtils.getContrastingTextColor(eventBlock.color)
            elide: Text.ElideRight
        }

        Row {
            spacing: 6
            width: parent.width
            visible: eventBlock.height > 60 || eventBlock.isNextEvent

            Rectangle {
                visible: eventBlock.isNextEvent
                width: nextText.implicitWidth + 8
                height: nextText.implicitHeight + 2
                color: ColorUtils.getContrastingTextColor(eventBlock.color)
                radius: Appearance.rounding.full
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    id: nextText
                    anchors.centerIn: parent
                    text: "NEXT"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: eventBlock.color
                }
            }

            StyledText {
                text: H.minutesToTimeStr(eventBlock.eventStartMinutes, Config.options?.time.format) + " - " + H.minutesToTimeStr(eventBlock.eventEndMinutes, Config.options?.time.format)
                font.weight: Font.Medium
                color: ColorUtils.getContrastingTextColor(eventBlock.color)
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
