import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.network

/**
 * Bluetooth tab of the Network page: the radio and every device the adapter
 * knows about or can currently see.
 *
 * Pairing questions are never asked here. They arrive whether or not this page
 * is open, so they are always put to the user in the shell-wide prompt instead
 * of appearing halfway down a settings page they may not be looking at.
 *
 * Scanning runs only while this tab is on screen. Discovery keeps the radio
 * busy and drains battery, so it starts when the tab loads and stops when it
 * goes away.
 */
ContentPage {
    id: root
    forceWidth: false

    Component.onCompleted: BluetoothStatus.startDiscovery()
    Component.onDestruction: BluetoothStatus.stopDiscovery()

    // The adapter may still have been powering on when the tab appeared, in
    // which case the scan above was refused and has to be started again.
    Connections {
        target: BluetoothStatus
        function onEnabledChanged() {
            if (BluetoothStatus.enabled)
                BluetoothStatus.startDiscovery();
        }
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
        icon: "bluetooth"
        title: Translation.tr("Bluetooth")

        NoticeBox {
            Layout.fillWidth: true
            visible: !BluetoothStatus.available
            materialIcon: "bluetooth_disabled"
            text: Translation.tr("No Bluetooth adapter is available. Either the machine has none, or its driver did not load.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: BluetoothStatus.available && BluetoothStatus.hardBlocked
            materialIcon: "airplanemode_active"
            text: Translation.tr("Bluetooth is blocked in hardware — by a physical switch, a keyboard toggle, or airplane mode. Software cannot lift that block.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: BluetoothStatus.available && BluetoothAgent.lastError.length > 0
            materialIcon: "key_off"
            text: Translation.tr("The pairing helper could not start, so devices that ask for a code cannot be paired from here. %1").arg(BluetoothAgent.lastError)
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: BluetoothAgent.ready && !BluetoothAgent.isDefaultAgent
            materialIcon: "info"
            text: Translation.tr("Another program is already handling pairing requests. Codes may be asked for there instead of by the shell.")
        }

        // Contextual BudsLink notices (Plan Section 35)
        NoticeBox {
            Layout.fillWidth: true
            visible: BudsLinkService.hasAudioCandidate && !BudsLinkService.serviceAvailable &&
                (!Config.ready || !Config.options?.bluetooth?.budsLink || Config.options.bluetooth.budsLink.showIntegrationNotices !== false)
            materialIcon: "headphones"
            text: Translation.tr("Enhanced earbud controls are available with BudsLink. Install BudsLink to see individual earbud battery and supported audio controls.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: BudsLinkService.serviceAvailable && !BudsLinkService.serviceCompatible
            materialIcon: "warning"
            text: Translation.tr("BudsLink was detected, but its desktop-integration interface is not compatible with this version of ii. Generic Bluetooth controls will continue to work.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: BudsLinkService.lastErrorCode === "serviceDisconnected" || BudsLinkService.lastErrorCode === "bridgeFailed"
            materialIcon: "sync_problem"
            text: Translation.tr("BudsLink stopped responding. ii is temporarily using standard Bluetooth information for this device.")
        }

        ConfigSwitch {
            id: radioSwitch
            buttonIcon: "bluetooth"
            text: Translation.tr("Enable Bluetooth")
            enabled: BluetoothStatus.available && !BluetoothStatus.hardBlocked
            checked: BluetoothStatus.enabled
            // The adapter owns this state, so the switch has to be handed its
            // binding back after the click that broke it.
            onCheckedChanged: {
                if (checked === BluetoothStatus.enabled)
                    return;
                BluetoothStatus.setEnabled(checked);
                checked = Qt.binding(() => BluetoothStatus.enabled);
            }
        }

        ConfigSwitch {
            buttonIcon: "visibility"
            text: Translation.tr("Visible to other devices")
            enabled: BluetoothStatus.enabled
            checked: BluetoothStatus.adapter?.discoverable ?? false
            onCheckedChanged: {
                const adapter = BluetoothStatus.adapter;
                if (!adapter || checked === adapter.discoverable)
                    return;
                adapter.discoverable = checked;
                checked = Qt.binding(() => BluetoothStatus.adapter?.discoverable ?? false);
            }
        }

        InfoRow {
            label: Translation.tr("Adapter")
            value: {
                const id = BluetoothStatus.adapterId;
                const name = BluetoothStatus.adapterName;
                if (id.length === 0)
                    return name;
                return name.length > 0 ? `${name} (${id})` : id;
            }
        }

        InfoRow {
            label: Translation.tr("Hardware address")
            value: BluetoothStatus.adapterAddress
        }
    }

    ContentSection {
        icon: "bluetooth_connected"
        title: Translation.tr("Connected")
        visible: connectedRepeater.count > 0

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                id: connectedRepeater
                model: ScriptModel {
                    values: BluetoothStatus.connectedDevices
                }

                delegate: BluetoothConnectedDeviceDelegate {
                    isFirst: index === 0
                    isLast: index === connectedRepeater.count - 1
                }
            }
        }
    }

    ContentSection {
        icon: "bluetooth_searching"
        title: Translation.tr("Nearby devices")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: BluetoothStatus.discovering ? Translation.tr("Scanning…")
                    : Translation.tr("%1 devices in range").arg(nearbyRepeater.count)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButtonWithIcon {
                enabled: BluetoothStatus.enabled
                materialIcon: BluetoothStatus.discovering ? "stop" : "refresh"
                mainText: BluetoothStatus.discovering ? Translation.tr("Stop")
                    : Translation.tr("Scan")
                onClicked: {
                    if (BluetoothStatus.discovering)
                        BluetoothStatus.stopDiscovery();
                    else
                        BluetoothStatus.startDiscovery();
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: BluetoothStatus.enabled
            spacing: 4

            Repeater {
                id: nearbyRepeater
                model: ScriptModel {
                    values: BluetoothStatus.unpairedDevices
                }

                delegate: BluetoothDeviceRow {
                    required property BluetoothDevice modelData
                    required property int index

                    device: modelData
                    isFirst: index === 0
                    isLast: index === nearbyRepeater.count - 1
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 8
            horizontalAlignment: Text.AlignHCenter
            visible: BluetoothStatus.enabled && nearbyRepeater.count === 0
            text: Translation.tr("Nothing new found yet. Put the other device in pairing mode.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "devices"
        title: Translation.tr("Paired devices")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                id: pairedRepeater
                model: ScriptModel {
                    values: BluetoothStatus.pairedButNotConnectedDevices
                }

                delegate: BluetoothDeviceRow {
                    required property BluetoothDevice modelData
                    required property int index

                    device: modelData
                    isFirst: index === 0
                    isLast: index === pairedRepeater.count - 1
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: pairedRepeater.count === 0
            text: connectedRepeater.count > 0 ? Translation.tr("Everything paired is connected.")
                : Translation.tr("No devices are paired yet.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
