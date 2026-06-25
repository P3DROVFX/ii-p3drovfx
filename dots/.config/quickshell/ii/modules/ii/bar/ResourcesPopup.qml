import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    readonly property int cardWidth: 150
    readonly property int cardHeight: 120
    readonly property int cardPadding: 14

    function formatKBValue(kb) {
        return (kb / (1024 * 1024)).toFixed(1);
    }

    function formatKBTotal(kb) {
        return "/" + (kb / (1024 * 1024)).toFixed(0) + "GB";
    }

    function formatBytesValue(bytes) {
        return (bytes / (1024 * 1024 * 1024)).toFixed(1);
    }

    function formatBytesTotal(bytes) {
        return "/" + (bytes / (1024 * 1024 * 1024)).toFixed(0) + "GB";
    }

    // Reusable card component
    component ResourceCard: Rectangle {
        id: card
        width: root.cardWidth
        height: root.cardHeight
        radius: Appearance.rounding.normal
        color: Appearance.colors.colPrimaryContainer

        property string icon: ""
        property string label: ""
        property string value: ""
        property string total: ""
        property real percentage: 0

        Column {
            anchors.fill: parent
            anchors.margins: root.cardPadding
            spacing: 6

            // Header: icon + label
            Row {
                spacing: 8
                Rectangle {
                    width: 20
                    height: 20
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colPrimary
                    anchors.verticalCenter: parent.verticalCenter

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.icon
                        iconSize: 12
                        fill: 1
                        color: Appearance.colors.colOnPrimary
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.label
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colPrimary
                }
            }

            // Value row: large value + total
            Row {
                spacing: 2
                anchors.left: parent.left

                StyledText {
                    id: valueText
                    text: card.value
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: card.total
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Normal
                    color: Appearance.colors.colOnSurfaceVariant
                    anchors.baseline: valueText.baseline
                }
            }

            // Percentage
            StyledText {
                text: Math.round(card.percentage * 100) + "%"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }

            // Progress bar - Material 3 style
            StyledProgressBar {
                valueBarWidth: parent.width
                valueBarHeight: 8
                value: card.percentage
                highlightColor: Appearance.colors.colPrimary
                trackColor: Appearance.m3colors.m3secondaryContainer
            }
        }
    }

    // Reusable stats card component (for CPU/GPU)
    component StatsCard: Rectangle {
        id: statsCard
        width: root.cardWidth
        height: root.cardHeight
        radius: Appearance.rounding.normal
        color: Appearance.colors.colPrimaryContainer

        property string icon: ""
        property string label: ""
        property var stats: []

        Column {
            anchors.fill: parent
            anchors.margins: root.cardPadding
            spacing: 8

            // Header: icon + label
            Row {
                spacing: 8
                Rectangle {
                    width: 20
                    height: 20
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colPrimary
                    anchors.verticalCenter: parent.verticalCenter

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: statsCard.icon
                        iconSize: 12
                        fill: 1
                        color: Appearance.colors.colOnPrimary
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: statsCard.label
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colPrimary
                }
            }

            // Stats rows
            Column {
                spacing: 6
                Repeater {
                    model: statsCard.stats
                    Row {
                        spacing: 8
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            iconSize: 16
                            fill: 1
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }
    }

    // Main grid layout 2x2
    Grid {
        id: mainGrid
        anchors.centerIn: parent
        columns: 2
        spacing: 12

        // RAM Card
        ResourceCard {
            icon: "memory"
            label: "RAM"
            value: root.formatKBValue(ResourceUsage.memoryUsed) + "GB"
            total: root.formatKBTotal(ResourceUsage.memoryTotal)
            percentage: ResourceUsage.memoryUsedPercentage
        }

        // Storage Card
        ResourceCard {
            icon: "hard_drive"
            label: Translation.tr("Storage")
            value: root.formatBytesValue(ResourceUsage.diskUsed) + "GB"
            total: root.formatBytesTotal(ResourceUsage.diskTotal)
            percentage: ResourceUsage.diskUsedPercentage
        }

        // CPU Card
        StatsCard {
            icon: "speed"
            label: "CPU"
            stats: [
                {
                    icon: "bolt",
                    text: Translation.tr("Load:") + " " + Math.round(ResourceUsage.cpuUsage * 100) + "%"
                },
                {
                    icon: "thermostat",
                    text: Translation.tr("Temp:") + " " + ResourceUsage.cpuTemp + "°C"
                },
                {
                    icon: "timer",
                    text: ResourceUsage.cpuFreqMhz + " MHz"
                }
            ]
        }

        // GPU Card
        StatsCard {
            icon: "video_settings"
            label: "GPU"
            stats: [
                {
                    icon: "bolt",
                    text: Translation.tr("Load:") + " " + ResourceUsage.gpuUsage + "%"
                },
                {
                    icon: "thermostat",
                    text: ResourceUsage.gpuTemp + "°C"
                },
                {
                    icon: "flash_on",
                    text: Math.round(ResourceUsage.gpuPowerW) + " W"
                }
            ]
        }
    }
}
