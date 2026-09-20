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
 * Connected Devices Battery List quick toggle.
 * Ported from the desktop background's DevicesBatteryList1x1Widget.
 *
 * Responsive layout filling the entire tile surface with 4 compact liquid-fill battery pills.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Connected Devices Battery")

    // Theme Tokens from WidgetColorScheme
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color pillBgColor: WidgetColorScheme.pillBgColor
    readonly property color pillFillColor: WidgetColorScheme.pillFillColor

    // Combined device battery list
    readonly property var deviceList: {
        let list = [];

        // 1. PC Laptop Battery
        if (Battery.available) {
            list.push({
                name: "Laptop",
                battery: Battery.percentage ?? 1.0,
                charging: Battery.isCharging || Battery.isPluggedIn,
                symbol: "laptop",
                accent: Appearance.colors.colPrimary,
                onAccent: Appearance.colors.colOnPrimary,
                container: Appearance.colors.colPrimaryContainer,
                onContainer: Appearance.colors.colOnPrimaryContainer,
                containerHover: Appearance.colors.colPrimaryContainerHover
            });
        }

        // 2. KDE Connect Mobile Phone
        if (KdeConnectService.activeDevice && KdeConnectService.activeDevice.reachable) {
            list.push({
                name: KdeConnectService.activeDeviceDisplayName || "Phone",
                battery: (KdeConnectService.activeDevice.charge ?? 100) / 100.0,
                charging: KdeConnectService.activeDevice.isCharging ?? false,
                symbol: "smartphone",
                accent: Appearance.colors.colTertiary,
                onAccent: Appearance.colors.colOnTertiary,
                container: Appearance.colors.colTertiaryContainer,
                onContainer: Appearance.colors.colOnTertiaryContainer,
                containerHover: Appearance.colors.colTertiaryContainerHover
            });
        }

        // 3. Connected Bluetooth Devices
        for (let i = 0; i < BluetoothStatus.connectedDevices.length; i++) {
            let bt = BluetoothStatus.connectedDevices[i];
            let devName = bt.name || "Bluetooth Device";
            let symbol = Icons.getBluetoothDeviceMaterialSymbol(bt.icon || "");

            let rawBattery = (bt.battery !== undefined && bt.battery !== null) ? bt.battery : (bt.batteryAvailable ? 0.80 : 0.80);
            let battVal = rawBattery > 1.0 ? rawBattery / 100.0 : rawBattery;

            list.push({
                name: devName,
                battery: battVal,
                charging: false,
                symbol: symbol !== "" ? symbol : "headphones",
                accent: Appearance.colors.colSecondaryContainer,
                onAccent: Appearance.colors.colOnSecondaryContainer,
                container: ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colSecondaryContainer, 0.5),
                onContainer: Appearance.colors.colOnSecondary,
                containerHover: ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colSecondaryContainer, 0.7)
            });
        }

        return list;
    }

    Rectangle {
        id: cardBg
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
        radius: Appearance.rounding.large
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Math.max(8, Math.round(root.surface.height * 0.05))
            spacing: Math.max(4, Math.round(root.surface.height * 0.025))

            Repeater {
                model: 4 // Fixed 4 compact battery slots

                delegate: Item {
                    id: rowSlot
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    readonly property var itemData: (root.deviceList.length > index) ? root.deviceList[index] : null
                    readonly property bool hasItem: itemData !== null
                    readonly property real fillPct: hasItem ? Math.min(1.0, Math.max(0.0, itemData.battery)) : 0.0
                    readonly property int displayPercent: Math.round(fillPct * 100)
                    readonly property color activeOnColor: hasItem ? itemData.onContainer : Appearance.colors.colOnSurfaceVariant

                    // Compact Pill Background Track
                    Rectangle {
                        id: pillTrack
                        anchors.fill: parent
                        radius: height / 2
                        color: hasItem ? (pillHover.hovered ? itemData.containerHover : itemData.container) : root.pillBgColor
                        opacity: hasItem ? 1.0 : 0.30

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pillTrack)
                        }

                        HoverHandler {
                            id: pillHover
                            enabled: rowSlot.hasItem
                        }

                        // Horizontal Liquid Fill Level Bar
                        Rectangle {
                            id: fillBar
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * rowSlot.fillPct
                            radius: pillTrack.radius
                            color: hasItem ? itemData.accent : root.pillFillColor

                            Behavior on width {
                                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                            }
                        }

                        // Layer 1: Content Row on Unfilled Track (ColOnSurface)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Math.max(6, Math.round(parent.height * 0.25))
                            anchors.rightMargin: Math.max(6, Math.round(parent.height * 0.25))
                            spacing: 6

                            MaterialSymbol {
                                visible: rowSlot.hasItem
                                text: rowSlot.hasItem ? rowSlot.itemData.symbol : "devices"
                                iconSize: Math.max(12, Math.min(20, Math.round(parent.height * 0.50)))
                                fill: 1
                                color: hasItem ? itemData.onContainer : Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: rowSlot.hasItem
                                text: rowSlot.hasItem ? rowSlot.itemData.name : ""
                                font.pixelSize: Math.max(9, Math.min(13, Math.round(parent.height * 0.38)))
                                font.weight: Font.Medium
                                color: hasItem ? itemData.onContainer : Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }

                            Item { Layout.fillWidth: true; visible: !rowSlot.hasItem }

                            Text {
                                visible: rowSlot.hasItem
                                text: rowSlot.displayPercent + "%"
                                color: hasItem ? itemData.onContainer : Appearance.colors.colOnSurfaceVariant
                                font {
                                    pixelSize: Math.max(9, Math.min(13, Math.round(parent.height * 0.38)))
                                    weight: Font.Medium
                                    family: "Google Sans Flex"
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: Math.max(14, Math.round(parent.height * 0.60))
                                Layout.preferredHeight: Math.max(14, Math.round(parent.height * 0.60))
                                radius: width / 2
                                color: hasItem ? itemData.accent : "transparent"
                                visible: rowSlot.hasItem && rowSlot.itemData.charging

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "bolt"
                                    iconSize: Math.max(10, Math.round(parent.height * 0.65))
                                    fill: 1
                                    color: itemData ? itemData.onAccent : Appearance.colors.colOnPrimary
                                }
                            }
                        }

                        // Layer 2: Masked Fill Overlay Row over liquid fill
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Math.max(6, Math.round(parent.height * 0.25))
                            anchors.rightMargin: Math.max(6, Math.round(parent.height * 0.25))
                            spacing: 6

                            layer.enabled: true
                            layer.smooth: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    x: fillBar.x
                                    y: fillBar.y
                                    width: fillBar.width
                                    height: fillBar.height
                                    radius: fillBar.radius
                                }
                            }

                            MaterialSymbol {
                                visible: rowSlot.hasItem
                                text: rowSlot.hasItem ? rowSlot.itemData.symbol : "devices"
                                iconSize: Math.max(12, Math.min(20, Math.round(parent.height * 0.50)))
                                fill: 1
                                color: itemData ? itemData.onAccent : Appearance.colors.colOnPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: rowSlot.hasItem
                                text: rowSlot.hasItem ? rowSlot.itemData.name : ""
                                font.pixelSize: Math.max(9, Math.min(13, Math.round(parent.height * 0.38)))
                                font.weight: Font.Medium
                                color: itemData ? itemData.onAccent : Appearance.colors.colOnPrimary
                                elide: Text.ElideRight
                            }

                            Item { Layout.fillWidth: true; visible: !rowSlot.hasItem }

                            Text {
                                visible: rowSlot.hasItem
                                text: rowSlot.displayPercent + "%"
                                color: itemData ? itemData.onAccent : Appearance.colors.colOnPrimary
                                font {
                                    pixelSize: Math.max(9, Math.min(13, Math.round(parent.height * 0.38)))
                                    weight: Font.Medium
                                    family: "Google Sans Flex"
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: Math.max(14, Math.round(parent.height * 0.60))
                                Layout.preferredHeight: Math.max(14, Math.round(parent.height * 0.60))
                                radius: width / 2
                                color: hasItem ? itemData.accent : "transparent"
                                visible: rowSlot.hasItem && rowSlot.itemData.charging

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "bolt"
                                    iconSize: Math.max(10, Math.round(parent.height * 0.65))
                                    fill: 1
                                    color: itemData ? itemData.onAccent : Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
