import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Bluetooth

AndroidQuickToggleButton {
    id: root

    toggleModel: BluetoothToggle {}

    // Always use our custom 2x2 layout (connected or empty state)
    wide2x2OverrideComponent: btWide2x2

    // Also use custom layout for 1x2 (tall, narrow)
    tall1x2OverrideComponent: btTall1x2

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

    // ── Master 2x2 component (connected or empty) ────────────────────────────
    Component {
        id: btWide2x2

        Item {
            anchors.fill: parent

            // ── CONNECTED STATE ───────────────────────────────────────────────
            Item {
                id: connectedView
                anchors.fill: parent
                visible: BluetoothStatus.connected

                readonly property var device: BluetoothStatus.firstActiveDevice
                readonly property string deviceName:   connectedView.device?.name ?? ""
                readonly property string deviceIcon:   connectedView.device?.icon ?? ""
                readonly property string customImg:    root.getDeviceImageSource(connectedView.device)
                readonly property bool   hasCustomImg: connectedView.customImg !== ""
                readonly property bool isEarbud: {
                    var ic = connectedView.deviceIcon.toLowerCase();
                    var nm = connectedView.deviceName.toLowerCase();
                    return !connectedView.hasCustomImg &&
                        (ic.includes("headset") || ic.includes("headphone")
                         || ic.includes("audio") || nm.includes("buds"));
                }
                readonly property real batteryFraction: connectedView.device?.battery ?? -1
                readonly property bool hasBattery:
                    (connectedView.device?.batteryAvailable ?? false)
                    && connectedView.batteryFraction >= 0
                readonly property int batteryPct: Math.round(connectedView.batteryFraction * 100)

                // earbud asset paths (same depth as ExpressiveBluetoothDevicesPopup)
                readonly property string pathCushion:
                    "../../../../../assets/images/devices/earbuds_cushion.svg"
                readonly property string pathStem:
                    "../../../../../assets/images/devices/earbuds_stem.svg"

                // colours matching the popup
            readonly property color colPrimary:   Appearance.colors.colPrimary
            readonly property color colSecondary: Appearance.colors.colSurfaceContainerLow

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // ── Icon area (60% height) ────────────────────────────────
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(connectedView.height * 0.60)

                        // Custom image (takes priority)
                        Image {
                            anchors.centerIn: parent
                            visible: connectedView.hasCustomImg
                            source: connectedView.customImg
                            width:  Math.min(parent.width, parent.height) * 0.72
                            height: width
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }

                        // Earbud SVG pair — side by side, outward-facing
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            visible: connectedView.isEarbud

                            // Left earbud — normal
                            Item {
                                width: 36; height: 58
                                anchors.verticalCenter: parent.verticalCenter
                                Image {
                                    anchors.fill: parent
                                    source: connectedView.pathCushion
                                    sourceSize: Qt.size(width, height)
                                    layer.enabled: true
                                    layer.effect: ColorOverlay { color: connectedView.colCushion }
                                }
                                Image {
                                    anchors.fill: parent
                                    source: connectedView.pathStem
                                    sourceSize: Qt.size(width, height)
                                    layer.enabled: true
                                    layer.effect: ColorOverlay { color: connectedView.colStem }
                                }
                            }

                            // Right earbud — mirrored (outward)
                            Item {
                                width: 36; height: 58
                                anchors.verticalCenter: parent.verticalCenter
                                Image {
                                    anchors.fill: parent
                                    source: connectedView.pathCushion
                                    sourceSize: Qt.size(width, height)
                                    mirror: true
                                    layer.enabled: true
                                    layer.effect: ColorOverlay { color: connectedView.colCushion }
                                }
                                Image {
                                    anchors.fill: parent
                                    source: connectedView.pathStem
                                    sourceSize: Qt.size(width, height)
                                    mirror: true
                                    layer.enabled: true
                                    layer.effect: ColorOverlay { color: connectedView.colStem }
                                }
                            }
                        }

                        // Generic MaterialSymbol fallback
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !connectedView.hasCustomImg && !connectedView.isEarbud
                            text: Icons.getBluetoothDeviceMaterialSymbol(connectedView.deviceIcon)
                            iconSize: Math.round(Math.min(parent.width, parent.height) * 0.70)
                            color: Appearance.colors.colOnLayer2
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // ── Device name ───────────────────────────────────────────
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        text: connectedView.deviceName
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // ── Battery ───────────────────────────────────────────────
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.bottomMargin: 4
                        visible: connectedView.hasBattery
                        text: connectedView.batteryPct + Translation.tr("% battery")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Thin
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }

            // ── EMPTY / DISCONNECTED STATE ────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: !BluetoothStatus.connected

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    // Large Cookie12Sided BT icon
                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        shapeString: "Cookie12Sided"
                        implicitSize: Math.round(Math.min(parent.parent.width, parent.parent.height) * 0.55)
                        color: BluetoothStatus.enabled
                            ? Appearance.colors.colLayer3
                            : Appearance.colors.colSurfaceContainerLow

                        Behavior on color {
                            ColorAnimation { duration: 200 }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                            iconSize: Math.round(parent.implicitSize * 0.52)
                            color: BluetoothStatus.enabled
                                ? Appearance.colors.colOnLayer3
                                : Appearance.colors.colOnSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter

                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                    }

                    // Status label
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        text: BluetoothStatus.enabled
                            ? Translation.tr("No devices")
                            : Translation.tr("Bluetooth off")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.35)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── 1x2 (tall, narrow) component ─────────────────────────────────────────
    Component {
        id: btTall1x2

        Item {
            anchors.fill: parent

            // ── CONNECTED STATE ───────────────────────────────────────────────
            Item {
                id: connectedTall
                anchors.fill: parent
                visible: BluetoothStatus.connected

                readonly property var device: BluetoothStatus.firstActiveDevice
                readonly property string deviceName:   connectedTall.device?.name ?? ""
                readonly property string deviceIcon:   connectedTall.device?.icon ?? ""
                readonly property string customImg:    root.getDeviceImageSource(connectedTall.device)
                readonly property bool   hasCustomImg: connectedTall.customImg !== ""
                readonly property bool isEarbud: {
                    var ic = connectedTall.deviceIcon.toLowerCase();
                    var nm = connectedTall.deviceName.toLowerCase();
                    return !connectedTall.hasCustomImg &&
                        (ic.includes("headset") || ic.includes("headphone")
                         || ic.includes("audio") || nm.includes("buds"));
                }
                readonly property real batteryFraction: connectedTall.device?.battery ?? -1
                readonly property bool hasBattery:
                    (connectedTall.device?.batteryAvailable ?? false)
                    && connectedTall.batteryFraction >= 0
                readonly property int batteryPct: Math.round(connectedTall.batteryFraction * 100)

                readonly property string pathCushion:
                    "../../../../../assets/images/devices/earbuds_cushion.svg"
                readonly property string pathStem:
                    "../../../../../assets/images/devices/earbuds_stem.svg"
                readonly property color colCushion: Appearance.colors.colOnSecondaryContainer
                readonly property color colStem:    Appearance.colors.colSecondary

                ColumnLayout {
                    anchors.fill: parent
                    spacing: -4

                    // ── Icon area (60% height, fixed icon size) ───────────────
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(connectedTall.height * 0.60)

                        // Custom image
                        Image {
                            anchors.centerIn: parent
                            visible: connectedTall.hasCustomImg
                            source: connectedTall.customImg
                            width: 60; height: 60
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true
                        }

                        // Earbud pair — fixed size, side by side
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            visible: connectedTall.isEarbud

                            Item {
                                width: 36; height: 58
                                anchors.verticalCenter: parent.verticalCenter
                                Image {
                                    anchors.fill: parent
                                    source: connectedTall.pathCushion
                                    sourceSize: Qt.size(width, height)
                                    layer.enabled: true
                                    layer.effect: ColorOverlay { color: connectedTall.colCushion }
                                }
                                Image {
                                    anchors.fill: parent
                                    source: connectedTall.pathStem
                                    sourceSize: Qt.size(width, height)
                                    layer.enabled: true
                                    layer.effect: ColorOverlay { color: connectedTall.colStem }
                                }
                            }
                            Item {
                                width: 36; height: 58
                                anchors.verticalCenter: parent.verticalCenter
                                Image {
                                    anchors.fill: parent
                                    source: connectedTall.pathCushion
                                    sourceSize: Qt.size(width, height)
                                    mirror: true
                                    layer.enabled: true
                                    layer.effect: ColorOverlay { color: connectedTall.colCushion }
                                }
                                Image {
                                    anchors.fill: parent
                                    source: connectedTall.pathStem
                                    sourceSize: Qt.size(width, height)
                                    mirror: true
                                    layer.enabled: true
                                    layer.effect: ColorOverlay { color: connectedTall.colStem }
                                }
                            }
                        }

                        // Generic symbol fallback
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !connectedTall.hasCustomImg && !connectedTall.isEarbud
                            text: Icons.getBluetoothDeviceMaterialSymbol(connectedTall.deviceIcon)
                            iconSize: 42
                            color: Appearance.colors.colOnLayer2
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // ── Device name ───────────────────────────────────────────
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        text: connectedTall.deviceName
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // ── Battery ───────────────────────────────────────────────
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        Layout.bottomMargin: 8
                        visible: connectedTall.hasBattery
                        text: connectedTall.batteryPct + Translation.tr("% battery")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Thin
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }

            // ── EMPTY / DISCONNECTED STATE ────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: !BluetoothStatus.connected

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        shapeString: "Cookie12Sided"
                        implicitSize: Math.round(Math.min(parent.parent.width, parent.parent.height) * 0.50)
                        color: BluetoothStatus.enabled
                            ? Appearance.colors.colLayer3
                            : Appearance.colors.colSurfaceContainerLow
                        Behavior on color { ColorAnimation { duration: 200 } }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                            iconSize: Math.round(parent.implicitSize * 0.52)
                            color: BluetoothStatus.enabled
                                ? Appearance.colors.colOnLayer3
                                : Appearance.colors.colOnSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        text: BluetoothStatus.enabled
                            ? Translation.tr("No devices")
                            : Translation.tr("BT off")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.35)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
