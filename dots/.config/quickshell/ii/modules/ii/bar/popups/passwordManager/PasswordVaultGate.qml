pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Everything before the vault is open: no CLI, signed out, locked.
 *
 * One shape carries the state (circle while checking, Cookie12 locked,
 * Clover signed out, Ghostish with nothing installed, SoftBurst on a wrong
 * password) and morphs between them; the only control is the one that gets
 * the person further — a password field, an unlock button or a sign-in.
 */
ColumnLayout {
    id: root

    property int contentWidth: 360
    readonly property string vaultState: PasswordManager.state
    readonly property bool failed: PasswordManager.errorText.length > 0
    readonly property bool unlocking: PasswordManager.busy && PasswordManager.busyAction === "unlock"
    // Each key of the master password, so the popup holds open while typing.
    signal typedKey()
    readonly property bool wantsPassword: root.vaultState === "locked" && PasswordManager.needsPassword

    spacing: 0

    function focusField(): void {
        if (root.wantsPassword)
            passwordInput.forceActiveFocus();
    }

    function submit(): void {
        if (root.unlocking)
            return;
        if (root.vaultState === "locked") {
            PasswordManager.unlock(passwordInput.text);
            passwordInput.text = "";
        } else if (root.vaultState === "unauthenticated") {
            PasswordManager.openLoginTerminal();
        }
    }

    Connections {
        target: PasswordManager
        function onErrorSerialChanged() {
            if (root.visible)
                shake.restart();
        }
    }

    // ── The state shape ──────────────────────────────────────────────────────
    MaterialShape {
        id: hero
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 14
        implicitSize: 104
        shapeString: {
            if (root.failed && root.vaultState === "locked")
                return "SoftBurst";
            switch (root.vaultState) {
            case "locked": return "Cookie12Sided";
            case "unauthenticated": return "Clover4Leaf";
            case "missing": return "Ghostish";
            default: return "Circle";
            }
        }
        color: (root.failed && root.vaultState === "locked") ? Appearance.colors.colErrorContainer
            : root.vaultState === "missing" ? Appearance.colors.colSurfaceContainerHighest
            : Appearance.colors.colPrimary

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: !root.unlocking
            text: {
                if (root.failed && root.vaultState === "locked")
                    return "password";
                switch (root.vaultState) {
                case "locked": return "lock";
                case "unauthenticated": return "person";
                case "missing": return "key_off";
                default: return "key";
                }
            }
            iconSize: 44
            fill: 1
            color: (root.failed && root.vaultState === "locked") ? Appearance.colors.colOnErrorContainer
                : root.vaultState === "missing" ? Appearance.colors.colOnSurface
                : Appearance.colors.colOnPrimary
        }

        MaterialLoadingIndicator {
            anchors.centerIn: parent
            visible: root.unlocking || root.vaultState === "unknown"
            loading: visible
            implicitSize: 64
            shapeColor: Appearance.colors.colOnPrimary
        }
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 16
        text: {
            switch (root.vaultState) {
            case "locked": return root.unlocking ? Translation.tr("Unlocking…") : Translation.tr("Vault locked");
            case "unauthenticated": return Translation.tr("Not signed in");
            case "missing": return Translation.tr("No password manager");
            default: return Translation.tr("Checking vault…");
            }
        }
        font.family: Appearance.font.family.title
        font.variableAxes: Appearance.font.variableAxes.titleRounded
        font.pixelSize: Appearance.font.pixelSize.huge + 4
        color: Appearance.colors.colOnSurface
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 2
        Layout.maximumWidth: root.contentWidth - 24
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: {
            switch (root.vaultState) {
            case "missing": return Translation.tr("Install bitwarden-cli, rbw or pass");
            case "unauthenticated": return Translation.tr("Sign in once from a terminal — US, EU or self-hosted");
            default: {
                const who = PasswordManager.account.length > 0 ? PasswordManager.account : PasswordManager.providerName;
                return PasswordManager.server.length > 0 ? `${who} · ${PasswordManager.server}` : who;
            }
            }
        }
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    // ── Master password field (bw) ───────────────────────────────────────────
    Rectangle {
        id: field
        visible: root.wantsPassword
        Layout.preferredWidth: root.contentWidth
        Layout.topMargin: 20
        implicitHeight: 56
        radius: height / 2
        color: Appearance.colors.colSurfaceContainerHighest

        ErrorShakeAnimation {
            id: shake
            target: field
            distance: 14
        }

        MaterialSymbol {
            id: fieldIcon
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: "password"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledTextInput {
            id: passwordInput
            anchors.left: fieldIcon.right
            anchors.leftMargin: 12
            anchors.right: unlockButton.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            echoMode: TextInput.Password
            passwordCharacter: "•"
            enabled: !root.unlocking
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.normal
            clip: true
            onTextEdited: {
                root.typedKey();
                if (root.failed)
                    PasswordManager.clearError();
            }
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: passwordInput.text.length === 0
                text: Translation.tr("Master password")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }
        }

        RippleButton {
            id: unlockButton
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 44
            implicitHeight: 44
            // Circle at rest, rounded square while it works.
            buttonRadius: root.unlocking ? Appearance.rounding.normal : Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            enabled: !root.unlocking
            onClicked: root.submit()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_forward"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    // ── rbw unlock / sign-in buttons ─────────────────────────────────────────
    RippleButton {
        visible: (root.vaultState === "locked" && !PasswordManager.needsPassword) || root.vaultState === "unauthenticated"
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 20
        implicitHeight: 48
        implicitWidth: buttonLabel.implicitWidth + 56
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        enabled: !root.unlocking
        onClicked: root.submit()

        RowLayout {
            id: buttonLabel
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                text: root.vaultState === "unauthenticated" ? "terminal" : "lock_open"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnPrimary
            }
            StyledText {
                text: root.vaultState === "unauthenticated" ? Translation.tr("Sign in") : Translation.tr("Unlock")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    // The failure, in words.
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 10
        Layout.maximumWidth: root.contentWidth - 24
        // Faded in place, so a wrong password never changes the popup's height.
        visible: root.vaultState === "locked" || root.failed
        opacity: root.failed ? 1 : 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: PasswordManager.errorCode === "auth" && root.vaultState === "locked"
            ? Translation.tr("Wrong master password")
            : (PasswordManager.errorText.length > 0 ? PasswordManager.errorText : " ")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colError
    }

    Item {
        Layout.preferredHeight: 6
    }
}
