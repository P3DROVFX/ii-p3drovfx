import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool vertical: false

    readonly property var activeDevices: BluetoothStatus.connectedDevices
    property int deviceIndex: 0
    readonly property var primaryDevice: activeDevices.length > 0 ? activeDevices[deviceIndex % activeDevices.length] : null
    readonly property bool hasDevices: activeDevices.length > 0

    onHasDevicesChanged: {
        if (typeof rootItem !== "undefined" && typeof rootItem.toggleVisible === "function")
            rootItem.toggleVisible(hasDevices);
    }

    Connections {
        target: BluetoothStatus
        function onConnectedDevicesChanged() {
            if (typeof rootItem !== "undefined" && typeof rootItem.toggleVisible === "function")
                rootItem.toggleVisible(BluetoothStatus.connectedDevices.length > 0);
        }
    }

    Component.onCompleted: {
        if (typeof rootItem !== "undefined" && typeof rootItem.toggleVisible === "function")
            rootItem.toggleVisible(hasDevices);
    }

    visible: hasDevices
    implicitWidth: hasDevices ? chip.implicitWidth : 0
    implicitHeight: hasDevices ? Appearance.sizes.baseBarHeight : 0

    

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    // Cycle through devices on click
    onClicked: {
        if (activeDevices.length > 1) {
            deviceIndex = (deviceIndex + 1) % activeDevices.length
        }
    }

    // Reset index if device list changes
    onActiveDevicesChanged: {
        if (deviceIndex >= activeDevices.length) {
            deviceIndex = 0
        }
    }

    property bool activated: root.hasDevices

    // Chip container - background is now handled dynamically by BarComponent
    Item {
        id: chip
        anchors.centerIn: parent
        implicitWidth: layout.implicitWidth + 28
        implicitHeight: Appearance.sizes.baseBarHeight - 6

        RowLayout {
            id: layout
            anchors.centerIn: parent
            spacing: 10

            // Device icon - shows bluetooth_disabled when no devices
            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: root.hasDevices ? Icons.getBluetoothDeviceMaterialSymbol(root.primaryDevice.icon) : "bluetooth_disabled"
                color: root.hasDevices ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            }

            // Device name (only visible when connected)
            StyledText {
                visible: root.hasDevices
                text: root.primaryDevice ? root.primaryDevice.name : ""
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.main
                color: Appearance.colors.colOnPrimary
                Layout.maximumWidth: 60
                elide: Text.ElideRight
            }

            readonly property var primaryPercent: root.primaryDevice ? EarbudsControlService.primaryBatteryPercent(root.primaryDevice) : null
            readonly property bool batteryAvailable: primaryPercent !== null || (root.primaryDevice && root.primaryDevice.batteryAvailable)
            readonly property real batteryFraction: primaryPercent !== null ? (primaryPercent / 100.0) : (root.primaryDevice?.battery ?? 0)

            // Horizontal battery bar (only visible when connected and battery available)
            StyledProgressBar {
                id: batteryContainer
                visible: parent.batteryAvailable
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 8
                Layout.preferredWidth: 42
                valueBarWidth: 42
                valueBarHeight: 8
                from: 0
                to: 1
                value: parent.batteryFraction
                highlightColor: {
                    if (parent.batteryFraction <= 0.15)
                        return Appearance.m3colors.m3error;
                    return Appearance.colors.colOnPrimary;
                }
                trackColor: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.7)
            }
        }
    }

    Loader {
        id: popupLoader
        source: Config.options.bar.bluetoothDevicesLayout === "expressive" ? "../../popups/bluetooth/ExpressiveBluetoothDevicesPopup.qml" : "../../popups/bluetooth/BluetoothDevicesPopup.qml"
        onLoaded: {
            item.hoverTarget = root;
        }
    }
}
