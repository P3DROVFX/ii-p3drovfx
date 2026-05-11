import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless

    // ── Propriedades reativas ──
    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isFull: Battery.isFull
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    readonly property bool isCritical: percentage <= Config.options.battery.critical / 100
    property color textColor: Appearance.colors.colOnSurface

    // Cor do preenchimento
    readonly property color fillColor: {
        if (root.isCritical && !root.isCharging)
            return "#E53935";
        if (root.isLow && !root.isCharging)
            return "#FB8C00";
        return "#43A047";
    }

    // Cor da moldura
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

    ColumnLayout {
        id: mainLayout
        anchors.centerIn: parent
        spacing: 2

        // Android 16 Style
        Item {
            id: android16Battery
            visible: Config.options.battery.style === "android16"
            Layout.alignment: Qt.AlignHCenter
            width: 16
            height: 31

            Item {
                anchors.centerIn: parent
                width: 31
                height: 16
                rotation: -90

                Row {
                    anchors.centerIn: parent
                    spacing: 1

                    ClippedProgressBar {
                        id: batteryProgress
                        width: 28
                        height: 16
                        radius: 4.5
                        value: root.percentage

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
                                text: Math.round(root.percentage * 100)
                                font.pixelSize: 10
                                font.weight: Font.Black
                                color: "white"
                            }
                        }
                    }

                    // Battery Tip
                    Rectangle {
                        width: 2
                        height: 6
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 1
                        color: (root.percentage >= 0.98) ? batteryProgress.highlightColor : batteryProgress.trackColor
                    }
                }

                // Bolt Overlay
                MaterialSymbol {
                    visible: root.isCharging || root.isPluggedIn
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.right
                    anchors.horizontalCenterOffset: -1
                    text: "bolt"
                    iconSize: 14
                    fill: 1
                    color: root.textColor
                }
            }
        }

        // Classic / Default Style
        Item {
            id: batteryContainer
            visible: Config.options.battery.style !== "android16"
            Layout.alignment: Qt.AlignHCenter
            height: 24
            width: 12

            Item {
                anchors.centerIn: parent
                width: 24
                height: 12
                rotation: -90

                // ── Camada 1: Fill ──
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
                            text: Math.round(root.percentage * 100)
                            font.pixelSize: 8
                            font.weight: Font.Black
                            color: "white"
                        }
                    }
                }

                // ── Camada 2: Moldura SVG ──
                CustomIcon {
                    anchors.fill: parent
                    source: "Battery.svg"
                    colorize: true
                    color: root.frameColor
                    z: 1
                }

                // ── Camada 3: Bolt ──
                MaterialSymbol {
                    visible: root.isCharging || root.isPluggedIn
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -2
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
