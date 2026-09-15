pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.lunae
import qs.services
import Quickshell

StyledListView {
    id: root
    property bool popup: false
    property bool elevated: popup

    spacing: 3

    property bool expanding: false
    Timer {
        id: expandResetTimer
        interval: LunaeAppearance.notifExpansionDuration
        onTriggered: root.expanding = false
    }

    model: ScriptModel {
        values: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    delegate: LunaeNotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        elevated: root.elevated
        width: ListView.view.width
        notificationGroup: popup ?
            Notifications.popupGroupsByAppName[modelData] :
            Notifications.groupsByAppName[modelData]

        onExpandedChanged: {
            root.expanding = true
            expandResetTimer.restart()
        }
    }
}
