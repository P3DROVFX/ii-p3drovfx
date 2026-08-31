import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.network

/**
 * Wired tab of the Network page: the Ethernet ports themselves, the profiles
 * saved for them, and the addressing of whichever one is up.
 *
 * The tab only exists while a wired device does, so nothing here has to explain
 * a machine with no socket. What it does have to explain is a socket that is
 * present and still carrying nothing, which is the normal wired failure.
 */
ContentPage {
    id: root
    forceWidth: false

    // Sub-pages belong to the page that owns the tab bar, not to a tab that is
    // unloaded the moment someone switches away from it.
    signal openSubPage(url page)

    property var ipConfig: ({})

    readonly property string ifname: NetworkState.wiredInterface
    readonly property bool anyLink: NetworkState.wiredHasLink
    readonly property bool anyUnmanaged: NetworkState.wiredDevices.some(device => !device.nmManaged)

    function editProfile(uuid: string): void {
        NetworkProfiles.editUuid = uuid;
        root.openSubPage(Qt.resolvedUrl("WiredProfileEditor.qml"));
    }

    function refreshIp(): void {
        if (!NetworkState.wiredConnected) {
            root.ipConfig = ({});
            return;
        }
        NetworkCommands.readIpConfig(root.ifname, config => root.ipConfig = config);
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

    Connections {
        target: NetworkState

        function onWiredConnectedChanged(): void {
            root.refreshIp();
        }
    }

    Component.onCompleted: root.refreshIp()

    ContentSection {
        id: portSection
        icon: "settings_ethernet"
        title: Translation.tr("Ethernet ports")

        // Held here rather than in the row so an open port survives the list
        // being rebuilt when a cable moves.
        property string expandedName: ""

        NoticeBox {
            Layout.fillWidth: true
            visible: !NetworkState.backendAvailable
            materialIcon: "error"
            text: Translation.tr("NetworkManager is not running, so none of this page can act. Start it with `systemctl enable --now NetworkManager`.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: NetworkState.backendAvailable && !NetworkState.hasWiredDevice
            materialIcon: "cable"
            text: Translation.tr("The wired port is gone. A USB or dock adapter was unplugged, or its driver was unloaded.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: NetworkState.hasWiredDevice && !root.anyLink
            materialIcon: "power_off"
            text: Translation.tr("No cable is plugged in. The port is there and working — nothing is on the other end of it.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.anyUnmanaged
            materialIcon: "block"
            text: Translation.tr("A port is set to unmanaged, so NetworkManager will not address it no matter which profile is saved for it. Open the port below to hand it back.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: NetworkState.wiredConnected && NetworkState.limited
            materialIcon: "public_off"
            text: Translation.tr("The cable is up and carrying traffic, but nothing on the far side is answering for the internet. %1.").arg(NetworkState.connectivityLabel(NetworkState.connectivity))
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                id: portRepeater
                model: ScriptModel {
                    values: NetworkState.wiredDevices
                    objectProp: "name"
                }

                delegate: WiredDeviceRow {
                    required property var modelData
                    required property int index

                    device: modelData
                    isFirst: index === 0
                    isLast: index === portRepeater.count - 1
                    expanded: portSection.expandedName === modelData.name
                    onToggleRequested: {
                        portSection.expandedName = portSection.expandedName === modelData.name
                            ? "" : modelData.name;
                    }
                }
            }
        }
    }

    ContentSection {
        id: savedSection
        icon: "bookmark"
        title: Translation.tr("Saved connections")

        property string expandedUuid: ""

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("NetworkManager makes a default profile the first time a cable appears, so a port that just works usually has one here already. A second profile is worth having when a particular network needs a fixed address or 802.1X.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: NetworkProfiles.wiredProfiles.length === 0 ? Translation.tr("Nothing saved yet")
                    : Translation.tr("%1 saved").arg(NetworkProfiles.wiredProfiles.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButtonWithIcon {
                materialIcon: "add"
                mainText: Translation.tr("Add connection")
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
                    values: NetworkProfiles.wiredProfiles
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
    }

    ContentSection {
        icon: "lan"
        title: Translation.tr("Addressing")
        visible: NetworkState.wiredConnected

        InfoRow {
            label: Translation.tr("Connection")
            value: NetworkState.wiredNetwork?.name ?? ""
        }

        InfoRow {
            label: Translation.tr("Port")
            value: root.ifname
        }

        InfoRow {
            label: Translation.tr("Link speed")
            value: NetworkState.wiredLinkSpeed > 0
                ? Translation.tr("%1 Mb/s").arg(NetworkState.wiredLinkSpeed) : ""
        }

        InfoRow {
            label: Translation.tr("IPv4 address")
            value: root.ipConfig.address ?? ""
        }

        InfoRow {
            label: Translation.tr("Subnet mask")
            value: NetworkCommands.prefixToMask(root.ipConfig.prefix ?? 0)
        }

        InfoRow {
            label: Translation.tr("Gateway")
            value: root.ipConfig.gateway ?? ""
        }

        InfoRow {
            label: Translation.tr("DNS")
            value: (root.ipConfig.dns ?? []).join(" / ")
        }

        InfoRow {
            label: Translation.tr("IPv6 address")
            value: root.ipConfig.address6 ?? ""
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            RippleButtonWithIcon {
                materialIcon: "refresh"
                mainText: Translation.tr("Refresh")
                onClicked: root.refreshIp()
            }

            RippleButtonWithIcon {
                enabled: (root.ipConfig.address ?? "").length > 0
                materialIcon: "content_copy"
                mainText: Translation.tr("Copy address")
                onClicked: Quickshell.clipboardText = root.ipConfig.address
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
