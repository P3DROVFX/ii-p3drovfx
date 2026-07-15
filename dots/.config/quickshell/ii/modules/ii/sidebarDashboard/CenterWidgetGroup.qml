import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarDashboard.notifications
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    implicitHeight: 250

    property int entranceTrigger: -1

    function triggerContentEntrance() {
        entranceTrigger++;
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                root.triggerContentEntrance();
            }
        }
    }

    NotificationList {
        anchors.fill: parent
        anchors.margins: 5
        entranceTrigger: root.entranceTrigger
    }
}
