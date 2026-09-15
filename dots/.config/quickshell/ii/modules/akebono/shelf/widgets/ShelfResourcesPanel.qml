import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var shelf
    signal closeRequested()

    readonly property var active:
        root.shelf ? root.shelf.resourcesOpen : false
    onActiveChanged: {
        ResourceUsage.resourcePopupMonitoringEnabled = root.active;
    }

    implicitWidth: row.implicitWidth + 24
    implicitHeight: row.implicitHeight + 24

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        ColumnLayout {
            spacing: 8

            ResourceCard {
                label: "RAM"
                iconText: "memory"
                iconShape: MaterialShape.Shape.Clover4Leaf
                value: ResourceUsage.memoryUsedPercentage
                sublabel: ResourceUsage.kbToGbString(ResourceUsage.memoryUsed) + " / " + ResourceUsage.kbToGbString(ResourceUsage.memoryTotal)
            }

            ResourceCard {
                label: "CPU"
                iconText: "planner_review"
                iconShape: MaterialShape.Shape.Gem
                value: ResourceUsage.cpuUsage
                sublabel: `${Math.round(ResourceUsage.cpuTemp)}°C`
                sublabelColor: ResourceUsage.cpuTemp > 80 ? Appearance.colors.colError
                    : ResourceUsage.cpuTemp > 60 ? Appearance.m3colors.m3tertiary
                    : Appearance.colors.colOnLayer1
            }
        }

        ColumnLayout {
            spacing: 8

            ResourceCard {
                label: "Swap"
                iconText: "swap_horiz"
                iconShape: MaterialShape.Shape.Bun
                value: ResourceUsage.swapUsedPercentage
                sublabel: ResourceUsage.kbToGbString(ResourceUsage.swapUsed) + " / " + ResourceUsage.kbToGbString(ResourceUsage.swapTotal)
            }

            ResourceCard {
                label: "Disk"
                iconText: "hard_drive"
                iconShape: MaterialShape.Shape.Circle
                value: ResourceUsage.diskUsedPercentage
                sublabel: (ResourceUsage.diskUsed / (1024 * 1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.diskTotal / (1024 * 1024 * 1024)).toFixed(0) + " GB"
            }
        }
    }

    component ResourceCard: Rectangle {
        id: card

        Layout.preferredWidth: 150
        Layout.preferredHeight: 96
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainerHigh

        required property string label
        required property string iconText
        required property var iconShape
        required property real value
        required property string sublabel
        property color sublabelColor: Appearance.colors.colOnSurfaceVariant
        property color accentColor: Appearance.colors.colPrimaryContainer
        property color symbolColor: Appearance.colors.colOnPrimaryContainer

        function usageColor(v) {
            if (v > 0.9)
                return Appearance.colors.colError
            return Appearance.colors.colPrimary
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: -4
                spacing: 0

                MaterialShapeWrappedMaterialSymbol {
                    shape: card.iconShape
                    text: card.iconText
                    iconSize: Appearance.font.pixelSize.huge
                    implicitSize: 28
                    color: card.accentColor
                    colSymbol: card.symbolColor
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: `${Math.round(card.value * 100)}%`
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                    color: Appearance.colors.colOnSurface
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    text: card.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurface
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                StyledText {
                    text: card.sublabel
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: card.sublabelColor
                    font.features: {
                        "tnum": 1
                    }
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            StyledProgressBar {
                Layout.fillWidth: true
                value: card.value
                highlightColor: card.usageColor(card.value)
                valueBarHeight: 6
            }
        }

        border.width: card.value > 0.9 ? 1.5 : 0
        border.color: card.value > 0.9 ? Appearance.colors.colError : "transparent"
    }
}