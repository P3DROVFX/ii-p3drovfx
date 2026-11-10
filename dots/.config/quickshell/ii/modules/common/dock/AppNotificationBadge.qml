import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Unread notifications from an app, on the icon's top-right corner. Shared by
// the dock and the desktop icons.
Rectangle {
    id: badge

    property int count: 0

    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: -4
    anchors.topMargin: -4
    height: 18
    width: Math.max(height, badgeText.implicitWidth + 10)
    radius: height / 2
    color: Appearance.colors.colTertiary
    scale: badge.count > 0 ? 1 : 0
    visible: scale > 0.01
    Behavior on scale {
        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
    }
    StyledText {
        id: badgeText
        anchors.centerIn: parent
        text: badge.count > 99 ? "99+" : String(badge.count)
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnTertiary
    }
}
