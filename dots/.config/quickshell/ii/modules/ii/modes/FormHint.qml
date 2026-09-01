import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/** Explanatory line under a control in a condition or action form. */
StyledText {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    font.pixelSize: Appearance.font.pixelSize.smaller
    color: Appearance.colors.colSubtext
}
