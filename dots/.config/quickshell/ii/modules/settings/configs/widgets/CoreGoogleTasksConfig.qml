import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 16

    NoticeBox {
        Layout.fillWidth: true
        materialIcon: "info"
        text: Translation.tr("Google Tasks, Gmail, and Google Drive backup share the same Google Cloud OAuth credentials configured in ii/.env (GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET). Set them once to authorize all Google services.")
    }

    // ── Warning / Error Banners ─────────────────────────────────

    WarningBox {
        Layout.fillWidth: true
        visible: !GoogleTasksService.credentialsConfigured
        text: Translation.tr("Google OAuth credentials are not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env.")
    }

    WarningBox {
        Layout.fillWidth: true
        visible: GoogleTasksService.reauthorizationRequired
        text: Translation.tr("Google authorization was revoked or expired. Click 'Reauthorize' below to reconnect.")
    }

    WarningBox {
        Layout.fillWidth: true
        visible: GoogleTasksService.lastErrorCode === "http_error" && (GoogleTasksService.lastHttpStatus === 403 || GoogleTasksService.lastErrorMessage.indexOf("disabled") >= 0 || GoogleTasksService.lastErrorMessage.indexOf("not been used") >= 0)
        text: Translation.tr("Google Tasks API is not enabled for this Google Cloud project. Enable 'Tasks API' in Google Cloud Console, then retry.")
    }

    WarningBox {
        Layout.fillWidth: true
        visible: GoogleTasksService.lastErrorCode !== "" && !GoogleTasksService.reauthorizationRequired && GoogleTasksService.lastHttpStatus !== 403 && GoogleTasksService.lastErrorCode !== "http_error"
        text: GoogleTasksService.lastErrorMessage !== "" ? GoogleTasksService.lastErrorMessage : Translation.tr("An error occurred while communicating with Google Tasks API.")
    }

    // ── Disconnected State: Connect Button ───────────────────────

    ContentSection {
        Layout.fillWidth: true
        icon: "account_circle"
        title: Translation.tr("Google Tasks Connection")
        visible: !GoogleTasksService.hasRefreshToken || GoogleTasksService.reauthorizationRequired

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("Google Tasks Setup")
            text: Translation.tr("Google Tasks uses the same OAuth 2.0 Client credentials (GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET) configured for Gmail and Google Drive. Authorize your Google account to sync tasks.")
            isFirst: true

            RippleButtonWithIcon {
                mainText: Translation.tr("Open Cloud Console")
                materialIcon: "open_in_new"
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                colBackground: Appearance.colors.colLayer0
                colBackgroundHover: Appearance.colors.colLayer0Hover
                colRipple: Appearance.colors.colLayer0Active
                downAction: () => {
                    Qt.openUrlExternally("https://console.cloud.google.com/apis/library/tasks.googleapis.com")
                }
            }
        }

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 48
            buttonRadius: Appearance.rounding.normal
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            enabled: GoogleTasksService.credentialsConfigured && !GoogleTasksService.authenticating

            RowLayout {
                anchors.centerIn: parent
                spacing: 12

                MaterialSymbol {
                    text: GoogleTasksService.authenticating ? "sync" : "login"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnPrimaryContainer

                    RotationAnimation on rotation {
                        running: GoogleTasksService.authenticating
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                    }
                }

                StyledText {
                    text: GoogleTasksService.authenticating
                        ? Translation.tr("Authorizing in browser...")
                        : Translation.tr("Connect Google Tasks")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            onClicked: {
                GoogleTasksService.startOAuth();
            }
        }
    }

    // ── Connected State: Account & Task List Settings ───────────

    ContentSection {
        Layout.fillWidth: true
        icon: "checklist"
        title: Translation.tr("Google Tasks Account & Lists")
        visible: GoogleTasksService.hasRefreshToken && !GoogleTasksService.reauthorizationRequired

        // Account status hero card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: accountLayout.implicitHeight + 28
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer

            RowLayout {
                id: accountLayout
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                Item {
                    implicitWidth: 44
                    implicitHeight: 44

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.height / 2
                        color: Appearance.colors.colPrimary
                        visible: GoogleTasksService.activeAccountAvatar === ""

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "account_circle"
                            iconSize: 28
                            color: Appearance.colors.colOnPrimary
                        }
                    }

                    StyledImage {
                        id: avatarImg
                        anchors.fill: parent
                        sourceSize: Qt.size(44, 44)
                        visible: GoogleTasksService.activeAccountAvatar !== ""
                        source: GoogleTasksService.activeAccountAvatar

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Circle {
                                diameter: avatarImg.height
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: GoogleTasksService.activeAccountEmail !== "" ? GoogleTasksService.activeAccountEmail : Translation.tr("Connected Account")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: Translation.tr("Google Tasks API Connected")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                        opacity: 0.75
                    }
                }

                MaterialSymbol {
                    text: "cloud_done"
                    iconSize: 24
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        // Task List selector section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: Translation.tr("Active Task List")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    color: Appearance.colors.colOnLayer1
                    Layout.fillWidth: true
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer0
                    colBackgroundHover: Appearance.colors.colLayer0Hover
                    colRipple: Appearance.colors.colLayer0Active

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                    }

                    onClicked: {
                        GoogleTasksService.refreshTaskLists();
                    }

                    StyledToolTip {
                        text: Translation.tr("Refresh task lists")
                    }
                }
            }

            // List of available task lists
            Repeater {
                model: GoogleTasksService.taskLists

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Appearance.rounding.normal
                    color: modelData.id === GoogleTasksService.selectedTaskListId
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer0

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            GoogleTasksService.selectTaskList(modelData.id, modelData.title || "");
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        MaterialSymbol {
                            text: modelData.id === GoogleTasksService.selectedTaskListId
                                ? "radio_button_checked"
                                : "radio_button_unchecked"
                            iconSize: 20
                            color: modelData.id === GoogleTasksService.selectedTaskListId
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            text: modelData.title || Translation.tr("Untitled List")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: modelData.id === GoogleTasksService.selectedTaskListId
                            color: modelData.id === GoogleTasksService.selectedTaskListId
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnLayer0
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: modelData.updated !== undefined
                            text: modelData.id === GoogleTasksService.selectedTaskListId
                                ? Translation.tr("Active")
                                : ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }

            StyledText {
                visible: GoogleTasksService.taskLists.length === 0
                text: Translation.tr("No task lists found. Click refresh or create a list in Google Tasks.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        // Action buttons (Reauthorize, Disconnect)
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 12

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer0
                colBackgroundHover: Appearance.colors.colLayer0Hover
                colRipple: Appearance.colors.colLayer0Active

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: Translation.tr("Reauthorize")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                    }
                }

                onClicked: {
                    GoogleTasksService.startOAuth();
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: "logout"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnErrorContainer
                    }
                    StyledText {
                        text: Translation.tr("Disconnect")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnErrorContainer
                    }
                }

                onClicked: {
                    GoogleTasksService.disconnect();
                }
            }
        }
    }
}
