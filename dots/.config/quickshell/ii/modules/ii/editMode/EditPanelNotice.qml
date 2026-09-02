import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The panel's way of saying why a control is not answering: Settings' NoticeBox
 * cut down to a 380px column - one line of icon, one paragraph, no card inside
 * a card.
 */
Rectangle {
    id: root

    property string text: ""
    property string symbol: "lock"

    Layout.fillWidth: true
    implicitHeight: noticeRow.implicitHeight + 20
    radius: Appearance.rounding.small
    color: Appearance.colors.colSecondaryContainer

    RowLayout {
        id: noticeRow
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: root.symbol
            iconSize: 18
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            Layout.fillWidth: true
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSecondaryContainer
            wrapMode: Text.Wrap
        }
    }
}
