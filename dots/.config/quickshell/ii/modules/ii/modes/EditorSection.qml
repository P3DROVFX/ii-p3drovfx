import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * A titled block of an editor page, drawn like the clock's settings sections: a primary
 * icon and title, a one-line subtitle under it, an optional control on the right of the
 * header, and the rows below as one tight stack.
 */
ColumnLayout {
    id: section

    property string title
    property string icon
    property string subtitle: ""
    property alias headerItem: headerSlot.sourceComponent
    default property alias rows: body.data

    Layout.fillWidth: true
    spacing: ClockStyle.gapSmall

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: ClockStyle.gapSmall
        Layout.rightMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapSmall

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
            text: section.icon
            iconSize: ClockStyle.iconSmall + 2
            color: ClockStyle.colPrimary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: section.title
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal + 1
                font.weight: Font.DemiBold
                color: ClockStyle.colPrimary
            }

            StyledText {
                visible: section.subtitle.length > 0
                Layout.fillWidth: true
                text: section.subtitle
                wrapMode: Text.WordWrap
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }

        Loader {
            id: headerSlot
            Layout.alignment: Qt.AlignVCenter
        }
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: 3
    }
}
