import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/** A titled group of settings rows; the rows share one surface split by 2 px gaps. */
ColumnLayout {
    id: root

    property string title: ""
    property string symbol: ""
    property string description: ""
    default property alias rows: rowColumn.data

    Layout.fillWidth: true
    spacing: 8

    RowLayout {
        Layout.leftMargin: 8
        spacing: 8

        MaterialSymbol {
            visible: root.symbol.length > 0
            text: root.symbol
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colPrimary
        }

        StyledText {
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colPrimary
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        visible: root.description.length > 0
        text: root.description
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    ColumnLayout {
        id: rowColumn
        Layout.fillWidth: true
        spacing: 2
    }
}
