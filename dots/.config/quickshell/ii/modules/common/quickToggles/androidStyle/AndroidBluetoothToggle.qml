import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import "QuickToggleResize.js" as Resize
import Qt5Compat.GraphicalEffects

AndroidQuickToggleButton {
    id: root

    toggleModel: BluetoothToggle {}

    expandedIconShape: "Clover8Leaf"
    centerExpandedIcon: true
    expandedSurfaceColor: BluetoothStatus.connected
        ? (root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3)
        : (BluetoothStatus.enabled ? Appearance.colors.colLayer3 : Appearance.colors.colSurfaceContainerLow)
    expandedSymbolColor: BluetoothStatus.connected
        ? (root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3)
        : (BluetoothStatus.enabled ? Appearance.colors.colOnLayer3 : Appearance.colors.colOnSurfaceVariant)
    expandedStatusTransparency: 0.4
    readonly property var device: BluetoothStatus.firstActiveDevice
    readonly property string deviceName: device?.name ?? ""
    readonly property string deviceIcon: device?.icon ?? ""
    readonly property string customImage: root.getDeviceImageSource(root.device)
    readonly property bool isEarbud: customImage === "" && (deviceIcon.toLowerCase().includes("headset")
        || deviceIcon.toLowerCase().includes("headphone") || deviceIcon.toLowerCase().includes("audio")
        || deviceName.toLowerCase().includes("buds"))
    readonly property bool hasBattery: (device?.batteryAvailable ?? false) && (device?.battery ?? -1) >= 0
    expandedTitle: BluetoothStatus.connected ? deviceName
        : (BluetoothStatus.enabled ? Translation.tr("No devices") : Translation.tr("Bluetooth off"))
    expandedStatus: BluetoothStatus.connected && hasBattery
        ? Math.round(device.battery * 100) + Translation.tr("% battery") : ""
    expandedIconComponent: BluetoothStatus.connected ? deviceArtwork : null

    // ── Helpers ───────────────────────────────────────────────────────────────
    function getDeviceImageSource(device) {
        if (!device)
            return "";
        var custom = Config.options.bluetoothDeviceImages.find(function(d) {
            return d.mac === device.address;
        });
        if (custom)
            return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
        return "";
    }

    Component {
        id: deviceArtwork
        Item {
            readonly property color colCushion: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
            readonly property color colStem: root.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
            Image {
                anchors.centerIn: parent
                width: parent.width * 0.8
                height: parent.height * 0.8
                visible: root.customImage !== ""
                source: root.customImage
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
            Row {
                anchors.centerIn: parent
                spacing: root.scaled(2)
                visible: root.isEarbud
                Repeater {
                    model: 2
                    Item {
                        id: bud
                        required property int index
                        width: root.scaled(Resize.mix(18, 22, root.morphWideProgress))
                        height: root.scaled(Resize.mix(28, 36, root.morphWideProgress))
                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                            }
                            Image {
                                anchors.fill: parent
                                source: "../../../../assets/images/devices/earbuds_cushion.svg"
                                sourceSize: Qt.size(width, height)
                                mirror: bud.index === 0
                            }
                        }
                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: root.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                            }
                            Image {
                                anchors.fill: parent
                                source: "../../../../assets/images/devices/earbuds_stem.svg"
                                sourceSize: Qt.size(width, height)
                                mirror: bud.index === 0
                            }
                        }
                    }
                }
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.customImage === "" && !root.isEarbud
                fill: root.toggled ? 1 : 0
                text: Icons.getBluetoothDeviceMaterialSymbol(root.deviceIcon)
                iconSize: root.scaled(Resize.mix(26, 28, root.morphWideProgress))
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
            }
        }
    }
}
