import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/** Explanatory line under a control in a condition or action form. */
StyledText {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    font.pixelSize: ClockStyle.textSmall
    color: ClockStyle.colSubtext
}
