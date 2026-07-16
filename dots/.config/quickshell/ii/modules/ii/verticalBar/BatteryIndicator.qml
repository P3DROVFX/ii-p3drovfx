import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.popups.battery
import Quickshell.Services.UPower

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool disablePopup: false
    property bool isMaterial: Config.options.bar.styles.battery === "material"
    property bool vertical: Config.options.bar.vertical
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
    property color colText: Appearance.colors.colOnSurface

    readonly property bool isPowerSaving: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property bool isPerformance: PowerProfiles.profile === PowerProfile.Performance

    readonly property color fillColor: {
        if (root.isCritical && !root.isCharging)
            return "#E53935";
        if (root.isLow && !root.isCharging)
            return "#FB8C00";
        return "#43A047";
    }

    readonly property color frameColor: {
        if (root.isCritical && !root.isCharging)
            return Appearance.m3colors.m3error;
        if (root.isLow && !root.isCharging)
            return Appearance.m3colors.m3error;
        return root.colText;
    }

    implicitWidth: Appearance.sizes.baseVerticalBarWidth
    implicitHeight: colLoader.item?.implicitHeight + (root.isMaterial ? 0 : 12)

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined

    Loader {
        id: colLoader
        active: root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: root.isMaterial ? colMaterial : colDefault

        Component {
            id: colDefault

            ColumnLayout {
                id: mainLayout
                anchors.centerIn: parent
                spacing: 2

                // 1. OneUI Style
                ClippedProgressBar {
                    id: oneuiBattery
                    visible: Config.options.battery.style === "oneui"
                    Layout.alignment: Qt.AlignHCenter
                    vertical: true
                    valueBarWidth: 21
                    valueBarHeight: 40
                    value: root.percentage
                    highlightColor: (root.isLow && !root.isCharging) ? Appearance.m3colors.m3error : Appearance.colors.colOnSecondaryContainer

                    font {
                        pixelSize: text.length > 2 ? 11 : 13
                        weight: text.length > 2 ? Font.Medium : Font.DemiBold
                    }

                    textMask: Item {
                        width: oneuiBattery.valueBarWidth
                        height: oneuiBattery.valueBarHeight

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: 2

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                fill: 1
                                renderType: Text.QtRendering
                                text: "bolt"
                                iconSize: Appearance.font.pixelSize.smaller
                                visible: root.isCharging || root.isPluggedIn
                            }

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                width: parent.width
                                height: percentageText.implicitWidth

                                StyledText {
                                    id: percentageText
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 1
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    renderType: Text.QtRendering
                                    font: oneuiBattery.font
                                    text: oneuiBattery.text
                                    rotation: -90
                                }
                            }
                        }
                    }
                }

                // 2. Android 16 Style
                Item {
                    id: android16Battery
                    visible: Config.options.battery.style === "android16"
                    Layout.alignment: Qt.AlignHCenter
                    width: 16
                    height: 32

                    Item {
                        anchors.centerIn: parent
                        width: 32
                        height: 16
                        rotation: -90
                        antialiasing: true

                        Row {
                            anchors.centerIn: parent
                            spacing: 1

                            ClippedProgressBar {
                                id: batteryProgress
                                width: 28
                                height: 16
                                radius: 4.5
                                value: root.percentage
                                antialiasing: true

                                highlightColor: {
                                    if (root.isLow && !root.isCharging)
                                        return Appearance.m3colors.m3error;
                                    if (root.isCharging || root.isPluggedIn)
                                        return "#43A047";
                                    return root.frameColor;
                                }
                                trackColor: Qt.rgba(root.frameColor.r, root.frameColor.g, root.frameColor.b, 0.3)

                                textMask: Item {
                                    width: 28
                                    height: 16
                                    StyledText {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: 1
                                        renderType: Text.QtRendering
                                        text: Math.round(root.percentage * 100)
                                        font.pixelSize: 10
                                        font.weight: Font.Black
                                        color: "white"
                                    }
                                }
                            }

                            Rectangle {
                                width: 2
                                height: 6
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 1
                                antialiasing: true
                                color: (root.percentage >= 0.98) ? batteryProgress.highlightColor : batteryProgress.trackColor
                            }
                        }

                        MaterialSymbol {
                            visible: root.isCharging || root.isPluggedIn
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenter: parent.right
                            anchors.horizontalCenterOffset: -1
                            renderType: Text.QtRendering
                            text: "bolt"
                            iconSize: 14
                            fill: 1
                            color: root.colText
                        }
                    }
                }

                // 3. Classic / Default Style
                Column {
                    id: batteryContainerOuter
                    visible: Config.options.battery.style !== "android16" && Config.options.battery.style !== "oneui"
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 7

                    Item {
                        visible: (Config.options.bar.battery.showPercentage === "left")
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: percentageTextLeft.implicitHeight
                        height: percentageTextLeft.implicitWidth

                        StyledText {
                            id: percentageTextLeft
                            anchors.centerIn: parent
                            text: Math.round(root.percentage * 100) + "%"
                            color: root.colText
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            rotation: -90
                        }
                    }

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 30
                        width: 14

                        Item {
                            anchors.centerIn: parent
                            width: 30
                            height: 14
                            rotation: -90
                            antialiasing: true

                            Item {
                                id: batteryContainer
                                anchors.fill: parent

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
                        }
                    }

                    Item {
                        visible: (Config.options.bar.battery.showPercentage === "right")
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: percentageTextRight.implicitHeight
                        height: percentageTextRight.implicitWidth

                        StyledText {
                            id: percentageTextRight
                            anchors.centerIn: parent
                            text: Math.round(root.percentage * 100) + "%"
                            color: root.colText
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            rotation: -90
                        }
                    }
                }
            }
        }

        Component {
            id: colMaterial

            VerticalMaterialBarWidget {
                primaryComponent: batteryIndicatorComponent
                secondaryComponent: batteryPercentageComponent

                showSecondary: Config.options.bar.battery.showSecondary
                secondaryOpposite: Config.options.bar.battery.secondaryOpposite
                swapPrimaryWithSecondary: Config.options.bar.battery.swapPrimaryWithSecondary
                showPrimary: Config.options.bar.battery.showPrimary
                
                Component {
                    id: batteryPercentageComponent
                    StyledText {
                        id: text
                        text: Math.round(root.percentage * 100)
                        anchors.horizontalCenter: parent.horizontalCenter
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
                        width: 16
                        height: 38
                        implicitHeight: height
                        
                        Item {
                            anchors.centerIn: parent
                            width: 32
                            height: 16
                            rotation: -90
                            antialiasing: true

                            Row {
                                anchors.centerIn: parent
                                spacing: 1

                                ClippedProgressBar {
                                    id: batteryProgress
                                    width: 28
                                    height: 16
                                    radius: 4.5
                                    value: root.percentage
                                    antialiasing: true

                                    highlightColor: {
                                        if (root.isLow && !root.effectivelyCharging)
                                            return Appearance.m3colors.m3error;
                                        if (root.effectivelyCharging)
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

                                    textMask: Item {
                                        width: 28
                                        height: 16
                                        StyledText {
                                            visible: Config.options.bar.battery.showPercentageInsideBattery
                                            anchors.centerIn: parent
                                            renderType: Text.QtRendering
                                            text: Math.round(root.percentage * 100)
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: "white"
                                            rotation: 90
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 2
                                    height: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 1
                                    antialiasing: true
                                    color: (root.percentage >= 0.98) ? batteryProgress.highlightColor : batteryProgress.trackColor
                                }
                            }

                            MaterialSymbol {
                                visible: root.effectivelyCharging

                                anchors.verticalCenter: parent.verticalCenter
                                anchors.horizontalCenter: parent.right
                                anchors.horizontalCenterOffset: -2
                                
                                text: "bolt"
                                iconSize: 16
                                fill: 1
                                style: Text.Outline
                                styleColor: batteryProgress.trackColor
                                color: root.colText
                                rotation: 90
                            }
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
