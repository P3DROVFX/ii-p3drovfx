import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    readonly property bool configured: EmailService.credentialsConfigured

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
        anchors.fill: parent
        anchors.margins: 40
        visible: !root.configured && !EmailService.loading && !EmailService.checkingCredentials
        contentHeight: setupCol.implicitHeight
        clip: true

        ColumnLayout {
            id: setupCol
            width: parent.width
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
                        { "step": "4", "text": "Configure OAuth Consent Screen (External, add scopes: gmail.modify, gmail.send, email, profile)", "url": "" },
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
                    enabled: !EmailService.checkingCredentials
                    onClicked: EmailService.checkCredentials()
                    
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        MaterialSymbol { 
                            text: EmailService.checkingCredentials ? "progress_activity" : (EmailService.credentialsCheckFailed ? "error" : "refresh")
                            iconSize: 22
                            color: EmailService.credentialsCheckFailed ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary 
                            
                            RotationAnimation on rotation {
                                running: EmailService.checkingCredentials
                                from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                            }
                        }
                        StyledText {
                            text: EmailService.checkingCredentials ? Translation.tr("Checking...") : (EmailService.credentialsCheckFailed ? Translation.tr("Credential Missing") : Translation.tr("Check Credentials"))
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
                        var envPath = FileUtils.trimFileProtocol(Directories.config + "/quickshell/ii/.env");
                        Qt.openUrlExternally("file://" + envPath);
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
                    text: "GMAIL_CLIENT_ID=your_id_here\nGMAIL_CLIENT_SECRET=your_secret_here"
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
            implicitSize: 120
            loading: parent.visible
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: EmailService.checkingCredentials ? Translation.tr("Checking environment...") : Translation.tr("Authenticating with Google...")
            font.pixelSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnSurface
            opacity: 0.8
        }
    }
}
