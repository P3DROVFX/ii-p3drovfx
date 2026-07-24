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

    configEntryName: "bluetooth_fill_cards"

    // Dynamic list combining Bluetooth connected devices + KDE Connect phone device
    readonly property var activeDevices: {
        let list = [];
        // Add KDE Connect phone device if available & reachable
        if (KdeConnectService.activeDevice && KdeConnectService.activeDevice.reachable) {
            list.push({
                isKdeConnect: true,
                name: KdeConnectService.activeDevice.name || "Mobile Phone",
                battery: (KdeConnectService.activeDevice.charge ?? 68) / 100.0,
                batteryAvailable: true,
                type: "phone",
                icon: "phone",
                symbol: "smartphone",
                connected: true
            });
        }
        // Add connected Bluetooth devices
        for (let i = 0; i < BluetoothStatus.connectedDevices.length; i++) {
            let bt = BluetoothStatus.connectedDevices[i];
            list.push({
                isKdeConnect: false,
                name: bt.name || "Bluetooth Device",
                battery: bt.battery,
                batteryAvailable: bt.batteryAvailable,
                type: bt.type || "other",
                icon: bt.icon || "",
                symbol: Icons.getBluetoothDeviceMaterialSymbol(bt.icon || ""),
                connected: true
            });
        }
        return list;
    }

    readonly property int deviceCount: Math.max(1, activeDevices.length)

    implicitWidth: deviceCount * 240
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg

    StyledRectangularShadow {
        id: bgShadow
        target: outerCardBg
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    // Outer Card Container (White / Neutral rounded container frame)
    Rectangle {
        id: outerCardBg
        anchors.fill: parent
        anchors.margins: 10
        color: root.expressive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerLow
        radius: Appearance.rounding.windowRounding

        layer.enabled: true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: outerCardBg.width
                height: outerCardBg.height
                radius: outerCardBg.radius
                antialiasing: true
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Repeater {
                model: root.deviceCount

                delegate: Item {
                    id: deviceCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    readonly property var device: (root.activeDevices.length > index) ? root.activeDevices[index] : null
                    readonly property bool isConnected: device !== null
                    readonly property real batteryLevel: (device && device.batteryAvailable) ? (device.battery ?? 0.8) : 0.68
                    readonly property int batteryPercent: Math.round(batteryLevel * 100)
                    readonly property string deviceName: device ? (device.name ?? "Bluetooth Device") : "Bluetooth Device"
                    readonly property string deviceSymbol: device ? (device.symbol || Icons.getBluetoothDeviceMaterialSymbol(device.icon || "")) : "bluetooth"
                    readonly property string deviceType: device ? (device.type ?? "other") : "other"

                    // Color palette according to device type (phone -> colTertiary, media -> colPrimary, others -> colSecondary)
                    readonly property color accentColor: {
                        if (root.expressive) return Appearance.colors.colOnPrimaryContainer
                        if (deviceType === "phone") return Appearance.colors.colTertiary
                        if (deviceType === "headset" || deviceType === "headphones" || deviceType === "media" || deviceType === "audio-card") return Appearance.colors.colPrimary
                        return Appearance.colors.colSecondary
                    }
                    readonly property color cardContainerColor: {
                        if (root.expressive) return Appearance.colors.colSurfaceContainerHigh
                        if (deviceType === "phone") return Appearance.colors.colTertiaryContainer
                        if (deviceType === "headset" || deviceType === "headphones" || deviceType === "media" || deviceType === "audio-card") return Appearance.colors.colPrimaryContainer
                        return Appearance.colors.colSecondaryContainer
                    }

                    Rectangle {
                        id: cardInnerBg
                        anchors.fill: parent
                        color: deviceCard.cardContainerColor
                        radius: Appearance.rounding.windowRounding - 4

                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: cardInnerBg.width
                                height: cardInnerBg.height
                                radius: cardInnerBg.radius
                                antialiasing: true
                            }
                        }

                        // Bottom Liquid Battery Fill Level Indicator
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: parent.height * deviceCard.batteryLevel
                            color: ColorUtils.applyAlpha(deviceCard.accentColor, 0.30)

                            Behavior on height {
                                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 0

                            // Top Badge Icon Container
                            Rectangle {
                                Layout.preferredWidth: 54
                                Layout.preferredHeight: 54
                                radius: width / 2
                                color: Appearance.colors.colSurfaceContainerHighest
                                opacity: 0.95

                                StyledDropShadow {
                                    target: parent
                                    visible: Config.options.background.widgets.enableShadows ?? true
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: deviceCard.deviceSymbol
                                    iconSize: 28
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            Item { Layout.fillHeight: true }

                            // Device Title & Subtitle Text
                            StyledText {
                                Layout.fillWidth: true
                                text: deviceCard.deviceName
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                                color: deviceCard.accentColor
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: deviceCard.isConnected ? Translation.tr("Connected") : Translation.tr("Discharged")
                                font.pixelSize: 15
                                font.weight: Font.Normal
                                color: ColorUtils.applyAlpha(deviceCard.accentColor, 0.80)
                                elide: Text.ElideRight
                            }

                            // Large Fill Percentage Text
                            Text {
                                Layout.topMargin: 4
                                text: deviceCard.batteryPercent + "%"
                                color: deviceCard.accentColor
                                font {
                                    pixelSize: 46
                                    weight: Font.Black
                                    bold: true
                                    family: "Google Sans Flex"
                                    variableAxes: ({ "wght": 900, "ROUND": 100 })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
