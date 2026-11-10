import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * A plain settings row in the timetable form's style: a shaped icon, label, hint, and
 * whatever control is put inside it on the right. On a page it sits on the pane colour;
 * inside a side sheet (`onSheet`) it takes the sheet's field colour so it still reads as
 * a row.
 *
 * Rows of one section read as one grouped shape, like the clock's settings: the first
 * and last visible rows of the group round their outer corners large, the joins stay
 * tight. A row finds its own place among its visible siblings that are rows too
 * (`groupedRow`), so a row hidden by a condition hands the corner to its neighbour.
 */
Rectangle {
    id: row

    property string icon
    property string label
    property string hint: ""
    property bool onSheet: false
    /// Each row brings its own shape, so a section is not a column of identical dots.
    property int shapeKind: MaterialShape.Shape.Cookie7Sided
    default property alias control: controlSlot.data

    readonly property bool groupedRow: true
    property bool first: row.edgeOf(true)
    property bool last: row.edgeOf(false)

    /// True when this is the first (or last) visible row of its group.
    function edgeOf(fromStart: bool): bool {
        const kids = row.parent?.children ?? [];
        const n = kids.length;
        for (let i = 0; i < n; i++) {
            const kid = kids[fromStart ? i : n - 1 - i];
            if (kid.groupedRow === true && kid.visible)
                return kid === row;
        }
        return true;
    }

    Layout.fillWidth: true
    implicitHeight: Math.max(ClockStyle.rowHeight + 4, rowLayout.implicitHeight + ClockStyle.gap * 2)
    topLeftRadius: row.first ? ClockStyle.radiusLarge : Appearance.rounding.verysmall
    topRightRadius: row.first ? ClockStyle.radiusLarge : Appearance.rounding.verysmall
    bottomLeftRadius: row.last ? ClockStyle.radiusLarge : Appearance.rounding.verysmall
    bottomRightRadius: row.last ? ClockStyle.radiusLarge : Appearance.rounding.verysmall
    color: row.onSheet ? ClockStyle.colField : ClockStyle.colPane

    RowLayout {
        id: rowLayout
        anchors {
            fill: parent
            // The timetable form's (ClockFormToggle's) insets, so shaped icons line up
            // with the toggle rows grouped beside them.
            leftMargin: ClockStyle.gap - 2
            rightMargin: ClockStyle.gap - 2
        }
        spacing: ClockStyle.gap - 2

        MaterialShapeWrappedMaterialSymbol {
            text: row.icon
            iconSize: 18
            padding: 9
            shape: row.shapeKind
            color: ClockStyle.colPrimaryContainer
            colSymbol: ClockStyle.colOnPrimaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            // The form's caption weight, matching the toggle rows of the same group.
            StyledText {
                id: labelText
                // Fills its cell so a row without a hint keeps the label on the left
                // instead of centring it.
                Layout.fillWidth: true
                text: row.label
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.Bold
                color: ClockStyle.colOnSurface

                HoverHandler {
                    id: labelHover
                }
                StyledToolTip {
                    extraVisibleCondition: labelHover.hovered && labelText.truncated
                    text: labelText.text
                }
            }

            StyledText {
                visible: row.hint.length > 0
                Layout.fillWidth: true
                text: row.hint
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }

        RowLayout {
            // A layout inside a layout fills by default, which would share the slack
            // with the label instead of sitting at the right edge.
            id: controlSlot

            Layout.fillWidth: false
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            spacing: ClockStyle.gapSmall
        }
    }
}
