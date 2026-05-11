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

    // ── Propriedades reativas ──
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

    implicitWidth: (Config.options.battery.style === "android16" ? android16Battery.width : batteryContainer.width) + 12
    implicitHeight: Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

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
                        return "#43A047";
                    if (root.isPowerSaving)
                        return "#FFC917";
                    if (root.isPerformance)
                        return "#42A5F5"; // Azul claro
                    return root.textColor;
                }
                trackColor: {
                    if (root.isLow && !root.effectivelyCharging)
                        return Appearance.m3colors.m3errorContainer;

                    // Fundo neutro (baseado na cor do texto) para excelente contraste no dark mode
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

        // ── Camada 3: Bolt outline ──
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

        // ── Camada 4: Bolt principal ──
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

    Item {
        id: batteryContainer
        visible: Config.options.battery.style !== "android16"
        anchors.centerIn: parent
        height: 14
        width: height * (28 / 13)

        // ── Camada 1: Fill (com clipping no nível da cor) ──
        Item {
            id: fillClipping
            clip: true
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            
            // O width define a "linha de corte".
            readonly property real clampedPct: Math.max(0, Math.min(1, root.percentage))
            width: parent.width * clampedPct
            z: 0

            // Preenchimento Sólido (O "Líquido" da bateria)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                
                // Padding interno visual (Aumentado para 3)
                anchors.leftMargin: 3
                
                height: parent.height - 6 // Padding vertical (3 em cima, 3 em baixo)
                width: (parent.width * (24/28)) - 6 // Largura total da área interna menos padding
                
                radius: 1.5 // Borda (Raio)
                
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

        // ── Camada 2: Moldura SVG ──
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

        // ── Camada 3: Bolt outline ──
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

        // ── Camada 4: Bolt principal ──
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

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
