import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.network

/**
 * Wi-Fi tab of the Network page: radio state, the scan list with everything a
 * network can be asked to do, hidden-network entry, and the addressing of the
 * current connection.
 */
ContentPage {
    id: root
    forceWidth: false

    property bool hiddenOpen: false

    // The network in use has its own section above the scan list, so the list
    // is everything except it. Read through Array.from: the service hands out a
    // QML list, which does not reliably answer to the JS array methods.
    readonly property var otherNetworks: Array.from(Network.friendlyWifiNetworks)
        .filter(network => network && !network.active)

    // Sub-pages belong to the page that owns the tab bar, not to a tab that is
    // unloaded the moment someone switches away from it.
    signal openSubPage(url page)

    function editProfile(uuid: string): void {
        NetworkProfiles.editUuid = uuid;
        root.openSubPage(Qt.resolvedUrl("WifiProfileEditor.qml"));
    }

    component InfoRow: RowLayout {
        id: infoRow
        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        visible: infoRow.value.length > 0
        spacing: 12

        StyledText {
            Layout.preferredWidth: 150
            text: infoRow.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: infoRow.value
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
        }
    }

    ContentSection {
        icon: "wifi"
        title: Translation.tr("Wi-Fi")

        NoticeBox {
            Layout.fillWidth: true
            visible: !NetworkState.backendAvailable
            materialIcon: "error"
            text: Translation.tr("NetworkManager is not running, so none of this page can act. Start it with `systemctl enable --now NetworkManager`.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: NetworkState.backendAvailable && !NetworkState.hasWifiDevice
            materialIcon: "wifi_off"
            text: Translation.tr("No Wi-Fi adapter is available. Either the machine has none, or its driver did not load.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: NetworkState.hasWifiDevice && !NetworkState.wifiHardwareEnabled
            materialIcon: "airplanemode_active"
            text: Translation.tr("Wi-Fi is blocked in hardware — by a physical switch, a keyboard toggle, or airplane mode. Software cannot lift that block.")
        }

        ConfigSwitch {
            id: radioSwitch
            buttonIcon: "wifi"
            text: Translation.tr("Enable Wi-Fi")
            enabled: NetworkState.hasWifiDevice && NetworkState.wifiHardwareEnabled
            checked: Network.wifiEnabled
            // The service owns this state, so the switch has to be handed its
            // binding back after the click that broke it.
            onCheckedChanged: {
                if (checked === Network.wifiEnabled)
                    return;
                Network.enableWifi(checked);
                checked = Qt.binding(() => Network.wifiEnabled);
            }
        }

        InfoRow {
            label: Translation.tr("Adapter")
            value: NetworkState.wifiInterface
        }

        InfoRow {
            label: Translation.tr("Hardware address")
            value: NetworkState.wifiMac
        }
    }

    ContentSection {
        icon: "link"
        title: Translation.tr("Connected network")
        visible: Network.wifiEnabled && Network.active !== null

        Loader {
            Layout.fillWidth: true
            active: Network.active !== null
            sourceComponent: Component {
                WifiNetworkRow {
                    accessPoint: Network.active
                    isFirst: true
                    isLast: true
                }
            }
        }
    }

    ContentSection {
        icon: "wifi_find"
        title: Translation.tr("Available networks")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: Network.wifiScanning ? Translation.tr("Scanning…")
                    : Translation.tr("%1 networks in range").arg(root.otherNetworks.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButtonWithIcon {
                enabled: Network.wifiEnabled && !Network.wifiScanning
                materialIcon: "refresh"
                mainText: Translation.tr("Scan")
                onClicked: Network.rescanWifi()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: Network.wifiEnabled
            spacing: 4

            Repeater {
                id: networkRepeater
                model: ScriptModel {
                    values: root.otherNetworks
                }

                delegate: WifiNetworkRow {
                    required property WifiAccessPoint modelData
                    required property int index

                    accessPoint: modelData
                    isFirst: index === 0
                    isLast: index === networkRepeater.count - 1
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 8
            horizontalAlignment: Text.AlignHCenter
            visible: Network.wifiEnabled && !Network.wifiScanning && root.otherNetworks.length === 0
            text: Translation.tr("No networks found.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        id: savedSection
        icon: "bookmark"
        title: Translation.tr("Saved networks")

        // Held here rather than in the row: the list is rebuilt after every
        // write, and an open row should survive that.
        property string expandedUuid: ""

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: NetworkProfiles.wifiProfiles.length === 0 ? Translation.tr("Nothing saved yet")
                    : Translation.tr("%1 saved").arg(NetworkProfiles.wifiProfiles.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButtonWithIcon {
                materialIcon: "add"
                mainText: Translation.tr("Add network")
                colBackground: Appearance.colors.colPrimary
                colText: Appearance.colors.colOnPrimary
                onClicked: root.editProfile("")
            }

            RippleButtonWithIcon {
                enabled: !NetworkProfiles.loading
                materialIcon: "refresh"
                mainText: Translation.tr("Refresh")
                onClicked: NetworkProfiles.refresh()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                id: savedRepeater
                model: ScriptModel {
                    values: NetworkProfiles.wifiProfiles
                    objectProp: "uuid"
                }

                delegate: SavedNetworkRow {
                    required property var modelData
                    required property int index

                    profile: modelData
                    isFirst: index === 0
                    isLast: index === savedRepeater.count - 1
                    expanded: savedSection.expandedUuid === modelData.uuid
                    onToggleRequested: {
                        savedSection.expandedUuid = savedSection.expandedUuid === modelData.uuid
                            ? "" : modelData.uuid;
                    }
                    onEditRequested: root.editProfile(modelData.uuid)
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 8
            horizontalAlignment: Text.AlignHCenter
            visible: NetworkProfiles.loadedOnce && NetworkProfiles.wifiProfiles.length === 0
            text: Translation.tr("Networks you join are saved here so they can be edited later.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "visibility_off"
        title: Translation.tr("Hidden network")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("A network that does not broadcast its name never appears in a scan. Type the name exactly as it was configured — it is case sensitive.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        MaterialTextField {
            id: hiddenSsid
            Layout.fillWidth: true
            placeholderText: Translation.tr("Network name (SSID)")
        }

        MaterialTextField {
            id: hiddenIdentity
            Layout.fillWidth: true
            placeholderText: Translation.tr("Identity (802.1X only, leave empty otherwise)")
        }

        MaterialTextField {
            id: hiddenPassword
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: Translation.tr("Password")
            onAccepted: root.joinHidden()
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.fillWidth: true
            }

            RippleButtonWithIcon {
                enabled: hiddenSsid.text.length > 0 && Network.wifiEnabled
                materialIcon: "add_link"
                mainText: Translation.tr("Join")
                colBackground: Appearance.colors.colPrimary
                colText: Appearance.colors.colOnPrimary
                onClicked: root.joinHidden()
            }
        }
    }

    ContentSection {
        icon: "lan"
        title: Translation.tr("Connection details")
        visible: Network.wifiStatus === "connected" || Network.wifiStatus === "limited"

        NoticeBox {
            Layout.fillWidth: true
            visible: Network.captivePortal
            materialIcon: "captive_portal"
            text: Translation.tr("This network wants you to sign in before it lets any traffic through.")

            RippleButtonWithIcon {
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open sign-in page")
                onClicked: Network.openPublicWifiPortal()
            }
        }

        InfoRow {
            label: Translation.tr("Network")
            value: Network.networkName
        }

        InfoRow {
            label: Translation.tr("Security")
            value: Network.active?.security ?? ""
        }

        InfoRow {
            label: Translation.tr("Band")
            value: {
                const frequency = Network.active?.frequency ?? 0;
                if (frequency <= 0)
                    return "";
                return Translation.tr("%1 (%2 MHz)").arg(Network.active?.bandLabel ?? "").arg(frequency);
            }
        }

        InfoRow {
            label: Translation.tr("Signal")
            value: Network.networkStrength > 0 ? `${Network.networkStrength}%` : ""
        }

        InfoRow {
            label: Translation.tr("Access point")
            value: Network.active?.bssid ?? ""
        }

        InfoRow {
            label: Translation.tr("IPv4 address")
            value: Network.ipAddress
        }

        InfoRow {
            label: Translation.tr("Subnet mask")
            value: Network.subnetMask
        }

        InfoRow {
            label: Translation.tr("Gateway")
            value: Network.gateway
        }

        InfoRow {
            label: Translation.tr("DNS")
            value: Network.dns
        }

        InfoRow {
            label: Translation.tr("IPv6 address")
            value: Network.ipAddress6
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            RippleButtonWithIcon {
                materialIcon: "link_off"
                mainText: Translation.tr("Disconnect")
                onClicked: Network.disconnectWifiNetwork()
            }

            RippleButtonWithIcon {
                materialIcon: "content_copy"
                mainText: Translation.tr("Copy address")
                enabled: Network.ipAddress.length > 0
                onClicked: Quickshell.clipboardText = Network.ipAddress
            }
        }
    }

    function joinHidden(): void {
        if (hiddenSsid.text.length === 0)
            return;
        Network.connectToHiddenNetwork(hiddenSsid.text, hiddenPassword.text, hiddenIdentity.text);
        hiddenPassword.text = "";
    }
}
