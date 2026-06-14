import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless

    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isFull: Battery.isFull
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    readonly property bool isCritical: percentage <= Config.options.battery.critical / 100
    readonly property bool effectivelyCharging: root.isCharging || root.isPluggedIn

    readonly property bool isPowerSaving: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property bool isPerformance: PowerProfiles.profile === PowerProfile.Performance

    property color textColor: Appearance.colors.colOnSurface
    visible: Battery.available

    implicitWidth: {
        if (Config.options.battery.style === "android16")
            return android16Battery.width + 12;
        if (Config.options.battery.style === "oneui")
            return oneuiBattery.implicitWidth + 12;
        return batteryContainerOuter.implicitWidth + 12;
    }
    implicitHeight: Appearance.sizes.baseBarHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    ClippedProgressBar {
        id: oneuiBattery
        visible: Config.options.battery.style === "oneui"
        anchors.centerIn: parent
        value: root.percentage
        highlightColor: (root.isLow && !root.effectivelyCharging) ? Appearance.m3colors.m3error : Appearance.colors.colOnSecondaryContainer

        Item {
            anchors.centerIn: parent
            width: oneuiBattery.valueBarWidth
            height: oneuiBattery.valueBarHeight

            RowLayout {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: (parent.height - height) / 2
                }
                spacing: 0

                MaterialSymbol {
                    id: boltIcon
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: -2
                    Layout.rightMargin: -2
                    fill: 1
                    text: "bolt"
                    iconSize: Appearance.font.pixelSize.smaller
                    visible: root.effectivelyCharging && root.percentage < 1 // TODO: animation
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    font: oneuiBattery.font
                    text: oneuiBattery.text
                }
            }
        }
    }

    Item {
        id: android16Battery
        visible: Config.options.battery.style === "android16"
        anchors.centerIn: parent
        width: 29 // 26 (bar) + 1 (spacing) + 2 (tip)
        height: 14

        Row {
            anchors.centerIn: parent
            spacing: 1

            ClippedProgressBar {
                id: batteryProgress
                width: 26
                height: 14

                radius: 4.5

                value: root.percentage
                highlightColor: {
                    if (root.isLow && !root.effectivelyCharging)
                        return Appearance.m3colors.m3error;
                    if (root.effectivelyCharging)
                        return '#55c35a';
                    if (root.isPowerSaving)
                        return "#FFC917";
                    if (root.isPerformance)
                        return "#42A5F5";
                    return root.textColor;
                }
                trackColor: {
                    if (root.isLow && !root.effectivelyCharging)
                        return Appearance.m3colors.m3errorContainer;
                    return Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.3);
                }

                // Custom text mask to include the bolt icon
                textMask: Item {
                    width: 26
                    height: 14

                    StyledText {
                        anchors.centerIn: parent
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        text: batteryProgress.text
                        color: (root.isLow && !root.effectivelyCharging) ? Appearance.m3colors.m3onError : root.textColor
                    }
                }
            }

            // Battery Tip
            Rectangle {
                id: batteryTip
                width: 2
                height: 6
                anchors.verticalCenter: parent.verticalCenter
                radius: 1
                color: (root.percentage >= 0.98) ? batteryProgress.highlightColor : batteryProgress.trackColor
            }
        }

        MaterialSymbol {
            visible: root.effectivelyCharging

            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.right
            anchors.horizontalCenterOffset: -1

            text: "bolt"
            iconSize: 17
            fill: 1
            color: Appearance.colors.colLayer0
            z: 2
        }

        MaterialSymbol {
            visible: root.effectivelyCharging

            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.right
            anchors.horizontalCenterOffset: -1

            text: "bolt"
            iconSize: 16
            fill: 1
            color: root.textColor
            z: 3
        }
    }

    Row {
        id: batteryContainerOuter
        visible: Config.options.battery.style !== "android16" && Config.options.battery.style !== "oneui"
        anchors.centerIn: parent
        spacing: 7

        StyledText {
            visible: (Config.options.battery.showPercentage === "left")
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: (Config.options.battery.showPercentage === "left" || Config.options.battery.showPercentage === "right") ? 0.5 : 0
            text: Math.round(root.percentage * 100) + "%"
            color: root.textColor
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Bold
        }

        Item {
            id: batteryContainer
            anchors.verticalCenter: parent.verticalCenter
            height: 14
            width: height * (28 / 13)

            Item {
                id: fillClipping
                clip: true
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.leftMargin: 3

                readonly property real clampedPct: Math.max(0, Math.min(1, root.percentage))
                width: (batteryContainer.width - 9) * clampedPct
                z: 0

                Rectangle {
                    y: 3
                    anchors.left: parent.left

                    height: 8
                    width: batteryContainer.width - 9
                    radius: 2

                    color: {
                        if (root.isCritical && !root.effectivelyCharging)
                            return "#E53935";
                        if (root.isLow && !root.effectivelyCharging)
                            return "#FB8C00";
                        if (root.effectivelyCharging)
                            return "#43A047";
                        if (root.isPowerSaving)
                            return "#FFC917";
                        if (root.isPerformance)
                            return "#42A5F5";
                        return root.textColor;
                    }
                }
            }

            CustomIcon {
                anchors.fill: parent
                source: "Battery.svg"
                colorize: true
                color: {
                    if (root.isCritical && !root.effectivelyCharging)
                        return Appearance.m3colors.m3error;
                    if (root.isLow && !root.effectivelyCharging)
                        return Appearance.m3colors.m3error;
                    return root.textColor;
                }
                z: 1
            }

            MaterialSymbol {
                visible: root.effectivelyCharging

                anchors.top: parent.top
                anchors.topMargin: -5
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: -(parent.width * (4 / 28)) / 2

                text: "bolt"
                iconSize: 17
                fill: 1
                color: Appearance.colors.colLayer0
                z: 2
            }

            MaterialSymbol {
                visible: root.effectivelyCharging

                anchors.top: parent.top
                anchors.topMargin: -6
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: -(parent.width * (4 / 28)) / 2

                text: "bolt"
                iconSize: 16
                fill: 1
                color: root.textColor
                z: 3
            }
        }

        StyledText {
            visible: (Config.options.battery.showPercentage === "right")
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.percentage * 100) + "%"
            color: root.textColor
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Bold
        }
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
