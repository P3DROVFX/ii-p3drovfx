import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import "."

Rectangle {
    id: currentTimeLine
    
    property real currentTimeY
    property real contentRowWidth
    property int timeColumnWidth

    width: contentRowWidth + 20
    height: 3
    color: Appearance.colors.colPrimary
    y: currentTimeY
    z: 10
    radius: Appearance.rounding.unsharpen

    // Material 3 time chip
    Rectangle {
        x: (timeColumnWidth / 2) - (width / 2)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(timeText.implicitWidth + 20, timeColumnWidth - 4)
        height: 32
        radius: Appearance.rounding.normal
        color: Appearance.colors.colPrimary

        StyledText {
            id: timeText
            anchors.centerIn: parent
            text: DateTime.time
            color: Appearance.colors.colOnPrimary
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }
}
