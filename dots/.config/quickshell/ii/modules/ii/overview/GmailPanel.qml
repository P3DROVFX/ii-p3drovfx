pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property bool unreadOnly: false
    property string noticeText: ""

    readonly property var rows: root.filteredMessages()
    readonly property var selectedMessage: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length ? root.rows[root.selectedIndex] : null
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : !EmailService.authenticated
        ? Translation.tr("Gmail is not connected")
        : EmailService.loading
            ? Translation.tr("Refreshing Gmail…")
        : root.selectedMessage
            ? String(root.selectedMessage.subject ?? "")
            : Translation.tr("%1 messages").arg(String(root.rows.length))

    implicitWidth: 720
    implicitHeight: scaffold.implicitHeight

    function modelRows(model) {
        const rows = [];
        for (let index = 0; model && index < model.count; index++)
            rows.push(model.get(index));
        return rows;
    }

    function filteredMessages() {
        const query = root.searchQuery.trim().toLocaleLowerCase();
        const local = root.modelRows(EmailService.inboxMessages);
        const remote = root.modelRows(EmailService.searchMessagesModel);
        const seen = ({});
        return local.concat(remote).filter(message => {
            const id = String(message?.id ?? "");
            if (seen[id])
                return false;
            seen[id] = true;
            if (root.unreadOnly && !message?.unread)
                return false;
            if (query.length === 0)
                return true;
            return [message?.from, message?.subject, message?.snippet].join(" ").toLocaleLowerCase().includes(query);
        });
    }

    function clampSelection() {
        root.selectedIndex = root.rows.length === 0 ? -1 : Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1));
    }

    function navigateUp(): bool {
        if (root.selectedIndex <= 0)
            return false;
        root.selectedIndex--;
        messageList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateDown(): bool {
        if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length - 1)
            return false;
        root.selectedIndex++;
        messageList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateLeft(): bool { root.unreadOnly = !root.unreadOnly; return true; }
    function navigateRight(): bool { root.unreadOnly = !root.unreadOnly; return true; }

    function activateSelected(): bool {
        if (!root.selectedMessage?.id)
            return false;
        EmailService.fetchEmailBody(root.selectedMessage.id);
        if (root.selectedMessage.unread)
            EmailService.markAsRead(root.selectedMessage.id);
        root.showNotice(Translation.tr("Loading message…"));
        return true;
    }

    function secondaryActivateSelected(): bool {
        if (!root.selectedMessage)
            return false;
        EmailService.composeDraftTo = String(root.selectedMessage.from ?? "");
        EmailService.composeDraftSubject = Translation.tr("Re: %1").arg(String(root.selectedMessage.subject ?? ""));
        GlobalStates.overviewOpen = false;
        Qt.callLater(() => GlobalStates.openCheatsheet("email"));
        return true;
    }

    function editSelected(): bool {
        if (!root.selectedMessage?.id)
            return false;
        EmailService.markAsRead(root.selectedMessage.id);
        root.showNotice(Translation.tr("Marked as read"));
        return true;
    }

    function openAccounts(): bool {
        GlobalStates.overviewOpen = false;
        Qt.callLater(() => GlobalStates.openCheatsheet("email"));
        return true;
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    function focusInput(): bool { return false; }

    onRowsChanged: root.clampSelection()
    onSearchQueryChanged: {
        root.selectedIndex = 0;
        if (root.searchQuery.trim().length >= 2 && EmailService.authenticated)
            remoteSearchTimer.restart();
    }

    Timer {
        id: remoteSearchTimer
        interval: 350
        repeat: false
        onTriggered: EmailService.searchMessages(root.searchQuery.trim())
    }

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Email")
        icon: "mail"
        accent: true
        statusText: root.statusText
        showStatus: true
        primaryHint: ({ label: Translation.tr("Open"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Reply"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Mark read"), actionId: "edit", keys: ["Ctrl", "E"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: EmailService.userEmail.length > 0 ? EmailService.userEmail : Translation.tr("Inbox")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }

                RippleButton {
                    implicitWidth: unreadLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                    implicitHeight: unreadLabel.implicitHeight + Appearance.sizes.elevationMargin
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.unreadOnly ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: root.unreadOnly ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: root.unreadOnly ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: root.unreadOnly = !root.unreadOnly
                    StyledText {
                        id: unreadLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Unread")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.unreadOnly ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: EmailService.authenticated
                spacing: Appearance.sizes.elevationMargin

                ListView {
                    id: messageList
                    Layout.preferredWidth: parent.width * 0.45
                    Layout.fillHeight: true
                    clip: true
                    spacing: Appearance.sizes.elevationMargin / 2
                    model: root.rows

                    delegate: RippleButton {
                        required property int index
                        required property var modelData
                        width: messageList.width
                        implicitHeight: messageContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                        buttonRadius: Appearance.rounding.normal
                        colBackground: root.selectedIndex === index ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: root.selectedIndex === index ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: root.selectedIndex === index ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: { root.selectedIndex = index; root.activateSelected(); }

                        ColumnLayout {
                            id: messageContent
                            anchors.fill: parent
                            anchors.margins: Appearance.sizes.elevationMargin
                            anchors.rightMargin: root.selectedIndex === index
                                ? Appearance.sizes.elevationMargin * 6
                                : Appearance.sizes.elevationMargin
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: String(modelData.from ?? "")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: modelData.unread ? Font.DemiBold : Font.Normal
                                color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(modelData.subject ?? "")
                                elide: Text.ElideRight
                                font.weight: modelData.unread ? Font.DemiBold : Font.Normal
                                color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(modelData.snippet ?? "")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                        }

                        ConfiguredKeyHint {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: Appearance.sizes.elevationMargin
                            visible: root.selectedIndex === index && Config.options.search.appearance.showKeyHints
                            actionId: "activate"
                            fallbackKeys: ["↵"]
                            surface: Appearance.colors.colPrimaryContainer
                            onSurface: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: root.rows.length === 0
                        spacing: Appearance.sizes.elevationMargin / 2

                        MaterialLoadingIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            visible: EmailService.loading
                            implicitWidth: Appearance.sizes.elevationMargin * 4
                            implicitHeight: implicitWidth
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            visible: !EmailService.loading
                            text: root.unreadOnly ? "mark_email_read" : "inbox"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: EmailService.loading
                                ? Translation.tr("Searching Gmail…")
                                : root.searchQuery.trim().length > 0
                                    ? Translation.tr("No messages match this search")
                                    : root.unreadOnly
                                        ? Translation.tr("No unread messages")
                                        : Translation.tr("Inbox is empty")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Appearance.sizes.elevationMargin / 2

                    StyledText {
                        Layout.fillWidth: true
                        text: String(root.selectedMessage?.subject ?? Translation.tr("Select a message"))
                        elide: Text.ElideRight
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: String(root.selectedMessage?.from ?? "")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: EmailService.loadingEmailBody ? Translation.tr("Loading message…") : (EmailService.currentEmailBody || String(root.selectedMessage?.snippet ?? ""))
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignTop
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !EmailService.authenticated
                Layout.fillHeight: true
                spacing: Appearance.sizes.elevationMargin

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "mark_email_unread"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Connect Gmail in Cheat Sheet to search your inbox here.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                }

                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: accountButtonContent.implicitWidth + Appearance.sizes.elevationMargin * 2
                    implicitHeight: Appearance.sizes.elevationMargin * 3
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    onClicked: root.openAccounts()

                    RowLayout {
                        id: accountButtonContent
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.elevationMargin / 2
                        MaterialSymbol { text: "account_circle"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnPrimaryContainer }
                        StyledText { text: Translation.tr("Open Gmail accounts"); color: Appearance.colors.colOnPrimaryContainer; font.weight: Font.DemiBold }
                    }
                }
            }
        }
    }
}
