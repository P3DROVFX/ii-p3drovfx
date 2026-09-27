import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/** A titled group of settings rows, drawn as one list with a small gap between rows. */
ColumnLayout {
    id: root

    property string title: ""
    property string symbol: ""
    default property alias rows: rowColumn.data

    spacing: ClockStyle.gapSmall

    RowLayout {
        Layout.leftMargin: ClockStyle.gapSmall
        spacing: ClockStyle.gapSmall

        MaterialSymbol {
            visible: root.symbol.length > 0
            text: root.symbol
            iconSize: ClockStyle.iconSmall
            color: ClockStyle.colPrimary
        }

        StyledText {
            text: root.title
            font.pixelSize: ClockStyle.textNormal
            font.weight: Font.DemiBold
            color: ClockStyle.colPrimary
        }
    }

    ColumnLayout {
        id: rowColumn
        Layout.fillWidth: true
        spacing: 2
    }
}
