pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The Timetable tab's settings: display, reminders, birthdays, calendar and
 * Google event colors, calendar sources (ICS links, Outlook) and the khal setup
 * guide. The Enable Timetable switch itself stays in Settings → Cheat Sheet.
 */
AppSettingsPage {
    id: root

    readonly property var timetable: Config.options.calendar.timetable
    readonly property var notifications: Config.options.calendar.timetable.notifications
    readonly property var imports: Config.options.calendar.timetable.imports
    readonly property var writableCalendars: CalendarService.calendars.filter(calendar => !calendar.readOnly)
    property string subscriptionDraft: ""
    property string outlookClientIdDraft: ""

    function toggleOffset(offset, checked) {
        const current = Array.from(root.notifications.offsets ?? []);
        const index = current.indexOf(offset);
        if (checked && index < 0)
            current.push(offset);
        if (!checked && index >= 0)
            current.splice(index, 1);
        root.notifications.offsets = current;
    }

    function connectOutlook() {
        OutlookService.beginAuthorization(root.outlookClientIdDraft);
    }

    function addSubscription() {
        if (CalendarSubscriptions.addSubscription(root.subscriptionDraft)) {
            root.subscriptionDraft = "";
            subscriptionRow.field.clear();
        }
    }

    title: Translation.tr("Timetable settings")
    subtitle: Translation.tr("Calendars, reminders and sources")

    Component.onCompleted: root.outlookClientIdDraft = OutlookService.clientId

    Connections {
        target: OutlookService

        function onClientIdChanged() {
            if (!outlookClientIdRow.field.activeFocus)
                root.outlookClientIdDraft = OutlookService.clientId;
        }
    }

    // ══ Primary column ══

    TimetableStatusCard {
        Layout.fillWidth: true
        onOpenSetupGuide: root.scrollTo(setupSection)
    }

    AppSettingsSection {
        title: Translation.tr("Timetable display")
        symbol: "tune"

        AppToggleRow {
            symbol: "calendar_today"
            title: Translation.tr("Start with today")
            description: Translation.tr("Week and 3-day views open on today instead of the first day of the configured week.")
            checked: Config.options.cheatsheet.timetableTodayFirst
            onToggled: value => Config.options.cheatsheet.timetableTodayFirst = value
        }
        AppToggleRow {
            symbol: "gradient"
            title: Translation.tr("Proximity color gradient")
            description: Translation.tr("Day, 3 days and Week replace synced event colors with a gradient based on distance from the next event.")
            checked: root.timetable.proximityColorGradient
            onToggled: value => root.timetable.proximityColorGradient = value
        }
        AppToggleRow {
            symbol: "sports_score"
            title: Translation.tr("Show sports events")
            description: Translation.tr("Shows read-only ESPN games in the Timetable alongside calendar events.")
            checked: root.timetable.sportsEvents
            onToggled: value => root.timetable.sportsEvents = value
        }
        AppToggleRow {
            symbol: "nightlight"
            title: Translation.tr("Moon phases in month view")
            description: Translation.tr("Adds an optional moon phase badge next to the weather icon in the month grid.")
            checked: root.timetable.moonPhases.enable
            onToggled: value => root.timetable.moonPhases.enable = value
        }
        AppToggleRow {
            symbol: "cake"
            title: Translation.tr("Show contact birthdays")
            description: Translation.tr("Projects birthdays from KDE Connect contacts as read-only entries without adding calendar events.")
            checked: root.timetable.birthdays.enable
            onToggled: value => root.timetable.birthdays.enable = value
        }
    }

    AppSettingsSection {
        title: Translation.tr("Event reminders")
        symbol: "notifications_active"

        AppToggleRow {
            symbol: "notifications"
            title: Translation.tr("Enable timetable notifications")
            checked: root.notifications.enable
            onToggled: value => root.notifications.enable = value
        }
        AppToggleRow {
            enabled: root.notifications.enable
            symbol: "today"
            title: Translation.tr("Notify all-day events")
            checked: root.notifications.notifyAllDay
            onToggled: value => root.notifications.notifyAllDay = value
        }
        AppToggleRow {
            enabled: root.notifications.enable
            symbol: "volume_up"
            title: Translation.tr("Play notification sound")
            checked: root.notifications.sound
            onToggled: value => root.notifications.sound = value
        }
    }

    AppSettingsSection {
        title: Translation.tr("Default reminder offsets")
        symbol: "alarm"
        description: Translation.tr("Event-specific calendar alarms take precedence over these defaults.")
        enabled: root.notifications.enable

        Repeater {
            model: [
                ["0m", Translation.tr("At start time")],
                ["-5m", Translation.tr("5 minutes before")],
                ["-15m", Translation.tr("15 minutes before")],
                ["-1h", Translation.tr("1 hour before")],
                ["-1d", Translation.tr("1 day before")]
            ]

            delegate: AppToggleRow {
                required property var modelData
                symbol: "alarm"
                title: modelData[1]
                checked: (root.notifications.offsets ?? []).includes(modelData[0])
                onToggled: value => root.toggleOffset(modelData[0], value)
            }
        }
    }

    AppSettingsSection {
        title: Translation.tr("Daily summary")
        symbol: "summarize"

        AppToggleRow {
            symbol: "today"
            title: Translation.tr("Send a daily calendar summary")
            checked: root.notifications.dailySummary
            onToggled: value => root.notifications.dailySummary = value
        }
        AppFieldRow {
            enabled: root.notifications.dailySummary
            symbol: "schedule"
            title: Translation.tr("Summary time")
            placeholder: Translation.tr("08:00")
            value: root.notifications.dailySummaryTime
            onEdited: text => {
                const value = text.trim();
                if (/^\d{2}:\d{2}$/.test(value))
                    root.notifications.dailySummaryTime = value;
            }
        }
    }

    AppSettingsSection {
        id: setupSection
        title: Translation.tr("khal & sync setup guide")
        symbol: "integration_instructions"

        AppSettingRow {
            below: GoogleCalendarSetupGuide {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                showSync: false
            }
        }
    }

    // ══ Secondary column ══

    secondary: [
        AppSettingsSection {
            title: Translation.tr("Calendar colors")
            symbol: "palette"
            description: Translation.tr("Calendar colors are stored as khal ANSI names and rendered with the matching Material You token.")

            AppSettingRow {
                visible: root.writableCalendars.length === 0
                symbol: "calendar_month"
                title: CalendarService.khalAvailable
                    ? Translation.tr("No writable calendars")
                    : Translation.tr("khal is not available")
                description: CalendarService.khalAvailable
                    ? Translation.tr("Writable calendars appear here once khal reports them. Set up synchronization in the guide below.")
                    : Translation.tr("Calendar colors need a configured khal. Set up synchronization in the guide below.")
            }

            Repeater {
                model: root.writableCalendars

                delegate: AppChoiceRow {
                    required property var modelData
                    symbol: "calendar_month"
                    title: modelData.name
                    currentValue: modelData.color ?? ""
                    onSelected: color => CalendarService.setCalendarColor(modelData.name, color)
                    options: [
                        { "label": Translation.tr("No calendar color"), "value": "" },
                        { "label": Translation.tr("Primary"), "value": "light blue" },
                        { "label": Translation.tr("Secondary"), "value": "light green" },
                        { "label": Translation.tr("Tertiary"), "value": "light magenta" },
                        { "label": Translation.tr("Error"), "value": "light red" },
                        { "label": Translation.tr("Cyan"), "value": "light cyan" },
                        { "label": Translation.tr("Yellow"), "value": "yellow" }
                    ]
                }
            }
        },

        AppSettingsSection {
            title: Translation.tr("Google event colors")
            symbol: "colorize"
            description: Translation.tr("Google does not export per-event colors over CalDAV, so the synced .ics files carry none. Reading and writing them goes through the Google Calendar API, which needs its own authorization: the Google Tasks grant does not cover calendars.")

            AppToggleRow {
                symbol: "palette"
                title: Translation.tr("Show Google event colors")
                checked: root.timetable.googleColors.enable
                onToggled: value => {
                    root.timetable.googleColors.enable = value;
                    if (value)
                        GoogleCalendarService.refreshColors(true);
                }
            }
            AppStepperRow {
                enabled: root.timetable.googleColors.enable
                symbol: "schedule"
                title: Translation.tr("Refresh interval (hours)")
                value: root.timetable.googleColors.refreshHours
                from: 1
                to: 168
                onMoved: value => root.timetable.googleColors.refreshHours = value
            }
            AppSettingRow {
                symbol: GoogleCalendarService.available ? "account_circle" : "link"
                title: GoogleCalendarService.available
                    ? (GoogleCalendarService.activeAccountEmail.length > 0 ? GoogleCalendarService.activeAccountEmail : Translation.tr("Connected"))
                    : Translation.tr("Google Calendar API")
                description: !GoogleCalendarService.available
                    ? (!GoogleCalendarService.credentialsConfigured
                        ? Translation.tr("Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in ii/.env first (see the setup guide below).")
                        : Translation.tr("Not connected"))
                    : GoogleCalendarService.colorsFetchedAt > 0
                        ? Translation.tr("%1 event(s) mapped").arg(String(Object.keys(GoogleCalendarService.colorByUid).length))
                        : Translation.tr("Not fetched yet")

                RippleButtonWithIcon {
                    visible: GoogleCalendarService.available
                    implicitHeight: 36
                    materialIcon: GoogleCalendarService.colorsSyncing ? "sync" : "refresh"
                    mainText: GoogleCalendarService.colorsSyncing ? Translation.tr("Syncing…") : Translation.tr("Refresh colors")
                    enabled: root.timetable.googleColors.enable && !GoogleCalendarService.colorsSyncing
                    colText: Appearance.colors.colOnSecondaryContainer
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: GoogleCalendarService.refreshColors(true)
                }
                IconAction {
                    visible: GoogleCalendarService.available
                    symbol: "link_off"
                    danger: true
                    tooltip: Translation.tr("Disconnect Google Calendar API")
                    onClicked: GoogleCalendarService.disconnect()
                }

                below: [
                    NoticeBox {
                        Layout.fillWidth: true
                        visible: GoogleCalendarService.authenticating
                        materialIcon: "hourglass_empty"
                        text: Translation.tr("Waiting for the browser. Complete the Google authorization to finish connecting.")
                    },
                    WarningBox {
                        Layout.fillWidth: true
                        visible: GoogleCalendarService.reauthorizationRequired
                        text: GoogleCalendarService.lastErrorMessage.length > 0
                            ? GoogleCalendarService.lastErrorMessage
                            : Translation.tr("The Google Calendar authorization expired or was revoked. Reconnect the account below.")
                    },
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        visible: !GoogleCalendarService.available
                        implicitHeight: 44
                        centerContent: true
                        materialIcon: "link"
                        mainText: Translation.tr("Connect Google Calendar")
                        colText: Appearance.colors.colOnPrimaryContainer
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        enabled: GoogleCalendarService.credentialsConfigured && !GoogleCalendarService.authenticating
                        onClicked: GoogleCalendarService.startOAuth()
                    }
                ]
            }
        },

        AppSettingsSection {
            title: Translation.tr("Calendar sources")
            symbol: "calendar_add_on"

            AppToggleRow {
                symbol: "calendar_add_on"
                title: Translation.tr("Enable calendar sources")
                description: Translation.tr("Master switch for local ICS imports, subscribed links and Outlook sources. Disabling keeps all saved configuration.")
                checked: root.imports.enable
                onToggled: value => root.imports.enable = value
            }

            AppFieldRow {
                id: subscriptionRow
                enabled: root.imports.enable
                symbol: "link"
                title: Translation.tr("Subscribed links")
                description: Translation.tr("Add a public ICS URL for a read-only calendar. II manages only its own vdirsyncer and khal sections; your existing configuration stays intact.")
                placeholder: "https://…/calendar.ics"
                value: root.subscriptionDraft
                onEdited: text => root.subscriptionDraft = text
                onAccepted: root.addSubscription()

                RippleButtonWithIcon {
                    implicitHeight: 36
                    mainText: Translation.tr("Add URL")
                    materialIcon: "add"
                    colText: Appearance.colors.colOnPrimaryContainer
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    enabled: root.imports.enable && !CalendarSubscriptions.applying && root.subscriptionDraft.trim().length > 0
                    onClicked: root.addSubscription()
                }
            }

            AppSettingRow {
                visible: CalendarSubscriptions.lastError.length > 0
                    || CalendarSubscriptions.applying || CalendarSubscriptions.syncInProgress
                below: [
                    WarningBox {
                        Layout.fillWidth: true
                        visible: CalendarSubscriptions.lastError.length > 0
                        text: CalendarSubscriptions.lastError
                    },
                    NoticeBox {
                        Layout.fillWidth: true
                        visible: CalendarSubscriptions.lastError.length === 0
                            && (CalendarSubscriptions.applying || CalendarSubscriptions.syncInProgress)
                        materialIcon: "sync"
                        text: CalendarSubscriptions.applying
                            ? Translation.tr("Updating calendar configuration…")
                            : Translation.tr("Synchronizing subscribed calendars…")
                    }
                ]
            }

            AppSettingRow {
                visible: root.timetable.subscriptions.length === 0
                symbol: "link_off"
                title: Translation.tr("No subscribed calendars yet. Add an ICS URL above to mirror a public calendar as read-only.")
            }

            Repeater {
                model: root.timetable.subscriptions

                delegate: AppSettingRow {
                    id: subscriptionEntry
                    required property string modelData
                    symbol: "cloud_download"
                    title: subscriptionEntry.modelData

                    IconAction {
                        symbol: "close"
                        danger: true
                        tooltip: Translation.tr("Remove subscribed calendar")
                        onClicked: CalendarSubscriptions.removeSubscription(subscriptionEntry.modelData)
                    }
                }
            }
        },

        AppSettingsSection {
            title: Translation.tr("Outlook calendar")
            symbol: "event_available"
            enabled: root.imports.enable

            AppToggleRow {
                symbol: "event_available"
                title: Translation.tr("Sync Outlook calendar")
                description: Translation.tr("Mirrors connected Outlook events into a local read-only Timetable calendar.")
                checked: root.imports.outlook.enable
                onToggled: value => root.imports.outlook.enable = value
            }

            // Connection flow: how to get a client ID, then device code sign-in.
            AppFieldRow {
                id: outlookClientIdRow
                visible: root.imports.outlook.enable && !OutlookService.deviceFlowActive
                symbol: "key"
                title: Translation.tr("Microsoft application (client) ID")
                help: Translation.tr("To get a client ID, open Microsoft Entra admin center, register an application, select the account types you need, then copy its Application (client) ID from Overview. Enable public client flows under Authentication for this Device Code sign-in. Do not create or paste a client secret: II stores only the public client ID and an encrypted refresh token in the system keyring.")
                placeholder: Translation.tr("Paste the public client ID from Microsoft Entra")
                value: root.outlookClientIdDraft
                field.enabled: !OutlookService.authenticating
                onEdited: text => root.outlookClientIdDraft = text

                IconAction {
                    symbol: "open_in_new"
                    tooltip: Translation.tr("Open Microsoft Entra")
                    onClicked: Qt.openUrlExternally("https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade")
                }
            }

            AppSettingRow {
                visible: outlookClientIdRow.visible

                below: RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        centerContent: true
                        materialIcon: OutlookService.authenticated ? "person_add" : "login"
                        mainText: OutlookService.authenticated ? Translation.tr("Reconnect Outlook") : Translation.tr("Connect Outlook")
                        enabled: !OutlookService.authenticating && root.outlookClientIdDraft.trim().length > 0
                        colText: Appearance.colors.colOnSecondaryContainer
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: root.connectOutlook()
                    }
                    RippleButtonWithIcon {
                        implicitHeight: 40
                        visible: OutlookService.authenticated
                        centerContent: true
                        materialIcon: "link_off"
                        mainText: Translation.tr("Disconnect")
                        enabled: !OutlookCalendarImport.syncing
                        colText: Appearance.colors.colOnErrorContainer
                        colBackground: Appearance.colors.colErrorContainer
                        colBackgroundHover: Appearance.colors.colErrorContainerHover
                        colRipple: Appearance.colors.colErrorContainerActive
                        onClicked: OutlookService.disconnect()
                    }
                }
            }

            AppSettingRow {
                visible: root.imports.outlook.enable && OutlookService.deviceFlowActive
                symbol: "phonelink_lock"
                title: OutlookService.deviceMessage || Translation.tr("Open Microsoft sign-in and enter this code:")

                below: [
                    StyledText {
                        Layout.fillWidth: true
                        text: OutlookService.userCode
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                        horizontalAlignment: Text.AlignHCenter
                    },
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        centerContent: true
                        materialIcon: "open_in_new"
                        mainText: Translation.tr("Open Microsoft sign-in")
                        colText: Appearance.colors.colOnPrimaryContainer
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: Qt.openUrlExternally(OutlookService.verificationUri)
                    }
                ]
            }

            AppSettingRow {
                visible: root.imports.outlook.enable && OutlookService.authenticated && !OutlookService.deviceFlowActive
                symbol: "account_circle"
                title: OutlookService.activeAccountEmail.length > 0
                    ? OutlookService.activeAccountEmail
                    : (OutlookCalendarImport.lastStatus.length > 0
                        ? OutlookCalendarImport.lastStatus
                        : Translation.tr("Outlook is connected."))

                RippleButtonWithIcon {
                    implicitHeight: 36
                    materialIcon: OutlookCalendarImport.syncing ? "sync" : "refresh"
                    mainText: OutlookCalendarImport.syncing ? Translation.tr("Synchronizing Outlook…") : Translation.tr("Sync Outlook now")
                    enabled: !OutlookCalendarImport.syncing
                    colText: Appearance.colors.colOnSecondaryContainer
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: OutlookCalendarImport.syncNow()
                }
            }

            AppSettingRow {
                visible: OutlookService.lastError.length > 0 || OutlookCalendarImport.lastError.length > 0
                below: WarningBox {
                    Layout.fillWidth: true
                    text: OutlookService.lastError.length > 0 ? OutlookService.lastError : OutlookCalendarImport.lastError
                }
            }

            AppToggleRow {
                enabled: root.imports.outlook.enable
                symbol: "attach_email"
                title: Translation.tr("Import ICS attachments from Outlook")
                description: Translation.tr("Checks calendar attachments in the connected Outlook mailbox and imports each successful attachment only once.")
                checked: root.imports.outlook.icsAttachments.enable
                onToggled: value => root.imports.outlook.icsAttachments.enable = value

                below: [
                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignRight
                        implicitHeight: 40
                        visible: root.imports.outlook.enable && OutlookService.authenticated
                        centerContent: true
                        materialIcon: OutlookIcsImport.scanning ? "sync" : "refresh"
                        mainText: OutlookIcsImport.scanning ? Translation.tr("Checking Outlook…") : Translation.tr("Check Outlook attachments")
                        enabled: root.imports.outlook.icsAttachments.enable && !OutlookIcsImport.scanning
                        colText: Appearance.colors.colOnSecondaryContainer
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: OutlookIcsImport.scanNow()
                    },
                    WarningBox {
                        Layout.fillWidth: true
                        visible: OutlookIcsImport.lastError.length > 0
                        text: OutlookIcsImport.lastError
                    },
                    NoticeBox {
                        Layout.fillWidth: true
                        visible: OutlookIcsImport.lastError.length === 0 && OutlookIcsImport.lastStatus.length > 0
                        materialIcon: "check_circle"
                        text: OutlookIcsImport.lastStatus
                    }
                ]
            }
        }
    ]

    /** A round icon action on a row; `danger` fills with the error container on hover. */
    component IconAction: RippleButton {
        id: action
        property string symbol: ""
        property string tooltip: ""
        property bool danger: false

        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: action.danger ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer1Hover
        colRipple: action.danger ? Appearance.colors.colErrorContainerActive : Appearance.colors.colLayer1Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: action.symbol
            iconSize: Appearance.font.pixelSize.normal
            color: action.danger && action.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
        }

        StyledToolTip {
            extraVisibleCondition: action.hovered
            text: action.tooltip
        }
    }
}
