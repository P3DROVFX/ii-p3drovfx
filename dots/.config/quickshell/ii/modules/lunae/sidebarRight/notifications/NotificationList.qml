import qs.modules.common
import qs.modules.common.widgets
import qs.modules.lunae.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property bool showStatusRow: true
    property real placeholderIconSize: 56
    readonly property real listContentHeight: listview.contentHeight
    readonly property bool expanding: listview.expanding

    LunaeNotificationSidebarListView {
        id: listview
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: root.showStatusRow ? statusRow.top : parent.bottom
        anchors.bottomMargin: root.showStatusRow ? 5 : 0

        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: listview.width
                height: listview.height
                radius: Appearance.rounding.normal
            }
        }

        popup: false
    }

    PagePlaceholder {
        shown: Notifications.list.length === 0
        icon: "notifications_active"
        placeholderIconSize: root.placeholderIconSize
        description: Translation.tr("Nothing")
        shape: MaterialShape.Shape.Ghostish
        descriptionHorizontalAlignment: Text.AlignHCenter
    }

    RowLayout {
        id: statusRow
        visible: root.showStatusRow
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        spacing: 4

        NotificationStatusButton {
            Layout.fillWidth: false
            buttonIcon: "notifications_paused"
            toggled: Notifications.silent
            onClicked: () => {
                Notifications.silent = !Notifications.silent;
            }
        }
        NotificationStatusButton {
            enabled: false
            Layout.fillWidth: true
            buttonText: Translation.tr("%1 notifications").arg(Notifications.list.length)
        }
        NotificationStatusButton {
            Layout.fillWidth: false
            buttonIcon: "delete_sweep"
            onClicked: () => {
                Notifications.discardAllNotifications()
            }
        }
    }
}