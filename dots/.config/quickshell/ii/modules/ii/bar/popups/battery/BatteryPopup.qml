import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

StyledPopup {
    id: root
    stickyHover: true
    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    readonly property bool hasTimeData: {
        const timeValue = Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
        const power = Battery.energyRate;
        return !(Battery.chargeState === 4 || timeValue <= 0 || power <= 0.01);
    }

    // Hero card glow color logic:
    readonly property color heroGlowColor: {
        if (Battery.percentage <= 0.15 && !Battery.isCharging)
            return Appearance.m3colors.m3error;
        if (Battery.isCharging)
            return "#10E055"; //using manually defined green
        return Appearance.colors.colPrimary;
    }

    ColumnLayout {
        id: mainLayout
        anchors.centerIn: parent
        spacing: 16

        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6
        
        onStartAnimChanged: {
            if (startAnim) {
                batteryHero.opacity = 0.0;
                batteryHero.scale = 0.85;
                batteryHeroTransform.y = 25;
                
                divider.opacity = 0.0;
                
                cellHealth.opacity = 0.0;
                cellHealth.scale = 0.85;
                cellHealthTransform.y = 25;
                
                cellWattage.opacity = 0.0;
                cellWattage.scale = 0.85;
                cellWattageTransform.y = 25;
                
                cellCycles.opacity = 0.0;
                cellCycles.scale = 0.85;
                cellCyclesTransform.y = 25;
                
                cellStatus.opacity = 0.0;
                cellStatus.scale = 0.85;
                cellStatusTransform.y = 25;
                
                Qt.callLater(function() {
                    batteryHeroAnim.start();
                    dividerAnim.start();
                    cellHealthAnim.start();
                    cellWattageAnim.start();
                    cellCyclesAnim.start();
                    cellStatusAnim.start();
                });
            }
        }

        readonly property var _visList: [
            true, // HERO
            true, // divider
            true, // grid cell 1
            true, // grid cell 2
            true, // grid cell 3
            true  // grid cell 4
        ]

        function getDelay(index) {
            const delays = [40, 100, 160, 220, 280, 340];
            return delays[Math.min(index, delays.length - 1)];
        }

        // HERO CARD
        Rectangle {
            id: batteryHero
            Layout.preferredWidth: 380
            Layout.preferredHeight: 220
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHigh

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: batteryHeroTransform
                y: 25
            }
            
            SequentialAnimation {
                id: batteryHeroAnim
                PauseAnimation { duration: mainLayout.getDelay(0) }
                ParallelAnimation {
                    NumberAnimation { target: batteryHero; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: batteryHero; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: batteryHeroTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12

                RowLayout {
                    spacing: 8

                    StyledText {
                        text: {
                            if (Battery.chargeState === 4) return Translation.tr("Fully Charged");
                            if (Battery.isCharging) return Translation.tr("Charging...");
                            return Translation.tr("Discharging...");
                        }
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.family: Appearance.font.family.title
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                RowLayout {
                    spacing: 8
                    StyledText {
                        text: Math.floor(Battery.percentage * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: "•"
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnSurface
                        visible: root.hasTimeData
                    }

                    StyledText {
                        text: {
                            if (!root.hasTimeData && Battery.chargeState !== 4)
                                return Translation.tr("Calculating...");
                            if (Battery.chargeState === 4)
                                return "";
                            const time = root.formatTime(
                                Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty
                            );
                            return Translation.tr("%1 left").arg(time);
                        }
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                        visible: root.hasTimeData
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: "0"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: "Monospace"
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: "50"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: "Monospace"
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: "100"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: "Monospace"
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                Item {
                    id: batteryBarContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64

                    Rectangle {
                        id: batteryTrack
                        anchors.fill: parent
                        radius: 16
                        color: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.9)
                    }

                    Rectangle {
                        id: batteryFill
                        width: parent.width * Battery.percentage
                        height: parent.height
                        radius: 16
                        color: root.heroGlowColor

                        Behavior on width {
                            NumberAnimation {
                                duration: 500
                                easing.type: Easing.OutQuint
                            }
                        }
                    }

                    Rectangle {
                        id: centerMarkerLine
                        width: 2
                        height: parent.height / 3
                        anchors.centerIn: parent
                        radius: 1
                        color: ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.9)
                        z: 1  // to stay above the fill
                    }
                }
            }
        }

        Rectangle {
            id: divider
            Layout.fillWidth: true
            height: 2
            radius: 1
            color: Appearance.colors.colSurfaceContainerHighest

            opacity: 0.0
            
            SequentialAnimation {
                id: dividerAnim
                PauseAnimation { duration: mainLayout.getDelay(1) }
                NumberAnimation { target: divider; property: "opacity"; to: 1.0; duration: 300 }
            }
        }

        // DETAILED INFO GRID
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 12
            columnSpacing: 12

            Rectangle {
                id: cellHealth
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh

                opacity: 0.0
                scale: 0.85
                transform: Translate {
                    id: cellHealthTransform
                    y: 25
                }
                
                SequentialAnimation {
                    id: cellHealthAnim
                    PauseAnimation { duration: mainLayout.getDelay(2) }
                    ParallelAnimation {
                        NumberAnimation { target: cellHealth; property: "opacity"; to: 1.0; duration: 300 }
                        NumberAnimation { target: cellHealth; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        NumberAnimation { target: cellHealthTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    MaterialShape {
                        shapeString: "Slanted"
                        implicitSize: 36
                        color: Appearance.colors.colPositiveContainer
                               ?? Appearance.colors.colPrimaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "health_metrics"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPositiveContainer
                                   ?? Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    ColumnLayout {
                        spacing: -2

                        StyledText {
                            text: Translation.tr("Health")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            text: `${Battery.health.toFixed(0)}%`
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Rectangle {
                id: cellWattage
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh

                opacity: 0.0
                scale: 0.85
                transform: Translate {
                    id: cellWattageTransform
                    y: 25
                }
                
                SequentialAnimation {
                    id: cellWattageAnim
                    PauseAnimation { duration: mainLayout.getDelay(3) }
                    ParallelAnimation {
                        NumberAnimation { target: cellWattage; property: "opacity"; to: 1.0; duration: 300 }
                        NumberAnimation { target: cellWattage; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        NumberAnimation { target: cellWattageTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    MaterialShape {
                        shapeString: "Slanted"
                        implicitSize: 36
                        color: Appearance.colors.colSecondaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: Battery.isCharging ? "electric_bolt" : "power"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    ColumnLayout {
                        spacing: -2

                        StyledText {
                            text: Battery.isCharging
                                  ? Translation.tr("Input")
                                  : Translation.tr("Draw")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            text: `${Math.abs(Battery.energyRate).toFixed(1)}W`
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Rectangle {
                id: cellCycles
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh

                opacity: 0.0
                scale: 0.85
                transform: Translate {
                    id: cellCyclesTransform
                    y: 25
                }
                
                SequentialAnimation {
                    id: cellCyclesAnim
                    PauseAnimation { duration: mainLayout.getDelay(4) }
                    ParallelAnimation {
                        NumberAnimation { target: cellCycles; property: "opacity"; to: 1.0; duration: 300 }
                        NumberAnimation { target: cellCycles; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        NumberAnimation { target: cellCyclesTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    MaterialShape {
                        shapeString: "Slanted"
                        implicitSize: 36
                        color: Appearance.colors.colTertiaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "autorenew"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnTertiaryContainer
                        }
                    }

                    ColumnLayout {
                        spacing: -2

                        StyledText {
                            text: Translation.tr("Cycles")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            text: {
                                if (Battery.cycles >= 0) {
                                    return Battery.cycles.toString();
                                }
                                return Battery.health > 0
                                      ? `~${Math.round((100 - Battery.health) * 10)}`
                                      : "--";
                            }
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Rectangle {
                id: cellStatus
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh

                opacity: 0.0
                scale: 0.85
                transform: Translate {
                    id: cellStatusTransform
                    y: 25
                }
                
                SequentialAnimation {
                    id: cellStatusAnim
                    PauseAnimation { duration: mainLayout.getDelay(5) }
                    ParallelAnimation {
                        NumberAnimation { target: cellStatus; property: "opacity"; to: 1.0; duration: 300 }
                        NumberAnimation { target: cellStatus; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        NumberAnimation { target: cellStatusTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    MaterialShape {
                        shapeString: "Slanted"
                        implicitSize: 36
                        color: Appearance.colors.colErrorContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "info"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnErrorContainer
                        }
                    }

                    ColumnLayout {
                        spacing: -2

                        StyledText {
                            text: Translation.tr("Status")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            text: {
                                if (Battery.chargeState === 4)
                                    return Translation.tr("Full");
                                if (Battery.isCharging)
                                    return Translation.tr("Charging");
                                return Translation.tr("Discharging");
                            }
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
