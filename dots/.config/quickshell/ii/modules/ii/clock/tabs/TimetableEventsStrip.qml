pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Upcoming timetable events as one-tap alarm suggestions. An alarm made here is dated,
 * carries the event's uid and rings `timetableLeadMinutes` before the event.
 */
ColumnLayout {
    id: root

    property date now: new Date()

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property int lookaheadDays: Math.max(1, Config.options.clockApp?.timetableLookaheadDays ?? 2)
    readonly property int leadMinutes: Math.max(0, Config.options.clockApp?.timetableLeadMinutes ?? 15)
    readonly property int maxEvents: 12
    readonly property real cardWidth: ClockStyle.eventCardWidth
    readonly property real cardHeight: ClockStyle.eventCardHeight

    readonly property var events: {
        const list = [];
        const base = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate());
        for (let i = 0; i < root.lookaheadDays && list.length < root.maxEvents; i++) {
            const day = new Date(base.getFullYear(), base.getMonth(), base.getDate() + i);
            for (const event of CalendarService.eventsForDay(day)) {
                if (!event?.startDate || CalendarService.isAllDayEvent(event))
                    continue;
                if (event.startDate.getTime() - root.leadMinutes * 60000 <= root.now.getTime())
                    continue;
                list.push(event);
                if (list.length >= root.maxEvents)
                    break;
            }
        }
        return list;
    }

    visible: root.events.length > 0
    spacing: ClockStyle.gapSmall

    RowLayout {
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall

        MaterialSymbol {
            text: "calendar_month"
            iconSize: ClockStyle.iconSmall
            color: ClockStyle.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("From your timetable")
            font.pixelSize: ClockStyle.textNormal
            font.weight: Font.DemiBold
            color: ClockStyle.colPrimary
        }

        ClockButton {
            variant: "text"
            label: Translation.tr("Open timetable")
            onClicked: GlobalStates.openTimetableAt(Qt.formatDate(root.now, "yyyy-MM-dd"))
        }
    }

    ListView {
        id: eventList
        Layout.fillWidth: true
        implicitHeight: root.cardHeight
        orientation: ListView.Horizontal
        spacing: ClockStyle.gapSmall
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.events.length

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse
            onWheel: event => {
                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                eventList.contentX = Math.max(0, Math.min(eventList.contentWidth - eventList.width, eventList.contentX - delta));
            }
        }

        delegate: Rectangle {
            id: eventCard
            required property int index
            readonly property var event: root.events[eventCard.index]
            readonly property bool hasAlarm: AlarmService.hasAlarmForEvent(eventCard.event)

            width: root.cardWidth
            height: root.cardHeight
            radius: ClockStyle.radiusLarge
            color: eventCard.hasAlarm ? ClockStyle.colSecondaryContainer : ClockStyle.colSurfaceHigh

            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            StaggeredEntrance {
                index: eventCard.index
                active: !ClockStyle.reducedMotion
            }

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: ClockStyle.gapLarge
                }
                spacing: ClockStyle.gapTiny

                StyledText {
                    Layout.fillWidth: true
                    text: ClockFormat.relativeDay(eventCard.event.startDate, root.now) + " · " + ClockFormat.dateTime(eventCard.event.startDate)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: String(eventCard.event.content ?? "")
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignTop
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.Medium
                    color: eventCard.hasAlarm ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                }
            }

            ClockIconButton {
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    margins: ClockStyle.gapSmall
                }
                symbol: eventCard.hasAlarm ? "alarm_on" : "alarm_add"
                filled: eventCard.hasAlarm
                colBackground: eventCard.hasAlarm ? "transparent" : ClockStyle.colPrimaryContainer
                colIcon: eventCard.hasAlarm ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnPrimaryContainer
                tooltip: Translation.tr("Alarm %1 min before").arg(String(root.leadMinutes))
                onClicked: {
                    if (!eventCard.hasAlarm)
                        AlarmService.addAlarmForEvent(eventCard.event, root.leadMinutes);
                }
            }
        }
    }
}
