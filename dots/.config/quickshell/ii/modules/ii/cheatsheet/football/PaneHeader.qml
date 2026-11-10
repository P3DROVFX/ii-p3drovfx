import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Title and subtitle of a list pane, with room for actions on the right.
RowLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    default property alias actions: actionRow.data

    Layout.fillWidth: true
    spacing: FootballStyle.gapSmall

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            text: root.title
            font.pixelSize: FootballStyle.textHuge + 8
            font.variableAxes: FootballStyle.axesPaneTitle
            color: FootballStyle.colOnPane
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.subtitle !== ""
            text: root.subtitle
            elide: Text.ElideRight
            font.pixelSize: FootballStyle.textSmall
            color: FootballStyle.colSubtext
        }
    }
    Row {
        id: actionRow
        spacing: FootballStyle.gapTiny
    }
}
