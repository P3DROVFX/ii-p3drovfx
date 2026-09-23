pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell.Bluetooth
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * A device connecting or disconnecting, as one strip across the island.
 *
 * The announcement only says what happened: the photo, the name, the state and the
 * battery. Controls live in the earbuds bubble, which stays for as long as a headset is
 * connected; a phone or a mouse just announces itself and goes.
 *
 * The state line reads the device itself rather than the event that brought the strip
 * up, so a disconnect can never say "Connected", and a Reconnect pressed here shows
 * "Connecting…" and then the result without a second announcement (a device returning
 * inside BluetoothSource's flap window would not get one).
 */
Item {
    id: root
    anchors.fill: parent

    /**
     * The device and the event, held through the fade-out: BluetoothSource clears both the
     * moment it dismisses, and the strip would blank while it is still leaving.
     */
    property var device: null
    property string action: "connected"

    function capture() {
        if (!GlobalStates.floatingNotchBtDevice)
            return;
        root.device = GlobalStates.floatingNotchBtDevice;
        root.action = GlobalStates.floatingNotchBtAction;
    }
    Component.onCompleted: root.capture()
    Connections {
        target: GlobalStates
        function onFloatingNotchBtDeviceChanged() {
            root.capture();
        }
        function onFloatingNotchBtActionChanged() {
            root.capture();
        }
    }

    readonly property string deviceName: root.device ? (root.device.name || root.device.alias || "") : ""
    readonly property bool connecting: root.device !== null && root.device.state === BluetoothDeviceState.Connecting
    readonly property bool isConnected: root.device ? root.device.connected : root.action === "connected"

    readonly property var battery: root.isConnected ? EarbudsControlService.batteryInfo(root.device) : null
    readonly property var budLevels: {
        const info = root.battery;
        if (!info || !info.available)
            return null;
        const left = info.components.find(c => c && c.id === "left" && c.available);
        const right = info.components.find(c => c && c.id === "right" && c.available);
        return (left && right) ? { left: left.level, right: right.level } : null;
    }
    readonly property var percent: root.isConnected ? EarbudsControlService.primaryBatteryPercent(root.device) : null
    readonly property bool hasBattery: root.percent !== null

    readonly property string imageSource: BluetoothDeviceImages.sourceFor(root.device)
    readonly property real imageSize: 38

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 16
        spacing: 12

        // The photo on a still cookie; greyed once the device is gone.
        Item {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            Layout.alignment: Qt.AlignVCenter

            MaterialCookie {
                anchors.centerIn: parent
                implicitSize: 44
                sides: 9
                color: root.isConnected ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colSurfaceContainerHighest
            }

            Image {
                id: photo
                anchors.centerIn: parent
                width: root.imageSize
                height: root.imageSize
                source: root.imageSource
                sourceSize: Qt.size(Math.ceil(root.imageSize * Screen.devicePixelRatio),
                    Math.ceil(root.imageSize * Screen.devicePixelRatio))
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                opacity: root.isConnected ? 1 : 0.45
                visible: root.imageSource !== "" && status === Image.Ready
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !photo.visible
                text: root.device ? Icons.getBluetoothDeviceMaterialSymbol(root.device.icon || "") : "bluetooth"
                iconSize: 24
                color: root.isConnected ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnSurfaceVariant
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.deviceName !== "" ? root.deviceName : Translation.tr("Bluetooth device")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
                maximumLineCount: 1
                wrapMode: Text.NoWrap
            }

            RowLayout {
                spacing: 5

                MaterialSymbol {
                    text: root.isConnected ? "bluetooth_connected"
                        : root.connecting ? "bluetooth_searching" : "bluetooth_disabled"
                    iconSize: 15
                    color: root.isConnected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: root.isConnected ? Translation.tr("Connected")
                        : root.connecting ? Translation.tr("Connecting…") : Translation.tr("Disconnected")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        // Connected: the battery. Gone: a way back.
        RowLayout {
            visible: root.isConnected && root.hasBattery
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            StyledText {
                text: root.budLevels ? `L ${root.budLevels.left} · R ${root.budLevels.right}` : `${root.percent}%`
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
                color: (root.percent ?? 100) <= 15 ? Appearance.m3colors.m3error : Appearance.colors.colOnSurfaceVariant
            }

            StyledProgressBar {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 5
                valueBarHeight: 5
                from: 0
                to: 100
                value: root.percent ?? 0
                highlightColor: (root.percent ?? 100) <= 15 ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                trackColor: Appearance.colors.colSurfaceContainerHighest
            }
        }

        RippleButton {
            visible: !root.isConnected && root.device !== null
            enabled: !root.connecting
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 32
            implicitWidth: reconnectRow.implicitWidth + 26
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            opacity: root.connecting ? 0.6 : 1
            onClicked: root.device?.connect()

            contentItem: RowLayout {
                id: reconnectRow
                spacing: 5

                MaterialSymbol {
                    text: "bluetooth_connected"
                    iconSize: 16
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    text: Translation.tr("Reconnect")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }
}
