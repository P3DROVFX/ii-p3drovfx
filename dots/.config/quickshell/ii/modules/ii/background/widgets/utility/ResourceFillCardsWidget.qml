pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "resource_fill_cards"

    visibleWhenLocked: root.lockBehavior === "keep"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property bool enableCpu: Config.options.background.widgets.resource_fill_cards?.enableCpu ?? true
    readonly property bool enableRam: Config.options.background.widgets.resource_fill_cards?.enableRam ?? true
    readonly property bool enableDisk: Config.options.background.widgets.resource_fill_cards?.enableDisk ?? true
    readonly property real contentScale: (Config.options.background.widgets.resource_fill_cards?.widgetSize ?? 100) / 100.0
    readonly property string orientation: Config.options.background.widgets.resource_fill_cards?.orientation ?? "horizontal"
    readonly property bool isHorizontal: orientation === "horizontal"

    readonly property var activeItems: {
        let list = [];
        if (enableCpu) list.push("cpu");
        if (enableRam) list.push("ram");
        if (enableDisk) list.push("disk");
        if (list.length === 0) list.push("cpu");
        return list;
    }

    readonly property int itemCount: activeItems.length

    implicitWidth: (isHorizontal ? itemCount * 240 : 240) * contentScale
    implicitHeight: (isHorizontal ? 240 : itemCount * 240) * contentScale

    StyledRectangularShadow {
        id: bgShadow
        target: outerCardBg
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: outerCardBg
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
        radius: Appearance.rounding.windowRounding

        layer.enabled: true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: outerCardBg.width
                height: outerCardBg.height
                radius: outerCardBg.radius
                antialiasing: true
            }
        }

        GridLayout {
            anchors.fill: parent
            anchors.margins: 10 * root.contentScale
            columnSpacing: 10 * root.contentScale
            rowSpacing: 10 * root.contentScale
            columns: root.isHorizontal ? root.itemCount : 1
            rows: root.isHorizontal ? 1 : root.itemCount

            Repeater {
                model: root.activeItems

                delegate: Item {
                    id: cardItem
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    required property string modelData

                    readonly property real fillLevel: {
                        if (modelData === "cpu") return ResourceUsage.cpuUsage;
                        if (modelData === "ram") return ResourceUsage.memoryUsedPercentage;
                        if (modelData === "disk") return ResourceUsage.diskUsedPercentage;
                        return 0;
                    }
                    readonly property color accentColor: {
                        if (modelData === "cpu") return Appearance.colors.colPrimary;
                        if (modelData === "ram") return Appearance.colors.colSecondary;
                        if (modelData === "disk") return Appearance.colors.colTertiary;
                        return Appearance.colors.colPrimary;
                    }
                    readonly property color containerColor: {
                        if (modelData === "cpu") return Appearance.colors.colPrimaryContainer;
                        if (modelData === "ram") return Appearance.colors.colSecondaryContainer;
                        if (modelData === "disk") return Appearance.colors.colTertiaryContainer;
                        return Appearance.colors.colPrimaryContainer;
                    }
                    readonly property string cardSymbol: {
                        if (modelData === "cpu") return "memory";
                        if (modelData === "ram") return "memory_alt";
                        if (modelData === "disk") return "hard_drive";
                        return "memory";
                    }
                    readonly property string cardTitle: {
                        if (modelData === "cpu") return Translation.tr("CPU Usage");
                        if (modelData === "ram") return Translation.tr("RAM Memory");
                        if (modelData === "disk") return Translation.tr("Disk Storage");
                        return "Resource";
                    }
                    readonly property string cardSubtitle: {
                        if (modelData === "cpu") {
                            let temp = ResourceUsage.cpuTemp;
                            return temp > 0 ? (Math.round(temp) + "°C Thermal") : Translation.tr("Processor Total");
                        }
                        if (modelData === "ram") {
                            let ramUsedGb = (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1);
                            let ramTotalGb = (ResourceUsage.memoryTotal / (1024 * 1024)).toFixed(1);
                            return `${ramUsedGb} / ${ramTotalGb} GB`;
                        }
                        if (modelData === "disk") {
                            let diskUsedGb = (ResourceUsage.diskUsed / (1024 * 1024 * 1024)).toFixed(0);
                            let diskTotalGb = (ResourceUsage.diskTotal / (1024 * 1024 * 1024)).toFixed(0);
                            return `${diskUsedGb} / ${diskTotalGb} GB`;
                        }
                        return "";
                    }
                    readonly property string cardValueText: {
                        if (modelData === "cpu") return Math.round(ResourceUsage.cpuUsage * 100) + "%";
                        if (modelData === "ram") return Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%";
                        if (modelData === "disk") return Math.round(ResourceUsage.diskUsedPercentage * 100) + "%";
                        return "0%";
                    }

                    Rectangle {
                        id: cardInnerBg
                        anchors.fill: parent
                        color: WidgetColorScheme.tintBackground(cardItem.containerColor)
                        radius: Math.max(0, Appearance.rounding.windowRounding - (4 * root.contentScale))

                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: cardInnerBg.width
                                height: cardInnerBg.height
                                radius: cardInnerBg.radius
                                antialiasing: true
                            }
                        }

                        // Bottom Liquid Fill Level Indicator
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: parent.height * Math.min(1.0, Math.max(0.0, cardItem.fillLevel))
                            color: ColorUtils.applyAlpha(cardItem.accentColor, 0.30)

                            Behavior on height {
                                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16 * root.contentScale
                            spacing: 0

                            // Top Badge Icon Container
                            Rectangle {
                                Layout.preferredWidth: 54 * root.contentScale
                                Layout.preferredHeight: 54 * root.contentScale
                                radius: width / 2
                                color: Appearance.colors.colSurfaceContainerHighest
                                opacity: 0.95

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: cardItem.cardSymbol
                                    iconSize: 28 * root.contentScale
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            Item { Layout.fillHeight: true }

                            // Metric Title & Subtitle Text
                            StyledText {
                                Layout.fillWidth: true
                                text: cardItem.cardTitle
                                font.pixelSize: 17 * root.contentScale
                                font.weight: Font.DemiBold
                                color: cardItem.accentColor
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: cardItem.cardSubtitle
                                font.pixelSize: 15 * root.contentScale
                                font.weight: Font.Normal
                                color: ColorUtils.applyAlpha(cardItem.accentColor, 0.80)
                                elide: Text.ElideRight
                            }

                            // Large Fill Value Text
                            Text {
                                Layout.topMargin: 4 * root.contentScale
                                text: cardItem.cardValueText
                                color: cardItem.accentColor
                                font {
                                    pixelSize: 42 * root.contentScale
                                    weight: Font.Black
                                    bold: true
                                    family: "Google Sans Flex"
                                    variableAxes: ({ "wght": 900 })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
