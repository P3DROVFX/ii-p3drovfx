import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/**
 * One line of settings: what it is, what it does, and the control that changes it.
 *
 * A component rather than a shape copied per row. The first version of the settings sheet
 * was five hundred lines of hand-built rectangles, and the cost of that was not the
 * length — it was that no two rows agreed on their padding, their icon size or their
 * colours, and a row with no control looked exactly like a row with one.
 */
Item {
    id: root

    property string symbol: ""
    property string title: ""
    property string description: ""
    /// The control goes here; a row with none is a statement, and reads as one.
    default property alias control: controlHolder.data

    readonly property bool hasControl: controlHolder.children.length > 0

    implicitHeight: Math.max(NotesMetrics.rowHeight, layout.implicitHeight + 20)

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.leftMargin: NotesMetrics.cardPadding
        anchors.rightMargin: NotesMetrics.cardPadding
        spacing: 14

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.symbol
            iconSize: 22
            color: Appearance.colors.colOnLayer1
            visible: root.symbol.length > 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                text: root.description
                visible: root.description.length > 0
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        Item {
            id: controlHolder
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
