pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.bluetooth
import qs.modules.common.widgets.bluetooth.budslink

Rectangle {
    id: root

    required property BluetoothDevice device
    property bool isFirst: false
    property bool isLast: false
    property bool expanded: false

    readonly property string deviceName: {
        const name = root.device?.name ?? "";
        if (name.length > 0)
            return name;
        return root.device?.deviceName ?? root.device?.address ?? "";
    }
    readonly property string address: root.device?.address ?? ""
    readonly property bool isConnected: root.device?.connected ?? false
    readonly property bool isPaired: root.device?.paired ?? false
    readonly property bool isPairing: root.device?.pairing ?? false
    readonly property int state: root.device?.state ?? BluetoothDeviceState.Disconnected
    readonly property bool busy: root.isPairing || root.state === BluetoothDeviceState.Connecting
        || root.state === BluetoothDeviceState.Disconnecting

    readonly property var batteryData: EarbudsControlService.batteryInfo(root.device)
    readonly property var noiseData: EarbudsControlService.noiseControl(root.device)
    readonly property var caData: EarbudsControlService.conversationAwareness(root.device)
    readonly property bool hasSettingsBtn: EarbudsControlService.supports(root.device, "deviceSettings")

    readonly property real outerRadius: Appearance.rounding.normal
    readonly property real innerRadius: Appearance.rounding.verysmall

    Layout.fillWidth: true
    implicitHeight: cardContent.implicitHeight
    topLeftRadius: root.isFirst ? root.outerRadius : root.innerRadius
    topRightRadius: root.isFirst ? root.outerRadius : root.innerRadius
    bottomLeftRadius: root.isLast ? root.outerRadius : root.innerRadius
    bottomRightRadius: root.isLast ? root.outerRadius : root.innerRadius
    color: Appearance.colors.colSecondaryContainer
    clip: true

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    ColumnLayout {
        id: cardContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // Header (Click to expand/collapse)
        Item {
            Layout.fillWidth: true
            implicitHeight: 64

            MouseArea {
                id: headerArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }

            Rectangle {
                anchors.fill: parent
                topLeftRadius: root.topLeftRadius
                topRightRadius: root.topRightRadius
                bottomLeftRadius: root.expanded ? 0 : root.bottomLeftRadius
                bottomRightRadius: root.expanded ? 0 : root.bottomRightRadius
                color: headerArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                opacity: 0.4
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 12

                MaterialSymbol {
                    Layout.preferredWidth: 24
                    text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon ?? "")
                    fill: 1
                    iconSize: 24
                    color: Appearance.colors.colOnSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: root.deviceName
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        // BudsLink pill badge
                        Rectangle {
                            implicitWidth: badgeText.implicitWidth + 12
                            implicitHeight: 20
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimary

                            StyledText {
                                id: badgeText
                                anchors.centerIn: parent
                                text: "BudsLink"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimary
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: {
                            const parts = [Translation.tr("Connected")];
                            if (root.noiseData && root.noiseData.available && root.noiseData.currentModeLabel) {
                                parts.push(root.noiseData.currentModeLabel);
                            }
                            parts.push(root.address);
                            return parts.join("  •  ");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                // Compact battery in collapsed header
                BluetoothBatteryBreakdown {
                    visible: !root.expanded && root.batteryData && root.batteryData.available
                    batteryInfo: root.batteryData
                    compact: true
                    showCase: true
                    Layout.alignment: Qt.AlignVCenter
                }

                MaterialSymbol {
                    visible: root.device?.trusted ?? false
                    text: "verified_user"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.normal
                    color: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.35)
                }

                MaterialLoadingIndicator {
                    visible: root.busy
                    loading: root.busy
                    implicitSize: 20
                }

                MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: headerArea.containsMouse ? 1 : 0.7
                    rotation: root.expanded ? 0 : -90

                    Behavior on rotation {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }
            }
        }

        // Expanded details & controls
        Item {
            Layout.fillWidth: true
            implicitHeight: root.expanded ? expandedCol.implicitHeight + 20 : 0
            clip: true

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            ColumnLayout {
                id: expandedCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 4
                opacity: root.expanded ? 1 : 0
                spacing: 14

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }

                // 1. Detailed Battery Breakdown
                BluetoothBatteryBreakdown {
                    visible: root.batteryData && root.batteryData.available
                    batteryInfo: root.batteryData
                    compact: false
                    showLabels: true
                    showCase: true
                    horizontal: true
                    Layout.fillWidth: true
                }

                // 2. Primary Noise Control Selector
                ColumnLayout {
                    visible: root.noiseData && root.noiseData.available && root.noiseData.modes.length > 0
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Noise Control")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    EarbudsNoiseControlSelector {
                        Layout.fillWidth: true
                        modes: root.noiseData ? root.noiseData.modes : []
                        currentMode: root.noiseData ? root.noiseData.currentMode : "off"
                        onModeRequested: modeKey => {
                            EarbudsControlService.setNoiseMode(root.device, modeKey);
                        }
                    }
                }

                // 3. Conversation Awareness Toggle
                EarbudsConversationAwareness {
                    visible: root.caData && root.caData.available
                    enabled: root.caData ? root.caData.enabled : false
                    available: root.caData ? root.caData.available : false
                    title: (root.caData && root.caData.title) ? root.caData.title : Translation.tr("Conversation Awareness")
                    onToggled: en => {
                        EarbudsControlService.setConversationAwareness(root.device, en);
                    }
                }

                // 4. Dynamic Option Boxes & Sliders
                BudsLinkDynamicControls {
                    device: root.device
                }

                // 5. Open Full BudsLink Settings Window
                RowLayout {
                    visible: root.hasSettingsBtn
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        materialIcon: "tune"
                        mainText: Translation.tr("Device settings")
                        colBackground: Appearance.colors.colSurfaceContainerHighest
                        colText: Appearance.colors.colOnSurface
                        onClicked: {
                            EarbudsControlService.openDeviceSettings(root.device);
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // Separator
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.85)
                }

                // 6. Reused BlueZ Actions (Connect/Disconnect, Forget, Trusted, Blocked, Rename)
                BluetoothDeviceActions {
                    device: root.device
                }
            }
        }
    }
}
