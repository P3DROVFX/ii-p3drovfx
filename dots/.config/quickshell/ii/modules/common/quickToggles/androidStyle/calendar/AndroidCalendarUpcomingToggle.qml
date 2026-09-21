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
 * a press on it starts a drag — so the port keeps the rows and lets the surface decide how
 * many of them there is room for, tallest footprint showing the whole three days. That is
 * also what makes it work at every size: the row heights come from the tile's width (a
 * list is read across, not down), the type follows them, and what the height cannot hold
 * is dropped from the bottom.
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

    function eventTitle(event) {
        const title = String(event?.content ?? event?.summary ?? "").trim();
        return title.length > 0 ? title : Translation.tr("Event");
    }

    /** "All Day", or the hours in the format the shell is set to read time in. */
    function eventTime(event) {
        if (event?.allDay === true)
            return Translation.tr("All Day");
        const format = Config.options?.time?.format ?? "hh:mm";
        const start = Qt.locale().toString(new Date(event.startDate), format);
        const end = Qt.locale().toString(new Date(event.endDate), format);
        return start + " - " + end;
    }

    // ── Colours: the widget's own pairing, on this surface ───────────────────
    readonly property color headingColor: Appearance.colors.colOnSurfaceVariant
    readonly property color cardColor: Appearance.colors.colSurfaceContainerHighest
    readonly property color cardTitleColor: Appearance.colors.colOnSurface
    readonly property color cardTimeColor: Qt.rgba(Appearance.colors.colOnSurfaceVariant.r,
        Appearance.colors.colOnSurfaceVariant.g, Appearance.colors.colOnSurfaceVariant.b, 0.75)
    readonly property color emptyColor: Appearance.colors.colSurfaceContainerLow

    // ── The room the tile has ────────────────────────────────────────────────
    readonly property real pad: Math.max(6, Math.min(16,
        Math.round(Math.min(root.surface.width, root.surface.height) * 0.067)))
    readonly property real contentWidth: Math.max(0, root.surface.width - root.pad * 2)
    readonly property real contentHeight: Math.max(0, root.surface.height - root.pad * 2)

    /**
     * The widget's 16 px over its 208 px of content width, kept from growing past a list
     * type, and held under what a day heading plus one of its cards costs in height —
     * 5.92 times the title size is that pair with the widget's own gaps. Without the
     * second cap a wide, short tile sizes its type off the width alone and has room for
     * the heading and nothing under it.
     */
    readonly property real titleSize: Math.max(9, Math.min(18,
        Math.round(Math.min(root.contentWidth * 0.077, root.contentHeight * 0.169))))
    readonly property real timeSize: Math.max(8, Math.round(root.titleSize * 0.8))
    readonly property real daySize: Math.max(9, Math.round(root.titleSize * 1.125))
    readonly property real cardPadH: Math.round(root.titleSize * 0.875)
    readonly property real cardPadV: Math.round(root.titleSize * 0.625)
    readonly property real lineGap: Math.round(root.titleSize * 0.125)
    readonly property real dayGap: Math.round(root.titleSize * 0.75)
    readonly property real withinDayGap: Math.round(root.titleSize * 0.375)

    // ── The rows, tallest-first from the widget's own list ───────────────────
    readonly property real dayRowHeight: Math.round(root.daySize * 1.55)
    readonly property real eventRowHeight: Math.round(root.titleSize * 1.35) + root.lineGap
        + Math.round(root.timeSize * 1.35) + root.cardPadV * 2
    readonly property real emptyRowHeight: Math.round(root.titleSize * 2.9)

    /**
     * Every row the widget's list would draw, in its order, and the gap above each one:
     * nothing within a day, the widget's 12 px between the days. Every row carries the
     * same fields — a hidden card's text may never be `undefined`, which Qt reports as a
     * failed assignment on every row that is not its kind.
     */
    readonly property var rows: {
        const built = [];
        for (let dayIndex = 0; dayIndex < root.days.length; dayIndex++) {
            const day = root.days[dayIndex];
            built.push({
                "kind": "day", "label": day.label, "isToday": day.isToday,
                "title": "", "time": "",
                "height": root.dayRowHeight, "gapBefore": dayIndex === 0 ? 0 : root.dayGap
            });
            if (day.events.length === 0) {
                built.push({
                    "kind": "empty", "label": "", "isToday": false, "title": "", "time": "",
                    "height": root.emptyRowHeight, "gapBefore": root.withinDayGap
                });
                continue;
            }
            for (let eventIndex = 0; eventIndex < day.events.length; eventIndex++) {
                built.push({
                    "kind": "event", "label": "", "isToday": false,
                    "height": root.eventRowHeight,
                    "gapBefore": eventIndex === 0 ? root.withinDayGap : root.lineGap,
                    "title": root.eventTitle(day.events[eventIndex]),
                    "time": root.eventTime(day.events[eventIndex])
                });
            }
        }
        return built;
    }

    /** Rows grow into a tall tile, but no further than twice the widget's own size. */
    readonly property real naturalHeight: {
        let total = 0;
        for (let index = 0; index < root.rows.length; index++)
            total += root.rows[index].gapBefore + root.rows[index].height;
        return total;
    }
    readonly property real rowScale: root.naturalHeight > 0
        ? Math.min(2, Math.max(1, root.contentHeight / root.naturalHeight)) : 1

    /** The rows that fit, each with its own place; the block centred on what is left. */
    readonly property var shownRows: {
        const scale = root.rowScale;
        const shown = [];
        let used = 0;
        for (let index = 0; index < root.rows.length; index++) {
            const row = root.rows[index];
            // Rounded down: growing into a tall tile may never round the block past the
            // height it is growing into and drop the row that had just fit.
            const gap = Math.floor(row.gapBefore * scale);
            const height = Math.min(root.contentHeight, Math.floor(row.height * scale));
            if (used + gap + height > root.contentHeight)
                break;
            shown.push({
                "kind": row.kind, "label": row.label, "isToday": row.isToday,
                "title": row.title, "time": row.time,
                "y": used + gap, "height": height
            });
            used += gap + height;
        }
        const offset = Math.max(0, Math.round((root.contentHeight - used) / 2));
        for (let index = 0; index < shown.length; index++)
            shown[index].y += offset;
        return shown;
    }

    // ── One line, for the footprints that have no room for a row ─────────────
    readonly property bool oneLine: root.contentHeight < 64 || root.shownRows.length === 0
    readonly property real lineSize: Math.max(9, Math.min(20,
        Math.round(Math.min(root.contentHeight * 0.42, root.contentWidth * 0.09))))
    readonly property real lineDaySize: Math.max(9, Math.round(root.lineSize * 0.85))
    readonly property bool lineShowsDay: root.contentWidth >= 150
    readonly property bool lineShowsTime: root.contentWidth >= 110

    // ── The (+) is the widget's, and it only fits where the heading does ─────
    readonly property bool showCreateButton: !root.oneLine && root.contentWidth >= 120
        && Math.floor(root.dayRowHeight * root.rowScale) >= 22

    // ── The list ─────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: root.pad
        visible: !root.oneLine

        Repeater {
            model: root.shownRows

            delegate: Item {
                required property var modelData

                x: 0
                y: modelData.y
                width: root.contentWidth
                height: modelData.height

                // ── The day's heading, with today's (+) at its right ─────────
                RowLayout {
                    anchors.fill: parent
                    visible: modelData.kind === "day"
                    spacing: root.withinDayGap

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: root.headingColor
                        font.weight: Font.Bold
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 8
                        font.pixelSize: root.daySize
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignVCenter
                    }

                    RippleButton {
                        id: createButton

                        readonly property real pillHeight: Math.round(modelData.height * 0.9)

                        visible: modelData.isToday && root.showCreateButton
                        enabled: !root.editMode
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: pillHeight
                        Layout.preferredWidth: Math.round(pillHeight * 1.43)
                        buttonRadius: Math.round(pillHeight / 2)
                        colBackground: root.cardColor
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive

                        onClicked: GlobalStates.openCheatsheet("timetable")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "add"
                            iconSize: Math.round(createButton.pillHeight * 0.62)
                            color: root.headingColor
                        }
                    }
                }

                // ── One event, as the widget's card ──────────────────────────
                Rectangle {
                    anchors.fill: parent
                    visible: modelData.kind === "event"
                    radius: Appearance.rounding.normal
                    color: root.cardColor

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: root.cardPadH
                        anchors.rightMargin: root.cardPadH
                        spacing: root.lineGap

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: root.cardTitleColor
                            fontSizeMode: Text.Fit
                            minimumPixelSize: 7
                            font.pixelSize: root.titleSize
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.time
                            color: root.cardTimeColor
                            font.weight: Font.ExtraBold
                            fontSizeMode: Text.Fit
                            minimumPixelSize: 7
                            font.pixelSize: root.timeSize
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                        }
                    }
                }

                // ── A day without events, as the widget's placeholder ────────
                Rectangle {
                    anchors.fill: parent
                    visible: modelData.kind === "empty"
                    radius: Appearance.rounding.normal
                    color: root.emptyColor

                    StyledText {
                        anchors.fill: parent
                        anchors.leftMargin: root.cardPadH
                        anchors.rightMargin: root.cardPadH
                        text: Translation.tr("No Events")
                        color: root.cardTimeColor
                        font.weight: Font.Medium
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 7
                        font.pixelSize: root.timeSize
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    // ── The one line, for 1x1 and the other single-row footprints ────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        visible: root.oneLine
        spacing: root.withinDayGap

        StyledText {
            visible: root.oneLine && root.lineShowsDay && root.nextEvent !== null
            text: root.nextEvent === null ? "" : root.nextEvent.dayLabel
            color: root.headingColor
            font.weight: Font.Medium
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            font.pixelSize: root.lineDaySize
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        StyledText {
            visible: root.oneLine && root.lineShowsTime && root.nextEvent !== null
            text: root.nextEvent === null ? "" : root.eventTime(root.nextEvent.event)
            color: root.cardTimeColor
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
            text: root.nextEvent === null ? "" : root.eventTitle(root.nextEvent.event)
            color: root.cardTitleColor
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
            color: root.cardTimeColor
            font.weight: Font.Medium
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            font.pixelSize: root.lineSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
