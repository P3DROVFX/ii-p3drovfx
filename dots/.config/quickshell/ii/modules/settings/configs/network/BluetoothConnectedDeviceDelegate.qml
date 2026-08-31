pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.settings.configs.network

Item {
    id: root

    required property BluetoothDevice modelData
    required property int index
    property bool isFirst: false
    property bool isLast: false

    readonly property BluetoothDevice device: modelData
    readonly property bool isBudsLink: EarbudsControlService.providerForDevice(root.device) === "budslink" &&
        (!Config.ready || !Config.options?.bluetooth?.budsLink || Config.options.bluetooth.budsLink.showEnhancedSettingsCard !== false)

    Layout.fillWidth: true
    implicitHeight: currentCard ? currentCard.implicitHeight : 58

    property var currentCard: isBudsLink ? budsLinkCardLoader.item : genericRowLoader.item

    Loader {
        id: budsLinkCardLoader
        anchors.left: parent.left
        anchors.right: parent.right
        active: root.isBudsLink
        visible: active
        sourceComponent: BudsLinkBluetoothDeviceCard {
            device: root.device
            isFirst: root.isFirst
            isLast: root.isLast
        }
    }

    Loader {
        id: genericRowLoader
        anchors.left: parent.left
        anchors.right: parent.right
        active: !root.isBudsLink
        visible: active
        sourceComponent: BluetoothDeviceRow {
            device: root.device
            isFirst: root.isFirst
            isLast: root.isLast
        }
    }
}
