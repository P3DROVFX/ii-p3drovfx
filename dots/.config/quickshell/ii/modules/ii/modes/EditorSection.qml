import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A titled block of an editor page: icon, title, one-line subtitle, an
 * optional control on the right of the header, and the rows under it.
 */
ColumnLayout {
    id: section
    property string title
    property string icon
    property string subtitle: ""
    property alias headerItem: headerSlot.sourceComponent
    default property alias rows: body.data

    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 10

        MaterialSymbol {
            text: section.icon
            iconSize: 20
            color: Appearance.colors.colPrimary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: section.title
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                visible: section.subtitle.length > 0
                Layout.fillWidth: true
                text: section.subtitle
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        Loader {
            id: headerSlot
        }
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: 4
    }
}
