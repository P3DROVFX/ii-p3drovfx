import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "email_inbox"

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg
    readonly property color itemBgColor: WidgetColorScheme.innerShapeColor
    readonly property color editBtnColor: WidgetColorScheme.accentColor
    readonly property color editIconColor: WidgetColorScheme.highlightTextColor

    readonly property int unreadCount: EmailService.authenticated ? EmailService.inboxUnreadCount : 0
    readonly property ListModel messagesModel: EmailService.authenticated ? EmailService.inboxMessages : null
    readonly property int totalCount: (EmailService.authenticated && messagesModel) ? messagesModel.count : 0

    function formatMsgTime(timestampStr, dateStr) {
        if (timestampStr) {
            let ts = Number(timestampStr);
            if (!isNaN(ts) && ts > 0) {
                return EmailService.formatRelativeDate(ts);
            }
        }
        if (dateStr && dateStr !== "") {
            let d = new Date(dateStr);
            if (!isNaN(d.getTime())) {
                return EmailService.formatRelativeDate(Math.floor(d.getTime() / 1000));
            }
            return dateStr;
        }
        return "";
    }

    StyledRectangularShadow {
        id: bgShadow
        target: bgRect
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    // Outer Container
    Rectangle {
        id: bgRect
        anchors.fill: parent
        anchors.margins: 10
        color: root.cardBgColor
        radius: Appearance.rounding.windowRounding

        layer.enabled: Config.options.background.widgets.enableInnerShadow ?? true
        layer.effect: InnerShadow {
            color: Qt.rgba(0, 0, 0, 0.15)
            radius: 8.0
            samples: 16
            horizontalOffset: 0
            verticalOffset: 1
            spread: 0.0
        }

        // Mask container for rounded corner clipping
        Item {
            id: contentContainer
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: contentContainer.width
                    height: contentContainer.height
                    radius: bgRect.radius
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 12
                anchors.bottomMargin: 0
                spacing: 8

                // Header: "Inbox (X)" + Edit / Compose Pencil Button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Inbox") + (root.unreadCount > 0 ? " (" + String(root.unreadCount) + ")" : (root.totalCount > 0 ? " (" + String(root.totalCount) + ")" : ""))
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.family: Appearance.font.family.title
                        font.weight: Font.DemiBold
                        color: root.textColorOnBg
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: Appearance.rounding.small
                        color: editMouseArea.containsMouse ? Qt.darker(root.editBtnColor, 1.1) : root.editBtnColor

                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "edit"
                            iconSize: 20
                            color: root.editIconColor
                        }

                        MouseArea {
                            id: editMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                GlobalStates.cheatsheetOpen = true;
                            }
                        }
                    }
                }

                // Unauthenticated / Loading / Empty fallback view
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !EmailService.authenticated || root.totalCount === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: !EmailService.authenticated ? "mail_lock" : (EmailService.loading ? "sync" : "inbox")
                            iconSize: 32
                            color: root.subtextColorOnBg
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: !EmailService.authenticated ? Translation.tr("Log in via Cheatsheet") : (EmailService.loading ? Translation.tr("Syncing...") : Translation.tr("No messages"))
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: root.subtextColorOnBg
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // Scrollable Email ListView (up to 6 items scrollable)
                ListView {
                    id: emailListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6
                    clip: true
                    visible: EmailService.authenticated && root.totalCount > 0

                    model: Math.min(6, root.totalCount)

                    delegate: Rectangle {
                        id: itemRect
                        width: ListView.view.width
                        height: 52
                        color: itemMouseArea.containsMouse ? Qt.darker(root.itemBgColor, 1.05) : root.itemBgColor
                        radius: Appearance.rounding.normal

                        required property int index

                        readonly property var msgData: root.messagesModel ? root.messagesModel.get(index) : null
                        readonly property string senderName: msgData ? (msgData.from || msgData.sender || Translation.tr("Unknown")) : ""
                        readonly property string subjectText: msgData ? (msgData.subject || msgData.snippet || Translation.tr("No Subject")) : ""
                        readonly property bool isUnread: msgData ? (msgData.unread ?? false) : false
                        readonly property string timeDisplay: msgData ? root.formatMsgTime(msgData.internalDate || msgData.timestamp, msgData.date) : ""

                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            spacing: 6

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: itemRect.senderName
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: itemRect.isUnread ? Font.Bold : Font.DemiBold
                                    color: root.textColorOnBg
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: itemRect.subjectText
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: root.subtextColorOnBg
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            // Trailing Timestamp display
                            StyledText {
                                text: itemRect.timeDisplay
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.subtextColorOnBg
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: itemMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                GlobalStates.cheatsheetOpen = true;
                            }
                        }
                    }
                }
            }
        }
    }
}
