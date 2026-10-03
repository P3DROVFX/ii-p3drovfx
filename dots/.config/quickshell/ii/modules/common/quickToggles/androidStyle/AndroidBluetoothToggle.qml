pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Android-style Bluetooth Quick Toggle.
 *
 * Supports compact 1x1 / 2x1 morphs and rich, expressive multi-row layouts
 * (1x2, 2x2, 4x2, 2x4, etc.) via BluetoothEndpointPanel following Google Material 3
 * Expressive design principles.
 */
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

    readonly property var activeDevice: EarbudsControlService.activeDevice ?? BluetoothStatus.firstActiveDevice
    readonly property var device: root.activeDevice
    readonly property string deviceName: activeDevice ? (activeDevice.name || activeDevice.alias || "") : ""
    readonly property string deviceIcon: activeDevice ? (activeDevice.icon || "") : ""
    readonly property string customImage: root.getDeviceImageSource(root.activeDevice)
    readonly property bool isEarbud: customImage === "" && (deviceIcon.toLowerCase().includes("headset")
        || deviceIcon.toLowerCase().includes("headphone") || deviceIcon.toLowerCase().includes("audio")
        || deviceName.toLowerCase().includes("buds"))

    readonly property var devBattery: root.activeDevice ? EarbudsControlService.batteryInfo(root.activeDevice) : null
    readonly property var primaryPercent: root.activeDevice ? EarbudsControlService.primaryBatteryPercent(root.activeDevice) : null
    readonly property bool hasBattery: (devBattery && devBattery.available) || primaryPercent !== null || (activeDevice?.batteryAvailable ?? false)
    readonly property real batteryFraction: primaryPercent !== null ? (primaryPercent / 100.0) : (activeDevice?.battery ?? 0)
    readonly property bool isConnected: BluetoothStatus.connected && root.activeDevice !== null

    expandedTitle: isConnected ? deviceName
        : (BluetoothStatus.enabled ? Translation.tr("No devices") : Translation.tr("Bluetooth off"))
    expandedStatus: isConnected && hasBattery
        ? Math.round(batteryFraction * 100) + Translation.tr("% battery") : ""
    expandedIconComponent: isConnected ? deviceArtwork : null

    // ── Helpers ───────────────────────────────────────────────────────────────
    function getDeviceImageSource(dev) {
        if (!dev)
            return "";

        if (Config.options && Config.options.bluetoothDeviceImages) {
            var custom = Config.options.bluetoothDeviceImages.find(function(d) {
                return d.mac === dev.address;
            });
            if (custom && custom.image)
                return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
        }

        var mac = (dev.address || "").replace(/:/g, "_").toUpperCase();
        var name = (dev.name || dev.alias || "").toLowerCase();
        var basePath = Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/") : "";

        if (mac === "E8_EE_CC_96_31_3A" || name.includes("q30") || name.includes("soundcore life q30") || name.includes("soundcore"))
            return basePath + "anker_q30_.png";
        if (mac === "68_7D_6B_94_0B_C2" || name.includes("buds 3 pro") || name.includes("buds3 pro") || name.includes("galaxy buds 3 pro"))
            return basePath + "galaxy_buds_3_pro.png";
        if (name.includes("galaxy buds 3") || name.includes("buds 3") || name.includes("buds3"))
            return basePath + "galaxy_buds_3.png";
        if (mac === "64_1B_2F_9B_95_CE" || name.includes("s23"))
            return basePath + "samsung_s23.png";
        if (name.includes("s24"))
            return basePath + "samsung_s24_ultra.png";
        if (name.includes("pixel buds") || name.includes("buds pro") || name.includes("buds fe") || name.includes("buds"))
            return basePath + "pixel_buds.png";
        if (name.includes("xbox") || name.includes("elite"))
            return basePath + "xbox_elite_series_2.png";

        return BluetoothDeviceImages.sourceFor(dev);
    }

    Component {
        id: deviceArtwork
        Item {
            anchors.fill: parent

            Image {
                anchors.centerIn: parent
                width: parent.width * 0.88
                height: parent.height * 0.88
                visible: root.customImage !== ""
                source: root.customImage
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Row {
                anchors.centerIn: parent
                spacing: root.scaled(2)
                visible: root.isEarbud && root.customImage === ""
                Repeater {
                    model: 2
                    Item {
                        id: bud
                        required property int index
                        width: Math.min(parent.parent.width * 0.45, root.scaled(28))
                        height: Math.min(parent.parent.height * 0.85, root.scaled(44))
                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                            }
                            Image {
                                anchors.fill: parent
                                source: Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/earbuds_cushion.svg") : ""
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
                                source: Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/earbuds_stem.svg") : ""
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
                iconSize: Math.min(parent.width * 0.75, root.scaled(32))
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
            }
        }
    }

    // ── Expressive multi-row face (1x2, 2x2, 4x2, 2x4, etc.) ──────────────────
    wide2x2OverrideComponent: tallFace
    tall1x2OverrideComponent: tallFace

    Component {
        id: tallFace
        BluetoothEndpointPanel {
            anchors.fill: parent
            anchors.margins: root.scaled(12)
            tile: root
        }
    }
}
