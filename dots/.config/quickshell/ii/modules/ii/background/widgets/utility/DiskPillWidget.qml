pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "resource_disk_pill"

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

    readonly property var options: Config.options.background.widgets.resource_disk_pill
    readonly property real contentScale: (options?.widgetSize ?? 100) / 100.0
    readonly property string aspectRatio: options?.aspectRatio ?? "2x0.5"
    readonly property bool showDetails: options?.showDetails ?? true
    readonly property bool isWide: aspectRatio === "2x0.5"
    readonly property real innerMargin: 4 * contentScale
    readonly property real innerRadius: Math.max(0, Appearance.rounding.windowRounding - innerMargin)

    implicitWidth: (isWide ? 480 : 240) * contentScale
    implicitHeight: 60 * contentScale

    readonly property real diskUsagePct: ResourceUsage.diskUsedPercentage
    readonly property string diskUsedGb: (ResourceUsage.diskUsed / (1024 * 1024 * 1024)).toFixed(0)
    readonly property string diskTotalGb: (ResourceUsage.diskTotal / (1024 * 1024 * 1024)).toFixed(0)

    readonly property string titleText: {
        if (root.isWide && root.showDetails)
            return Translation.tr("Disk") + " · " + root.diskUsedGb + "/" + root.diskTotalGb + " GB";
        if (root.isWide)
            return Translation.tr("Disk Usage");
        return Translation.tr("Disk");
    }
    readonly property string valueText: Math.round(root.diskUsagePct * 100) + "%"

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)

        Item {
            anchors.fill: parent
            anchors.margins: root.innerMargin

            Rectangle {
                id: bgTrack
                anchors.fill: parent
                radius: root.innerRadius
                color: WidgetColorScheme.pillBgColor

                layer.enabled: true
                layer.samples: 4
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: bgTrack.width
                        height: bgTrack.height
                        radius: bgTrack.radius
                    }
                }

                // ── Track Text Layer (Unfilled side) ──
                RowLayout {
                    id: trackTextRow
                    anchors.fill: parent
                    anchors.leftMargin: 16 * root.contentScale
                    anchors.rightMargin: 16 * root.contentScale
                    spacing: 10 * root.contentScale

                    MaterialSymbol {
                        text: "hard_drive"
                        iconSize: 18 * root.contentScale
                        color: WidgetColorScheme.textColorOnPillTrack
                        Layout.alignment: Qt.AlignVCenter
                    }

                    StyledText {
                        text: root.titleText
                        font.pixelSize: 13 * root.contentScale
                        font.weight: Font.Bold
                        font.family: Appearance.font.family.main
                        color: WidgetColorScheme.textColorOnPillTrack
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    StyledText {
                        text: root.valueText
                        font.pixelSize: 13 * root.contentScale
                        font.weight: Font.Bold
                        font.family: Appearance.font.family.main
                        color: WidgetColorScheme.textColorOnPillTrack
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // ── Progress Fill Layer (Clipped overlay) ──
                Rectangle {
                    id: progressFill
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(0, parent.width * Math.min(1.0, Math.max(0.0, root.diskUsagePct)))
                    color: WidgetColorScheme.pillFillColor
                    clip: true

                    Behavior on width {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.OutCubic
                        }
                    }

                    RowLayout {
                        width: bgTrack.width
                        height: bgTrack.height
                        anchors.left: progressFill.left
                        anchors.leftMargin: 16 * root.contentScale
                        spacing: 10 * root.contentScale

                        MaterialSymbol {
                            text: "hard_drive"
                            iconSize: 18 * root.contentScale
                            color: WidgetColorScheme.textColorOnPillFill
                            Layout.alignment: Qt.AlignVCenter
                        }

                        StyledText {
                            text: root.titleText
                            font.pixelSize: 13 * root.contentScale
                            font.weight: Font.Bold
                            font.family: Appearance.font.family.main
                            color: WidgetColorScheme.textColorOnPillFill
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        StyledText {
                            text: root.valueText
                            font.pixelSize: 13 * root.contentScale
                            font.weight: Font.Bold
                            font.family: Appearance.font.family.main
                            color: WidgetColorScheme.textColorOnPillFill
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
