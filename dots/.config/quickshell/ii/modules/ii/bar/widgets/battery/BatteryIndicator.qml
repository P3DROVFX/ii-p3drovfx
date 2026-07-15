import qs.modules.ii.bar.popups.battery
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
    property bool disablePopup: false
    property bool isMaterial: Config.options.bar.styles.battery === "material"
    property bool vertical: Config.options.bar.vertical

    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isFull: Battery.isFull
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    readonly property bool isCritical: percentage <= Config.options.battery.critical / 100
    readonly property bool effectivelyCharging: root.isCharging || root.isPluggedIn
    readonly property bool chargeLimitReached: Battery.chargeLimitReached
    readonly property bool showCheck: root.chargeLimitReached || (root.isFull && root.effectivelyCharging)

    readonly property bool isPowerSaving: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property bool isPerformance: PowerProfiles.profile === PowerProfile.Performance

    property color colText: Appearance.colors.colOnSurface
    visible: Battery.available

    Component.onCompleted: {
        if (typeof rootItem !== "undefined") {
            rootItem.toggleVisible(Battery.available);
        }
    }

    Connections {
        target: Battery
        function onAvailableChanged() {
            if (typeof rootItem !== "undefined") {
                rootItem.toggleVisible(Battery.available);
            }
        }
    }
    
    implicitWidth: {
        if (root.isMaterial) {
            return rowLoader.item?.width - 1
        }
        if (Config.options.battery.style === "android16") {
            return rowLoader.item?.width + 12;
        }
        if (Config.options.battery.style === "oneui") {
            return rowLoader.item?.implicitWidth + 12;
        }
        return rowLoader.item?.implicitWidth + 12;
    }
    implicitHeight: Appearance.sizes.baseBarHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    Loader {
        id: rowLoader
        active: !root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: root.isMaterial ? rowMaterial : rowDefault

        Component {
            id: rowDefault
            Item {
                implicitWidth: {
                    if (Config.options.battery.style === "android16")
                        return android16Battery.width;
                    if (Config.options.battery.style === "oneui")
                        return oneuiBattery.implicitWidth;
                    return batteryContainerOuter.implicitWidth;
                }

                // ─── OneUI style ──────────────────────────────────────────
                ClippedProgressBar {
                    id: oneuiBattery
                    visible: Config.options.battery.style === "oneui"
                    anchors.centerIn: parent
                    value: root.percentage
                    highlightColor: (root.isLow && !root.effectivelyCharging) ? Appearance.m3colors.m3error : Appearance.colors.colOnSecondaryContainer

                    Rectangle {
                        anchors.fill: parent
                        radius: 2

                        MaterialSymbol {
                            id: boltIcon
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: -2
                            Layout.rightMargin: -2
                            fill: 1
                            text: root.showCheck ? "check" : "bolt"
                            iconSize: Appearance.font.pixelSize.smaller
                            visible: (root.effectivelyCharging || root.showCheck) && root.percentage < 1
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            font: oneuiBattery.font
                            text: oneuiBattery.text
                        }
                    }
                }

                // ─── Android 16 style ────────────────────────────────────
                Item {
                    id: android16Battery
                    visible: Config.options.battery.style === "android16"
                    anchors.centerIn: parent
                    width: 29
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
                                if (root.effectivelyCharging || root.chargeLimitReached)
                                    return '#55c35a';
                                if (root.isPowerSaving)
                                    return "#FFC917";
                                if (root.isPerformance)
                                    return "#42A5F5";
                                return root.colText;
                            }
                            trackColor: {
                                if (root.isLow && !root.effectivelyCharging)
                                    return Appearance.m3colors.m3errorContainer;
                                return Qt.rgba(root.colText.r, root.colText.g, root.colText.b, 0.3);
                            }

                            textMask: Item {
                                width: 26
                                height: 14
                                StyledText {
                                    anchors.centerIn: parent
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    text: batteryProgress.text
                                    color: (root.isLow && !root.effectivelyCharging) ? Appearance.m3colors.m3onError : root.colText
                                }
                            }
                        }

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
                        visible: root.effectivelyCharging || root.showCheck
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.right
                        anchors.horizontalCenterOffset: -1
                        text: root.showCheck ? "check" : "bolt"
                        iconSize: 17
                        fill: 1
                        color: Appearance.colors.colLayer0
                        z: 2
                    }

                    MaterialSymbol {
                        visible: root.effectivelyCharging || root.showCheck
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.right
                        anchors.horizontalCenterOffset: -1
                        text: root.showCheck ? "check" : "bolt"
                        iconSize: 16
                        fill: 1
                        color: root.colText
                        z: 3
                    }
                }

                // ─── Default (legacy) style ─────────────────────────────
                Row {
                    id: batteryContainerOuter
                    visible: Config.options.battery.style !== "android16" && Config.options.battery.style !== "oneui"
                    anchors.centerIn: parent
                    spacing: 7

                    StyledText {
                        visible: (Config.options.bar.battery.showPercentage === "left")
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: (Config.options.bar.battery.showPercentage === "left" || Config.options.bar.battery.showPercentage === "right") ? 0.5 : 0
                        text: Math.round(root.percentage * 100) + "%"
                        color: root.colText
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
                                    if (root.effectivelyCharging || root.chargeLimitReached)
                                        return "#43A047";
                                    if (root.isPowerSaving)
                                        return "#FFC917";
                                    if (root.isPerformance)
                                        return "#42A5F5";
                                    return root.colText;
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
                                return root.colText;
                            }
                            z: 1
                        }

                        MaterialSymbol {
                            visible: root.effectivelyCharging || root.showCheck
                            anchors.top: parent.top
                            anchors.topMargin: root.showCheck ? -3 : -5
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.horizontalCenterOffset: -(parent.width * (4 / 28)) / 2
                            text: root.showCheck ? "check" : "bolt"
                            iconSize: 17
                            fill: 1
                            color: Appearance.colors.colLayer0
                            z: 2
                        }

                        MaterialSymbol {
                            visible: root.effectivelyCharging || root.showCheck
                            anchors.top: parent.top
                            anchors.topMargin: root.showCheck ? -4 : -6
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.horizontalCenterOffset: -(parent.width * (4 / 28)) / 2
                            text: root.showCheck ? "check" : "bolt"
                            iconSize: 16
                            fill: 1
                            color: root.colText
                            z: 3
                        }
                    }

                    StyledText {
                        visible: (Config.options.bar.battery.showPercentage === "right")
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(root.percentage * 100) + "%"
                        color: root.colText
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                    }
                }
            }
        }

        Component {
            id: rowMaterial

            MaterialBarWidget {
                primaryComponent: batteryIndicatorComponent
                secondaryComponent: batteryPercentageComponent
                secondaryExtraMargin: 4
                componentsPadding: 6

                showSecondary: Config.options.bar.battery.showSecondary
                secondaryOpposite: Config.options.bar.battery.secondaryOpposite
                swapPrimaryWithSecondary: Config.options.bar.battery.swapPrimaryWithSecondary
                showPrimary: Config.options.bar.battery.showPrimary

                Component {
                    id: batteryPercentageComponent
                    StyledText {
                        id: text
                        text: Math.round(root.percentage * 100)
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 1
                        color: Config.options.bar.battery.swapPrimaryWithSecondary ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                        font.family: Appearance.font.family.main
                        font.features: { "tnum": 1 }
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                Component {
                    id: batteryIndicatorComponent
                    Item {
                        id: android16Battery
                        anchors.centerIn: parent
                        width: 26
                        height: 14
                        implicitWidth: width

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
                                    if (root.effectivelyCharging || root.chargeLimitReached)
                                        return '#55c35a';
                                    if (root.isPowerSaving)
                                        return "#FFC917";
                                    if (root.isPerformance)
                                        return "#42A5F5";
                                    var color = Config.options.bar.battery.swapPrimaryWithSecondary ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainerHover
                                    return color;
                                }
                                trackColor: {
                                    if (root.isLow && !root.effectivelyCharging)
                                        return Appearance.m3colors.m3errorContainer;
                                    var color = Config.options.bar.battery.swapPrimaryWithSecondary ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainerHover
                                    var opacity = Config.options.bar.battery.swapPrimaryWithSecondary ? 0.3 : 0.6
                                    return Qt.rgba(color.r, color.g, color.b, opacity);
                                }

                                // Custom text mask to include the bolt icon
                                textMask: Item {
                                    width: 26
                                    height: 14

                                    StyledText {
                                        visible: Config.options.bar.battery.showPercentageInsideBattery
                                        anchors.centerIn: parent
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        text: batteryProgress.text
                                        color: (root.isLow && !root.effectivelyCharging) ? Appearance.m3colors.m3onError : root.colText
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
                            visible: root.effectivelyCharging || root.showCheck

                            anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenter: parent.right
                            anchors.horizontalCenterOffset: -1

                            text: root.showCheck ? "check" : "bolt"
                            iconSize: 16
                            fill: 1
                            style: Text.Outline
                            styleColor: batteryProgress.trackColor
                            color: root.colText
                            z: 2
                        }
                    }
                }
            }
        }
    }

    Component {
        id: popupComponent
        BatteryPopup {
            hoverTarget: root
        }
    }

    Loader {
        active: !root.disablePopup
        sourceComponent: popupComponent
    }
}
