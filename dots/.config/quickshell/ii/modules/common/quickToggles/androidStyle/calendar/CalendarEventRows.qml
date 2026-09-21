pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A day-by-day list of a calendar's events, as the background's "Calendar Upcoming 3 Days"
 * desktop widget draws it: a heading per day, each event as a card with its title and its
 * hours, and "No Events" where a day has none.
 *
 * The widget's own list scrolls; a quick-toggle tile cannot (in edit mode a press on it
 * belongs to the grid), so this draws the rows it is given and lets the box it is placed
 * in decide how many of them fit — a taller box shows more, and the rest are dropped from
 * the bottom. The type comes from the box's width (a list is read across, not down) held
 * under what a heading plus one of its cards costs in height, so a wide, short box sizes
 * its type off the width alone and has room for the heading and nothing under it. Rows
 * grow into a tall box, but no further than twice the widget's own size.
 *
 * It is not a tile: it has no idea what a grid is, and takes its box from whoever places
 * it. That is what lets the same list sit under the upcoming widget's one-line footprint
 * and under a month grid, without either of them owning a second copy of the rows.
 *
 * `CalendarService` owns the order of a day's events (all-day first, then by start), and
 * the caller owns which days it hands over — this only draws them.
 */
Item {
    id: root

    /** [{ label, isToday, events: [event, …] }, …] — the days to draw, in order. */
    property var days: []
    /** Draw the widget's round (+) on today's heading. */
    property bool withCreateButton: false
    /** The tile's edit mode; the (+) stays inert while the grid owns the pointer. */
    property bool editMode: false
    /**
     * Whether this list is drawn at all. It has to be told: `visible` does not stop a
     * Repeater from materialising its delegates, so a hidden list would still build a
     * button, a card and three texts per row — the whole cost, for nothing.
     */
    property bool show: true

    // ── Colours: the widget's own pairing, on this surface ───────────────────
    readonly property color headingColor: Appearance.colors.colOnSurfaceVariant
    readonly property color cardColor: Appearance.colors.colSurfaceContainerHighest
    readonly property color cardTitleColor: Appearance.colors.colOnSurface
    readonly property color cardTimeColor: Qt.rgba(Appearance.colors.colOnSurfaceVariant.r,
        Appearance.colors.colOnSurfaceVariant.g, Appearance.colors.colOnSurfaceVariant.b, 0.75)
    readonly property color emptyColor: Appearance.colors.colSurfaceContainerLow

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

    // ── The room the list has ────────────────────────────────────────────────
    readonly property real listWidth: root.width
    readonly property real listHeight: root.height

    /**
     * The widget's 16 px over its 208 px of content width, kept from growing past a list
     * type, and held under what a day heading plus one of its cards costs in height. That
     * pair is 5.92 times the title size with the widget's own gaps, so a box only ever
     * gets a heading with nothing under it if the factor sits closer to 1/5.92 than to the
     * rounding of those five terms — this keeps a margin under it.
     */
    readonly property real titleSize: Math.max(9, Math.min(18,
        Math.round(Math.min(root.listWidth * 0.077, root.listHeight * 0.158))))
    readonly property real timeSize: Math.max(8, Math.round(root.titleSize * 0.8))
    readonly property real daySize: Math.max(9, Math.round(root.titleSize * 1.125))
    readonly property real cardPadH: Math.round(root.titleSize * 0.875)
    readonly property real cardPadV: Math.round(root.titleSize * 0.625)
    readonly property real lineGap: Math.round(root.titleSize * 0.125)
    readonly property real dayGap: Math.round(root.titleSize * 0.75)
    readonly property real withinDayGap: Math.round(root.titleSize * 0.375)

    /** The widget's row heights, from the sizes above. */
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
                "kind": "day", "label": String(day?.label ?? ""), "isToday": day?.isToday === true,
                "title": "", "time": "",
                "height": root.dayRowHeight, "gapBefore": dayIndex === 0 ? 0 : root.dayGap
            });
            const events = Array.from(day?.events ?? []);
            if (events.length === 0) {
                built.push({
                    "kind": "empty", "label": "", "isToday": false, "title": "", "time": "",
                    "height": root.emptyRowHeight, "gapBefore": root.withinDayGap
                });
                continue;
            }
            for (let eventIndex = 0; eventIndex < events.length; eventIndex++) {
                built.push({
                    "kind": "event", "label": "", "isToday": false,
                    "height": root.eventRowHeight,
                    "gapBefore": eventIndex === 0 ? root.withinDayGap : root.lineGap,
                    "title": root.eventTitle(events[eventIndex]),
                    "time": root.eventTime(events[eventIndex])
                });
            }
        }
        return built;
    }

    /** Rows grow into a tall box, but no further than twice the widget's own size. */
    readonly property real naturalHeight: {
        let total = 0;
        for (let index = 0; index < root.rows.length; index++)
            total += root.rows[index].gapBefore + root.rows[index].height;
        return total;
    }
    readonly property real rowScale: root.naturalHeight > 0
        ? Math.min(2, Math.max(1, root.listHeight / root.naturalHeight)) : 1

    /** The rows that fit, each with its own place; the block centred on what is left. */
    readonly property var shownRows: {
        const scale = root.rowScale;
        const shown = [];
        let used = 0;
        for (let index = 0; index < root.rows.length; index++) {
            const row = root.rows[index];
            // Rounded down: growing into a tall box may never round the block past the
            // height it is growing into and drop the row that had just fit.
            const gap = Math.floor(row.gapBefore * scale);
            const height = Math.min(root.listHeight, Math.floor(row.height * scale));
            if (used + gap + height > root.listHeight)
                break;
            shown.push({
                "kind": row.kind, "label": row.label, "isToday": row.isToday,
                "title": row.title, "time": row.time,
                "y": used + gap, "height": height
            });
            used += gap + height;
        }
        const offset = Math.max(0, Math.round((root.listHeight - used) / 2));
        for (let index = 0; index < shown.length; index++)
            shown[index].y += offset;
        return shown;
    }

    /** The (+) is the widget's, and it only fits where the heading does. */
    readonly property bool showCreateButton: root.withCreateButton && root.listWidth >= 120
        && Math.floor(root.dayRowHeight * root.rowScale) >= 22

    /**
     * The model is how many rows fit, not the rows themselves. A model of objects is a new
     * array on every re-evaluation — and the sizes above are re-evaluated on every frame of
     * a resize, so the Repeater would tear down and rebuild every row, with its button and
     * its cards, for as long as the handle moves. With a count, a resize only re-binds each
     * delegate's place; delegates are built and dropped when the count changes.
     */
    Repeater {
        model: root.show ? root.shownRows.length : 0

        delegate: Item {
            id: rowItem

            required property int index

            /** Guarded: a binding can land here after the row stopped being drawn. */
            readonly property var row: root.shownRows[rowItem.index] ?? ({
                "kind": "", "label": "", "isToday": false, "title": "", "time": "",
                "y": 0, "height": 0
            })

            x: 0
            y: rowItem.row.y
            width: root.listWidth
            height: rowItem.row.height

            // ── The day's heading, with today's (+) at its right ─────────────
            RowLayout {
                anchors.fill: parent
                visible: rowItem.row.kind === "day"
                spacing: root.withinDayGap

                StyledText {
                    Layout.fillWidth: true
                    text: rowItem.row.label
                    color: root.headingColor
                    font.weight: Font.Bold
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 8
                    font.pixelSize: root.daySize
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                }

                /**
                 * Behind a Loader, so the one row that carries the widget's (+) is the
                 * only one that builds a button at all — a control with its ripple and
                 * its pointer handling is the heaviest thing a row can hold.
                 */
                Loader {
                    readonly property real pillHeight: Math.round(rowItem.row.height * 0.9)

                    active: rowItem.row.isToday && root.showCreateButton
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: pillHeight
                    Layout.preferredWidth: active ? Math.round(pillHeight * 1.43) : 0

                    sourceComponent: Component {
                        RippleButton {
                            id: createPill

                            enabled: !root.editMode
                            buttonRadius: Math.round(createPill.height / 2)
                            colBackground: root.cardColor
                            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                            colRipple: Appearance.colors.colSurfaceContainerHighestActive

                            onClicked: GlobalStates.openCheatsheet("timetable")

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "add"
                                iconSize: Math.round(createPill.height * 0.62)
                                color: root.headingColor
                            }
                        }
                    }
                }
            }

            // ── One event, as the widget's card ──────────────────────────────
            Rectangle {
                anchors.fill: parent
                visible: rowItem.row.kind === "event"
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
                        text: rowItem.row.title
                        color: root.cardTitleColor
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 7
                        font.pixelSize: root.titleSize
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: rowItem.row.time
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

            // ── A day without events, as the widget's placeholder ────────────
            Rectangle {
                anchors.fill: parent
                visible: rowItem.row.kind === "empty"
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
