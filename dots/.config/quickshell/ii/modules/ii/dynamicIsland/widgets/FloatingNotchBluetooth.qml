import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
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

    function getDeviceImageSource(device) {
        if (!device) return "";
        let custom = Config.options.bluetoothDeviceImages.find(d => d.mac === device.address);
        if (custom) {
            return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
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
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 14
        visible: !root.isExpanded

        Item {
            id: iconContainer
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            Layout.alignment: Qt.AlignVCenter

            MaterialCookie {
                id: cookieShape
                anchors.centerIn: parent
                implicitSize: 60
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

                RowLayout {
                    visible: root.activeDevice ? root.activeDevice.batteryAvailable : false
                    spacing: 4

                    StyledProgressBar {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 6
                        valueBarHeight: 6
                        from: 0
                        to: 1
                        value: root.activeDevice ? root.activeDevice.battery : 0
                        highlightColor: {
                            const battery = root.activeDevice ? root.activeDevice.battery : 0;
                            if (battery <= 0.15) return Appearance.m3colors.m3error;
                            return Appearance.colors.colPrimary;
                        }
                        trackColor: Appearance.colors.colSurfaceContainerHighest
                    }

                    StyledText {
                        text: root.activeDevice ? Math.round(root.activeDevice.battery * 100) + "%" : ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: {
                            const battery = root.activeDevice ? root.activeDevice.battery : 0;
                            if (battery <= 0.15) return Appearance.m3colors.m3error;
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

                RowLayout {
                    visible: root.activeDevice ? root.activeDevice.batteryAvailable : false
                    spacing: 6

                    StyledProgressBar {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 8
                        valueBarHeight: 8
                        from: 0
                        to: 1
                        value: root.activeDevice ? root.activeDevice.battery : 0
                        highlightColor: {
                            const battery = root.activeDevice ? root.activeDevice.battery : 0;
                            if (battery <= 0.15) return Appearance.m3colors.m3error;
                            return Appearance.colors.colPrimary;
                        }
                        trackColor: Appearance.colors.colSurfaceContainerHighest
                    }

                    StyledText {
                        text: root.activeDevice ? Math.round(root.activeDevice.battery * 100) + "%" : ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: {
                            const battery = root.activeDevice ? root.activeDevice.battery : 0;
                            if (battery <= 0.15) return Appearance.m3colors.m3error;
                            return Appearance.colors.colOnSurface;
                        }
                    }
                }
            }

            Loader {
                active: root.activeDevice && (SoundcoreService.isHeadsetSupported(root.activeDevice) || BudsService.isHeadsetSupported(root.activeDevice))
                Layout.fillWidth: true
                sourceComponent: RowLayout {
                    spacing: 6

                    readonly property var service: {
                        if (SoundcoreService.isHeadsetSupported(root.activeDevice)) return SoundcoreService;
                        if (BudsService.isHeadsetSupported(root.activeDevice)) return BudsService;
                        return null;
                    }
                    readonly property string currentMode: service ? service.getModeForMac(root.activeDevice.address) : "Normal"

                    RippleButton {
                        id: ancBtn
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: 13
                        colBackground: parent.currentMode === "NoiseCanceling" ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                        colBackgroundHover: parent.currentMode === "NoiseCanceling" ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                        onClicked: parent.service.setMode(root.activeDevice.address, "NoiseCanceling")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "noise_control_off"
                            iconSize: 14
                            color: ancBtn.colBackground === Appearance.colors.colPrimary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    RippleButton {
                        id: normalBtn
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: 13
                        colBackground: parent.currentMode === "Normal" ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                        colBackgroundHover: parent.currentMode === "Normal" ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                        onClicked: parent.service.setMode(root.activeDevice.address, "Normal")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "hearing"
                            iconSize: 14
                            color: normalBtn.colBackground === Appearance.colors.colPrimary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    RippleButton {
                        id: transBtn
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: 13
                        colBackground: parent.currentMode === "Transparency" ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                        colBackgroundHover: parent.currentMode === "Transparency" ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                        onClicked: parent.service.setMode(root.activeDevice.address, "Transparency")

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "visibility"
                            iconSize: 14
                            color: transBtn.colBackground === Appearance.colors.colPrimary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                    }
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
