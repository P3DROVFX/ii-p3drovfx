import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: false


    // Temp state before saving
    property string tempClientId: ""
    property string tempClientSecret: ""
    property string tempAccessToken: ""
    
    // Auth process state
    property bool authRunning: false
    property string authErrorMsg: ""

    Component.onCompleted: {
        loadTempData();
    }

    function loadTempData() {
        tempClientId = TickTickService.clientId;
        tempClientSecret = TickTickService.clientSecret;
        tempAccessToken = TickTickService.accessToken;
    }


    WarningBox {
        Layout.fillWidth: true
        visible: authErrorMsg !== ""
        text: authErrorMsg
    }

    ContentSection {
        icon: "cloud_sync"
        title: Translation.tr("TickTick Credentials")

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("TickTick Developer Center")
            text: Translation.tr("Register your application to get Client ID and Client Secret.")
            isFirst: true

            RippleButtonWithIcon {
                mainText: Translation.tr("Open Website")
                materialIcon: "open_in_new"
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                colBackground: Appearance.colors.colLayer0
                colBackgroundHover: Appearance.colors.colLayer0Hover
                colRipple: Appearance.colors.colLayer0Active
                downAction: () => {
                    Qt.openUrlExternally("https://developer.ticktick.com/manage")
                }
            }
        }

        ConfigTextField {
            text: Translation.tr("Client ID")
            icon: "key"
            placeholderText: Translation.tr("Enter your TickTick Client ID")
            inputText: root.tempClientId
            textField.onTextChanged: root.tempClientId = textField.text.trim()
        }

        ConfigTextField {
            text: Translation.tr("Client Secret")
            icon: "vpn_key"
            placeholderText: Translation.tr("Enter your TickTick Client Secret")
            inputText: root.tempClientSecret
            textField.echoMode: TextInput.Password
            textField.onTextChanged: root.tempClientSecret = textField.text.trim()
        }

        ConfigTextField {
            text: Translation.tr("Access Token")
            icon: "token"
            placeholderText: Translation.tr("Enter or generate an Access Token")
            inputText: root.tempAccessToken
            textField.echoMode: TextInput.Password
            textField.onTextChanged: root.tempAccessToken = textField.text.trim()
        }
    }

    ContentSection {
        icon: "sync_saved_locally"
        title: Translation.tr("Actions")

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 48
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                enabled: !root.authRunning && root.tempClientId.length > 0 && root.tempClientSecret.length > 0

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    MaterialSymbol {
                        id: authIcon
                        text: "vpn_key"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnPrimaryContainer

                        RotationAnimation on rotation {
                            running: root.authRunning
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                        }
                    }
                    StyledText {
                        text: root.authRunning ? Translation.tr("Authorizing in browser...") : Translation.tr("Authorize & Generate Token")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                onClicked: {
                    root.authRunning = true;
                    root.authErrorMsg = "";
                    authTokenProc.command = ["python3", Quickshell.shellPath("scripts/ticktick/get_token.py"), root.tempClientId, root.tempClientSecret];
                    authTokenProc.running = false;
                    authTokenProc.running = true;
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 48
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    MaterialSymbol {
                        text: "save"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: Translation.tr("Save Credentials")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                onClicked: {
                    saveCredentials();
                }
            }
        }
    }

    function saveCredentials() {
        // Save to Gnome Keyring via KeyringStorage
        KeyringStorage.setNestedField(["apiKeys", "ticktick_client_id"], root.tempClientId);
        KeyringStorage.setNestedField(["apiKeys", "ticktick_client_secret"], root.tempClientSecret);
        KeyringStorage.setNestedField(["apiKeys", "ticktick_access_token"], root.tempAccessToken);

        // Backup to .env
        backupEnvProc.command = ["python3", Quickshell.shellPath("scripts/ticktick/backup_env.py"), root.tempClientId, root.tempClientSecret, root.tempAccessToken];
        backupEnvProc.running = false;
        backupEnvProc.running = true;

        // Apply changes immediately to the service
        TickTickService.clientId = root.tempClientId;
        TickTickService.clientSecret = root.tempClientSecret;
        TickTickService.accessToken = root.tempAccessToken;
        TickTickService.refresh();

        console.log("[TickTickConfig] Credentials saved and applied.");
    }

    Process {
        id: authTokenProc
        stdout: StdioCollector {
            onStreamFinished: {
                let token = text.trim();
                if (token.length > 0 && !token.startsWith("ERROR")) {
                    root.tempAccessToken = token;
                    root.authRunning = false;
                    // Auto save credentials after successful authorization
                    Qt.callLater(() => {
                        saveCredentials();
                    });
                } else {
                    root.authErrorMsg = Translation.tr("Failed to get token: ") + token;
                    root.authRunning = false;
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.authRunning = false;
                if (root.authErrorMsg === "") {
                    root.authErrorMsg = Translation.tr("Authorization process exited with code ") + code;
                }
            }
        }
    }

    Process {
        id: backupEnvProc
    }

    NoticeBox {
        Layout.fillWidth: true
        text: Translation.tr("Gmail credentials are set in ii/.env. Sports (ESPN) options live in the Sports bar widget page.")
    }
}
