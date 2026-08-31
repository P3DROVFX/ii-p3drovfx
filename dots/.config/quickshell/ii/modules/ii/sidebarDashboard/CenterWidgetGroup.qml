import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarDashboard.notifications
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true

    property bool collapsed: false
    property int entranceTrigger: -1
    readonly property real contentMargin: 5
    property real verticalContentMargin: collapsed ? 0 : contentMargin
    readonly property real collapsedHeight: notificationList.collapsedHeight
    readonly property real minimumExpandedHeight: notificationList.minimumExpandedHeight + contentMargin * 2
    implicitHeight: collapsed ? collapsedHeight : 250

    Behavior on verticalContentMargin {
        SidebarGroupAnimation {
            animationSpec: Appearance.animation.elementMove
        }
    }

    NotificationList {
        id: notificationList
        anchors.fill: parent
        anchors.leftMargin: root.contentMargin
        anchors.rightMargin: root.contentMargin
        anchors.topMargin: root.verticalContentMargin
        anchors.bottomMargin: root.verticalContentMargin
        collapsed: root.collapsed
        entranceTrigger: root.entranceTrigger
    }
}
