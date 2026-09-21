pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A notification, expanded: what it says, and what can be done about it.
 *
 * The island's contracted notification face is a glance - the app, the summary, one
 * line of the body. This is that same face with the notification's content under it:
 * the body in as many lines as the card holds, and the notification's own actions
 * beside the Close and Copy every notification gets. The lay of it is the notification
 * list's own item (`modules/common/widgets/NotificationItem.qml`, in its expanded
 * state) - icon and app, summary, body, a row of equal action buttons - so a
 * notification reads the same wherever it is seen, and the island changes only where it
 * is drawn: straight onto its own body, with the text in the island's own tokens, since
 * the body of the island already is the card a list item would have to draw.
 *
 * It is handed a size and never asks for one: the descriptor in IslandRegistry is where
 * the card's box is decided, and the body is capped at the lines that box holds.
 */
Item {
    id: root
    anchors.fill: parent

    /** The card's own padding, on every side. */
    readonly property real padding: 12
    /** How many lines of the body the box holds; more is elided, not spilled. */
    readonly property int bodyLines: 4

    // ── Which notification ───────────────────────────────────────────────────
    /**
     * The one on show, held after the popup list lets go of it.
     *
     * The island decides when a face leaves; a notification that expires (or is
     * superseded) while the card is still fading must not swap its text and icon out in
     * a single frame under the pointer - the same hold the contracted face keeps.
     */
    readonly property var liveNotif: Notifications.popupList.length > 0
        ? Notifications.popupList[Notifications.popupList.length - 1] : null
    property var heldNotif: null
    onLiveNotifChanged: {
        if (root.liveNotif)
            root.heldNotif = root.liveNotif;
    }
    Component.onCompleted: root.heldNotif = root.liveNotif
    readonly property var notif: root.liveNotif ?? root.heldNotif

    /**
     * Urgency as the server sent it, not as the service stores it.
     *
     * `Notifications.list` keeps urgency as a string for the JSON it writes to disk,
     * and the components that take an urgency want the enum - the app icon paints a
     * different shape for a critical notification, the action buttons a different
     * pair of colours.
     */
    readonly property var urgency: (root.notif && root.notif.notification)
        ? root.notif.notification.urgency : NotificationUrgency.Normal
    readonly property bool urgent: root.urgency === NotificationUrgency.Critical

    /** The accent the contracted face uses for the app's name. */
    readonly property color accentColor: root.urgent ? Appearance.colors.colPrimary : Appearance.colors.colSecondary

    /**
     * The body, as the notification list draws it: markup kept, links live.
     *
     * The line breaks become `<br/>` because the text is rendered as markup, and the
     * app's name goes with it so the Chromium-family first line (a bare link to the
     * site) is dropped the same way there.
     */
    readonly property string bodyText: {
        if (!root.notif)
            return "";
        const body = NotificationUtils.processNotificationBody(root.notif.body ?? "",
            root.notif.appName || root.notif.summary || "");
        return body.replace(/\n/g, "<br/>");
    }

    function close() {
        if (root.notif)
            Notifications.discardNotification(root.notif.notificationId);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 10

        // ── The app, and what it said in one line ────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            NotificationAppIcon {
                Layout.alignment: Qt.AlignVCenter
                appIcon: root.notif ? root.notif.appIcon : ""
                summary: root.notif ? root.notif.summary : ""
                urgency: root.urgency
                image: root.notif ? root.notif.image : ""
                implicitSize: 40
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.bold: true
                    color: root.accentColor
                    opacity: 0.85
                    text: root.notif ? (root.notif.appName || "") : ""
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.bold: true
                    color: Appearance.colors.colOnSurface
                    text: root.notif ? root.notif.summary : ""
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }
        }

        // ── The content, which is the whole reason this face exists ──────────
        /**
         * Filling the height the box has left over rather than sized to its own text:
         * a one-line body then leaves the air under it, and the actions stay where they
         * are instead of climbing up the card.
         */
        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.bodyText !== ""
            verticalAlignment: Text.AlignTop
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            text: `<style>img{max-width:${root.width - 2 * root.padding}px;}</style>` + root.bodyText
            maximumLineCount: root.bodyLines
            elide: Text.ElideRight
            onLinkActivated: link => {
                Qt.openUrlExternally(link);
                GlobalStates.sidebarRightOpen = false;
            }

            PointingHandLinkHover {}
        }

        // ── The actions ──────────────────────────────────────────────────────
        // Close, whatever the notification itself offers, and Copy: the same three
        // kinds of button, in the same order, as the notification list's item.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            NotificationActionButton {
                Layout.fillWidth: true
                urgency: root.urgency
                onClicked: root.close()

                contentItem: MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: root.urgent ? Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
                    text: "close"
                }
            }

            Repeater {
                model: root.notif ? root.notif.actions : []

                NotificationActionButton {
                    required property var modelData
                    Layout.fillWidth: true
                    buttonText: modelData.text
                    urgency: root.urgency
                    onClicked: {
                        const identifier = modelData.identifier;
                        if (identifier.startsWith("__qs_")) {
                            Notifications.executeShellAction(root.notif, identifier);
                            root.close();
                        } else {
                            Notifications.attemptInvokeAction(root.notif.notificationId, identifier);
                        }
                    }

                    /**
                     * The reference lets a long label scroll the row sideways; this card
                     * is one fixed width, so the label gives way instead of running over
                     * its neighbour. Same text, same colours, one line.
                     */
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.text
                        elide: Text.ElideRight
                        color: root.urgent ? Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
                    }
                }
            }

            NotificationActionButton {
                id: copyButton
                Layout.fillWidth: true
                urgency: root.urgency
                onClicked: {
                    Quickshell.clipboardText = root.notif ? root.notif.body : "";
                    copyIcon.text = "inventory";
                    copyIconTimer.restart();
                }

                Timer {
                    id: copyIconTimer
                    interval: 1500
                    repeat: false
                    onTriggered: copyIcon.text = "content_copy"
                }

                contentItem: MaterialSymbol {
                    id: copyIcon
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: copyButton.urgency === NotificationUrgency.Critical
                        ? Appearance.m3colors.m3onSurfaceVariant
                        : Appearance.m3colors.m3onSurface
                    text: "content_copy"
                }
            }
        }
    }
}