import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Signing in to GitHub, wherever publishing needs it.
 *
 * Nothing here opens a browser on this machine. The device flow prints a code
 * to type on whatever device is convenient, and when this build carries no
 * OAuth app of its own it hands over the one command that does work instead of
 * failing with nothing to act on.
 */
ColumnLayout {
    id: root
    spacing: 8
    Layout.fillWidth: true

    property string userCode: ""
    property string verificationUri: ""
    property string fallbackCommand: ""
    property string errorText: ""
    property bool waitingOnTerminal: false

    readonly property bool signedIn: PresetStore.auth.authenticated === true
    readonly property string login: PresetStore.auth.login ?? ""
    readonly property bool hasGh: PresetStore.auth.hasGh === true
    // With no OAuth app registered for this build the in-shell code can never
    // arrive, so offering the button that asks for it would only ever fail.
    readonly property bool canUseDeviceFlow: PresetStore.auth.deviceFlow === true

    function setUpInTerminal(): void {
        root.errorText = "";
        const terminal = (Config.options.apps && Config.options.apps.terminal) || "kitty -1";
        Quickshell.execDetached(["bash", "-c",
            terminal + " -e bash " + Directories.scriptPath + "/preset_store_signin.sh &"]);
        // The script runs outside the shell, so there is no signal to wait on.
        // Polling is what turns "it finished over there" into a signed-in panel
        // without the user having to come back and press anything.
        root.waitingOnTerminal = true;
        authPoll.ticks = 0;
        authPoll.restart();
    }

    Component.onCompleted: PresetStore.refreshAuth()

    Timer {
        id: authPoll
        property int ticks: 0
        interval: 2000
        repeat: true
        onTriggered: {
            authPoll.ticks++;
            // Ten minutes is longer than any sign-in takes and short enough
            // that a window left open all day is not polled forever.
            if (root.signedIn || authPoll.ticks > 300) {
                authPoll.stop();
                root.waitingOnTerminal = false;
                return;
            }
            PresetStore.refreshAuth();
        }
    }

    Connections {
        target: PresetStore

        function onLoginCodeReady(code, uri, expires): void {
            root.userCode = code;
            root.verificationUri = uri;
            root.errorText = "";
        }

        function onLoginUnavailable(command, reason): void {
            root.fallbackCommand = command;
            root.userCode = "";
        }

        function onLoginFinished(ok, who, error): void {
            root.userCode = "";
            root.errorText = ok ? "" : error;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.signedIn

        MaterialSymbol {
            text: "verified_user"
            iconSize: 18
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Signed in to GitHub as %1").arg(root.login)
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideRight
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: !root.signedIn

        StyledText {
            Layout.fillWidth: true
            text: root.hasGh
                ? Translation.tr("Publishing puts the preset in a repository of your own, so it needs your GitHub account.")
                : Translation.tr("Publishing needs the GitHub CLI. It can be installed and signed in from here, in a terminal — installing it asks for your password.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                visible: root.canUseDeviceFlow
                materialIcon: "login"
                mainText: PresetStore.loggingIn ? Translation.tr("Waiting…")
                                              : Translation.tr("Sign in to GitHub")
                enabled: !PresetStore.loggingIn
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: {
                    root.errorText = "";
                    root.fallbackCommand = "";
                    PresetStore.login();
                }
            }

            RippleButtonWithIcon {
                materialIcon: "terminal"
                mainText: root.waitingOnTerminal
                    ? Translation.tr("Waiting for the terminal…")
                    : (root.hasGh ? Translation.tr("Sign in from a terminal")
                                  : Translation.tr("Install it and sign in"))
                enabled: !root.waitingOnTerminal
                colBackground: root.canUseDeviceFlow ? Appearance.colors.colSurfaceContainerHigh
                                                     : Appearance.colors.colSecondaryContainer
                colBackgroundHover: root.canUseDeviceFlow ? Appearance.colors.colSurfaceContainerHighest
                                                          : Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.setUpInTerminal()
            }

            Item { Layout.fillWidth: true }
        }

        // The code is only worth showing while it is still being waited on.
        Rectangle {
            Layout.fillWidth: true
            visible: root.userCode.length > 0
            implicitHeight: codeColumn.implicitHeight + 24
            radius: Appearance.rounding.small
            color: Appearance.colors.colSecondaryContainer

            ColumnLayout {
                id: codeColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("On any device, open %1 and enter this code:").arg(root.verificationUri)
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSecondaryContainer
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: root.userCode
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    RippleButtonWithIcon {
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy code")
                        onClicked: Quickshell.clipboardText = root.userCode
                    }

                    RippleButtonWithIcon {
                        materialIcon: "close"
                        mainText: Translation.tr("Cancel")
                        onClicked: {
                            PresetStore.cancelLogin();
                            root.userCode = "";
                        }
                    }
                }
            }
        }

        // The same thing the button does, for anyone who would rather type it
        // into a terminal they already have open.
        HelperCodeBox {
            Layout.fillWidth: true
            visible: root.fallbackCommand.length > 0 || !root.canUseDeviceFlow
            icon: "terminal"
            title: Translation.tr("Or run it yourself")
            text: Translation.tr("This build carries no GitHub app of its own, so signing in goes through the GitHub CLI. Run this once, then come back.")
            codeSnippet: root.fallbackCommand.length > 0 ? root.fallbackCommand
                : (root.hasGh ? "gh auth login --scopes repo"
                              : `bash ${Directories.scriptPath}/preset_store_signin.sh`)
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            text: root.errorText
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colError
        }
    }
}
