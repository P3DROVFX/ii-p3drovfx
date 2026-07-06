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

        // HERO CARD
        Rectangle {
            Layout.preferredWidth: 380
            Layout.preferredHeight: 220
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHigh

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12

                RowLayout {
                    spacing: 8

                    StyledText {
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
                    }

                    AxisLabel {
                        text: "50"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    AxisLabel {
                        text: "100"
                        anchors.right: parent.right
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
            Layout.fillWidth: true
            height: 2
            radius: 1
            color: Appearance.colors.colSurfaceContainerHighest
        }

        // DETAILED INFO GRID
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 12
            columnSpacing: 12

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh

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
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh

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
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh

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
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh

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
                                if (Battery.chargeLimitReached)
                                    return Translation.tr("Limit reached");
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
