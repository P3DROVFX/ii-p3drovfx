import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 10

    // When true, also shows the manual sync row. The Timetable settings page
    // hosts its own sync controls, so it opts out to avoid duplicating them.
    property bool showSync: true

    readonly property var setupSteps: [
        Translation.tr("Open Google Cloud Console and create or select the project shared with Gmail, Tasks and Drive."),
        Translation.tr("Enable the Google Calendar API in APIs & Services → Library."),
        Translation.tr("Configure the OAuth consent screen, add your account as a test user, and allow Calendar plus basic email scopes."),
        Translation.tr("Create an OAuth 2.0 Desktop client under Credentials."),
        Translation.tr("Save that same client ID and secret in ii/.env as GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET."),
        Translation.tr("Configure vdirsyncer with the same credential pair, run vdirsyncer discover once, then vdirsyncer sync."),
        Translation.tr("Point khal at the synchronized directory (khal configure). Timetable then reads locally and syncs each completed edit in the background.")
    ]

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "sync"
            text: Translation.tr("Google Calendar ↔ vdirsyncer ↔ khal ↔ Timetable. New events appear locally first; after khal saves the ICS file, II synchronizes the affected writable calendar in the background.")
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "key"
            text: Translation.tr("Use the same Google Cloud OAuth Desktop credentials as the other Google integrations: GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in ii/.env. When configuring the vdirsyncer google_calendar storage, copy this same pair instead of creating another OAuth client.")
        }
    }

    WarningBox {
        Layout.fillWidth: true
        visible: !GoogleCalendarService.credentialsConfigured
        text: Translation.tr("Google OAuth credentials are missing. Add GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET to ii/.env before authorizing Calendar API features.")
    }

    WarningBox {
        Layout.fillWidth: true
        visible: !CalendarService.khalAvailable
        text: Translation.tr("khal is not ready yet. Install and configure khal plus vdirsyncer before Timetable can read or synchronize calendars.")
    }

    ContentSubsectionLabel {
        text: Translation.tr("Google Calendar setup")
    }

    Repeater {
        model: root.setupSteps

        delegate: RowLayout {
            required property int index
            required property string modelData
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                implicitWidth: 24
                implicitHeight: 24
                radius: width / 2
                color: Appearance.colors.colPrimaryContainer

                StyledText {
                    anchors.centerIn: parent
                    text: String(index + 1)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: modelData
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.Wrap
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        RippleButtonWithIcon {
            Layout.fillWidth: true
            implicitHeight: 40
            centerContent: true
            materialIcon: "open_in_new"
            mainText: Translation.tr("Open Google Cloud Console")
            colText: Appearance.colors.colOnSecondaryContainer
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: Qt.openUrlExternally("https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            implicitHeight: 40
            centerContent: true
            materialIcon: GoogleCalendarService.available ? "link_off" : "link"
            mainText: GoogleCalendarService.available ? Translation.tr("Disconnect API") : Translation.tr("Authorize Calendar API")
            enabled: GoogleCalendarService.credentialsConfigured && !GoogleCalendarService.authenticating
            colText: Appearance.colors.colOnPrimaryContainer
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            onClicked: {
                if (GoogleCalendarService.available)
                    GoogleCalendarService.disconnect();
                else
                    GoogleCalendarService.startOAuth();
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: GoogleCalendarService.authenticating
            ? Translation.tr("Complete Google authorization in your browser.")
            : (GoogleCalendarService.available
                ? Translation.tr("Calendar API authorized for %1.").arg(GoogleCalendarService.activeAccountEmail)
                : Translation.tr("Calendar API authorization is optional for per-event Google colors; calendar event sync itself uses vdirsyncer."))
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnSurfaceVariant
        wrapMode: Text.Wrap
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.showSync
        spacing: 8

        RippleButtonWithIcon {
            Layout.fillWidth: true
            implicitHeight: 40
            centerContent: true
            materialIcon: "sync"
            mainText: Translation.tr("Synchronize writable calendars")
            enabled: CalendarService.khalAvailable
            colText: Appearance.colors.colOnSecondaryContainer
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: CalendarService.requestWritableCalendarSyncs()
        }

        StyledText {
            Layout.fillWidth: true
            text: CalendarService.lastCalendarSyncError.length > 0
                ? CalendarService.lastCalendarSyncError
                : (CalendarService.lastCalendarSyncStatus.length > 0
                    ? CalendarService.lastCalendarSyncStatus
                    : Translation.tr("No manual synchronization has run in this session."))
            font.pixelSize: Appearance.font.pixelSize.small
            color: CalendarService.lastCalendarSyncError.length > 0
                ? Appearance.colors.colError
                : Appearance.colors.colOnSurfaceVariant
            wrapMode: Text.Wrap
        }
    }
}
