pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Calendar, as the background's "Calendar Month Grid 2x1" desktop widget: the month, the
 * weekday and the day of the month down the left, and the month's own grid on the right,
 * today marked with a filled circle.
 *
 * The widget is a 492 x 240 design — a shade over two to one — and it is ported at that
 * proportion rather than re-laid-out: the left block keeps its share of the width, the
 * grid keeps the rest, and every size in them (the three lines, the header, the cells) is
 * the widget's own number as a fraction of the surface. A 5x4 tile is the design at
 * almost exactly its original pixel size; the wider and shorter footprints the grid
 * allows are the same design with less room, never a different one. Nothing is written
 * against a stored footprint, so the two sections follow the resize handle together.
 *
 * The month grid is the part that cannot be dropped into any shape: it needs the height
 * of six rows plus its header, which is why this design's sizes are the horizontal ones
 * from two rows up (see the catalog entry) and why the row count follows the month.
 *
 * One thing is taken from the running locale rather than from the widget: the weekday
 * header letters. The widget translates `M T W T F S S`, which is English in every
 * language, so each column takes the first letter of this locale's abbreviated name
 * instead — while the week keeps starting on Monday, as the widget draws it.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Calendar")

    // ── The month ────────────────────────────────────────────────────────────
    readonly property date today: DateTime.clock.date
    readonly property int currentDay: root.today.getDate()
    readonly property int currentMonth: root.today.getMonth()
    readonly property int currentYear: root.today.getFullYear()

    /** Monday is column 0, as the widget's grid is drawn. */
    readonly property int firstDayOfWeek: (new Date(root.currentYear, root.currentMonth, 1).getDay() + 6) % 7
    readonly property int daysInMonth: new Date(root.currentYear, root.currentMonth + 1, 0).getDate()
    readonly property int gridRows: Math.max(1, Math.ceil((root.firstDayOfWeek + root.daysInMonth) / 7))
    readonly property int gridCells: root.gridRows * 7

    readonly property string monthText: root.withoutTrailingDot(DateTime.monthNameLong)
    readonly property string weekdayText: root.withoutTrailingDot(DateTime.dayNameLong)
    readonly property string dayText: DateTime.dayOfMonthPadded

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

    function withoutTrailingDot(value: string): string {
        return String(value).replace(/\.$/, "");
    }

    // ── Colours: the widget's own text colour, with the accent on today only ──
    readonly property color labelColor: Appearance.colors.colOnLayer2
    readonly property color todayCircleColor: Appearance.colors.colPrimary
    readonly property color todayTextColor: Appearance.colors.colOnPrimary

    // ── The widget's numbers, as fractions of the surface ─────────────────────
    // The design is 492 x 240 with 20 px around it; each term below is that number
    // over 240 (or over the 452 px of content width for the two sections).
    readonly property real pad: Math.max(6, Math.min(20,
        Math.round(Math.min(root.surface.width, root.surface.height) * 0.083)))
    readonly property real contentWidth: Math.max(0, root.surface.width - root.pad * 2)
    readonly property real contentHeight: Math.max(0, root.surface.height - root.pad * 2)

    readonly property real leftWidth: Math.round(root.contentWidth * 0.376)
    readonly property real sectionGap: Math.round(root.contentWidth * 0.035)
    readonly property real gridWidth: Math.max(0, root.contentWidth - root.leftWidth - root.sectionGap)

    readonly property real cellWidth: root.gridWidth / 7
    readonly property real headerHeight: Math.round(root.contentHeight * 0.12)
    readonly property real cellHeight: Math.max(0, (root.contentHeight - root.headerHeight) / root.gridRows)

    readonly property real monthCeiling: Math.max(9, Math.round(root.contentHeight * 0.09))
    readonly property real weekdayCeiling: Math.max(11, Math.round(root.contentHeight * 0.11))
    readonly property real dayCeiling: Math.max(24, Math.round(root.contentHeight * 0.42))
    /**
     * The grid's type is the widget's 13 px over 240, capped by what a cell can hold: a
     * month of six rows is the tallest thing here, and at the smallest footprint the
     * cells are the limit, not the design.
     */
    readonly property real gridCeiling: Math.min(Math.max(9, Math.round(root.contentHeight * 0.065)),
        Math.max(6, Math.round(Math.min(root.cellHeight, root.headerHeight) * 0.85)))

    // ── The widget's own margin, and the two sections inside it ─────────────
    Item {
        id: content

        anchors.fill: parent
        anchors.margins: root.pad

        // ── Left: the date ───────────────────────────────────────────────────
        ColumnLayout {
            x: 0
            y: 0
            width: root.leftWidth
            height: root.contentHeight
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(root.monthCeiling * 1.35)
                text: root.monthText
                color: root.labelColor
                font.weight: Font.Medium
                fontSizeMode: Text.Fit
                minimumPixelSize: 8
                font.pixelSize: root.monthCeiling
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(root.weekdayCeiling * 1.35)
                text: root.weekdayText
                color: root.labelColor
                font.weight: Font.Bold
                fontSizeMode: Text.Fit
                minimumPixelSize: 8
                font.pixelSize: root.weekdayCeiling
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }

            StyledText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.dayText
                color: root.labelColor
                font.weight: Font.Black
                font.variableAxes: ({ "wght": 900 })
                fontSizeMode: Text.Fit
                minimumPixelSize: 14
                font.pixelSize: root.dayCeiling
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }
        }

        // ── Right: the month's grid ──────────────────────────────────────────
        Item {
            x: root.leftWidth + root.sectionGap
            y: 0
            width: root.gridWidth
            height: root.contentHeight

            Repeater {
                model: root.weekdayLetters

                delegate: Item {
                    required property int index
                    required property string modelData

                    x: index * root.cellWidth
                    y: 0
                    width: root.cellWidth
                    height: root.headerHeight

                    StyledText {
                        anchors.fill: parent
                        text: modelData
                        color: root.labelColor
                        font.weight: Font.Bold
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 7
                        font.pixelSize: root.gridCeiling
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Repeater {
                model: root.gridCells

                delegate: Item {
                    required property int index

                    readonly property int column: index % 7
                    readonly property int row: Math.floor(index / 7)
                    readonly property int dayNumber: index - root.firstDayOfWeek + 1
                    readonly property bool inMonth: dayNumber >= 1 && dayNumber <= root.daysInMonth
                    readonly property bool isToday: inMonth && dayNumber === root.currentDay

                    visible: inMonth
                    x: column * root.cellWidth
                    y: root.headerHeight + row * root.cellHeight
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
                        color: isToday ? root.todayTextColor : root.labelColor
                        font.weight: isToday ? Font.Bold : Font.Medium
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 7
                        font.pixelSize: root.gridCeiling
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
