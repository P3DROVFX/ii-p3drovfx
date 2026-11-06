import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    readonly property var cfg: Config.options.bar.passwordManager

    Component.onCompleted: {
        PasswordManager.detect();
        PasswordManager.refresh();
    }

    function providerLabel(id: string, name: string): string {
        if (id === "auto")
            return name;
        return (PasswordManager.installed?.[id] ?? false) ? name : Translation.tr("%1 (not installed)").arg(name);
    }

    RowLayout {
        spacing: Appearance.rounding.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Passwords")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── What the widget is talking to, right now ─────────────────────────────
    Rectangle {
        id: heroCard
        Layout.fillWidth: true
        implicitHeight: 104
        radius: Appearance.rounding.verylarge
        color: PasswordManager.unlocked ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        readonly property color contentColor: PasswordManager.unlocked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 18

            MaterialShapeWrappedMaterialSymbol {
                implicitSize: 64
                shapeString: PasswordManager.unlocked ? "Cookie7Sided" : PasswordManager.state === "missing" ? "Ghostish" : "Cookie12Sided"
                color: PasswordManager.state === "missing" ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colPrimary
                colSymbol: PasswordManager.state === "missing" ? Appearance.colors.colOnSurface : Appearance.colors.colOnPrimary
                text: PasswordManager.unlocked ? "key" : PasswordManager.state === "missing" ? "key_off" : "lock"
                iconSize: 30
                fill: 1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        switch (PasswordManager.state) {
                        case "unlocked": return Translation.tr("%1 is open").arg(PasswordManager.providerName);
                        case "locked": return Translation.tr("%1 is locked").arg(PasswordManager.providerName);
                        case "unauthenticated": return Translation.tr("Not signed in to %1").arg(PasswordManager.providerName);
                        case "missing": return Translation.tr("No password manager found");
                        default: return Translation.tr("Checking…");
                        }
                    }
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: heroCard.contentColor
                }
                StyledText {
                    Layout.fillWidth: true
                    text: PasswordManager.state === "missing"
                        ? Translation.tr("Install bitwarden-cli (bw), rbw or pass, then come back here")
                        : PasswordManager.unlocked
                            ? Translation.tr("%1 logins · %2").arg(PasswordManager.items.length).arg(PasswordManager.account)
                            : PasswordManager.account
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: heroCard.contentColor
                    opacity: 0.8
                }
            }
        }
    }

    ContentSection {
        icon: "style"
        title: Translation.tr("Style")

        ContentSubsection {
            title: Translation.tr("Visual style")
            icon: "palette"
            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.passwordManager
                onSelected: newValue => Config.options.bar.styles.passwordManager = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "dock_to_bottom", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" }
                ]
            }
        }

        ExpressiveColorModeSubsection {
            visible: Config.options.bar.styles.passwordManager === "expressive"
            currentValue: root.cfg.colorMode
            onSelected: newValue => root.cfg.colorMode = String(newValue)
        }
    }

    ContentSection {
        icon: "passkey"
        title: Translation.tr("Vault")

        ContentSubsection {
            title: Translation.tr("Password manager")
            icon: "key"
            ConfigSelectionArray {
                currentValue: root.cfg.provider
                onSelected: newValue => root.cfg.provider = String(newValue)
                options: [
                    { displayName: Translation.tr("Automatic"), icon: "auto_awesome", value: "auto" },
                    { displayName: root.providerLabel("bitwarden", "Bitwarden"), icon: "shield_lock", value: "bitwarden" },
                    { displayName: root.providerLabel("rbw", "rbw"), icon: "terminal", value: "rbw" },
                    { displayName: root.providerLabel("pass", "pass"), icon: "folder_supervised", value: "pass" }
                ]
            }
        }

        ConfigSpinBox {
            icon: "content_paste_off"
            text: Translation.tr("Clear copied secrets after (seconds, 0 = never)")
            value: root.cfg.clipboardClear
            from: 0
            to: 600
            stepSize: 5
            onValueChanged: root.cfg.clipboardClear = value
        }

        ConfigSpinBox {
            icon: "lock_clock"
            text: Translation.tr("Lock after minutes without use (0 = never)")
            value: root.cfg.autoLock
            from: 0
            to: 480
            stepSize: 5
            onValueChanged: root.cfg.autoLock = value
        }

        ConfigSwitch {
            buttonIcon: "screen_lock_portrait"
            text: Translation.tr("Lock the vault with the screen")
            checked: root.cfg.lockWithScreen
            onCheckedChanged: root.cfg.lockWithScreen = checked
        }

        ConfigSwitch {
            buttonIcon: "web_asset"
            text: Translation.tr("Suggest the login for the focused window")
            checked: root.cfg.suggestForWindow
            onCheckedChanged: root.cfg.suggestForWindow = checked
        }
    }

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Shortcut")

        HelperCodeBox {
            Layout.fillWidth: true
            icon: "keyboard_command_key"
            title: Translation.tr("Open from a keybind")
            text: Translation.tr("Bind this to a key in Hyprland: the popup opens on the focused monitor with the search ready. Enter copies the password, Shift+Enter the username, Ctrl+T the 2FA code, Ctrl+Enter types the login (needs wtype).")
            codeSnippet: "qs -c ii ipc call passwordManager toggle"
        }
    }
}
