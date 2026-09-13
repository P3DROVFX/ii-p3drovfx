import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/**
 * A group of settings rows, as one slab.
 *
 * The app separates sections with air and a corner radius, never a rule, so a section is
 * a surface and the gap around it is the separation. Rows inside it touch.
 */
Item {
    id: root

    property string title: ""
    default property alias rows: column.data

    implicitHeight: heading.implicitHeight + 6 + slab.implicitHeight

    StyledText {
        id: heading
        anchors.left: parent.left
        anchors.leftMargin: NotesMetrics.cardPadding
        text: root.title
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }

    Rectangle {
        id: slab
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.bottom
        anchors.topMargin: 6
        implicitHeight: column.implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 0
        }
    }
}
