import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    visible: Battery.available

    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isFull: Battery.isFull
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    readonly property bool isCritical: percentage <= Config.options.battery.critical / 100
    property color textColor: Appearance.colors.colOnSurface

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
        return root.textColor;
    }

    implicitWidth: Appearance.sizes.baseVerticalBarWidth
    implicitHeight: mainLayout.implicitHeight + 12

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined

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
                    color: root.textColor
                }
            }
        }

        // 3. Classic / Default Style
        Item {
            id: batteryContainer
            visible: Config.options.battery.style !== "android16" && Config.options.battery.style !== "oneui"
            Layout.alignment: Qt.AlignHCenter
            height: 24
            width: 12

            Item {
                anchors.centerIn: parent
                width: 24
                height: 12
                rotation: -90
                antialiasing: true

                Item {
                    id: fillClipping
                    clip: true
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left

                    readonly property real clampedPct: Math.max(0, Math.min(1, root.percentage))
                    width: parent.width * clampedPct
                    z: 0

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 2

                        height: parent.height - 4
                        width: (24 * (20 / 24)) - 4

                        radius: 1
                        color: root.fillColor

                        StyledText {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: 1
                            renderType: Text.QtRendering
                            text: Math.round(root.percentage * 100)
                            font.pixelSize: 8
                            font.weight: Font.Black
                            color: "white"
                        }
                    }
                }

                Image {
                    id: batteryFrame
                    anchors.fill: parent
                    source: Qt.resolvedUrl("../../assets/icons/Battery.svg")
                    sourceSize: Qt.size(24, 12)
                    antialiasing: true
                    visible: false
                }

                ColorOverlay {
                    anchors.fill: batteryFrame
                    source: batteryFrame
                    color: root.frameColor
                    z: 1
                }

                MaterialSymbol {
                    visible: root.isCharging || root.isPluggedIn
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -2
                    renderType: Text.QtRendering
                    text: "bolt"
                    iconSize: 14
                    fill: 1
                    color: Appearance.colors.colLayer0
                    z: 2
                }

                MaterialSymbol {
                    visible: root.isCharging || root.isPluggedIn
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -2
                    renderType: Text.QtRendering
                    text: "bolt"
                    iconSize: 12
                    fill: 1
                    color: root.textColor
                    z: 3
                }
            }
        }
    }

    Bar.BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
