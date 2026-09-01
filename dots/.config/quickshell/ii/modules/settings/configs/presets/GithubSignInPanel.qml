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

    readonly property bool signedIn: PresetStore.auth.authenticated === true
    readonly property string login: PresetStore.auth.login ?? ""

    Component.onCompleted: PresetStore.refreshAuth()

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
            text: PresetStore.auth.hasGh
                ? Translation.tr("Publishing puts the preset in a repository of your own, so it needs your GitHub account.")
                : Translation.tr("Publishing needs the GitHub CLI. Install the github-cli package, then sign in.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
            wrapMode: Text.Wrap
        }

        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignLeft
            materialIcon: "login"
            mainText: PresetStore.loggingIn ? Translation.tr("Waiting…") : Translation.tr("Sign in to GitHub")
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

        HelperCodeBox {
            Layout.fillWidth: true
            visible: root.fallbackCommand.length > 0
            icon: "terminal"
            title: Translation.tr("Sign in from a terminal")
            text: Translation.tr("This build carries no GitHub app of its own, so signing in goes through the GitHub CLI. Run this once, then come back.")
            codeSnippet: root.fallbackCommand
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
