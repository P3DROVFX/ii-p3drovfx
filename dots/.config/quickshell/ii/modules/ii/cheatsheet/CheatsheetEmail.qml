import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import "./email"
import "./email/EmailIconRules.js" as IconRules

Item {
    id: root
    property real spacing: 8

    property string activeTab: "inbox"

    property bool emailOpen: false
    property bool emailActive: false
    property string selectedMessageId: ""
    property string selectedThreadId: ""
    property string selectedSubject: ""
    property string selectedFrom: ""
    property string selectedSnippet: ""
    property string selectedIcon: "person"
    property string selectedDate: ""
    property bool selectedUnread: false
    property string selectedLabelsString: ""
    property bool selectedIsStack: false

    property real emailOpenStartX: 0
    property real emailOpenStartY: 0
    property real emailOpenStartWidth: 0
    property real emailOpenStartHeight: 0
    property real emailOpenIconX: 0
    property real emailOpenIconY: 0
    property real emailOpenIconW: 0
    property real emailOpenIconH: 0
    property real emailOpenSubjectX: 0
    property real emailOpenSubjectY: 0
    property real emailOpenSubjectW: 0
    property real emailOpenSubjectH: 0

    Rectangle {
        anchors.fill: parent
        color: "transparent" //Appearance.colors.colLayer4 we can use this, but i'm not sure on what to use.
        radius: Appearance.rounding.windowRounding
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Math.max(12, Appearance.rounding.windowRounding / 2.0)
        spacing: 4

        // Navigation
        EmailSidebar {
            id: emailSidebar
            activeTab: root.activeTab
            Connections {
                target: emailSidebar
                function onActiveTabChanged() {
                    if (root.emailOpen && root.emailActive) {
                        emailContent.startClose();
                    }
                    root.activeTab = emailSidebar.activeTab;
                    // Silent sync (force=false) - will only show loading if model is empty
                    EmailService.syncLabel(root.activeTab);
                }
            }
        }

        // Content Area
        Item {
            Layout.fillHeight: true
            Layout.fillWidth: true

            EmailAuth {
                anchors.fill: parent
                visible: !EmailService.authenticated
            }

            EmailInbox {
                id: emailInbox
                anchors.fill: parent
                visible: EmailService.authenticated && root.activeTab !== "settings"

                opacity: (root.emailActive || root.activeTab === "compose") ? 0.0 : 1.0
                scale: (root.emailActive || root.activeTab === "compose") ? 0.95 : 1.0
                enabled: !root.emailActive && root.activeTab !== "compose"

                Behavior on opacity {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.OutCubic
                    }
                }

                loading: EmailService.loading
                activeTab: root.activeTab
                model: root.activeTab === "all_inboxes" ? EmailService.allInboxesMessages : root.activeTab === "spam" ? EmailService.spamMessages : root.activeTab === "sent" ? EmailService.sentMessages : root.activeTab === "trash" ? EmailService.trashMessages : root.activeTab === "starred" ? EmailService.starredMessages : root.activeTab === "important" ? EmailService.importantMessages : root.activeTab === "purchases" ? EmailService.purchasesMessages : root.activeTab === "search" ? EmailService.searchMessagesModel : root.activeTab.indexOf("label_") === 0 ? EmailService.searchMessagesModel : EmailService.inboxMessages
                onEmailSelected: function (messageId, threadId, isStack, startX, startY, startWidth, startHeight, iconX, iconY, iconW, iconH, subjectX, subjectY, subjectW, subjectH) {
                    // Buscar dados do email no model ativo
                    var currentModel = emailInbox.model;
                    for (var i = 0; i < currentModel.count; i++) {
                        var item = currentModel.get(i);
                        if (item.id === messageId) {
                            root.selectedSubject = item.subject;
                            root.selectedFrom = item.from;
                            root.selectedSnippet = item.snippet;
                            root.selectedIcon = IconRules.classify(item.subject, item.from, item.snippet);
                            root.selectedDate = item.date;
                            root.selectedUnread = item.unread;
                            root.selectedLabelsString = item.labelsString || "";
                            break;
                        }
                    }
                    root.selectedMessageId = messageId;
                    root.selectedThreadId = threadId;
                    root.selectedIsStack = isStack;
                    root.emailOpenStartX = startX;
                    root.emailOpenStartY = startY;
                    root.emailOpenStartWidth = startWidth;
                    root.emailOpenStartHeight = startHeight;
                    root.emailOpenIconX = iconX;
                    root.emailOpenIconY = iconY;
                    root.emailOpenIconW = iconW;
                    root.emailOpenIconH = iconH;
                    root.emailOpenSubjectX = subjectX;
                    root.emailOpenSubjectY = subjectY;
                    root.emailOpenSubjectW = subjectW;
                    root.emailOpenSubjectH = subjectH;
                    if (root.selectedUnread) {
                        EmailService.markAsRead(messageId);
                        // Atualizar no model local
                        for (var i = 0; i < emailInbox.model.count; i++) {
                            if (emailInbox.model.get(i).id === messageId) {
                                emailInbox.model.setProperty(i, "unread", false);
                                break;
                            }
                        }
                        EmailService.decrementUnreadForModel(emailInbox.model);
                    }
                    root.emailOpen = true;
                    root.emailActive = true;
                    if (EmailService.stackingEnabled && root.selectedIsStack) {
                        EmailService.fetchThread(threadId);
                    } else {
                        EmailService.fetchEmailBody(messageId);
                    }
                }
            }

            EmailStackedContent {
                id: emailStackedContent
                anchors.fill: parent
                z: 10
                visible: root.emailOpen && EmailService.stackingEnabled && root.selectedIsStack
                startX: root.emailOpenStartX
                startY: root.emailOpenStartY
                startWidth: root.emailOpenStartWidth
                startHeight: root.emailOpenStartHeight
                subject: root.selectedSubject
                threadId: root.selectedThreadId
                onCloseStarted: {
                    root.emailActive = false;
                }
                onCloseRequested: {
                    root.emailOpen = false;
                    root.selectedMessageId = "";
                    EmailService.currentThreadMessages.clear();
                }
                onReplyRequested: function (to, subject, body, threadId, inReplyTo) {
                    emailStackedContent.startClose();
                    root.activeTab = "compose";
                    emailCompose.setReplyMode(to, subject, body, threadId, inReplyTo);
                }
            }

            EmailContent {
                id: emailContent
                anchors.fill: parent
                z: 10
                visible: root.emailOpen && (!EmailService.stackingEnabled || !root.selectedIsStack)
                messageId: root.selectedMessageId
                startX: root.emailOpenStartX
                startY: root.emailOpenStartY
                startWidth: root.emailOpenStartWidth
                startHeight: root.emailOpenStartHeight
                cardIconX: root.emailOpenIconX
                cardIconY: root.emailOpenIconY
                cardIconW: root.emailOpenIconW
                cardIconH: root.emailOpenIconH
                cardSubjectX: root.emailOpenSubjectX
                cardSubjectY: root.emailOpenSubjectY
                cardSubjectW: root.emailOpenSubjectW
                cardSubjectH: root.emailOpenSubjectH
                subject: root.selectedSubject
                senderFull: root.selectedFrom
                icon: root.selectedIcon
                date: root.selectedDate
                body: EmailService.currentEmailBody
                htmlPath: EmailService.currentEmailHtmlPath
                loadingBody: EmailService.loadingEmailBody
                attachments: EmailService.currentEmailAttachments
                labelsString: root.selectedLabelsString
                threadId: root.selectedThreadId
                onCloseStarted: {
                    root.emailActive = false;
                }
                onCloseRequested: {
                    root.emailOpen = false;
                    root.selectedMessageId = "";
                    EmailService.currentEmailBody = "";
                    EmailService.currentEmailHtmlPath = "";
                    EmailService.currentEmailAttachments.clear();
                }
                onReplyRequested: {
                    emailContent.startClose();
                    root.activeTab = "compose";
                    emailCompose.setReplyMode(to, subject, body, threadId, inReplyTo);
                }
            }

            EmailCompose {
                id: emailCompose
                anchors.fill: parent
                z: 11
                visible: isOpen || isAnimating
                isOpen: root.activeTab === "compose"
                onCloseRequested: {
                    root.activeTab = "inbox";
                    emailSidebar.activeTab = "inbox";
                }
            }

            EmailSettings {
                anchors.fill: parent
                visible: (EmailService.authenticated || EmailService.userEmail !== "") && root.activeTab === "settings"
            }

            // Global Loading Overlay - Only shown if the list is empty and we are fetching
            Rectangle {
                anchors.fill: parent
                color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
                visible: EmailService.loading && emailInbox.model.count === 0 && EmailService.authenticated && root.activeTab !== "settings"
                z: 100
                radius: Appearance.rounding.windowRounding

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 24

                    MaterialLoadingIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        implicitSize: 160
                        loading: parent.parent.visible
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.activeTab === "spam" ? Translation.tr("Checking for Spam") : root.activeTab === "sent" ? Translation.tr("Retrieving Sent") : root.activeTab === "trash" ? Translation.tr("Emptying Bin") : root.activeTab === "search" ? Translation.tr("Searching") : root.activeTab.indexOf("label_") === 0 ? Translation.tr("Loading Label") : Translation.tr("Fetching Messages")
                            font.pixelSize: 32
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Connecting to Gmail and retrieving your updates...")
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.8
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: EmailService
        function onAuthenticatedChanged() {
            if (!EmailService.authenticated) {
                root.activeTab = "inbox";
            }
        }
        function onActiveAccountIndexChanged() {
            if (!EmailService.stayInSettingsAfterAccountSwitch && root.activeTab === "settings") {
                root.activeTab = "inbox";
                emailSidebar.activeTab = "inbox";
            }
        }
    }
}
