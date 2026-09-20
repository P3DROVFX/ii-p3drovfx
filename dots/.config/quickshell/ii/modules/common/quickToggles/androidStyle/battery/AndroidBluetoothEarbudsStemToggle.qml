pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Bluetooth Earbuds Stem quick toggle.
 * Ported from the desktop background's BluetoothEarbudsStemWidget.
 *
 * Responsive layout filling the entire tile surface with dual SVG earbuds and title.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        if (root.earbudDevice && root.earbudDevice.name) {
            return root.earbudDevice.name + " (" + root.primaryPercent + "%)";
        }
        return Translation.tr("Bluetooth Earbuds");
    }

    // Bluetooth Audio / Earbuds Device detection
    readonly property var connectedDevices: BluetoothStatus.connectedDevices
    readonly property var earbudDevice: {
        for (let i = 0; i < connectedDevices.length; i++) {
            let dev = connectedDevices[i];
            let icon = (dev.icon || "").toLowerCase();
            let name = (dev.name || "").toLowerCase();
            if (icon.includes("headset") || icon.includes("headphone") || icon.includes("audio") || name.includes("buds") || name.includes("zkd") || name.includes("pro")) {
                return dev;
            }
        }
        return connectedDevices.length > 0 ? connectedDevices[0] : null;
    }

    readonly property var devBattery: root.earbudDevice ? EarbudsControlService.batteryInfo(root.earbudDevice) : null
    readonly property bool isConnected: earbudDevice !== null
    readonly property real batteryLevel: (earbudDevice && earbudDevice.batteryAvailable) ? (earbudDevice.battery ?? 1.0) : 1.0
    readonly property int batteryPercent: Math.round(batteryLevel * 100)
    readonly property int primaryPercent: (devBattery && devBattery.available && devBattery.aggregate !== null) ? devBattery.aggregate : batteryPercent
    readonly property string fullName: earbudDevice ? (earbudDevice.name ?? Translation.tr("Bluetooth Earbuds")) : ""

    // Separate Title line 1 and line 2
    readonly property string titlePart1: {
        if (!isConnected) return Translation.tr("Not");
        let parts = fullName.split(" ");
        if (parts.length > 1) return parts[0];
        return parts[0] || Translation.tr("Bluetooth");
    }
    readonly property string titlePart2: {
        if (!isConnected) return Translation.tr("Connected");
        let parts = fullName.split(" ");
        if (parts.length > 1) return parts.slice(1).join(" ");
        return Translation.tr("Earbuds");
    }

    // SVG Asset Paths
    readonly property string iconEarbudsCushion: "../../../../../assets/images/devices/earbuds_cushion.svg"
    readonly property string iconEarbudsStem: "../../../../../assets/images/devices/earbuds_stem.svg"

    // Palette Tokens from WidgetColorScheme
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color colPrimaryText: WidgetColorScheme.textColorOnBg
    readonly property color colSecondaryCushion: WidgetColorScheme.innerShapeColor

    Rectangle {
        id: cardBg
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
        radius: Appearance.rounding.large
        clip: true

        Item {
            anchors.fill: parent
            anchors.margins: Math.max(10, Math.round(root.surface.height * 0.08))

            // Top-Left Device Name Title / Disconnected Status
            ColumnLayout {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 2
                anchors.topMargin: 2
                spacing: 1

                StyledText {
                    text: root.titlePart1
                    font.pixelSize: Math.max(12, Math.min(22, Math.round(root.surface.height * 0.11)))
                    font.weight: Font.DemiBold
                    color: root.colPrimaryText
                    opacity: root.isConnected ? 1.0 : 0.60
                }

                StyledText {
                    text: root.titlePart2
                    font.pixelSize: Math.max(12, Math.min(22, Math.round(root.surface.height * 0.11)))
                    font.weight: Font.Bold
                    color: root.colPrimaryText
                    opacity: root.isConnected ? 1.0 : 0.60
                }
            }

            // Bottom-Left Earbud 1 (Stem facing left, cushion facing left-top)
            Item {
                id: earbudLeft
                width: Math.max(28, Math.min(parent.width * 0.26, root.surface.height * 0.28, 62))
                height: Math.round(width * 1.56)
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 4
                anchors.bottomMargin: 4
                opacity: root.isConnected ? 1.0 : 0.25

                // Cushion Layer (Secondary color)
                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl(root.iconEarbudsCushion)
                    sourceSize: Qt.size(width, height)
                    smooth: true
                    mipmap: true
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: root.colSecondaryCushion
                    }
                }

                // Stem Layer (Primary color)
                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl(root.iconEarbudsStem)
                    sourceSize: Qt.size(width, height)
                    smooth: true
                    mipmap: true
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: root.colPrimaryText
                    }
                }
            }

            // Top-Right Earbud 2 (Stem facing right, flipped horizontally)
            Item {
                id: earbudRight
                width: Math.max(28, Math.min(parent.width * 0.26, root.surface.height * 0.28, 62))
                height: Math.round(width * 1.56)
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 4
                anchors.topMargin: 4
                opacity: root.isConnected ? 1.0 : 0.25
                transformOrigin: Item.Center
                rotation: 180

                // Cushion Layer
                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl(root.iconEarbudsCushion)
                    sourceSize: Qt.size(width, height)
                    smooth: true
                    mipmap: true
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: root.colSecondaryCushion
                    }
                }

                // Stem Layer
                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl(root.iconEarbudsStem)
                    sourceSize: Qt.size(width, height)
                    smooth: true
                    mipmap: true
                    layer.enabled: true
                    layer.effect: ColorOverlay {
                        color: root.colPrimaryText
                    }
                }
            }

            // Bottom-Right Large Battery Percentage Text
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 2
                anchors.bottomMargin: 2
                visible: root.isConnected
                text: root.primaryPercent + "%"
                color: root.colPrimaryText
                font {
                    pixelSize: Math.max(20, Math.min(root.surface.height * 0.26, root.surface.width * 0.26, 46))
                    weight: Font.Bold
                    bold: true
                    family: "Google Sans Flex"
                    variableAxes: ({ "wght": 800, "RNDS": 100 })
                }
            }
        }
    }
}
