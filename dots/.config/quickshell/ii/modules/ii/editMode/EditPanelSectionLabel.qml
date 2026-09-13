import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The heading over a run of rows on Edit Mode's panel.
 */
StyledText {
    Layout.fillWidth: true
    Layout.leftMargin: 6
    Layout.topMargin: 10
    Layout.bottomMargin: 2
    font.pixelSize: Appearance.font.pixelSize.smaller
    font.weight: Font.DemiBold
    color: Appearance.colors.colOnSurfaceVariant
}
