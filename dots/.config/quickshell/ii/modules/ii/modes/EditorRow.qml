import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A plain settings row: icon, label, hint, and whatever control is put
 * inside it on the right.
 */
Rectangle {
    id: row
    property string icon
    property string label
    property string hint: ""
    default property alias control: controlSlot.data

    Layout.fillWidth: true
    implicitHeight: Math.max(56, rowLayout.implicitHeight + 16)
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    RowLayout {
        id: rowLayout
        anchors {
            fill: parent
            leftMargin: 14
            rightMargin: 14
        }
        spacing: 12

        MaterialSymbol {
            text: row.icon
            iconSize: 22
            color: Appearance.colors.colOnLayer2
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                // Fills its cell so a row without a hint keeps the label on
                // the left instead of centring it.
                Layout.fillWidth: true
                text: row.label
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                visible: row.hint.length > 0
                Layout.fillWidth: true
                text: row.hint
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        RowLayout {
            // A layout inside a layout fills by default, which would share
            // the slack with the label instead of sitting at the right edge.
            id: controlSlot

            Layout.fillWidth: false
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            spacing: 8
        }
    }
}
