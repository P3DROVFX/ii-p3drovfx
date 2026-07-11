pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false
    // Only the floating popup is user-resizable; the sidebar notification
    // center and phone mirror always render at their normal size.
    readonly property real zoom: popup ? (Config.options.notifications.zoomPercent / 100) : 1.0
    dismissToLeft: popup && (Config.options.notifications.position ?? "top_right").endsWith("left")
    useSlideInAnimation: popup

    spacing: 3

    model: ScriptModel {
        values: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        zoom: root.zoom
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        notificationGroup: popup ?
            Notifications.popupGroupsByAppName[modelData] :
            Notifications.groupsByAppName[modelData]
    }
}
