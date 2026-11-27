pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * ii Vitals as a 2x1 tile: today's steps, a ring filling toward the phone's step goal
 * around them, and last night's sleep under. A click opens the Vitals app. Off, or with
 * nothing synced for today, it says so in one line, as the sports tile does.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Vitals")

    readonly property string today: Qt.formatDate(DateTime.clock.date, "yyyy-MM-dd")
    readonly property var day: {
        void VitalsService.dataVersion;
        return VitalsService.enabled ? VitalsService.summary(root.today) : null;
    }
    readonly property var steps: root.day?.t?.steps ?? null
    readonly property int goal: VitalsService.meta?.goals?.steps ?? 0
    readonly property var night: root.day?.sleep ?? null
    readonly property bool hasData: root.steps !== null || root.night !== null
    readonly property real ringSize: Math.round(Math.min(root.surface.height - 16, 52))

    MouseArea {
        anchors.fill: parent
        enabled: !root.editMode
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            GlobalStates.sidebarRightOpen = false;
            GlobalStates.openVitalsApp("");
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 10
        spacing: 8

        // The goal ring with the walker; without data it stays an empty badge.
        Item {
            Layout.preferredWidth: root.ringSize
            Layout.preferredHeight: root.ringSize

            MaterialShape {
                anchors.centerIn: parent
                visible: !root.hasData
                implicitSize: root.ringSize
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colPrimaryContainer
            }
            CircularProgress {
                anchors.centerIn: parent
                visible: root.hasData
                implicitSize: root.ringSize
                lineWidth: 4
                value: root.goal > 0 ? Math.min(1, (root.steps ?? 0) / root.goal) : 0
                colPrimary: Appearance.colors.colPrimary
                colSecondary: Appearance.colors.colSecondaryContainer
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.hasData ? "directions_walk" : "ecg_heart"
                iconSize: Math.round(root.ringSize * 0.46)
                fill: 1
                color: root.hasData ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnPrimaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: !root.hasData ? Translation.tr("Vitals")
                    : root.steps === null ? Translation.tr("No steps yet")
                    : VitalsTypes.format("steps", root.steps)
                color: Appearance.colors.colOnLayer2
                font.family: Appearance.font.family.main
                font.pixelSize: root.hasData && root.steps !== null ? Appearance.font.pixelSize.huge : Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                font.variableAxes: root.hasData && root.steps !== null ? ({ "wght": 760, "wdth": 60, "ROND": 100 }) : ({})
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 3

                MaterialSymbol {
                    visible: root.night !== null
                    text: "bedtime"
                    iconSize: Appearance.font.pixelSize.small
                    fill: 1
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: !VitalsService.enabled ? Translation.tr("Off")
                        : !root.hasData ? Translation.tr("No data yet")
                        : root.night !== null ? VitalsTypes.duration(root.night.min)
                        : Translation.tr("steps today")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }
}
