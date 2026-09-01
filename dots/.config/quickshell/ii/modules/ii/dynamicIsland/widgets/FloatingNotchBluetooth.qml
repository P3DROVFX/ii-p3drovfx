import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.bluetooth
import qs.services
import Quickshell

Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var device: GlobalStates.floatingNotchBtDevice
    readonly property string action: GlobalStates.floatingNotchBtAction
    readonly property string deviceName: device ? (device.name || device.alias || "Device") : ""
    readonly property var activeDevice: device

    readonly property var devBattery: root.activeDevice ? EarbudsControlService.batteryInfo(root.activeDevice) : null
    readonly property var devNoise: root.activeDevice ? EarbudsControlService.noiseControl(root.activeDevice) : null
    readonly property var primaryPercent: root.activeDevice ? EarbudsControlService.primaryBatteryPercent(root.activeDevice) : null
    readonly property bool hasBattery: (devBattery && devBattery.available) || primaryPercent !== null || (root.activeDevice && root.activeDevice.batteryAvailable)
    readonly property real batteryFraction: primaryPercent !== null ? (primaryPercent / 100.0) : (root.activeDevice?.battery ?? 0)

    function getDeviceImageSource(device) {
        if (!device) return "";
        if (Config.options && Config.options.bluetoothDeviceImages) {
            let custom = Config.options.bluetoothDeviceImages.find(d => d.mac === device.address);
            if (custom && custom.image) {
                return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
            }
        }

        const mac = (device.address || "").replace(/:/g, "_").toUpperCase();
        const name = (device.name || device.alias || "").toLowerCase();
        const basePath = Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/") : "";

        if (mac === "E8_EE_CC_96_31_3A" || name.includes("q30") || name.includes("soundcore life q30") || name.includes("soundcore")) {
            return basePath + "anker_q30_.png";
        }
        if (mac === "68_7D_6B_94_0B_C2" || name.includes("buds 3 pro") || name.includes("buds3 pro") || name.includes("galaxy buds 3 pro")) {
            return basePath + "galaxy_buds_3_pro.png";
        }
        if (name.includes("galaxy buds 3") || name.includes("buds 3") || name.includes("buds3")) {
            return basePath + "galaxy_buds_3.png";
        }
        if (mac === "64_1B_2F_9B_95_CE" || name.includes("s23")) {
            return basePath + "samsung_s23.png";
        }
        if (name.includes("s24")) {
            return basePath + "samsung_s24_ultra.png";
        }
        if (name.includes("pixel buds") || name.includes("buds pro") || name.includes("buds fe") || name.includes("buds")) {
            return basePath + "pixel_buds.png";
        }
        if (name.includes("xbox") || name.includes("elite")) {
            return basePath + "xbox_elite_series_2.png";
        }

        return "";
    }

    readonly property string resolvedDeviceName: activeDevice ? (activeDevice.name || activeDevice.alias) : deviceName
    readonly property string deviceIcon: activeDevice ? Icons.getBluetoothDeviceMaterialSymbol(activeDevice.icon || "") : "headphones"
    readonly property string deviceImageSource: getDeviceImageSource(activeDevice)
    readonly property bool hasCustomImage: deviceImageSource !== ""

    RowLayout {
        id: contractedLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 10
        visible: !root.isExpanded

        Item {
            id: iconContainer
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignVCenter

            MaterialCookie {
                id: cookieShape
                anchors.centerIn: parent
                implicitSize: 44
                color: Appearance.colors.colPrimaryContainer

                RotationAnimation on rotation {
                    from: 0; to: 360
                    duration: 15000
                    loops: Animation.Infinite
                    running: true
                }
            }

            Loader {
                anchors.centerIn: parent
                active: root.hasCustomImage
                sourceComponent: Image {
                    source: root.deviceImageSource
                    width: 44
                    height: 44
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
            }

            Loader {
                anchors.centerIn: parent
                active: !root.hasCustomImage
                sourceComponent: MaterialSymbol {
                    text: root.deviceIcon
                    iconSize: 28
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: root.resolvedDeviceName !== "" ? root.resolvedDeviceName : Translation.tr("Bluetooth Device")
                font.pixelSize: 18
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
                maximumLineCount: 1
                wrapMode: Text.NoWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: root.action === "connected" ? "bluetooth_connected" : "bluetooth_disabled"
                    iconSize: 14
                    color: root.action === "connected" ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: root.action === "connected" ? Translation.tr("Connected") : Translation.tr("Disconnected")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                // Contracted Battery Indicator (Multi-component breakdown or single progress bar)
                BluetoothBatteryBreakdown {
                    visible: root.devBattery && root.devBattery.available && root.devBattery.components.length > 1
                    batteryInfo: root.devBattery
                    compact: true
                    showCase: false
                }

                RowLayout {
                    visible: (!root.devBattery || !root.devBattery.available || root.devBattery.components.length <= 1) && root.hasBattery
                    spacing: 4

                    StyledProgressBar {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 6
                        valueBarHeight: 6
                        from: 0
                        to: 1
                        value: root.batteryFraction
                        highlightColor: {
                            if (root.batteryFraction <= 0.15) return Appearance.m3colors.m3error;
                            return Appearance.colors.colPrimary;
                        }
                        trackColor: Appearance.colors.colSurfaceContainerHighest
                    }

                    StyledText {
                        text: Math.round(root.batteryFraction * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: {
                            if (root.batteryFraction <= 0.15) return Appearance.m3colors.m3error;
                            return Appearance.colors.colOnSurfaceVariant;
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 14
        visible: root.isExpanded

        Item {
            Layout.preferredWidth: 72
            Layout.preferredHeight: 72
            Layout.alignment: Qt.AlignVCenter

            MaterialCookie {
                id: expandedCookie
                anchors.centerIn: parent
                implicitSize: 68
                color: Appearance.colors.colPrimaryContainer

                RotationAnimation on rotation {
                    from: 0; to: 360
                    duration: 15000
                    loops: Animation.Infinite
                    running: root.isExpanded
                }
            }

            Loader {
                anchors.centerIn: parent
                active: root.hasCustomImage
                sourceComponent: Image {
                    source: root.deviceImageSource
                    width: 52
                    height: 52
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
            }

            Loader {
                anchors.centerIn: parent
                active: !root.hasCustomImage
                sourceComponent: MaterialSymbol {
                    text: root.deviceIcon
                    iconSize: 32
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                text: root.resolvedDeviceName !== "" ? root.resolvedDeviceName : Translation.tr("Bluetooth Device")
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
                maximumLineCount: 1
                wrapMode: Text.NoWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: root.action === "connected" ? "bluetooth_connected" : "bluetooth_disabled"
                    iconSize: 14
                    color: root.action === "connected" ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: root.action === "connected" ? Translation.tr("Connected") : Translation.tr("Disconnected")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                // Expanded Battery: Multi-component breakdown or single progress bar
                BluetoothBatteryBreakdown {
                    visible: root.devBattery && root.devBattery.available && root.devBattery.components.length > 1
                    batteryInfo: root.devBattery
                    compact: true
                    showCase: true
                }

                RowLayout {
                    visible: (!root.devBattery || !root.devBattery.available || root.devBattery.components.length <= 1) && root.hasBattery
                    spacing: 6

                    StyledProgressBar {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 8
                        valueBarHeight: 8
                        from: 0
                        to: 1
                        value: root.batteryFraction
                        highlightColor: {
                            if (root.batteryFraction <= 0.15) return Appearance.m3colors.m3error;
                            return Appearance.colors.colPrimary;
                        }
                        trackColor: Appearance.colors.colSurfaceContainerHighest
                    }

                    StyledText {
                        text: Math.round(root.batteryFraction * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: {
                            if (root.batteryFraction <= 0.15) return Appearance.m3colors.m3error;
                            return Appearance.colors.colOnSurface;
                        }
                    }
                }
            }

            // Dynamic Noise Control Selector (via EarbudsControlService)
            EarbudsNoiseControlSelector {
                visible: root.devNoise && root.devNoise.available && root.devNoise.modes.length > 0
                Layout.fillWidth: true
                compact: true
                modes: root.devNoise ? root.devNoise.modes : []
                currentMode: root.devNoise ? root.devNoise.currentMode : "off"
                onModeRequested: modeKey => {
                    EarbudsControlService.setNoiseMode(root.activeDevice, modeKey);
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: Appearance.rounding.full
                    color: disconnectMa.containsMouse
                        ? Appearance.colors.colErrorContainerHover
                        : Appearance.m3colors.m3errorContainer

                    scale: disconnectMa.pressed ? 0.95 : (disconnectMa.containsMouse ? 1.02 : 1.0)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on scale { NumberAnimation { duration: 150 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "bluetooth_disabled"
                            iconSize: 14
                            color: Appearance.m3colors.m3onErrorContainer
                        }
                        StyledText {
                            text: Translation.tr("Disconnect")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.m3colors.m3onErrorContainer
                        }
                    }

                    MouseArea {
                        id: disconnectMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            if (root.activeDevice) {
                                root.activeDevice.connecting = false;
                                root.activeDevice.connected = false;
                            }
                            GlobalStates.floatingNotchBtDevice = null;
                            GlobalStates.floatingNotchBtAction = "connected";
                            GlobalStates.floatingNotchBtNotifActive = false;
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: Appearance.rounding.full
                    color: settingsMa.containsMouse
                        ? Appearance.colors.colSurfaceContainerHighestHover
                        : Appearance.colors.colSurfaceContainerHighest

                    scale: settingsMa.pressed ? 0.95 : (settingsMa.containsMouse ? 1.02 : 1.0)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on scale { NumberAnimation { duration: 150 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "settings"
                            iconSize: 14
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            text: Translation.tr("Settings")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    MouseArea {
                        id: settingsMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            GlobalStates.floatingNotchBtDevice = null;
                            GlobalStates.floatingNotchBtAction = "connected";
                            GlobalStates.floatingNotchBtNotifActive = false;
                            Quickshell.execDetached(["blueman-manager"]);
                        }
                    }
                }
            }
        }
    }
}
