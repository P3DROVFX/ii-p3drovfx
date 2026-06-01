import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    Layout.fillHeight: true
    Layout.preferredWidth: 300

    property string activeTab
    property real spacing: 8

    Rectangle {
        anchors.fill: parent
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
        topLeftRadius: Appearance.rounding.windowRounding
        topRightRadius: Appearance.rounding.verysmall
        bottomLeftRadius: Appearance.rounding.windowRounding
        bottomRightRadius: Appearance.rounding.verysmall
    }

    // Build the nav button list dynamically
    property var _navButtons: {
        var list = EmailService.navOrder;
        var visibilityMap = {
            "all_inboxes": EmailService.enableAllInboxes,
            "inbox": true,
            "spam": EmailService.enableSpam,
            "sent": EmailService.enableSent,
            "trash": EmailService.enableTrash,
            "starred": EmailService.enableStarred,
            "important": EmailService.enableImportant,
            "purchases": EmailService.enablePurchases
        };
        return list.filter(item => visibilityMap[item.tab] !== false);
    }

    // Build the labels list
    property var _labelButtons: {
        var arr = EmailService.enabledLabels;
        var list = [];
        for (var i = 0; i < EmailService.labels.count; i++) {
            var lbl = EmailService.labels.get(i);
            if (lbl && arr.includes(lbl.id)) {
                list.push({
                    id: lbl.id,
                    name: lbl.name,
                    unread: lbl.messagesUnread
                });
            }
        }
        return list;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 24

        RippleButtonWithIcon {
            Layout.fillWidth: true
            implicitHeight: 64
            buttonRadius: Appearance.rounding.full
            toggled: root.activeTab === "compose"
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colPrimaryActive
            colBackgroundToggled: Appearance.colors.colPrimary
            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
            colRippleToggled: Appearance.colors.colPrimaryActive

            scale: down ? 0.95 : hovered ? 1.02 : 1.0
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            contentItem: Item {
                anchors.fill: parent
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "edit"
                        iconSize: 20
                        fill: root.activeTab === "compose" ? 1 : 0
                        color: root.activeTab === "compose" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Compose")
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: root.activeTab === "compose" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            enabled: EmailService.authenticated
            opacity: enabled ? 1.0 : 0.5
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            onClicked: {
                root.activeTab = "compose";
            }
        }

        StyledFlickable {
            id: navFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: -12
            Layout.rightMargin: -12
            clip: true
            contentHeight: scrollContent.implicitHeight
            Layout.topMargin: 24

            ColumnLayout {
                id: scrollContent
                x: 12
                width: navFlickable.width - 24
                spacing: 24

                // Navigation Button Group
                ColumnLayout {
                    id: navGroup
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: root._navButtons
                        delegate: EmailNavButton {
                            Layout.fillWidth: true
                            enabled: EmailService.authenticated
                            toggled: root.activeTab === modelData.tab
                            onClicked: root.activeTab = modelData.tab

                            iconName: modelData.icon
                            label: modelData.label

                            badgeText: {
                                if (!EmailService.enableUnreadBadges)
                                    return "";
                                var count = 0;
                                if (modelData.tab === "all_inboxes") {
                                    for (let i = 0; i < EmailService.allInboxesMessages.count; i++) {
                                        if (EmailService.allInboxesMessages.get(i).unread)
                                            count++;
                                    }
                                } else if (modelData.tab === "inbox")
                                    count = EmailService.inboxUnreadCount;
                                else if (modelData.tab === "spam")
                                    count = EmailService.spamUnreadCount;
                                else if (modelData.tab === "sent")
                                    count = EmailService.sentUnreadCount;
                                else if (modelData.tab === "trash")
                                    count = EmailService.trashUnreadCount;
                                else if (modelData.tab === "starred")
                                    count = EmailService.starredUnreadCount;
                                else if (modelData.tab === "important")
                                    count = EmailService.importantUnreadCount;
                                else if (modelData.tab === "purchases")
                                    count = EmailService.purchasesUnreadCount;
                                return count > 0 ? count.toString() : "";
                            }

                            isFirst: index === 0
                            isLast: index === root._navButtons.length - 1
                        }
                    }
                }

                // Labels Group
                ColumnLayout {
                    id: labelsGroup
                    Layout.fillWidth: true
                    spacing: 4
                    visible: root._labelButtons.length > 0

                    Repeater {
                        model: root._labelButtons
                        delegate: EmailNavButton {
                            Layout.fillWidth: true
                            enabled: EmailService.authenticated
                            toggled: root.activeTab === "label_" + modelData.id
                            onClicked: {
                                if (root.activeTab !== "label_" + modelData.id) {
                                    root.activeTab = "label_" + modelData.id;
                                }
                            }

                            iconName: "label"
                            label: modelData.name
                            badgeText: (EmailService.enableUnreadBadges && modelData.unread > 0) ? modelData.unread.toString() : ""

                            isFirst: index === 0
                            isLast: index === root._labelButtons.length - 1
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                id: searchBox
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: "transparent"
                radius: Appearance.rounding.full
                border.width: 1
                border.color: mouseAreaSearchInput.containsMouse || searchInput.activeFocus ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant

                Behavior on border.color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(searchBox)
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Appearance.colors.colOnSurface
                    opacity: mouseAreaSearchInput.containsMouse ? 0.05 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                MouseArea {
                    id: mouseAreaSearchInput
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.IBeamCursor
                    onClicked: searchInput.forceActiveFocus()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 8
                    spacing: 4

                    MaterialSymbol {
                        text: "search"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurface
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Search emails...")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurfaceVariant
                            visible: searchInput.text.length === 0 && !searchInput.activeFocus
                        }

                        Keys.onReturnPressed: {
                            if (searchInput.text.trim().length > 0) {
                                EmailService.searchMessages(searchInput.text);
                                root.activeTab = "search";
                            }
                        }
                    }

                    Rectangle {
                        id: searchActionBtn
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary
                        visible: searchInput.text.length > 0

                        scale: {
                            if (searchInput.text.length === 0)
                                return 0;
                            return mouseAreaSearch.pressed ? 0.9 : mouseAreaSearch.containsMouse ? 1.05 : 1.0;
                        }

                        Behavior on scale {
                            animation: Appearance.animation.clickBounce.numberAnimation.createObject(searchActionBtn)
                        }
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(searchActionBtn)
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_forward"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimary
                        }

                        MouseArea {
                            id: mouseAreaSearch
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (searchInput.text.trim().length > 0) {
                                    EmailService.searchMessages(searchInput.text);
                                    root.activeTab = "search";
                                }
                            }
                        }
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 56

                buttonRadius: Appearance.rounding.full
                toggled: root.activeTab === "settings"
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colPrimaryActive
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                colRippleToggled: Appearance.colors.colPrimaryActive

                scale: down ? 0.95 : hovered ? 1.02 : 1.0
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                contentItem: Item {
                    anchors.fill: parent
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "settings"
                            iconSize: Appearance.font.pixelSize.huge
                            fill: root.activeTab === "settings" ? 1 : 0
                            color: root.activeTab === "settings" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Settings")
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.DemiBold
                            color: root.activeTab === "settings" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }

                enabled: EmailService.authenticated
                opacity: enabled ? 1.0 : 0.5
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                onClicked: {
                    root.activeTab = "settings";
                }
            }
        }
    }
}
