import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentPage {
    id: root

    forceWidth: false
    property bool showBackButton: false
    property string subscriptionDraft: ""
    property string outlookClientIdDraft: ""
    signal goBack()

    function toggleOffset(offset, checked) {
        const current = Array.from(Config.options.calendar.timetable.notifications.offsets ?? []);
        const index = current.indexOf(offset);
        if (checked && index < 0)
            current.push(offset);
        if (!checked && index >= 0)
            current.splice(index, 1);
        Config.options.calendar.timetable.notifications.offsets = current;
    }

    function connectOutlook() {
        OutlookService.beginAuthorization(root.outlookClientIdDraft);
    }

    readonly property var writableCalendars: CalendarService.calendars.filter(calendar => !calendar.readOnly)

    Component.onCompleted: root.outlookClientIdDraft = OutlookService.clientId

    Connections {
        target: OutlookService

        function onClientIdChanged() {
            if (!outlookClientIdInput.textField.activeFocus)
                root.outlookClientIdDraft = OutlookService.clientId;
        }
    }

    RowLayout {
        visible: root.showBackButton
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Timetable Settings")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ══ Engine status (khal / calendars health) ══
    TimetableStatusCard {
        id: statusCard
        Layout.fillWidth: true
        onOpenSetupGuide: {
            // Scroll to and highlight the setup guide section.
            SearchRegistry.currentSearch = Translation.tr("khal & sync setup guide");
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Timetable display")

        ConfigSwitch {
            buttonIcon: "calendar_today"
            text: Translation.tr("Start with today")
            description: Translation.tr("Week and 3-day views open on today instead of the first day of the configured week.")
            checked: Config.options.cheatsheet.timetableTodayFirst
            onCheckedChanged: {
                Config.options.cheatsheet.timetableTodayFirst = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "gradient"
            text: Translation.tr("Proximity color gradient")
            description: Translation.tr("Day, 3 days and Week replace synced event colors with a gradient based on distance from the next event.")
            checked: Config.options.calendar.timetable.proximityColorGradient
            onCheckedChanged: {
                Config.options.calendar.timetable.proximityColorGradient = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "sports_score"
            text: Translation.tr("Show sports events")
            description: Translation.tr("Shows read-only ESPN games in the Timetable alongside calendar events.")
            checked: Config.options.calendar.timetable.sportsEvents
            onCheckedChanged: {
                Config.options.calendar.timetable.sportsEvents = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "nightlight"
            text: Translation.tr("Moon phases in month view")
            description: Translation.tr("Adds an optional moon phase badge next to the weather icon in the month grid.")
            checked: Config.options.calendar.timetable.moonPhases.enable
            onCheckedChanged: {
                Config.options.calendar.timetable.moonPhases.enable = checked;
            }
        }
    }

    ContentSection {
        icon: "notifications_active"
        title: Translation.tr("Event reminders")

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Enable timetable notifications")
            checked: Config.options.calendar.timetable.notifications.enable
            onCheckedChanged: Config.options.calendar.timetable.notifications.enable = checked
        }

        ConfigSwitch {
            enabled: Config.options.calendar.timetable.notifications.enable
            buttonIcon: "today"
            text: Translation.tr("Notify all-day events")
            checked: Config.options.calendar.timetable.notifications.notifyAllDay
            onCheckedChanged: Config.options.calendar.timetable.notifications.notifyAllDay = checked
        }

        ConfigSwitch {
            enabled: Config.options.calendar.timetable.notifications.enable
            buttonIcon: "volume_up"
            text: Translation.tr("Play notification sound")
            checked: Config.options.calendar.timetable.notifications.sound
            onCheckedChanged: Config.options.calendar.timetable.notifications.sound = checked
        }

        ContentSubsectionLabel {
            text: Translation.tr("Default reminder offsets")
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Event-specific calendar alarms take precedence over these defaults.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            wrapMode: Text.Wrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            enabled: Config.options.calendar.timetable.notifications.enable
            spacing: 4

            Repeater {
                model: [
                    ["0m", Translation.tr("At start time")],
                    ["-5m", Translation.tr("5 minutes before")],
                    ["-15m", Translation.tr("15 minutes before")],
                    ["-1h", Translation.tr("1 hour before")],
                    ["-1d", Translation.tr("1 day before")]
                ]

                delegate: ConfigSwitch {
                    required property var modelData
                    buttonIcon: "alarm"
                    text: modelData[1]
                    checked: (Config.options.calendar.timetable.notifications.offsets ?? []).includes(modelData[0])
                    onCheckedChanged: root.toggleOffset(modelData[0], checked)
                }
            }
        }

        ContentSubsectionLabel {
            text: Translation.tr("Daily summary")
        }

        ConfigSwitch {
            buttonIcon: "today"
            text: Translation.tr("Send a daily calendar summary")
            checked: Config.options.calendar.timetable.notifications.dailySummary
            onCheckedChanged: Config.options.calendar.timetable.notifications.dailySummary = checked
        }

        ConfigTextField {
            enabled: Config.options.calendar.timetable.notifications.dailySummary
            icon: "schedule"
            text: Translation.tr("Summary time")
            placeholderText: Translation.tr("08:00")
            inputText: Config.options.calendar.timetable.notifications.dailySummaryTime
            textField.onEditingFinished: {
                const value = textField.text.trim();
                if (/^\d{2}:\d{2}$/.test(value))
                    Config.options.calendar.timetable.notifications.dailySummaryTime = value;
            }
        }
    }

    ContentSection {
        icon: "cake"
        title: Translation.tr("Contact birthdays")

        ConfigSwitch {
            buttonIcon: "cake"
            text: Translation.tr("Show contact birthdays")
            description: Translation.tr("Projects birthdays from KDE Connect contacts as read-only entries without adding calendar events.")
            checked: Config.options.calendar.timetable.birthdays.enable
            onCheckedChanged: Config.options.calendar.timetable.birthdays.enable = checked
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Calendar colors")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Calendar colors are stored as khal ANSI names and rendered with the matching Material You token.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            wrapMode: Text.Wrap
        }

        // Empty state: khal unavailable or no writable calendars
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            visible: root.writableCalendars.length === 0

            PagePlaceholder {
                anchors.fill: parent
                shown: visible
                icon: "calendar_month"
                title: CalendarService.khalAvailable
                    ? Translation.tr("No writable calendars")
                    : Translation.tr("khal is not available")
                description: CalendarService.khalAvailable
                    ? Translation.tr("Writable calendars appear here once khal reports them. Set up synchronization in the guide below.")
                    : Translation.tr("Calendar colors need a configured khal. Set up synchronization in the guide below.")
                iconSize: 40
                iconPadding: 8
                titlePixelSize: Appearance.font.pixelSize.large
                descriptionPixelSize: Appearance.font.pixelSize.small
            }
        }

        Repeater {
            model: root.writableCalendars

            delegate: ContentSubsection {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name
                icon: "calendar_month"

                ConfigSelectionArray {
                    currentValue: modelData.color ?? ""
                    onSelected: color => CalendarService.setCalendarColor(modelData.name, color)
                    options: [
                        { displayName: Translation.tr("No calendar color"), value: "" },
                        { displayName: Translation.tr("Primary"), value: "light blue" },
                        { displayName: Translation.tr("Secondary"), value: "light green" },
                        { displayName: Translation.tr("Tertiary"), value: "light magenta" },
                        { displayName: Translation.tr("Error"), value: "light red" },
                        { displayName: Translation.tr("Cyan"), value: "light cyan" },
                        { displayName: Translation.tr("Yellow"), value: "yellow" }
                    ]
                }
            }
        }
    }

    ContentSection {
        id: googleColorsSection
        icon: "colorize"
        title: Translation.tr("Google event colors")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Google does not export per-event colors over CalDAV, so the synced .ics files carry none. Reading and writing them goes through the Google Calendar API, which needs its own authorization: the Google Tasks grant does not cover calendars.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            wrapMode: Text.Wrap
        }

        ConfigSwitch {
            buttonIcon: "palette"
            text: Translation.tr("Show Google event colors")
            checked: Config.options.calendar.timetable.googleColors.enable
            onCheckedChanged: {
                Config.options.calendar.timetable.googleColors.enable = checked;
                if (checked)
                    GoogleCalendarService.refreshColors(true);
            }
        }

        ConfigSpinBox {
            icon: "schedule"
            text: Translation.tr("Refresh interval (hours)")
            value: Config.options.calendar.timetable.googleColors.refreshHours
            from: 1
            to: 168
            stepSize: 1
            enabled: Config.options.calendar.timetable.googleColors.enable
            onValueChanged: Config.options.calendar.timetable.googleColors.refreshHours = value
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: GoogleCalendarService.authenticating
            materialIcon: "hourglass_empty"
            text: Translation.tr("Waiting for the browser. Complete the Google authorization to finish connecting.")
        }

        WarningBox {
            Layout.fillWidth: true
            visible: GoogleCalendarService.reauthorizationRequired
            text: GoogleCalendarService.lastErrorMessage.length > 0
                ? GoogleCalendarService.lastErrorMessage
                : Translation.tr("The Google Calendar authorization expired or was revoked. Reconnect the account below.")
        }

        // Not connected: primary action to connect
        ColumnLayout {
            Layout.fillWidth: true
            visible: !GoogleCalendarService.available
            spacing: 8

            RippleButtonWithIcon {
                Layout.fillWidth: true
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

            StyledText {
                Layout.fillWidth: true
                text: !GoogleCalendarService.credentialsConfigured
                    ? Translation.tr("Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in ii/.env first (see the setup guide below).")
                    : Translation.tr("Not connected")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }
        }

        // Connected: account + disconnect + colors sync
        RowLayout {
            Layout.fillWidth: true
            visible: GoogleCalendarService.available
            spacing: 10

            MaterialSymbol {
                text: "account_circle"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: GoogleCalendarService.activeAccountEmail.length > 0
                    ? GoogleCalendarService.activeAccountEmail
                    : Translation.tr("Connected")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideMiddle
            }

            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colErrorContainer
                onClicked: GoogleCalendarService.disconnect()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "link_off"
                    iconSize: Appearance.font.pixelSize.normal
                    color: parent.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    extraVisibleCondition: parent.hovered
                    text: Translation.tr("Disconnect Google Calendar API")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: GoogleCalendarService.available
            spacing: 10

            RippleButtonWithIcon {
                materialIcon: GoogleCalendarService.colorsSyncing ? "sync" : "refresh"
                mainText: GoogleCalendarService.colorsSyncing ? Translation.tr("Syncing…") : Translation.tr("Refresh colors")
                centerContent: true
                enabled: Config.options.calendar.timetable.googleColors.enable
                    && !GoogleCalendarService.colorsSyncing
                onClicked: GoogleCalendarService.refreshColors(true)
            }

            StyledText {
                Layout.fillWidth: true
                text: GoogleCalendarService.colorsFetchedAt > 0
                    ? Translation.tr("%1 event(s) mapped").arg(String(Object.keys(GoogleCalendarService.colorByUid).length))
                    : Translation.tr("Not fetched yet")
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }

    ContentSection {
        id: setupSection
        icon: "integration_instructions"
        title: Translation.tr("khal & sync setup guide")

        GoogleCalendarSetupGuide {
            id: setupGuide
            Layout.fillWidth: true
            showSync: false
        }
    }

    ContentSection {
        icon: "calendar_add_on"
        title: Translation.tr("Calendar sources")

        ConfigSwitch {
            buttonIcon: "calendar_add_on"
            text: Translation.tr("Enable calendar sources")
            description: Translation.tr("Master switch for local ICS imports, subscribed links and Outlook sources. Disabling keeps all saved configuration.")
            checked: Config.options.calendar.timetable.imports.enable
            onCheckedChanged: Config.options.calendar.timetable.imports.enable = checked
        }

        ContentSubsectionLabel {
            text: Translation.tr("Subscribed links")
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Add a public ICS URL for a read-only calendar. II manages only its own vdirsyncer and khal sections; your existing configuration stays intact.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            wrapMode: Text.Wrap
        }

        ConfigTextField {
            id: subscriptionInput
            Layout.fillWidth: true
            enabled: Config.options.calendar.timetable.imports.enable
            icon: "link"
            text: Translation.tr("Calendar ICS URL")
            placeholderText: "https://…/calendar.ics"
            inputText: root.subscriptionDraft
            textField.onTextChanged: root.subscriptionDraft = textField.text
            textField.onAccepted: addSubscriptionButton.addDraft()
        }

        RippleButtonWithIcon {
            id: addSubscriptionButton
            Layout.alignment: Qt.AlignRight
            implicitHeight: 40
            mainText: Translation.tr("Add URL")
            materialIcon: "add"
            colText: Appearance.colors.colOnPrimaryContainer
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            enabled: Config.options.calendar.timetable.imports.enable && !CalendarSubscriptions.applying && root.subscriptionDraft.trim().length > 0

            function addDraft() {
                if (CalendarSubscriptions.addSubscription(root.subscriptionDraft)) {
                    root.subscriptionDraft = "";
                    subscriptionInput.textField.clear();
                }
            }

            onClicked: addDraft()
        }

        WarningBox {
            Layout.fillWidth: true
            visible: CalendarSubscriptions.lastError.length > 0
            text: CalendarSubscriptions.lastError
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: CalendarSubscriptions.lastError.length === 0
                && (CalendarSubscriptions.applying || CalendarSubscriptions.syncInProgress)
            materialIcon: "sync"
            text: CalendarSubscriptions.applying
                ? Translation.tr("Updating calendar configuration…")
                : Translation.tr("Synchronizing subscribed calendars…")
        }

        // Empty state when no subscriptions configured
        Rectangle {
            Layout.fillWidth: true
            visible: Config.options.calendar.timetable.subscriptions.length === 0
            implicitHeight: 56
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                MaterialSymbol {
                    text: "link_off"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("No subscribed calendars yet. Add an ICS URL above to mirror a public calendar as read-only.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
        }

        Repeater {
            model: Config.options.calendar.timetable.subscriptions

            delegate: Rectangle {
                required property string modelData
                Layout.fillWidth: true
                implicitHeight: 48
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    spacing: 8

                    MaterialSymbol {
                        text: "cloud_download"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData
                        elide: Text.ElideMiddle
                        maximumLineCount: 1
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }

                    RippleButton {
                        id: removeSubscriptionButton
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colErrorContainer
                        onClicked: CalendarSubscriptions.removeSubscription(modelData)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: Appearance.font.pixelSize.normal
                            color: removeSubscriptionButton.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            extraVisibleCondition: removeSubscriptionButton.hovered
                            text: Translation.tr("Remove subscribed calendar")
                        }
                    }
                }
            }
        }

        ContentSubsectionLabel {
            text: Translation.tr("Outlook calendar")
        }

        ConfigSwitch {
            enabled: Config.options.calendar.timetable.imports.enable
            buttonIcon: "event_available"
            text: Translation.tr("Sync Outlook calendar")
            description: Translation.tr("Mirrors connected Outlook events into a local read-only Timetable calendar.")
            checked: Config.options.calendar.timetable.imports.outlook.enable
            onCheckedChanged: Config.options.calendar.timetable.imports.outlook.enable = checked
        }

        // ── Outlook connection flow ──
        ColumnLayout {
            Layout.fillWidth: true
            visible: Config.options.calendar.timetable.imports.enable
                && Config.options.calendar.timetable.imports.outlook.enable
            spacing: 10

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("To get a client ID, open Microsoft Entra admin center, register an application, select the account types you need, then copy its Application (client) ID from Overview. Enable public client flows under Authentication for this Device Code sign-in. Do not create or paste a client secret: II stores only the public client ID and an encrypted refresh token in the system keyring.")
            }

            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignRight
                implicitHeight: 40
                centerContent: true
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open Microsoft Entra")
                colText: Appearance.colors.colOnSecondaryContainer
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: Qt.openUrlExternally("https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade")
            }

            // Device code flow in progress
            ColumnLayout {
                Layout.fillWidth: true
                visible: OutlookService.deviceFlowActive
                spacing: 6

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "phonelink_lock"
                    text: OutlookService.deviceMessage || Translation.tr("Open Microsoft sign-in and enter this code:")
                }

                StyledText {
                    Layout.fillWidth: true
                    text: OutlookService.userCode
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

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
            }

            // Not authenticated: client ID + connect
            ColumnLayout {
                Layout.fillWidth: true
                visible: !OutlookService.deviceFlowActive
                spacing: 8

                ConfigTextField {
                    id: outlookClientIdInput
                    Layout.fillWidth: true
                    enabled: !OutlookService.authenticating
                    icon: "key"
                    text: Translation.tr("Microsoft application (client) ID")
                    placeholderText: Translation.tr("Paste the public client ID from Microsoft Entra")
                    inputText: root.outlookClientIdDraft
                    textField.onTextChanged: root.outlookClientIdDraft = textField.text
                }

                RowLayout {
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

            // Connected: account status + sync actions
            ColumnLayout {
                Layout.fillWidth: true
                visible: OutlookService.authenticated && !OutlookService.deviceFlowActive
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    MaterialSymbol {
                        text: "account_circle"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: OutlookService.activeAccountEmail.length > 0
                            ? OutlookService.activeAccountEmail
                            : (OutlookCalendarImport.lastStatus.length > 0
                                ? OutlookCalendarImport.lastStatus
                                : Translation.tr("Outlook is connected."))
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideMiddle
                    }
                }

                RippleButtonWithIcon {
                    Layout.alignment: Qt.AlignRight
                    implicitHeight: 40
                    centerContent: true
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
        }

        WarningBox {
            Layout.fillWidth: true
            visible: OutlookService.lastError.length > 0 || OutlookCalendarImport.lastError.length > 0
            text: OutlookService.lastError.length > 0 ? OutlookService.lastError : OutlookCalendarImport.lastError
        }

        ContentSubsectionLabel {
            text: Translation.tr("Outlook attachments")
        }

        ConfigSwitch {
            enabled: Config.options.calendar.timetable.imports.enable
                && Config.options.calendar.timetable.imports.outlook.enable
            buttonIcon: "attach_email"
            text: Translation.tr("Import ICS attachments from Outlook")
            description: Translation.tr("Checks calendar attachments in the connected Outlook mailbox and imports each successful attachment only once.")
            checked: Config.options.calendar.timetable.imports.outlook.icsAttachments.enable
            onCheckedChanged: Config.options.calendar.timetable.imports.outlook.icsAttachments.enable = checked
        }

        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignRight
            implicitHeight: 40
            visible: Config.options.calendar.timetable.imports.enable
                && Config.options.calendar.timetable.imports.outlook.enable
                && OutlookService.authenticated
            centerContent: true
            materialIcon: OutlookIcsImport.scanning ? "sync" : "refresh"
            mainText: OutlookIcsImport.scanning ? Translation.tr("Checking Outlook…") : Translation.tr("Check Outlook attachments")
            enabled: Config.options.calendar.timetable.imports.outlook.icsAttachments.enable
                && !OutlookIcsImport.scanning
            colText: Appearance.colors.colOnSecondaryContainer
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: OutlookIcsImport.scanNow()
        }

        WarningBox {
            Layout.fillWidth: true
            visible: OutlookIcsImport.lastError.length > 0
            text: OutlookIcsImport.lastError
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: OutlookIcsImport.lastError.length === 0
                && OutlookIcsImport.lastStatus.length > 0
            materialIcon: "check_circle"
            text: OutlookIcsImport.lastStatus
        }
    }
}
