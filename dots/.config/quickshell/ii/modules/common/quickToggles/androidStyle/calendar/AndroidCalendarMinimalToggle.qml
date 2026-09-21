pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Calendar, as the background's "Calendar Minimal 1x1" desktop widget: the weekday, the
 * day of the month as the hero and the month, in the widget's two tones — the labels in
 * the tile's text colour and the number in the accent.
 *
 * The widget is drawn for a square cell and this grid is not one (96 x 56 px per cell),
 * so nothing is scaled from the widget's numbers: the design is laid out again from the
 * surface the tile is given, in two stages. Which stage a tile gets is decided by the
 * room it actually has, never by the size it was stored at — the stack needs the height
 * of three lines, and a tile much wider than it is tall would strand those three lines in
 * the middle with empty sides. That is also what makes the taller footprints repeat: a
 * 4x4 is the same proportion as a 2x2, so it is the same stage with a bigger number.
 *
 * | Tile                                  | Stage                                                     |
 * |---------------------------------------|-----------------------------------------------------------|
 * | 1x1                                   | row: weekday and day, the month dropped for want of width  |
 * | 2x1, 3x1 and wider rows               | row: weekday left, day centre, month right                 |
 * | 4x2, 5x2, 6x2, 6x3 and wider          | row, the same one                                          |
 * | 1x2 … 1x8, 2x2 … 2x8, 3x2, 4x4, 6x4…  | stack: weekday over day over month, exactly the widget     |
 *
 * Every size inside a stage comes from the surface too, and every text is drawn with
 * `fontSizeMode: Text.Fit`, so a long weekday name in a narrow tile shrinks instead of
 * running past its margin. Nothing here is conditional on the stored size, so resizing
 * the tile re-lays it out as the handle moves.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Calendar")

    // ── The date ─────────────────────────────────────────────────────────────
    readonly property string dayText: DateTime.dayOfMonth

    /** Short names only where the long ones could not be drawn at a legible size. */
    readonly property bool fullNames: root.stacked
        ? root.contentWidth >= 150
        : root.rowLabelBox >= 96
    readonly property string weekdayText: root.withoutTrailingDot(root.fullNames
        ? DateTime.dayNameLong : DateTime.dayNameShort)
    readonly property string monthText: root.withoutTrailingDot(root.fullNames
        ? DateTime.monthNameLong : DateTime.monthNameShort)

    /** Qt's abbreviated names carry the locale's full stop ("qua."); the widget drops it. */
    function withoutTrailingDot(value: string): string {
        return String(value).replace(/\.$/, "");
    }

    // ── The widget's two tones, on this surface ──────────────────────────────
    readonly property color labelColor: Appearance.colors.colOnLayer2
    readonly property color heroColor: Appearance.colors.colPrimary

    // ── The room the tile has ────────────────────────────────────────────────
    readonly property real pad: Math.max(6, Math.min(14,
        Math.round(Math.min(root.surface.width, root.surface.height) * 0.10)))
    readonly property real contentWidth: Math.max(0, root.surface.width - root.pad * 2)
    readonly property real contentHeight: Math.max(0, root.surface.height - root.pad * 2)

    /**
     * The stack, and row with it, are the widget's own column: the room for three lines
     * decides the first, and twice the width again decides that the three lines are no
     * longer a column but a row.
     */
    readonly property bool stacked: root.surface.height >= 84
        && root.surface.width < root.surface.height * 2.6

    readonly property real heroCeiling: Math.max(12, Math.round(root.contentHeight * 0.9))

    // ── Stack (2x2, 1x2, 2x4, 4x4, …) ────────────────────────────────────────
    readonly property real stackLabelCeiling: Math.max(10, Math.min(26,
        Math.round(root.contentHeight * 0.18)))
    readonly property real stackLabelBox: Math.round(root.stackLabelCeiling * 1.4)
    readonly property real stackGap: Math.max(0, Math.round(root.contentHeight * 0.03))

    // ── Row (1x1, 4x1, 4x2, …) ───────────────────────────────────────────────
    readonly property real rowGap: Math.max(2, Math.round(root.contentHeight * 0.08))
    readonly property real rowLabelBox: Math.max(26, Math.min(160,
        Math.round(root.contentWidth * 0.26)))
    readonly property real rowLabelCeiling: Math.max(9, Math.min(26,
        Math.round(root.contentHeight * 0.34)))
    /**
     * The month is the third element of a row, and the last to earn its place: when the
     * weekday's column and a usable day number already take the width there is none left
     * for it, so the 1x1 draws the widget's two leading elements only.
     */
    readonly property bool rowFitsMonth: root.contentWidth
        - 2 * root.rowLabelBox - 3 * root.rowGap >= Math.max(22, Math.round(root.contentHeight * 0.8))

    component DateLabel: StyledText {
        color: root.labelColor
        font.weight: Font.Medium
        fontSizeMode: Text.Fit
        minimumPixelSize: 8
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component HeroDay: StyledText {
        text: root.dayText
        color: root.heroColor
        font.weight: Font.Black
        font.variableAxes: ({ "wght": 900 })
        fontSizeMode: Text.Fit
        minimumPixelSize: 12
        font.pixelSize: root.heroCeiling
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // ── Stage 1: the widget's column ─────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        visible: root.stacked
        spacing: root.stackGap

        DateLabel {
            Layout.fillWidth: true
            Layout.preferredHeight: root.stackLabelBox
            text: root.weekdayText
            font.pixelSize: root.stackLabelCeiling
        }

        HeroDay {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        DateLabel {
            Layout.fillWidth: true
            Layout.preferredHeight: root.stackLabelBox
            text: root.monthText
            font.pixelSize: root.stackLabelCeiling
        }
    }

    // ── Stage 2: the same three, read across ─────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        visible: !root.stacked
        spacing: root.rowGap

        DateLabel {
            Layout.preferredWidth: root.rowLabelBox
            Layout.fillHeight: true
            text: root.weekdayText
            font.pixelSize: root.rowLabelCeiling
        }

        HeroDay {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        DateLabel {
            visible: root.rowFitsMonth
            Layout.preferredWidth: root.rowLabelBox
            Layout.fillHeight: true
            text: root.monthText
            font.pixelSize: root.rowLabelCeiling
        }
    }
}
