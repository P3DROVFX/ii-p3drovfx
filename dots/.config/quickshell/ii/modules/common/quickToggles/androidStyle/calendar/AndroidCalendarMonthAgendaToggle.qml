pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * The month as a calendar card: its name, the weekdays, and the month's own days in seven
 * columns, today marked with a filled circle — the compact month view as a quick toggle.
 *
 * The card is built to work at 1x1, which is 96 x 56 px in this grid: a month of six weeks
 * in seven columns has 12 px of width per day and, with nothing else on the tile, 7 px of
 * height. So the grid takes the whole tile there and drops its own furniture — the month
 * name and the weekday letters only come back once the days are still legible with them,
 * because at 1x1 they would cost more height than the days themselves.
 *
 * Height is what turns it into an agenda: from a tile three rows tall on, the grid takes
 * three fifths and the space under it draws the calendar's coming events — the same list,
 * from the same `CalendarEventRows`, that the upcoming widget uses, with the days that
 * have nothing in them left out of it. Taller tiles show more of them; a tile that is only
 * two rows tall has no room for a row of events and stays a grid.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Calendar")

    // ── The month ────────────────────────────────────────────────────────────
    readonly property date today: DateTime.clock.date ?? new Date()
    readonly property int currentDay: root.today.getDate()
    readonly property int currentMonth: root.today.getMonth()
    readonly property int currentYear: root.today.getFullYear()
    readonly property string monthLabel: Qt.locale().toString(root.today, "MMMM")

    /** Monday is column 0, as the weekday row is drawn. */
    readonly property int firstDayOfWeek: (new Date(root.currentYear, root.currentMonth, 1).getDay() + 6) % 7
    readonly property int daysInMonth: new Date(root.currentYear, root.currentMonth + 1, 0).getDate()
    readonly property int monthRows: Math.max(1, Math.ceil((root.firstDayOfWeek + root.daysInMonth) / 7))
    readonly property int monthCells: root.monthRows * 7

    /** One letter per column, from this locale's abbreviated names. */
    readonly property var weekdayLetters: {
        const letters = [];
        const monday = new Date(root.currentYear, root.currentMonth, root.currentDay - ((root.today.getDay() + 6) % 7));
        for (let index = 0; index < 7; index++) {
            const day = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + index);
            const name = Qt.locale().toString(day, "ddd").replace(/\./g, "");
            letters.push(name.substring(0, 1).toLocaleUpperCase());
        }
        return letters;
    }

    /** What is coming, day by day — empty days are not agenda material. */
    readonly property var agendaDays: {
        const anchor = root.today;
        const list = [];
        for (let offset = 0; offset < 14; offset++) {
            const date = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate() + offset);
            const events = CalendarService.eventsForDay(date) ?? [];
            if (events.length === 0)
                continue;
            list.push({
                "date": date,
                "isToday": offset === 0,
                "label": Qt.locale().toString(date, "ddd, MMM d"),
                "events": events
            });
        }
        if (list.length === 0)
            list.push({ "date": anchor, "isToday": true, "label": Qt.locale().toString(anchor, "ddd, MMM d"), "events": [] });
        return list;
    }

    // ── Colours ──────────────────────────────────────────────────────────────
    readonly property color dayColor: Appearance.colors.colOnLayer2
    readonly property color weekdayColor: Appearance.colors.colOnSurfaceVariant
    readonly property color todayCircleColor: Appearance.colors.colPrimary
    readonly property color todayTextColor: Appearance.colors.colOnPrimary

    // ── The room the tile has ────────────────────────────────────────────────
    readonly property real pad: Math.max(4, Math.min(12,
        Math.round(Math.min(root.surface.width, root.surface.height) * 0.08)))
    readonly property real contentWidth: Math.max(0, root.surface.width - root.pad * 2)
    readonly property real contentHeight: Math.max(0, root.surface.height - root.pad * 2)

    // ── The grid, on the card's own proportions ──────────────────────────────
    // The reference card is 206 px of content: an 18 px month name, 13 px weekday
    // letters, and days in 24 x 28 px cells.
    readonly property real cellWidth: root.contentWidth / 7
    readonly property real naturalCellHeight: Math.max(6, Math.min(34, Math.round(root.cellWidth * 1.15)))
    readonly property real minimumCellHeight: 7

    /**
     * Both capped by the height as well, at the quarter of it the reference card spends on
     * its furniture. Off the width alone a tile that is wide and short gives its name and
     * its letters half the height — and takes it from the days, which is the one thing the
     * card exists for.
     */
    readonly property real titleSize: Math.max(8, Math.min(18,
        Math.round(Math.min(root.contentWidth * 0.087, root.contentHeight * 0.085))))
    readonly property real headerSize: Math.max(7, Math.min(14,
        Math.round(Math.min(root.contentWidth * 0.063, root.titleSize * 0.72))))
    readonly property real titleGap: Math.round(root.titleSize * 0.5)
    readonly property real titleHeight: Math.round(root.titleSize * 1.35)
    readonly property real headerHeight: Math.round(root.headerSize * 1.5)
    readonly property real chromeHeight: root.titleHeight + root.titleGap + root.headerHeight

    /**
     * Three rows of the grid is where an agenda becomes possible: at two rows tall the
     * tile is 102 px of content, which a month of six weeks already wants for itself.
     */
    readonly property bool withAgenda: root.contentHeight > 120
    /** What the agenda leaves the grid: three fifths of the tile, or all of it. */
    readonly property real gridFloorHeight: root.withAgenda
        ? Math.round(root.contentHeight * 0.6) : root.contentHeight

    /** The name and the weekday letters only while the days stay legible under them. */
    readonly property bool showChrome: (root.gridFloorHeight - root.chromeHeight) / root.monthRows
        >= root.minimumCellHeight
    readonly property real reservedChrome: root.showChrome ? root.chromeHeight : 0

    /**
     * The grid gives way to the agenda only as far as its own share and the agenda's
     * minimum allow: an agenda that can hold a heading and nothing under it is worth less
     * than the days it took the height from, so the grid stops at whichever comes first —
     * its dense floor (the days' own minimum) or the tile less one agenda row pair.
     */
    readonly property real agendaFloorHeight: 56
    readonly property real minimumGridHeight: root.reservedChrome
        + root.monthRows * root.minimumCellHeight
    readonly property real gridTargetHeight: root.withAgenda
        ? Math.round(Math.max(root.minimumGridHeight,
            Math.min(root.gridFloorHeight, root.contentHeight - root.agendaFloorHeight)))
        : root.contentHeight

    readonly property real cellHeight: Math.max(root.minimumCellHeight,
        Math.min(root.naturalCellHeight,
            (root.gridTargetHeight - root.reservedChrome) / root.monthRows))
    readonly property real gridHeight: Math.round(root.reservedChrome + root.monthRows * root.cellHeight)
    readonly property real agendaHeight: Math.max(0, root.contentHeight - root.gridHeight)
    readonly property bool showAgenda: root.withAgenda && root.agendaHeight >= root.agendaFloorHeight
    /** Alone on the tile, the card sits in the middle of it; with an agenda, at the top. */
    readonly property real cardY: root.pad + (root.showAgenda ? 0
        : Math.round(Math.max(0, root.contentHeight - root.gridHeight) / 2))

    /** The type in a cell, from the cell itself — never from the tile. */
    readonly property real daySize: Math.max(5, Math.min(18,
        Math.round(Math.min(root.cellWidth, root.cellHeight) * 0.85)))

    // ── The card ─────────────────────────────────────────────────────────────
    Item {
        x: root.pad
        y: root.cardY
        width: root.contentWidth
        height: root.gridHeight

        StyledText {
            id: monthTitle
            x: 0
            y: 0
            width: parent.width
            // Collapsed, not just hidden: the name and the letters hold no box at all
            // while the days cannot afford them, so nothing in the card can reach past
            // the tile even for a frame.
            height: root.showChrome ? root.titleHeight : 0
            visible: root.showChrome
            text: root.monthLabel
            color: root.dayColor
            font.weight: Font.Bold
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            font.pixelSize: root.titleSize
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        Repeater {
            model: root.weekdayLetters

            delegate: Item {
                required property int index
                required property string modelData

                x: index * root.cellWidth
                y: root.showChrome ? root.titleHeight + root.titleGap : 0
                width: root.cellWidth
                height: root.showChrome ? root.headerHeight : 0
                visible: root.showChrome

                StyledText {
                    anchors.fill: parent
                    text: modelData
                    color: root.weekdayColor
                    font.weight: Font.Bold
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 6
                    font.pixelSize: root.headerSize
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Repeater {
            model: root.monthCells

            delegate: Item {
                required property int index

                readonly property int column: index % 7
                readonly property int row: Math.floor(index / 7)
                readonly property int dayNumber: index - root.firstDayOfWeek + 1
                readonly property bool inMonth: dayNumber >= 1 && dayNumber <= root.daysInMonth
                readonly property bool isToday: inMonth && dayNumber === root.currentDay

                visible: inMonth
                x: column * root.cellWidth
                y: root.reservedChrome + row * root.cellHeight
                width: root.cellWidth
                height: root.cellHeight

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.85
                    height: width
                    radius: width / 2
                    color: root.todayCircleColor
                    visible: isToday
                }

                StyledText {
                    anchors.fill: parent
                    text: dayNumber.toString()
                    color: isToday ? root.todayTextColor : root.dayColor
                    font.weight: isToday ? Font.Bold : Font.Medium
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 5
                    font.pixelSize: root.daySize
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    // ── What is coming, under the month ──────────────────────────────────────
    /**
     * Loaded only while the agenda is shown: an inactive Loader builds no rows, and the
     * days behind it are not even computed, so a tile that is only a month pays for a
     * month.
     */
    Loader {
        x: root.pad
        y: root.cardY + root.gridHeight
        width: root.contentWidth
        height: root.agendaHeight
        active: root.showAgenda

        sourceComponent: Component {
            CalendarEventRows {
                days: root.agendaDays
            }
        }
    }
}
