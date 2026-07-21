import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

StyledText {
    id: label

    font.pixelSize: Appearance.font.pixelSize.smaller
    font.bold: true
    color: Appearance.m3colors.m3outline

    Layout.fillWidth: true
    // Clip the painted text to the ColumnLayout-allocated height so that when the OSD
    // collapses and the allocated space shrinks, the text does not overflow into the
    // elements below it in the column.
    clip: true
}
