import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/**
 * A titled slab holding one drawing — a chart, a heatmap.
 *
 * The sibling of `NotesSettingsSection`, which holds rows. Same heading, same surface,
 * same air around it; the difference is that a chart has to be *given* a height, because
 * nothing inside it has an opinion about how tall it should be.
 */
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    /// How tall the drawing itself is, inside the padding.
    property real contentHeight: 180
    default property alias content: holder.data

    implicitHeight: heading.implicitHeight + 6 + slab.implicitHeight

    ColumnLayout {
        id: heading
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: NotesMetrics.cardPadding
        anchors.rightMargin: NotesMetrics.cardPadding
        spacing: 1

        StyledText {
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            text: root.subtitle
            visible: root.subtitle.length > 0
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            opacity: 0.75
            wrapMode: Text.WordWrap
        }
    }

    Rectangle {
        id: slab
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.bottom
        anchors.topMargin: 6
        implicitHeight: root.contentHeight + NotesMetrics.cardPadding * 2
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh

        Item {
            id: holder
            anchors.fill: parent
            anchors.margins: NotesMetrics.cardPadding
        }
    }
}
