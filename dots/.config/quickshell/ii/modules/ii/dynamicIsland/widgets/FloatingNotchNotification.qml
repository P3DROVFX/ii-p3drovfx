import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects

Item {
    id: root
    anchors.fill: parent
    anchors.topMargin: 2
    anchors.bottomMargin: 2

    property bool isExpanded: false

    readonly property var latestNotif: Notifications.popupList.length > 0 ? Notifications.popupList[Notifications.popupList.length - 1] : null
    readonly property bool isUrgent: latestNotif && latestNotif.urgency === NotificationUrgency.Critical.toString()
    readonly property bool hasImage: latestNotif && latestNotif.image !== ""

    readonly property color accentColor: isUrgent ? Appearance.colors.colPrimary : Appearance.colors.colSecondary
    readonly property color accentContainerColor: isUrgent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
    readonly property color accentOnColor: isUrgent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer

    property real pulseOpacity: 0.0

    SequentialAnimation {
        id: pulseAnimation
        running: root.isUrgent && !root.isExpanded
        loops: Animation.Infinite
        NumberAnimation {
            target: root
            property: "pulseOpacity"
            from: 0.0
            to: 0.35
            duration: 800
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "pulseOpacity"
            from: 0.35
            to: 0.0
            duration: 800
            easing.type: Easing.InQuad
        }
    }

    // ── CONTRACTED MODE ─────────────────────────────────────────────────────
    Item {
        id: contractedLayout
        anchors.fill: parent
        visible: !root.isExpanded

        Rectangle {
            id: contractedMaskRect
            anchors.fill: parent
            radius: Appearance.rounding.small
            visible: false
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: contractedMaskRect
        }

        Rectangle {
            id: contractedBg
            anchors.fill: parent
            color: Appearance.colors.colSurfaceContainer
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            NotificationAppIcon {
                id: notifIcon
                Layout.alignment: Qt.AlignVCenter
                appIcon: root.latestNotif ? root.latestNotif.appIcon : ""
                summary: root.latestNotif ? root.latestNotif.summary : ""
                urgency: (root.latestNotif && root.latestNotif.notification) ? root.latestNotif.notification.urgency : 1
                image: root.latestNotif ? root.latestNotif.image : ""
                implicitSize: 28

                scale: root.isUrgent ? 1.0 + root.pulseOpacity * 0.08 : 1.0
                Behavior on scale {
                    NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.bold: true
                    color: root.accentColor
                    text: root.latestNotif ? (root.latestNotif.appName || "") : ""
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    opacity: 0.85
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.bold: true
                    color: Appearance.colors.colOnSurface
                    text: root.latestNotif ? root.latestNotif.summary : ""
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                text: root.isUrgent ? "priority_high" : "notifications"
                iconSize: Appearance.font.pixelSize.small
                color: root.accentColor
                opacity: root.isUrgent ? 0.7 + root.pulseOpacity * 0.3 : 0.35
                Layout.alignment: Qt.AlignVCenter

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }
        }
    }

    // ── EXPANDED MODE ───────────────────────────────────────────────────────
    Item {
        id: expandedLayout
        anchors.fill: parent
        visible: root.isExpanded
        opacity: root.isExpanded ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: expandedMaskRect
            anchors.fill: parent
            radius: Appearance.rounding.windowRounding
            visible: false
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: expandedMaskRect
        }

        Image {
            id: expandedBgImage
            anchors.fill: parent
            source: root.hasImage ? root.latestNotif.image : ""
            fillMode: Image.PreserveAspectCrop
            visible: root.hasImage
            opacity: 0.3
        }

        Rectangle {
            anchors.fill: parent
            visible: root.hasImage
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer, 0.15) }
                GradientStop { position: 0.5; color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer, 0.6) }
                GradientStop { position: 1.0; color: Appearance.colors.colSurfaceContainer }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: !root.hasImage
            color: Appearance.colors.colSurfaceContainer
        }

        Item {
            id: expandedHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            height: expandedHeaderRow.implicitHeight

            RowLayout {
                id: expandedHeaderRow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 8

                NotificationAppIcon {
                    id: expandedNotifIcon
                    Layout.alignment: Qt.AlignVCenter
                    appIcon: root.latestNotif ? root.latestNotif.appIcon : ""
                    summary: root.latestNotif ? root.latestNotif.summary : ""
                    urgency: (root.latestNotif && root.latestNotif.notification) ? root.latestNotif.notification.urgency : 1
                    image: root.latestNotif ? root.latestNotif.image : ""
                    implicitSize: 28
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.bold: true
                        color: root.accentColor
                        text: root.latestNotif ? (root.latestNotif.appName || "") : ""
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                        text: root.latestNotif ? root.latestNotif.summary : ""
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                    }
                }

                MaterialSymbol {
                    text: root.isUrgent ? "priority_high" : "notifications"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.accentColor
                    opacity: root.isUrgent ? 0.9 : 0.4
                    Layout.alignment: Qt.AlignTop
                }
            }
        }

        StyledText {
            id: expandedBody
            anchors.top: expandedHeader.bottom
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.hasImage ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
            text: root.latestNotif ? root.latestNotif.body : ""
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            opacity: 0.85
        }

        RowLayout {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            height: 34
            spacing: 6

            Repeater {
                model: root.latestNotif ? root.latestNotif.actions : []
                NotificationActionButton {
                    required property var modelData
                    Layout.fillWidth: true
                    buttonText: modelData.text
                    urgency: root.latestNotif ? root.latestNotif.urgency : 1

                    onClicked: {
                        if (root.latestNotif) {
                            Notifications.attemptInvokeAction(root.latestNotif.notificationId, modelData.identifier);
                        }
                    }
                }
            }

            NotificationActionButton {
                Layout.fillWidth: true
                urgency: root.latestNotif ? root.latestNotif.urgency : 1

                onClicked: {
                    if (root.latestNotif) {
                        Quickshell.clipboardText = root.latestNotif.body;
                    }
                }

                contentItem: RowLayout {
                    spacing: 6
                    anchors.centerIn: parent

                    MaterialSymbol {
                        iconSize: 14
                        color: Appearance.colors.colOnSurface
                        text: "content_copy"
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurface
                        text: Translation.tr("Copy")
                    }
                }
            }

            NotificationActionButton {
                Layout.fillWidth: true
                urgency: root.latestNotif ? root.latestNotif.urgency : 1

                onClicked: {
                    if (root.latestNotif) {
                        Notifications.discardNotification(root.latestNotif.notificationId);
                    }
                }

                contentItem: RowLayout {
                    spacing: 6
                    anchors.centerIn: parent

                    MaterialSymbol {
                        iconSize: 14
                        color: Appearance.colors.colOnSurface
                        text: "close"
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurface
                        text: Translation.tr("Close")
                    }
                }
            }
        }
    }
}
