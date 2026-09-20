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

Item {
    id: root
    anchors.fill: parent

    readonly property var liveNotif: Notifications.popupList.length > 0 ? Notifications.popupList[Notifications.popupList.length - 1] : null
    /**
     * The notification on screen, held after the popup list lets go of it.
     *
     * Opening search (or anything that clears popups) emptied the list while this face
     * was still fading out, so its text and icon swapped to the empty state in a single
     * frame in the middle of the transition. The island decides when the face leaves;
     * until then it keeps showing what it showed.
     */
    property var heldNotif: null
    onLiveNotifChanged: {
        if (root.liveNotif)
            root.heldNotif = root.liveNotif;
    }
    Component.onCompleted: root.heldNotif = root.liveNotif
    readonly property var latestNotif: root.liveNotif ?? root.heldNotif
    readonly property bool isUrgent: latestNotif && latestNotif.urgency === NotificationUrgency.Critical.toString()
    readonly property bool hasImage: latestNotif && latestNotif.image !== ""

    readonly property color accentColor: isUrgent ? Appearance.colors.colPrimary : Appearance.colors.colSecondary
    readonly property color accentContainerColor: isUrgent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
    readonly property color accentOnColor: isUrgent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer

    property real pulseOpacity: 0.0

    SequentialAnimation {
        id: pulseAnimation
        running: root.isUrgent
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

    // ── The face ─────────────────────────────────────────────────────────────
    /**
     * One padding for every side, so the icon's air above and below matches its air at
     * the edge. The icon is then whatever is left of the height - it used to be a fixed
     * 28px in a 56px face, which left it looking small and off-centre against the text.
     */
    readonly property real padding: 10
    readonly property real iconSize: Math.max(24, Math.round(root.height - 2 * root.padding))

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        spacing: root.padding

        NotificationAppIcon {
            id: notifIcon
            Layout.alignment: Qt.AlignVCenter
            appIcon: root.latestNotif ? root.latestNotif.appIcon : ""
            summary: root.latestNotif ? root.latestNotif.summary : ""
            urgency: (root.latestNotif && root.latestNotif.notification) ? root.latestNotif.notification.urgency : 1
            image: root.latestNotif ? root.latestNotif.image : ""
            implicitSize: root.iconSize

            scale: root.isUrgent ? 1.0 + root.pulseOpacity * 0.08 : 1.0
            Behavior on scale {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

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
    }
}
