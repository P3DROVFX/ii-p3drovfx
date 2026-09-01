pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Health card for the Timetable calendar engine (khal + vdirsyncer).
// Shows one of three states: disabled, khal unavailable (error) or ready.
Rectangle {
    id: root

    readonly property bool timetableEnabled: Config.options.cheatsheet.enableTimetable
    readonly property int writableCalendarCount: CalendarService.calendars.filter(calendar => !calendar.readOnly).length
    readonly property int readOnlyCalendarCount: CalendarService.calendars.length - root.writableCalendarCount

    readonly property string status: {
        if (!root.timetableEnabled)
            return Translation.tr("Timetable disabled");
        if (!CalendarService.khalAvailable)
            return Translation.tr("khal unavailable");
        if (CalendarService.calendars.length === 0)
            return Translation.tr("No calendars found");
        return Translation.tr("Ready");
    }
    readonly property bool healthy: root.timetableEnabled && CalendarService.khalAvailable && CalendarService.calendars.length > 0
    readonly property string detail: {
        if (!root.timetableEnabled)
            return Translation.tr("Enable the Timetable switch in Cheatsheet settings to use the calendar.");
        if (!CalendarService.khalAvailable)
            return Translation.tr("Install and configure khal and vdirsyncer, then run a recheck.");
        if (CalendarService.calendars.length === 0)
            return Translation.tr("khal is configured but reports no calendars. Open the setup guide below or run khal configure.");
        return Translation.tr("%1 writable calendar(s) · %2 read-only").arg(String(root.writableCalendarCount)).arg(String(root.readOnlyCalendarCount));
    }

    signal openSetupGuide()

    implicitHeight: cardLayout.implicitHeight + Appearance.font.pixelSize.large

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: cardLayout

        anchors.fill: parent
        anchors.margins: Appearance.font.pixelSize.small
        spacing: Appearance.font.pixelSize.smallest

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.font.pixelSize.smallest

            MaterialShapeWrappedMaterialSymbol {
                text: "calendar_month"
                iconSize: Appearance.font.pixelSize.large
                padding: Appearance.font.pixelSize.smallest
                shape: root.healthy ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Cookie7Sided
                color: root.healthy ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                colSymbol: root.healthy ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Calendar engine")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }

            Rectangle {
                implicitWidth: statusPillText.implicitWidth + Appearance.font.pixelSize.normal
                implicitHeight: statusPillText.implicitHeight + Appearance.font.pixelSize.smallest
                radius: Appearance.rounding.full
                color: root.healthy ? Appearance.colors.colPrimaryContainer
                    : (root.timetableEnabled ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer)

                StyledText {
                    id: statusPillText

                    anchors.centerIn: parent
                    text: root.status
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: root.healthy ? Appearance.colors.colOnPrimaryContainer
                        : (root.timetableEnabled ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.font.pixelSize.smallest

            StyledText {
                Layout.fillWidth: true
                text: root.detail
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            RippleButtonWithIcon {
                id: recheckButton

                implicitHeight: 40
                centerContent: true
                materialIcon: CalendarService.loading ? "progress_activity" : "refresh"
                mainText: CalendarService.loading ? Translation.tr("Checking…") : Translation.tr("Recheck")
                enabled: !CalendarService.loading
                Accessible.name: Translation.tr("Recheck khal")
                Accessible.description: Translation.tr("Check again whether khal and its calendars are available. Current status: %1").arg(root.status)
                colText: Appearance.colors.colOnPrimaryContainer
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: CalendarService.recheckKhal()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.healthy
            spacing: Appearance.font.pixelSize.smallest

            MaterialSymbol {
                text: "arrow_outward"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: Translation.tr("See the khal & sync setup guide below")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colPrimary

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openSetupGuide()
                }
            }
        }
    }
}
