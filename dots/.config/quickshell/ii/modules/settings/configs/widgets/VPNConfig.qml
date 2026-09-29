import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    RowLayout {
        visible: root.showBackButton
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("VPN Configuration")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "vpn_lock"
        title: Translation.tr("VPN Management & Protocols")

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            text: Translation.tr("Supported VPN backends: NetworkManager profiles (OpenVPN and WireGuard), NordVPN CLI, and Proton VPN CLI when installed. Credentials stay in the provider or system keyring; they are never saved to config.json.")
        }

        ConfigSwitch {
            buttonIcon: "link_off"
            text: Translation.tr("Disconnect VPN when integration is disabled")
            checked: Config.options.vpn.disconnectOnDisable
            onCheckedChanged: Config.options.vpn.disconnectOnDisable = checked
            StyledToolTip { text: Translation.tr("Disconnects the active provider/profile when VPN integration is turned off. NetworkManager itself remains running.") }
        }

        ConfigSwitch {
            buttonIcon: "autorenew"
            text: Translation.tr("Connect VPN automatically")
            checked: Config.options.vpn.autoConnect
            onCheckedChanged: Config.options.vpn.autoConnect = checked
            StyledToolTip {
                text: Translation.tr("Automatically connects to default profile upon shell startup or network availability.")
            }
        }

        ContentSubsectionLabel { text: Translation.tr("Provider & Profiles") }

        ConfigSelectionArray {
            Layout.fillWidth: true
            options: [
                { displayName: Translation.tr("NetworkManager"), icon: "lan", value: "networkmanager" },
                { displayName: Translation.tr("NordVPN"), icon: "vpn_key", value: "nordvpn", enabled: VpnService.nordvpnAvailable },
                { displayName: Translation.tr("Proton VPN"), icon: "vpn_key", value: "protonvpn", enabled: VpnService.protonvpnAvailable }
            ]
            currentValue: Config.options.vpn.defaultProvider
            onSelected: value => Config.options.vpn.defaultProvider = value
        }

        ConfigTextField {
            icon: "bookmark"
            text: Translation.tr("Default VPN profile")
            placeholderText: Translation.tr("Choose a profile in the VPN dialog")
            inputText: Config.options.vpn.defaultProfile
            textField.onTextChanged: Config.options.vpn.defaultProfile = textField.text
        }

        ConfigTextField {
            icon: "location_on"
            text: Translation.tr("Default VPN location")
            placeholderText: Translation.tr("Country code or name for NordVPN/Proton VPN (e.g. CH), or a profile name")
            inputText: Config.options.vpn.defaultLocation
            textField.onTextChanged: Config.options.vpn.defaultLocation = textField.text
        }

        ConfigSwitch {
            buttonIcon: "shield_lock"
            text: Translation.tr("Proton VPN Secure Core")
            description: Translation.tr("Routes through a Secure Core server first; the default location becomes the exit country")
            enabled: VpnService.protonvpnAvailable
            checked: Config.options.vpn.protonSecureCore
            onCheckedChanged: Config.options.vpn.protonSecureCore = checked
        }

        ContentSubsectionLabel { text: Translation.tr("Advanced Security") }

        ConfigSwitch {
            buttonIcon: "security"
            text: VpnService.killSwitchSupported ? Translation.tr("Proton VPN kill switch") : Translation.tr("VPN kill switch (unsupported by backend)")
            description: !VpnService.killSwitchSupported ? ""
                : VpnService.protonConnected ? Translation.tr("Disconnect Proton VPN to change it")
                : Translation.tr("Blocks the internet if the VPN drops; disconnecting on purpose restores it")
            enabled: VpnService.killSwitchSupported && !VpnService.protonConnected && !VpnService.killSwitchPending
            checked: VpnService.killSwitchEnabled
            // Proton's settings own this state, so hand the binding back after the click.
            onCheckedChanged: {
                if (checked === VpnService.killSwitchEnabled)
                    return;
                VpnService.setKillSwitch(checked);
                checked = Qt.binding(() => VpnService.killSwitchEnabled);
            }
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: !VpnService.staleSocketHookInstalled || VpnService.staleSocketHookOutdated
            topLeftRadius: Appearance.rounding.large
            topRightRadius: Appearance.rounding.large
            bottomLeftRadius: Appearance.rounding.large
            bottomRightRadius: Appearance.rounding.large
            icon: "sync_problem"
            title: VpnService.staleSocketHookOutdated ? Translation.tr("The connection reset hook is out of date")
                : Translation.tr("Reset connections when the VPN changes")
            text: Translation.tr("Connections opened before a VPN connects, disconnects or switches server stay tied to the old address and hang until the app gives up, which many apps report as having no internet. This NetworkManager hook resets them so apps reconnect at once. It runs as root, only when a VPN goes up or down.")
            codeSnippet: VpnService.staleSocketHookInstallCommand
            actionText: VpnService.staleSocketHookOutdated ? Translation.tr("Update it now") : Translation.tr("Install it now")
            actionIcon: "download"
            actionBusy: VpnService.staleSocketHookInstalling
            busyText: Translation.tr("Installing…")
            statusIsError: VpnService.staleSocketHookResult === "failed" || VpnService.staleSocketHookResult === "cancelled"
            statusText: VpnService.staleSocketHookResult === "failed" ? Translation.tr("Installation failed")
                : VpnService.staleSocketHookResult === "cancelled" ? Translation.tr("Authentication was cancelled")
                : ""
            onActionClicked: VpnService.installStaleSocketHook()
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: VpnService.staleSocketHookInstalled && !VpnService.staleSocketHookOutdated
            topLeftRadius: Appearance.rounding.large
            topRightRadius: Appearance.rounding.large
            bottomLeftRadius: Appearance.rounding.large
            bottomRightRadius: Appearance.rounding.large
            icon: "check_circle"
            title: Translation.tr("Connections are reset when the VPN changes")
            text: Translation.tr("Connections a VPN change leaves hanging are reset automatically. To remove the hook, run:")
            codeSnippet: VpnService.staleSocketHookRemoveCommand
        }

        ConfigSwitch {
            buttonIcon: "lan"
            text: VpnService.blockLanSupported ? Translation.tr("Block local network while VPN is active") : Translation.tr("Block local network (unsupported by backend)")
            checked: Config.options.vpn.blockLan
            enabled: VpnService.blockLanSupported
            onCheckedChanged: Config.options.vpn.blockLan = checked
        }

        ConfigSwitch {
            buttonIcon: "troubleshoot"
            text: Translation.tr("Enable VPN diagnostics")
            checked: Config.options.vpn.enableDiagnostics
            onCheckedChanged: Config.options.vpn.enableDiagnostics = checked
        }

        TipBox {
            Layout.fillWidth: true
            materialIcon: "help"
            text: Translation.tr("VPN Setup: Make sure NetworkManager VPN plugins (nmcli) or WireGuard interfaces are installed. Click/Right-click the Quick Toggle to connect or select profiles.")
        }
    }
}
