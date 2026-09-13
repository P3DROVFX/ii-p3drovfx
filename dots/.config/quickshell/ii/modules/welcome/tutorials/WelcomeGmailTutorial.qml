import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.welcome
import qs.modules.welcome.tutorials
import qs.services
import Quickshell
import Quickshell.Io
import "."

WelcomeIntegrationTutorial {
    id: root

    title: Translation.tr("Set up Gmail")
    subtitle: Translation.tr("Connect your Google account so II can read, organize and send your email from the cheatsheet.")
    materialIcon: "mail"
    statusText: WelcomeTutorialRegistry.statusTextFor("gmail")
    statusKind: WelcomeTutorialRegistry.stateKindFor("gmail")
    usedInChips: ["Email", "Cheatsheet"]

    signal openSettingsTarget(string pageId, string subPageId, string sectionId)

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
                } catch(e) {}
            }
        }
    }

    Process {
        id: saveGmailCredentialsProc
        command: ["python3", Quickshell.shellPath("scripts/email/backup_gmail_env.py"), EmailService.tempGmailClientId, EmailService.tempGmailClientSecret]
        onExited: (code) => {
            EmailService.gmailCredentialsTempLoaded = false;
            EmailService.checkCredentials();
        }
    }

    // Step 1: Google Cloud Project
    WelcomeTutorialStep {
        stepNumber: "1"
        stateKind: EmailService.credentialsConfigured ? "complete" : "current"
        title: Translation.tr("Create a Google Cloud project")
        supportingText: Translation.tr("Open Google Cloud Console and create a new project, or select one you already use for II.")

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open Google Cloud Console")
                centerContent: true
                horizontalPadding: 16
                buttonRadius: Appearance.rounding.full
                implicitHeight: 40
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colText: Appearance.colors.colOnSecondaryContainer
                onClicked: Qt.openUrlExternally("https://console.cloud.google.com")
            }
        }
    }

    // Step 2: Enable Gmail API
    WelcomeTutorialStep {
        stepNumber: "2"
        stateKind: EmailService.credentialsConfigured ? "complete" : "current"
        title: Translation.tr("Enable the Gmail API")
        supportingText: Translation.tr("Open APIs & Services → Library, search for 'Gmail API' and enable it for this project.")
    }

    // Step 3: Configure OAuth consent
    WelcomeTutorialStep {
        stepNumber: "3"
        stateKind: EmailService.credentialsConfigured ? "complete" : "current"
        title: Translation.tr("Configure OAuth consent screen")
        supportingText: Translation.tr("Configure the OAuth consent screen as External, and add the following required permissions:\n• https://www.googleapis.com/auth/gmail.modify (read, write, send, delete emails)\n• https://www.googleapis.com/auth/gmail.send (send emails on your behalf)\n• https://www.googleapis.com/auth/userinfo.email (view your email address)\n• https://www.googleapis.com/auth/userinfo.profile (view your basic profile info)")
    }

    // Step 4: Add test user
    WelcomeTutorialStep {
        stepNumber: "4"
        stateKind: EmailService.credentialsConfigured ? "complete" : "current"
        title: Translation.tr("Add your account as a test user")
        supportingText: Translation.tr("Add the Google account you want to use with II to the OAuth consent screen's test users list.")
    }

    // Step 5: Create Desktop credentials
    WelcomeTutorialStep {
        stepNumber: "5"
        stateKind: EmailService.credentialsConfigured ? "complete" : "current"
        title: Translation.tr("Create Desktop OAuth credentials")
        supportingText: Translation.tr("Go to APIs & Services → Credentials → Create Credentials → OAuth client ID and choose Desktop app.")
    }

    // Step 6: Add credentials to II
    WelcomeTutorialStep {
        stepNumber: "6"
        stateKind: EmailService.credentialsConfigured ? "complete" : (EmailService.tempGmailClientId.length > 0 ? "current" : "pending")
        title: Translation.tr("Add the credentials to II")
        supportingText: Translation.tr("Enter your Client ID and Client Secret below and click Save & Apply.")

        ConfigTextField {
            Layout.fillWidth: true
            text: Translation.tr("Client ID")
            icon: "key"
            placeholderText: Translation.tr("Enter your Gmail Client ID")
            inputText: EmailService.tempGmailClientId
            textField.onTextChanged: EmailService.tempGmailClientId = textField.text.trim()
        }

        ConfigTextField {
            Layout.fillWidth: true
            text: Translation.tr("Client Secret")
            icon: "vpn_key"
            placeholderText: Translation.tr("Enter your Gmail Client Secret")
            inputText: EmailService.tempGmailClientSecret
            textField.echoMode: TextInput.Password
            textField.onTextChanged: EmailService.tempGmailClientSecret = textField.text.trim()
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }

            RippleButton {
                implicitHeight: 40
                implicitWidth: 180
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                enabled: !EmailService.checkingCredentials && EmailService.tempGmailClientId.length > 0 && EmailService.tempGmailClientSecret.length > 0
                onClicked: {
                    KeyringStorage.setNestedFields([
                        { path: ["apiKeys", "gmail_client_id"], value: EmailService.tempGmailClientId },
                        { path: ["apiKeys", "gmail_client_secret"], value: EmailService.tempGmailClientSecret }
                    ]);
                    saveGmailCredentialsProc.running = false;
                    saveGmailCredentialsProc.running = true;
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: EmailService.checkingCredentials ? "progress_activity" : "save"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: EmailService.checkingCredentials ? Translation.tr("Saving…") : Translation.tr("Save & Apply")
                        color: Appearance.colors.colOnPrimary
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    // Step 7: Connect account
    WelcomeTutorialStep {
        stepNumber: "7"
        stateKind: EmailService.authenticated ? "complete" : (EmailService.credentialsConfigured ? "current" : "pending")
        title: Translation.tr("Connect your Google account")
        supportingText: Translation.tr("II will open your browser. Sign in with the Google account you added as a test user and approve access.")

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }

            RippleButton {
                implicitHeight: 44
                implicitWidth: 220
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                enabled: EmailService.credentialsConfigured && !EmailService.authenticating
                onClicked: EmailService.startOAuth()

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: EmailService.authenticating ? "hourglass_empty" : "login"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: EmailService.authenticating ? Translation.tr("Waiting for browser…") : Translation.tr("Connect Account")
                        color: Appearance.colors.colOnPrimary
                        font.weight: Font.Bold
                    }
                }
            }
        }
    }

    // Step 8: Verify inbox
    WelcomeTutorialStep {
        stepNumber: "8"
        isLast: true
        stateKind: EmailService.authenticated ? "complete" : "pending"
        title: Translation.tr("Verify inbox in II")
        supportingText: EmailService.authenticated
            ? Translation.tr("✓ Gmail connected! Your inbox is ready in the cheatsheet.")
            : Translation.tr("Complete the connection to start reading and organizing emails.")

        RowLayout {
            Layout.fillWidth: true
            visible: EmailService.authenticated
            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                materialIcon: "mail"
                mainText: Translation.tr("Open Email in Cheatsheet")
                centerContent: true
                horizontalPadding: 16
                buttonRadius: Appearance.rounding.full
                implicitHeight: 40
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colText: Appearance.colors.colOnPrimary
                onClicked: root.openSettingsTarget("cheatSheet", "", "mail")
            }
        }
    }
}
