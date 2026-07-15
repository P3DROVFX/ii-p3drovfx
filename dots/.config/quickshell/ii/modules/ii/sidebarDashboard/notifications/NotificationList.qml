import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property int entranceTrigger: -1

    NotificationListView { // Scrollable window
        id: listview
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: statusRow.top
        anchors.bottomMargin: 5

        clip: true
        // layer.enabled and OpacityMask removed to optimize performance and prevent lag on dashboard open
        // layer.enabled: true
        // layer.effect: OpacityMask {
        //     maskSource: Rectangle {
        //         width: Math.floor(listview.width)
        //         height: Math.floor(listview.height)
        //         radius: Appearance.rounding.windowRounding
        //     }
        // }

        popup: false
        entranceTrigger: root.entranceTrigger
    }

    // Placeholder when list is empty
    PagePlaceholder {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: statusRow.top
        shown: Notifications.list.length === 0
        icon: "notifications_active"
        description: Translation.tr("Nothing")
        shape: MaterialShape.Shape.Ghostish
        descriptionHorizontalAlignment: Text.AlignHCenter
    }

    ButtonGroup {
        id: statusRow
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        property int entranceTrigger: root.entranceTrigger
        property real _entranceOpacity: 0
        property real _entranceTranslateY: 20
        property bool _entranceDone: false

        onEntranceTriggerChanged: {
            _entranceDone = false;
            _entranceOpacity = 0;
            _entranceTranslateY = 20;
            Qt.callLater(function() {
                entranceAnim.start();
            });
        }

        Component.onCompleted: {
            _entranceDone = false;
            _entranceOpacity = 0;
            _entranceTranslateY = 20;
            Qt.callLater(function() {
                entranceAnim.start();
            });
        }

        SequentialAnimation {
            id: entranceAnim
            PauseAnimation { duration: 200 }
            ParallelAnimation {
                NumberAnimation { target: statusRow; property: "_entranceOpacity"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
                NumberAnimation { target: statusRow; property: "_entranceTranslateY"; from: 20; to: 0; duration: 320; easing.type: Easing.OutCubic }
            }
            PropertyAction { target: statusRow; property: "_entranceDone"; value: true }
        }

        opacity: statusRow._entranceDone ? 1.0 : statusRow._entranceOpacity
        transform: Translate {
            y: statusRow._entranceDone ? 0 : statusRow._entranceTranslateY
        }

        GroupButtonWithIcon {
            id: snoozeButton
            Layout.fillWidth: false
            buttonIcon: "notifications_paused"
            toggled: Notifications.silent
            onClicked: () => {
                Notifications.silent = !Notifications.silent;
            }

            SequentialAnimation {
                id: snoozeEntranceAnim
                NumberAnimation { target: snoozeButton; property: "rotation"; from: -360; to: 0; duration: 450; easing.type: Easing.OutCubic }
            }
            Connections {
                target: statusRow
                function onEntranceTriggerChanged() {
                    if (statusRow.entranceTrigger >= 0) {
                        rotation = -360;
                        snoozeEntranceAnim.start();
                    }
                }
            }
        }
        GroupButtonWithIcon {
            enabled: false
            Layout.fillWidth: true
            buttonText: Translation.tr("%1 notifications").arg(Notifications.list.length)
        }
        GroupButtonWithIcon {
            id: deleteAllButton
            Layout.fillWidth: false
            buttonIcon: "delete_sweep"
            onClicked: () => {
                Notifications.discardAllNotifications()
            }

            SequentialAnimation {
                id: deleteEntranceAnim
                NumberAnimation { target: deleteAllButton; property: "rotation"; from: 360; to: 0; duration: 450; easing.type: Easing.OutCubic }
            }
            Connections {
                target: statusRow
                function onEntranceTriggerChanged() {
                    if (statusRow.entranceTrigger >= 0) {
                        rotation = 360;
                        deleteEntranceAnim.start();
                    }
                }
            }
        }
    }
}