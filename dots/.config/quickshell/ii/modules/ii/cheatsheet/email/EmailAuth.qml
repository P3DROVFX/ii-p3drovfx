import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property bool configured: EmailService.credentialsConfigured

    Component.onCompleted: {
        if (!EmailService.gmailCredentialsTempLoaded) {
            loadGmailCredentialsProc.running = true;
        }
    }

    Process {
        id: loadGmailCredentialsProc
        command: ["python3", Quickshell.shellPath("scripts/email/get_gmail_credentials.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(text);
                    EmailService.tempGmailClientId = data.client_id || "";
                    EmailService.tempGmailClientSecret = data.client_secret || "";
                    EmailService.gmailCredentialsTempLoaded = true;
                } catch(e) {
                    console.error("[EmailAuth] Failed to parse existing Gmail credentials");
                }
            }
        }
    }

    Process {
        id: saveGmailCredentialsProc
        command: ["python3", Quickshell.shellPath("scripts/email/backup_gmail_env.py"), EmailService.tempGmailClientId, EmailService.tempGmailClientSecret]
        onExited: (code) => {
            console.log("[EmailAuth] Gmail credentials backup finished with code:", code);
            EmailService.gmailCredentialsTempLoaded = false;
            EmailService.checkCredentials();
        }
    }

    function saveGmailCredentials() {
        KeyringStorage.setNestedFields([
            { path: ["apiKeys", "gmail_client_id"], value: EmailService.tempGmailClientId },
            { path: ["apiKeys", "gmail_client_secret"], value: EmailService.tempGmailClientSecret }
        ]);
        saveGmailCredentialsProc.running = false;
        saveGmailCredentialsProc.running = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
        topLeftRadius: Appearance.rounding.verysmall
        topRightRadius: Appearance.rounding.windowRounding
        bottomLeftRadius: Appearance.rounding.verysmall
        bottomRightRadius: Appearance.rounding.windowRounding
    }

    // --- Ready / Connecting State ---
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 32
        visible: root.configured && !EmailService.loading && !EmailService.checkingCredentials

        MaterialShape {
            id: mainShape
            Layout.alignment: Qt.AlignHCenter
            implicitSize: 200
            shape: EmailService.authenticating ? MaterialShape.Shape.Cookie9Sided : (readyMouseArea.containsMouse ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.SoftBurst)
            color: Appearance.colors.colSurfaceContainerHighest
            
            rotation: EmailService.authenticating ? _loadingRotation : (readyMouseArea.containsMouse ? 180 : 0)

            property real _loadingRotation: 0
            NumberAnimation on _loadingRotation {
                running: EmailService.authenticating
                from: 0
                to: 360
                duration: 2000
                loops: Animation.Infinite
            }

            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(mainShape)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "mail"
                fill: 0.99
                iconSize: 100
                color: Appearance.colors.colOnSurface
                rotation: -mainShape.rotation
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: EmailService.authenticating ? Translation.tr("Waiting for browser...") : Translation.tr("Connect your account")
                font.pixelSize: 42
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: EmailService.authenticating ? Translation.tr("Please complete the sign-in in your browser window.") : Translation.tr("Sync your email account to start")
                font.pixelSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnSurfaceVariant
                opacity: 0.8
            }
        }

        // Connect Button
        Rectangle {
            id: connectBtn
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 280
            Layout.preferredHeight: 64
            radius: Appearance.rounding.full
            enabled: !EmailService.authenticating
            color: !enabled ? Appearance.colors.colSurfaceContainerHighest : (readyMouseArea.pressed ? Appearance.colors.colPrimaryActive : readyMouseArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
            
            opacity: enabled ? 1.0 : 0.6

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(connectBtn)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(connectBtn)
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 12
                
                StyledText {
                    text: EmailService.authenticating ? Translation.tr("Connecting...") : Translation.tr("Connect Account")
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.Bold
                    color: connectBtn.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                }

                MaterialSymbol {
                    text: EmailService.authenticating ? "hourglass_empty" : "arrow_forward"
                    iconSize: Appearance.font.pixelSize.huge
                    color: connectBtn.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                    
                    RotationAnimation on rotation {
                        running: EmailService.authenticating
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                    }
                }
            }

            MouseArea {
                id: readyMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    EmailService.startOAuth()
                }
            }
            
            scale: readyMouseArea.pressed ? 0.95 : readyMouseArea.containsMouse ? 1.02 : 1.0
            Behavior on scale {
                animation: Appearance.animation.clickBounce.numberAnimation.createObject(connectBtn)
            }
        }
    }

    // --- Needs Setup State (Tutorial) ---
    Flickable {
        id: setupFlickable
        anchors.fill: parent
        visible: !root.configured && !EmailService.loading && !EmailService.checkingCredentials
        contentHeight: setupCol.implicitHeight + 80
        contentWidth: width
        clip: true

        ColumnLayout {
            id: setupCol
            x: 40
            y: 40
            width: setupFlickable.width - 80
            spacing: 24

            ColumnLayout {
                spacing: 8
                StyledText {
                    text: Translation.tr("Gmail Setup Required")
                    font.pixelSize: 42
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    text: Translation.tr("To use Gmail, you need to provide your own API credentials for privacy and security.")
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnSurfaceVariant
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }

            // Tutorial Steps
            ColumnLayout {
                spacing: 16
                Layout.fillWidth: true

                Repeater {
                    model: [
                        { "step": "1", "text": "Go to Google Cloud Console", "url": "https://console.cloud.google.com" },
                        { "step": "2", "text": "Create a new project (or select an existing one)", "url": "" },
                        { "step": "3", "text": "Enable Gmail API (APIs & Services → Library → search 'Gmail API')", "url": "" },
                        { "step": "4", "text": "Configure OAuth Consent Screen (External, and add the following Scopes:\n  • https://www.googleapis.com/auth/gmail.modify (read, write, send, delete emails)\n  • https://www.googleapis.com/auth/gmail.send (send emails on your behalf)\n  • https://www.googleapis.com/auth/userinfo.email (view your email address)\n  • https://www.googleapis.com/auth/userinfo.profile (view your basic profile info))", "url": "" },
                        { "step": "5", "text": "Add your email as a test user in the OAuth consent screen", "url": "" },
                        { "step": "6", "text": "Create OAuth 2.0 credentials (APIs & Services → Credentials → Create → OAuth Client ID → Desktop App)", "url": "" },
                        { "step": "7", "text": "Copy Client ID and Client Secret into your .env file (see .env.example in .config/quickshell/ii)", "url": "" }
                    ]

                    delegate: RowLayout {
                        spacing: 16
                        Layout.fillWidth: true
                        
                        Rectangle {
                            width: 32; height: 32
                            radius: 16
                            color: Appearance.colors.colPrimaryContainer
                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.step
                                color: Appearance.colors.colOnPrimaryContainer
                                font.weight: Font.Bold
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            StyledText {
                                text: Translation.tr(modelData.text)
                                color: Appearance.colors.colOnSurface
                                font.weight: Font.Medium
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                            StyledText {
                                visible: modelData.url !== ""
                                text: modelData.url
                                color: Appearance.colors.colPrimary
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally(modelData.url)
                                }
                            }
                        }
                    }
                }
            }

            // Credentials Inputs
            ColumnLayout {
                spacing: 12
                Layout.fillWidth: true
                Layout.topMargin: 16

                StyledText {
                    text: Translation.tr("Gmail Credentials")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                ConfigTextField {
                    text: Translation.tr("Client ID")
                    icon: "key"
                    placeholderText: Translation.tr("Enter your Gmail Client ID")
                    inputText: EmailService.tempGmailClientId
                    textField.onTextChanged: EmailService.tempGmailClientId = textField.text.trim()
                }

                ConfigTextField {
                    text: Translation.tr("Client Secret")
                    icon: "vpn_key"
                    placeholderText: Translation.tr("Enter your Gmail Client Secret")
                    inputText: EmailService.tempGmailClientSecret
                    textField.echoMode: TextInput.Password
                    textField.onTextChanged: EmailService.tempGmailClientSecret = textField.text.trim()
                }
            }

            // Action Buttons
            RowLayout {
                spacing: 16
                Layout.topMargin: 16
                Layout.alignment: Qt.AlignLeft

                RippleButton {
                    id: checkBtn
                    Layout.preferredHeight: 56
                    Layout.preferredWidth: 260
                    buttonRadius: Appearance.rounding.full
                    colBackground: EmailService.credentialsCheckFailed ? Appearance.colors.colError : Appearance.colors.colPrimary
                    colBackgroundHover: EmailService.credentialsCheckFailed ? Appearance.colors.colErrorHover : Appearance.colors.colPrimaryHover
                    enabled: !EmailService.checkingCredentials && EmailService.tempGmailClientId.length > 0 && EmailService.tempGmailClientSecret.length > 0
                    onClicked: root.saveGmailCredentials()
                    
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        MaterialSymbol { 
                            text: EmailService.checkingCredentials ? "progress_activity" : (EmailService.credentialsCheckFailed ? "error" : "save")
                            iconSize: 22
                            color: EmailService.credentialsCheckFailed ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary 
                            
                            RotationAnimation on rotation {
                                running: EmailService.checkingCredentials
                                from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                            }
                        }
                        StyledText {
                            text: EmailService.checkingCredentials ? Translation.tr("Saving...") : Translation.tr("Save & Apply")
                            color: EmailService.credentialsCheckFailed ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                    }
                }

                RippleButton {
                    Layout.preferredHeight: 56
                    Layout.preferredWidth: 220
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                    onClicked: {
                        var envDir = FileUtils.trimFileProtocol(Directories.config + "/quickshell/ii");
                        Quickshell.execDetached(["xdg-open", envDir]);
                    }
                    
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 10
                        MaterialSymbol { text: "edit"; iconSize: 22; color: Appearance.colors.colOnSurface }
                        StyledText {
                            text: Translation.tr("Open .env")
                            color: Appearance.colors.colOnSurface
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                    }
                }
            }
            
            // Env Snippet
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: snippetText.implicitHeight + 40
                color: Appearance.colors.colSurfaceContainerLow
                radius: Appearance.rounding.small
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                
                StyledText {
                    id: snippetText
                    anchors.centerIn: parent
                    width: parent.width - 40
                    text: "GOOGLE_CLIENT_ID=your_id_here\nGOOGLE_CLIENT_SECRET=your_secret_here"
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.Wrap
                    lineHeight: 1.2
                }
            }
        }
    }

    // --- Loading State ---
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24
        visible: EmailService.loading || EmailService.checkingCredentials

        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            implicitSize: 160
            loading: parent.visible
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: EmailService.checkingCredentials ? Translation.tr("Checking environment...") : Translation.tr("Authenticating with Google...")
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
