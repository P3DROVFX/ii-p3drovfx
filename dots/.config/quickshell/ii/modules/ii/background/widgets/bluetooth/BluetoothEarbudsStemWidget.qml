import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "bluetooth_earbuds_stem"

    implicitWidth: 240
    implicitHeight: 240

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

    readonly property bool isConnected: earbudDevice !== null
    readonly property real batteryLevel: (earbudDevice && earbudDevice.batteryAvailable) ? (earbudDevice.battery ?? 1.0) : 1.0
    readonly property int batteryPercent: Math.round(batteryLevel * 100)
    readonly property string fullName: earbudDevice ? (earbudDevice.name ?? Translation.tr("Bluetooth Earbuds")) : ""

    // Separate Title line 1 and line 2 for pixel match
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

    StyledRectangularShadow {
        id: bgShadow
        target: cardBg
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: cardBg
        anchors.fill: parent
        anchors.margins: 10
        color: root.cardBgColor
        radius: Appearance.rounding.windowRounding

        layer.enabled: true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: cardBg.width
                height: cardBg.height
                radius: cardBg.radius
                antialiasing: true
            }
        }

        Item {
            anchors.fill: parent
            anchors.margins: 20

            // Top-Left Device Name Title / Disconnected Status
            ColumnLayout {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 4
                anchors.topMargin: 4
                spacing: 2

                StyledText {
                    text: root.titlePart1
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    color: root.colPrimaryText
                    opacity: root.isConnected ? 1.0 : 0.60
                }

                StyledText {
                    text: root.titlePart2
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    color: root.colPrimaryText
                    opacity: root.isConnected ? 1.0 : 0.60
                }
            }

            // Bottom-Left Earbud 1 (Stem facing left, cushion facing left-top)
            Item {
                id: earbudLeft
                width: 60
                height: 94
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 8
                anchors.bottomMargin: 8
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
                width: 60
                height: 94
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 8
                anchors.topMargin: 8
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

            // Bottom-Right Large Battery Percentage Text (Hidden when disconnected)
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 4
                anchors.bottomMargin: 4
                visible: root.isConnected
                text: root.batteryPercent + "%"
                color: root.colPrimaryText
                font {
                    pixelSize: 44
                    weight: Font.Bold
                    bold: true
                    family: "Google Sans Flex"
                    variableAxes: ({ "wght": 800, "RNDS": 100 })
                }
            }
        }
    }
}
