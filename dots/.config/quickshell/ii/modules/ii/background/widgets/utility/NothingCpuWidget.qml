pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "resource_nothing_cpu"

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

    readonly property var options: Config.options.background.widgets.resource_nothing_cpu || ({})
    readonly property real contentScale: (options?.widgetSize ?? 100) / 100.0
    readonly property bool useAccentColor: options?.useAccentColor ?? false

    implicitWidth: 240 * contentScale
    implicitHeight: 120 * contentScale

    // Font Loader for Ndot 57
    FontLoader {
        id: ndotFont
        source: "file://" + Directories.assetsPath + "/fonts/Ndot57-Regular.otf"
    }

    // Resource Data
    readonly property real cpuUsagePct: ResourceUsage.cpuUsage
    readonly property real cpuTemp: ResourceUsage.cpuTemp
    readonly property string detailText: {
        if (root.cpuTemp > 0)
            return Math.round(root.cpuTemp) + "°C · PROCESSOR";
        return Translation.tr("PROCESSOR");
    }

    // Shadow Effect
    StyledDropShadow {
        id: shadowEffect
        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Math.round(16 * root.contentScale)
            spacing: 0

            // Top Header: Label ("CPU") and Percentage ("45%")
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: Translation.tr("CPU")
                    font.family: ndotFont.name
                    font.pixelSize: Math.round(13 * root.contentScale)
                    color: WidgetColorScheme.subtextColorOnBg
                    renderType: Text.QtRendering
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Math.round(root.cpuUsagePct * 100) + "%"
                    font.family: ndotFont.name
                    font.pixelSize: Math.round(18 * root.contentScale)
                    color: root.useAccentColor ? WidgetColorScheme.accentColor : WidgetColorScheme.textColorOnBg
                    renderType: Text.QtRendering
                }
            }

            Item { Layout.fillHeight: true }

            // Middle: Fine Horizontal Segmented Bar
            Item {
                id: barContainer
                Layout.fillWidth: true
                implicitHeight: Math.round(24 * root.contentScale)

                readonly property int totalSegments: 24
                readonly property real gap: Math.round(3 * root.contentScale)
                readonly property real segWidth: Math.max(1, (width - (totalSegments - 1) * gap) / totalSegments)
                readonly property int activeCount: Math.round(root.cpuUsagePct * totalSegments)

                Row {
                    anchors.fill: parent
                    spacing: barContainer.gap

                    Repeater {
                        model: barContainer.totalSegments

                        delegate: Rectangle {
                            required property int index
                            width: barContainer.segWidth
                            height: parent.height
                            radius: Math.round(4 * root.contentScale)

                            readonly property bool isActive: index < barContainer.activeCount
                            readonly property color activeColor: root.useAccentColor ? WidgetColorScheme.accentColor : WidgetColorScheme.textColorOnBg
                            readonly property color inactiveColor: Qt.rgba(WidgetColorScheme.subtextColorOnBg.r, WidgetColorScheme.subtextColorOnBg.g, WidgetColorScheme.subtextColorOnBg.b, 0.18)

                            color: isActive ? activeColor : inactiveColor

                            Behavior on color {
                                ColorAnimation {
                                    duration: 250
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // Bottom Detail: e.g., "42°C · PROCESSOR"
            Text {
                text: root.detailText
                font.family: ndotFont.name
                font.pixelSize: Math.round(13 * root.contentScale)
                color: WidgetColorScheme.subtextColorOnBg
                renderType: Text.QtRendering
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }
}
