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
        const timeValue = Battery.isCharging ? Battery.timeToFullEffective : Battery.timeToEmpty;
        const power = Battery.energyRate;
        return !(Battery.chargeState === 4 || Battery.chargeLimitReached || timeValue <= 0 || power <= 0.01);
    }

    // Hide the limit label when it would collide with the fixed 0/50/100 labels
    readonly property bool showLimitLabel: Battery.chargeLimitActive && Battery.chargeLimit >= 8
        && Battery.chargeLimit <= 92 && Math.abs(Battery.chargeLimit - 50) >= 8

    // Hero card glow color logic:
    readonly property color heroGlowColor: {
        if (Battery.percentage <= 0.15 && !Battery.isCharging)
            return Appearance.m3colors.m3error;
        if (Battery.isCharging || Battery.chargeLimitReached)
            return "#10E055"; //using manually defined green
        return Appearance.colors.colPrimary;
    }

    component AxisLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.small
        font.family: "Monospace"
        color: Appearance.colors.colOnSurfaceVariant
    }

    ColumnLayout {
        id: mainLayout
        anchors.centerIn: parent
        spacing: 16

        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6
        
        onStartAnimChanged: {
            if (startAnim) {
                // Reset parent cards
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

                // Reset internal sub-elements
                batteryHero.animProgress = 0.0;
                batteryHeroStatusText.opacity = 0.0;
                batteryHeroStatusTextTrans.y = 10;
                batteryHeroStatsRow.opacity = 0.0;
                batteryHeroStatsRow.scale = 0.9;
                axisLabelZero.opacity = 0.0;
                axisLabel50.opacity = 0.0;
                axisLabel100.opacity = 0.0;

                cellHealthShape.scale = 0.8;
                cellHealthShape.rotation = -10;
                cellHealthTitle.opacity = 0.0;
                cellHealthValue.opacity = 0.0;
                cellHealthValue.scale = 0.9;

                cellWattageShape.scale = 0.8;
                cellWattageShape.rotation = -10;
                cellWattageTitle.opacity = 0.0;
                cellWattageValue.opacity = 0.0;
                cellWattageValue.scale = 0.9;

                cellCyclesShape.scale = 0.8;
                cellCyclesShape.rotation = -10;
                cellCyclesTitle.opacity = 0.0;
                cellCyclesValue.opacity = 0.0;
                cellCyclesValue.scale = 0.9;

                cellStatusShape.scale = 0.8;
                cellStatusShape.rotation = -10;
                cellStatusTitle.opacity = 0.0;
                cellStatusValue.opacity = 0.0;
                cellStatusValue.scale = 0.9;
                
                Qt.callLater(function() {
                    // Start parent card animations
                    batteryHeroAnim.start();
                    dividerAnim.start();
                    cellHealthAnim.start();
                    cellWattageAnim.start();
                    cellCyclesAnim.start();
                    cellStatusAnim.start();

                    // Start internal sub-elements animations
                    batteryHeroStatusTextAnim.start();
                    batteryHeroStatsRowAnim.start();
                    label0Anim.start();
                    label50Anim.start();
                    label100Anim.start();
                    batteryFillAnim.start();

                    cellHealthShapeAnim.start();
                    cellHealthTitleAnim.start();
                    cellHealthValueAnim.start();

                    cellWattageShapeAnim.start();
                    cellWattageTitleAnim.start();
                    cellWattageValueAnim.start();

                    cellCyclesShapeAnim.start();
                    cellCyclesTitleAnim.start();
                    cellCyclesValueAnim.start();

                    cellStatusShapeAnim.start();
                    cellStatusTitleAnim.start();
                    cellStatusValueAnim.start();
                });
            }
        }

        Connections {
            target: root
            function onPopupOpenProgressChanged() {
                if (root && root.popupOpenProgress === 0.0) {
                    batteryHeroAnim.stop();
                    dividerAnim.stop();
                    cellHealthAnim.stop();
                    cellWattageAnim.stop();
                    cellCyclesAnim.stop();
                    cellStatusAnim.stop();

                    batteryHeroStatusTextAnim.stop();
                    batteryHeroStatsRowAnim.stop();
                    label0Anim.stop();
                    label50Anim.stop();
                    label100Anim.stop();
                    batteryFillAnim.stop();

                    cellHealthShapeAnim.stop();
                    cellHealthTitleAnim.stop();
                    cellHealthValueAnim.stop();

                    cellWattageShapeAnim.stop();
                    cellWattageTitleAnim.stop();
                    cellWattageValueAnim.stop();

                    cellCyclesShapeAnim.stop();
                    cellCyclesTitleAnim.stop();
                    cellCyclesValueAnim.stop();

                    cellStatusShapeAnim.stop();
                    cellStatusTitleAnim.stop();
                    cellStatusValueAnim.stop();

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

                    batteryHero.animProgress = 0.0;
                    batteryHeroStatusText.opacity = 0.0;
                    batteryHeroStatusTextTrans.y = 10;
                    batteryHeroStatsRow.opacity = 0.0;
                    batteryHeroStatsRow.scale = 0.9;
                    axisLabelZero.opacity = 0.0;
                    axisLabel50.opacity = 0.0;
                    axisLabel100.opacity = 0.0;

                    cellHealthShape.scale = 0.8;
                    cellHealthShape.rotation = -10;
                    cellHealthTitle.opacity = 0.0;
                    cellHealthValue.opacity = 0.0;
                    cellHealthValue.scale = 0.9;

                    cellWattageShape.scale = 0.8;
                    cellWattageShape.rotation = -10;
                    cellWattageTitle.opacity = 0.0;
                    cellWattageValue.opacity = 0.0;
                    cellWattageValue.scale = 0.9;

                    cellCyclesShape.scale = 0.8;
                    cellCyclesShape.rotation = -10;
                    cellCyclesTitle.opacity = 0.0;
                    cellCyclesValue.opacity = 0.0;
                    cellCyclesValue.scale = 0.9;

                    cellStatusShape.scale = 0.8;
                    cellStatusShape.rotation = -10;
                    cellStatusTitle.opacity = 0.0;
                    cellStatusValue.opacity = 0.0;
                    cellStatusValue.scale = 0.9;
                }
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

            property real animProgress: 0.0
            
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
                        id: batteryHeroStatusText
                        text: {
                            if (Battery.chargeState === 4) return Translation.tr("Fully Charged");
                            if (Battery.chargeLimitReached) return Translation.tr("Charge limit reached");
                            if (Battery.isCharging) return Translation.tr("Charging...");
                            return Translation.tr("Discharging...");
                        }
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.family: Appearance.font.family.title
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant

                        opacity: 0.0
                        transform: Translate {
                            id: batteryHeroStatusTextTrans
                            y: 10
                        }

                        SequentialAnimation {
                            id: batteryHeroStatusTextAnim
                            PauseAnimation { duration: mainLayout.getDelay(0) + 60 }
                            ParallelAnimation {
                                NumberAnimation { target: batteryHeroStatusText; property: "opacity"; from: 0.0; to: 1.0; duration: 350 }
                                NumberAnimation { target: batteryHeroStatusTextTrans; property: "y"; from: 10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                RowLayout {
                    id: batteryHeroStatsRow
                    spacing: 8
                    opacity: 0.0
                    scale: 0.9

                    SequentialAnimation {
                        id: batteryHeroStatsRowAnim
                        PauseAnimation { duration: mainLayout.getDelay(0) + 120 }
                        ParallelAnimation {
                            NumberAnimation { target: batteryHeroStatsRow; property: "opacity"; from: 0.0; to: 1.0; duration: 380 }
                            NumberAnimation { target: batteryHeroStatsRow; property: "scale"; from: 0.9; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        }
                    }

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
                            if (!root.hasTimeData && Battery.chargeState !== 4 && !Battery.chargeLimitReached)
                                return Translation.tr("Calculating...");
                            if (Battery.chargeState === 4 || Battery.chargeLimitReached)
                                return "";
                            const time = root.formatTime(
                                Battery.isCharging ? Battery.timeToFullEffective : Battery.timeToEmpty
                            );
                            if (Battery.isCharging && Battery.chargeLimitActive)
                                return Translation.tr("%1 until %2%").arg(time).arg(Battery.chargeLimit);
                            return Translation.tr("%1 left").arg(time);
                        }
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                        visible: root.hasTimeData
                    }
                }

                Item { Layout.fillHeight: true }

                Item {
                    id: axisLabels
                    Layout.fillWidth: true
                    implicitHeight: axisLabelZero.implicitHeight

                    AxisLabel {
                        id: axisLabelZero
                        text: "0"
                        anchors.left: parent.left
                        opacity: 0.0

                        SequentialAnimation {
                            id: label0Anim
                            PauseAnimation { duration: mainLayout.getDelay(0) + 180 }
                            NumberAnimation { target: axisLabelZero; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                        }
                    }

                    AxisLabel {
                        id: axisLabel50
                        text: "50"
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: 0.0

                        SequentialAnimation {
                            id: label50Anim
                            PauseAnimation { duration: mainLayout.getDelay(0) + 200 }
                            NumberAnimation { target: axisLabel50; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                        }
                    }

                    AxisLabel {
                        id: axisLabel100
                        text: "100"
                        anchors.right: parent.right
                        opacity: 0.0

                        SequentialAnimation {
                            id: label100Anim
                            PauseAnimation { duration: mainLayout.getDelay(0) + 220 }
                            NumberAnimation { target: axisLabel100; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                        }
                    }

                    Loader {
                        active: root.showLimitLabel
                        x: axisLabels.width * (Battery.chargeLimit / 100) - width / 2
                        sourceComponent: AxisLabel {
                            text: Battery.chargeLimit
                        }
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
                        width: parent.width * Battery.percentage * batteryHero.animProgress
                        height: parent.height
                        radius: 16
                        color: root.heroGlowColor

                        SequentialAnimation {
                            id: batteryFillAnim
                            PauseAnimation { duration: mainLayout.getDelay(0) + 100 }
                            NumberAnimation { target: batteryHero; property: "animProgress"; from: 0.0; to: 1.0; duration: 500; easing.type: Easing.OutQuint }
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

                    Loader {
                        active: Battery.chargeLimitActive
                        anchors.verticalCenter: parent.verticalCenter
                        x: batteryBarContainer.width * (Battery.chargeLimit / 100) - width / 2
                        z: 1  // to stay above the fill, same as the center marker
                        sourceComponent: Rectangle {
                            implicitWidth: 2
                            implicitHeight: batteryBarContainer.height / 3
                            radius: 1
                            color: ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.9)
                        }
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
                        id: cellHealthShape
                        shapeString: "Slanted"
                        implicitSize: 36
                        color: Appearance.colors.colPositiveContainer
                               ?? Appearance.colors.colPrimaryContainer
                        scale: 0.8
                        rotation: -10

                        SequentialAnimation {
                            id: cellHealthShapeAnim
                            PauseAnimation { duration: mainLayout.getDelay(2) + 60 }
                            ParallelAnimation {
                                NumberAnimation { target: cellHealthShape; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                NumberAnimation { target: cellHealthShape; property: "rotation"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            }
                        }

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
                            id: cellHealthTitle
                            text: Translation.tr("Health")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.0

                            SequentialAnimation {
                                id: cellHealthTitleAnim
                                PauseAnimation { duration: mainLayout.getDelay(2) + 120 }
                                NumberAnimation { target: cellHealthTitle; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                            }
                        }

                        StyledText {
                            id: cellHealthValue
                            text: `${Battery.health.toFixed(0)}%`
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                            opacity: 0.0
                            scale: 0.9

                            SequentialAnimation {
                                id: cellHealthValueAnim
                                PauseAnimation { duration: mainLayout.getDelay(2) + 180 }
                                ParallelAnimation {
                                    NumberAnimation { target: cellHealthValue; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                    NumberAnimation { target: cellHealthValue; property: "scale"; from: 0.9; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                }
                            }
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
                        id: cellWattageShape
                        shapeString: "Slanted"
                        implicitSize: 36
                        color: Appearance.colors.colSecondaryContainer
                        scale: 0.8
                        rotation: -10

                        SequentialAnimation {
                            id: cellWattageShapeAnim
                            PauseAnimation { duration: mainLayout.getDelay(3) + 60 }
                            ParallelAnimation {
                                NumberAnimation { target: cellWattageShape; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                NumberAnimation { target: cellWattageShape; property: "rotation"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            }
                        }

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
                            id: cellWattageTitle
                            text: Battery.isCharging
                                  ? Translation.tr("Input")
                                  : Translation.tr("Draw")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.0

                            SequentialAnimation {
                                id: cellWattageTitleAnim
                                PauseAnimation { duration: mainLayout.getDelay(3) + 120 }
                                NumberAnimation { target: cellWattageTitle; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                            }
                        }

                        StyledText {
                            id: cellWattageValue
                            text: `${Math.abs(Battery.energyRate).toFixed(1)}W`
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                            opacity: 0.0
                            scale: 0.9

                            SequentialAnimation {
                                id: cellWattageValueAnim
                                PauseAnimation { duration: mainLayout.getDelay(3) + 180 }
                                ParallelAnimation {
                                    NumberAnimation { target: cellWattageValue; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                    NumberAnimation { target: cellWattageValue; property: "scale"; from: 0.9; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                }
                            }
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
                        id: cellCyclesShape
                        shapeString: "Slanted"
                        implicitSize: 36
                        color: Appearance.colors.colTertiaryContainer
                        scale: 0.8
                        rotation: -10

                        SequentialAnimation {
                            id: cellCyclesShapeAnim
                            PauseAnimation { duration: mainLayout.getDelay(4) + 60 }
                            ParallelAnimation {
                                NumberAnimation { target: cellCyclesShape; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                NumberAnimation { target: cellCyclesShape; property: "rotation"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            }
                        }

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
                            id: cellCyclesTitle
                            text: Translation.tr("Cycles")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.0

                            SequentialAnimation {
                                id: cellCyclesTitleAnim
                                PauseAnimation { duration: mainLayout.getDelay(4) + 120 }
                                NumberAnimation { target: cellCyclesTitle; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                            }
                        }

                        StyledText {
                            id: cellCyclesValue
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
                            opacity: 0.0
                            scale: 0.9

                            SequentialAnimation {
                                id: cellCyclesValueAnim
                                PauseAnimation { duration: mainLayout.getDelay(4) + 180 }
                                ParallelAnimation {
                                    NumberAnimation { target: cellCyclesValue; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                    NumberAnimation { target: cellCyclesValue; property: "scale"; from: 0.9; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                }
                            }
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
                        id: cellStatusShape
                        shapeString: "Slanted"
                        implicitSize: 36
                        color: Appearance.colors.colErrorContainer
                        scale: 0.8
                        rotation: -10

                        SequentialAnimation {
                            id: cellStatusShapeAnim
                            PauseAnimation { duration: mainLayout.getDelay(5) + 60 }
                            ParallelAnimation {
                                NumberAnimation { target: cellStatusShape; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                NumberAnimation { target: cellStatusShape; property: "rotation"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            }
                        }

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
                            id: cellStatusTitle
                            text: Translation.tr("Status")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.0

                            SequentialAnimation {
                                id: cellStatusTitleAnim
                                PauseAnimation { duration: mainLayout.getDelay(5) + 120 }
                                NumberAnimation { target: cellStatusTitle; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                            }
                        }

                        StyledText {
                            id: cellStatusValue
                            text: {
                                if (Battery.chargeState === 4)
                                    return Translation.tr("Full");
                                if (Battery.chargeLimitReached)
                                    return Translation.tr("Limit reached");
                                if (Battery.isCharging)
                                    return Translation.tr("Charging");
                                return Translation.tr("Discharging");
                            }
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                            opacity: 0.0
                            scale: 0.9

                            SequentialAnimation {
                                id: cellStatusValueAnim
                                PauseAnimation { duration: mainLayout.getDelay(5) + 180 }
                                ParallelAnimation {
                                    NumberAnimation { target: cellStatusValue; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                                    NumberAnimation { target: cellStatusValue; property: "scale"; from: 0.9; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
