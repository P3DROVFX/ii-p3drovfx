pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Calendar, as the background's "Calendar Upcoming 3 Days 1x1" desktop widget: the next
 * three days, each under its own date heading, every event as a card with its title and
 * its hours, today's heading carrying the widget's round (+) into the timetable, and
 * "No Events" where a day has none.
 *
 * The widget is a 240 x 240 card whose list *scrolls*: three days of events never fit its
 * box, which is why the desktop version is a ListView. A tile cannot scroll — in edit mode
 * a press on it starts a drag — so the rows and how many of them fit are
 * `CalendarEventRows`, shared with the month card that grows into this same list. What is
 * this widget's own is the one-line footprint at the bottom.
 *
 * One-row footprints (1x1, 2x1, 4x1 …) have no room for a heading plus a card, so they
 * draw the widget's *content* as a single line instead — the next event's hours and title,
 * with the day before them when there is width for it — and "No Events" when the three
 * days are empty. That is a removal, not another design: everything shown is the same
 * text the rows would carry.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Calendar")

    // ── The next three days, out of the service's own index ──────────────────
    readonly property var days: {
        const anchor = DateTime.clock.date ?? new Date();
        const list = [];
        for (let offset = 0; offset < 3; offset++) {
            const date = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate() + offset);
            list.push({
                "date": date,
                "isToday": offset === 0,
                "label": Qt.locale().toString(date, "ddd, MMM d"),
                // The service's index is already a day's events in its own order:
                // all-day first, then by start time.
                "events": CalendarService.eventsForDay(date) ?? []
            });
        }
        return list;
    }

    /** The first event of the three days, for the footprints with room for one line. */
    readonly property var nextEvent: {
        for (let dayIndex = 0; dayIndex < root.days.length; dayIndex++) {
            const day = root.days[dayIndex];
            if (day.events.length > 0)
                return { "dayLabel": day.label, "isToday": day.isToday, "event": day.events[0] };
        }
        return null;
    }

    // ── The room the tile has ────────────────────────────────────────────────
    readonly property real pad: Math.max(6, Math.min(16,
        Math.round(Math.min(root.surface.width, root.surface.height) * 0.067)))
    readonly property real contentWidth: Math.max(0, root.surface.width - root.pad * 2)
    readonly property real contentHeight: Math.max(0, root.surface.height - root.pad * 2)

    // ── The rows, from the shared list ───────────────────────────────────────
    CalendarEventRows {
        id: eventList

        anchors.fill: parent
        anchors.margins: root.pad
        visible: !root.oneLine
        // Told, not just hidden: a Repeater builds its delegates for an invisible list too.
        show: !root.oneLine
        days: root.days
        withCreateButton: true
        editMode: root.editMode
    }

    // ── One line, for the footprints that have no room for a row ─────────────
    readonly property bool oneLine: root.contentHeight < 64 || eventList.shownRows.length === 0
    readonly property real lineSize: Math.max(9, Math.min(20,
        Math.round(Math.min(root.contentHeight * 0.42, root.contentWidth * 0.09))))
    readonly property real lineDaySize: Math.max(9, Math.round(root.lineSize * 0.85))
    readonly property bool lineShowsDay: root.contentWidth >= 150
    readonly property bool lineShowsTime: root.contentWidth >= 110

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        visible: root.oneLine
        spacing: Math.round(root.lineSize * 0.4)

        StyledText {
            visible: root.oneLine && root.lineShowsDay && root.nextEvent !== null
            text: root.nextEvent === null ? "" : root.nextEvent.dayLabel
            color: eventList.headingColor
            font.weight: Font.Medium
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            font.pixelSize: root.lineDaySize
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        StyledText {
            visible: root.oneLine && root.lineShowsTime && root.nextEvent !== null
            text: root.nextEvent === null ? "" : eventList.eventTime(root.nextEvent.event)
            color: eventList.cardTimeColor
            font.weight: Font.ExtraBold
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            font.pixelSize: root.lineSize * 0.8
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.oneLine && root.nextEvent !== null
            text: root.nextEvent === null ? "" : eventList.eventTitle(root.nextEvent.event)
            color: eventList.cardTitleColor
            font.weight: Font.DemiBold
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            font.pixelSize: root.lineSize
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.oneLine && root.nextEvent === null
            text: Translation.tr("No Events")
            color: eventList.cardTimeColor
            font.weight: Font.Medium
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            font.pixelSize: root.lineSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
