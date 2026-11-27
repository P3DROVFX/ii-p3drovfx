pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Health card for the Timetable calendar engine (khal + vdirsyncer).
// Shows one of three states: disabled, khal unavailable (error) or ready; without
// khal, the phone's calendar (ii tools) counts as ready.
Rectangle {
    id: root

    readonly property bool timetableEnabled: Config.options?.calendarApp?.enable ?? true
    readonly property int writableCalendarCount: CalendarService.calendars.filter(calendar => !calendar.readOnly).length
    readonly property int readOnlyCalendarCount: CalendarService.calendars.length - root.writableCalendarCount

    readonly property string status: {
        if (!root.timetableEnabled)
            return Translation.tr("Calendar disabled");
        if (!CalendarService.khalAvailable)
            return CalendarService.phoneCalendarActive ? Translation.tr("Phone calendar") : Translation.tr("khal unavailable");
        if (CalendarService.calendars.length === 0)
            return Translation.tr("No calendars found");
        if (CalendarService.googleAuthRequired)
            return Translation.tr("Local mode");
        return Translation.tr("Ready");
    }
    readonly property bool healthy: root.timetableEnabled && (CalendarService.khalAvailable
        ? CalendarService.calendars.length > 0
        : CalendarService.phoneCalendarActive)
    readonly property string detail: {
        if (!root.timetableEnabled)
            return Translation.tr("Enable Calendar in Settings → Apps & Overlays to use it.");
        if (!CalendarService.khalAvailable && CalendarService.phoneCalendarActive)
            return Translation.tr("Events come from the phone through ii tools (%1 calendar(s)). khal is optional.").arg(String(CalendarService.phoneCalendars.filter(calendar => calendar.shown).length));
        if (!CalendarService.khalAvailable)
            return Translation.tr("Install khal to store local events offline, then run a recheck.");
        if (CalendarService.calendars.length === 0)
            return Translation.tr("khal is configured but reports no calendars. Open the setup guide below or run khal configure.");
        if (CalendarService.googleAuthRequired)
            return Translation.tr("%1 writable calendar(s) working locally. Cloud sync token expired (reconnect anytime if you want Google sync).").arg(String(root.writableCalendarCount));
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
                id: reconnectButton

                visible: CalendarService.googleAuthRequired
                implicitHeight: 40
                centerContent: true
                materialIcon: CalendarService.reauthenticatingGoogle ? "progress_activity" : "login"
                mainText: CalendarService.reauthenticatingGoogle ? Translation.tr("Connecting…") : Translation.tr("Reconnect Google")
                enabled: !CalendarService.reauthenticatingGoogle
                Accessible.name: Translation.tr("Reconnect Google Calendar")
                Accessible.description: Translation.tr("Open browser to reauthorize Google Calendar synchronization")
                colText: Appearance.colors.colOnError
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colRipple: Appearance.colors.colOnError
                onClicked: CalendarService.startGoogleReauth()
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
