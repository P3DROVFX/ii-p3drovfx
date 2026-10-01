import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * A plain settings row in the clock's row style: icon, label, hint, and whatever control
 * is put inside it on the right. On a page it sits on the pane colour; inside a side
 * sheet (`onSheet`) it takes the sheet's field colour so it still reads as a row.
 */
Rectangle {
    id: row

    property string icon
    property string label
    property string hint: ""
    property bool onSheet: false
    default property alias control: controlSlot.data

    Layout.fillWidth: true
    implicitHeight: Math.max(ClockStyle.rowHeight + 4, rowLayout.implicitHeight + ClockStyle.gap * 2)
    radius: ClockStyle.radiusSmall
    color: row.onSheet ? ClockStyle.colField : ClockStyle.colPane

    RowLayout {
        id: rowLayout
        anchors {
            fill: parent
            leftMargin: ClockStyle.gapLarge
            rightMargin: ClockStyle.gap
        }
        spacing: ClockStyle.gap + 2

        MaterialSymbol {
            text: row.icon
            iconSize: ClockStyle.iconNormal - 2
            color: ClockStyle.colOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                // Fills its cell so a row without a hint keeps the label on the left
                // instead of centring it.
                Layout.fillWidth: true
                text: row.label
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal + 1
                color: ClockStyle.colOnSurface
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
