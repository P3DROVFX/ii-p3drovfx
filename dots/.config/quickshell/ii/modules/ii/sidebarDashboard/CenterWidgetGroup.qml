import qs
import qs.modules.common
import qs.modules.common.animations
import qs.modules.common.widgets
import qs.services
import qs.modules.common.notifications
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
    // The collapsed pill keeps the same inset on every edge; the collapsed
    // height therefore carries the vertical margins too, otherwise the status
    // row would be clipped by the card's clip.
    readonly property real collapsedHeight: notificationList.collapsedHeight + contentMargin * 2
    readonly property real minimumExpandedHeight: notificationList.minimumExpandedHeight + contentMargin * 2
    implicitHeight: collapsed ? collapsedHeight : 250

    NotificationList {
        id: notificationList
        anchors.fill: parent
        anchors.margins: root.contentMargin
        collapsed: root.collapsed
        entranceTrigger: root.entranceTrigger
    }
}
