import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

MouseArea {
    id: root

    readonly property var activeDevices: BluetoothStatus.connectedDevices
    property int deviceIndex: 0
    readonly property var primaryDevice: activeDevices.length > 0 ? activeDevices[deviceIndex % activeDevices.length] : null
    readonly property bool hasDevices: activeDevices.length > 0

    Connections {
        target: BluetoothStatus
        function onConnectedDevicesChanged() {
            if (typeof rootItem !== "undefined")
                rootItem.toggleVisible(BluetoothStatus.connectedDevices.length > 0)
        }
    }

    Component.onCompleted: {
        if (typeof rootItem !== "undefined")
            rootItem.toggleVisible(hasDevices)
    }

    implicitWidth: Appearance.sizes.baseVerticalBarWidth
    implicitHeight: chip.implicitHeight

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

    Item {
        id: chip
        anchors.centerIn: parent
        implicitWidth: Appearance.sizes.baseVerticalBarWidth
        implicitHeight: layout.implicitHeight + 16

        ColumnLayout {
            id: layout
            anchors.centerIn: parent
            spacing: 4

            // Device icon
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: Appearance.font.pixelSize.larger
                text: root.hasDevices ? Icons.getBluetoothDeviceMaterialSymbol(root.primaryDevice.icon) : "bluetooth_disabled"
                color: root.hasDevices ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            }

            // Device name (only visible when connected) — vertical, truncated
            StyledText {
                visible: root.hasDevices
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Appearance.sizes.baseVerticalBarWidth - 12
                text: root.primaryDevice ? root.primaryDevice.name : ""
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.family: Appearance.font.family.main
                color: Appearance.colors.colOnPrimary
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            // Horizontal battery bar (compact, centered below name)
            StyledProgressBar {
                id: batteryBar
                visible: root.primaryDevice ? root.primaryDevice.batteryAvailable : false
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 6
                Layout.preferredWidth: 28
                valueBarWidth: 28
                valueBarHeight: 6
                from: 0
                to: 1
                value: root.primaryDevice?.battery ?? 0
                highlightColor: {
                    if (!root.primaryDevice)
                        return Appearance.colors.colOnPrimary;
                    if (root.primaryDevice.battery <= 0.15)
                        return Appearance.m3colors.m3error;
                    return Appearance.colors.colOnPrimary;
                }
                trackColor: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.7)
            }
        }
    }

    Loader {
        id: popupLoader
        source: Config.options.bar.bluetoothDevicesLayout === "expressive" ? "../bar/popups/bluetooth/ExpressiveBluetoothDevicesPopup.qml" : "../bar/popups/bluetooth/BluetoothDevicesPopup.qml"
        onLoaded: {
            item.hoverTarget = root;
        }
    }
}
