import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    signal openWifi()
    signal openBluetooth()
    signal openAudioOutput()

    // The flow binds this on every page it loads; without it the binding
    // logged a missing property each time this step came up.
    property bool nextButtonHovered: false

    readonly property string wifiName: Network.networkName
        || (Network.active ? Network.active.ssid : "")
        || Translation.tr("No network selected")
    readonly property string bluetoothName: BluetoothStatus.firstActiveDevice
        ? BluetoothStatus.firstActiveDevice.name
        : Translation.tr("No device connected")
    readonly property var bluetoothDevice: BluetoothStatus.firstActiveDevice
    readonly property string bluetoothDeviceIcon: root.bluetoothDevice
        ? Icons.getBluetoothDeviceMaterialSymbol(root.bluetoothDevice.icon || "")
        : "bluetooth"
    readonly property bool bluetoothBatteryAvailable: (root.bluetoothDevice && root.bluetoothDevice.batteryAvailable) ? true : false
    readonly property string bluetoothBattery: root.bluetoothBatteryAvailable
        ? String(Math.round(((root.bluetoothDevice && root.bluetoothDevice.battery !== undefined) ? root.bluetoothDevice.battery : 0) * 100)) + "%"
        : Translation.tr("Battery unavailable")
    readonly property string audioName: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : Translation.tr("No output detected")
    readonly property bool wifiConnected: Network.wifiStatus === "connected"
    /**
     * Being online is what this step is actually asking about, and a machine
     * on a cable is online. Keying the card on Wi-Fi alone painted a full red
     * error for the one group of users with nothing left to fix.
     */
    readonly property bool online: root.wifiConnected || Network.ethernet
    readonly property bool wiredOnly: !root.wifiConnected && Network.ethernet
    /**
     * The way out, offered only while there is genuinely nothing connected.
     * A step that is already done needs no permission to leave it.
     */
    readonly property string skipLabel: root.online ? "" : Translation.tr("Set up later")
    property bool wifiConnectionWasKnown: false

    Component.onCompleted: root.wifiConnectionWasKnown = root.wifiConnected

    onWifiConnectedChanged: {
        if (root.wifiConnectionWasKnown && root.wifiConnected)
            wifiConnectFeedback.restart();
        root.wifiConnectionWasKnown = true;
    }

    SequentialAnimation {
        id: wifiConnectFeedback

        NumberAnimation {
            target: wifiStatusChip
            property: "scale"
            to: 1.03
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        NumberAnimation {
            target: wifiStatusChip
            property: "scale"
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.rounding.small

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Connect the essentials before you start.")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.larger
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Appearance.rounding.small

            Rectangle {
                id: wifiCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 420
                Layout.preferredWidth: 2
                radius: Appearance.rounding.large
                color: root.online
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colErrorContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Appearance.rounding.large
                    spacing: Appearance.rounding.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.rounding.small

                        MaterialShapeWrappedMaterialSymbol {
                            text: root.wiredOnly ? "lan" : root.online ? "wifi" : "wifi_off"
                            shape: wifiButton.hovered
                                ? MaterialShape.Shape.Sunny
                                : MaterialShape.Shape.Cookie9Sided
                            iconSize: Appearance.font.pixelSize.huge
                            padding: Appearance.rounding.normal
                            fill: 1
                            rotation: wifiButton.hovered ? 8 : 0
                            color: root.online ? Appearance.colors.colPrimary : Appearance.colors.colError
                            colSymbol: root.online ? Appearance.colors.colOnPrimary : Appearance.colors.colOnError
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: root.wiredOnly ? Translation.tr("Network") : Translation.tr("Wi-Fi")
                            color: root.online ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.hugeass
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillWidth: true }

                        Pill {
                            id: wifiStatusChip
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: wifiStatusChipContent.implicitWidth + Appearance.rounding.normal * 2
                            implicitHeight: Appearance.font.pixelSize.huge + Appearance.rounding.small
                            color: root.online
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colError

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            RowLayout {
                                id: wifiStatusChipContent
                                anchors.fill: parent
                                anchors.leftMargin: Appearance.rounding.small
                                anchors.rightMargin: Appearance.rounding.small
                                spacing: Appearance.rounding.verysmall

                                MaterialSymbol {
                                    id: wifiStatusIcon
                                    text: root.online ? "check" : "error"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: root.online ? Appearance.colors.colOnPrimary : Appearance.colors.colOnError
                                    scale: root.online ? 1 : 0.88

                                    Behavior on scale {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }

                                StyledText {
                                    text: root.online
                                        ? Translation.tr("Connected")
                                        : Translation.tr("Not connected")
                                    color: root.online ? Appearance.colors.colOnPrimary : Appearance.colors.colOnError
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.wifiName
                        color: root.online ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.wiredOnly
                            ? Translation.tr("You are online through a wired connection.")
                            : root.wifiConnected
                                ? Translation.tr("Wireless connection is active.")
                                : Translation.tr("Choose a network to bring your desktop online. You can also do this later.")
                        color: root.online ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                        font.family: Appearance.font.family.main
                        font.variableAxes: Appearance.font.variableAxes.rounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true }

                    RippleButtonWithIcon {
                        id: wifiButton
                        Layout.alignment: Qt.AlignLeft
                        Layout.fillWidth: true
                        implicitHeight: 60
                        hoverEnabled: true
                        buttonRadius: Appearance.rounding.full
                        horizontalPadding: Appearance.rounding.large
                        materialIcon: "router"
                        mainText: Translation.tr("Set up Wi-Fi")
                        mainTextWeight: Font.Bold
                        mainTextFontFamily: Appearance.font.family.title
                        mainTextVariableAxes: Appearance.font.variableAxes.titleRounded
                        centerContent: true
                        iconPixelSize: Appearance.font.pixelSize.huge
                        textPixelSize: Appearance.font.pixelSize.larger
                        contentSpacing: Appearance.rounding.small
                        colText: root.online ? Appearance.colors.colOnPrimary : Appearance.colors.colOnError
                        colBackground: root.online ? Appearance.colors.colPrimary : Appearance.colors.colError
                        colBackgroundHover: root.online ? Appearance.colors.colPrimaryHover : Appearance.colors.colErrorHover
                        colBackgroundActive: root.online ? Appearance.colors.colPrimaryActive : Appearance.colors.colErrorActive
                        colRipple: root.online ? Appearance.colors.colPrimaryActive : Appearance.colors.colErrorContainerActive
                        onClicked: root.openWifi()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 300
                Layout.preferredWidth: 1
                spacing: Appearance.rounding.small

                Rectangle {
                    id: bluetoothCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Appearance.rounding.normal
                        spacing: Appearance.rounding.small

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Appearance.rounding.small
                            MaterialShapeWrappedMaterialSymbol {
                                text: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"
                                shape: bluetoothButton.hovered
                                    ? MaterialShape.Shape.Burst
                                    : MaterialShape.Shape.Cookie7Sided
                                iconSize: Appearance.font.pixelSize.huge
                                padding: Appearance.rounding.small
                                rotation: bluetoothButton.hovered ? -8 : 0
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Bluetooth")
                                color: Appearance.colors.colOnLayer1
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.Bold
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Appearance.rounding.verysmall

                            MaterialSymbol {
                                text: root.bluetoothDeviceIcon
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                id: bluetoothNameLabel
                                Layout.fillWidth: true
                                text: root.bluetoothName
                                color: Appearance.colors.colOnLayer2
                                font.family: Appearance.font.family.main
                                font.variableAxes: Appearance.font.variableAxes.rounded
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Bold
                                elide: Text.ElideRight

                                transform: Translate {
                                    y: root.bluetoothDevice ? 0 : Appearance.rounding.verysmall

                                    Behavior on y {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }
                            }

                            StyledText {
                                id: bluetoothBatteryLabel
                                text: root.bluetoothBatteryAvailable ? root.bluetoothBattery : ""
                                color: Appearance.colors.colOnLayer2
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Bold
                                Layout.preferredWidth: root.bluetoothBatteryAvailable ? implicitWidth : 0
                                Layout.minimumWidth: 0
                                opacity: root.bluetoothBatteryAvailable ? 1 : 0

                                Behavior on Layout.preferredWidth {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        RippleButtonWithIcon {
                            id: bluetoothButton
                            Layout.fillWidth: true
                            implicitHeight: 58
                            hoverEnabled: true
                            buttonRadius: Appearance.rounding.full
                            horizontalPadding: Appearance.rounding.large
                            materialIcon: "bluetooth"
                            mainText: Translation.tr("Set up")
                            mainTextWeight: Font.Bold
                            mainTextFontFamily: Appearance.font.family.title
                            mainTextVariableAxes: Appearance.font.variableAxes.titleRounded
                            centerContent: true
                            iconPixelSize: Appearance.font.pixelSize.huge
                            textPixelSize: Appearance.font.pixelSize.larger
                            contentSpacing: Appearance.rounding.small
                            colText: Appearance.colors.colOnSecondaryContainer
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                            colRipple: Appearance.colors.colSecondaryContainerActive
                            onClicked: root.openBluetooth()
                        }
                    }
                }

                Rectangle {
                    id: audioCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Appearance.rounding.normal
                        spacing: Appearance.rounding.small

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Appearance.rounding.small
                            MaterialShapeWrappedMaterialSymbol {
                                text: Audio.muted ? "volume_off" : "volume_up"
                                shape: audioButton.hovered
                                    ? MaterialShape.Shape.SoftBurst
                                    : MaterialShape.Shape.Cookie7Sided
                                iconSize: Appearance.font.pixelSize.huge
                                padding: Appearance.rounding.small
                                rotation: audioButton.hovered ? 8 : 0
                                scale: Audio.muted ? 0.92 : 1

                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Audio")
                                color: Appearance.colors.colOnLayer1
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.Bold
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Audio.sink
                                ? Translation.tr("%1 · %2%").arg(root.audioName).arg(String(Math.round(Audio.value * 100)))
                                : root.audioName
                            color: Appearance.colors.colOnLayer2
                            font.family: Appearance.font.family.main
                            font.variableAxes: Appearance.font.variableAxes.rounded
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillHeight: true }

                        RippleButtonWithIcon {
                            id: audioButton
                            Layout.fillWidth: true
                            implicitHeight: 58
                            hoverEnabled: true
                            buttonRadius: Appearance.rounding.full
                            horizontalPadding: Appearance.rounding.large
                            materialIcon: "tune"
                            mainText: Translation.tr("Choose output")
                            mainTextWeight: Font.Bold
                            mainTextFontFamily: Appearance.font.family.title
                            mainTextVariableAxes: Appearance.font.variableAxes.titleRounded
                            centerContent: true
                            iconPixelSize: Appearance.font.pixelSize.huge
                            textPixelSize: Appearance.font.pixelSize.larger
                            contentSpacing: Appearance.rounding.small
                            colText: Appearance.colors.colOnSecondaryContainer
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                            colRipple: Appearance.colors.colSecondaryContainerActive
                            onClicked: root.openAudioOutput()
                        }
                    }
                }
            }
        }
    }
}
