pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The phone's calendar (ii tools) in the Timetable: status, what the PC may do with
 * it, how copies of khal's events are handled, and which phone calendars show.
 * Shared by Settings → ii tools and the Timetable settings; both write
 * `Config.options.iiTools.calendar`.
 */
AppSettingsSection {
    id: root

    readonly property var options: Config.options.iiTools.calendar
    readonly property var feed: CalendarService.phoneFeed
    readonly property int eventCount: CalendarService.phoneEvents.length
    readonly property int calendarCount: CalendarService.phoneCalendars.filter(calendar => calendar.shown).length

    function providerLabel(provider) {
        switch (String(provider)) {
        case "google":
            return "Google";
        case "samsung":
            return "Samsung";
        case "outlook":
            return "Outlook";
        case "local":
            return Translation.tr("On the phone");
        default:
            return String(provider);
        }
    }

    readonly property string statusTitle: {
        if (!root.options.enable)
            return Translation.tr("Off");
        if (IiLinkService.calendarDev !== "" && CalendarService.phoneLive)
            return Translation.tr("Receiving the phone's calendar");
        if (IiLinkService.calendarDev !== "")
            return Translation.tr("Phone connected, waiting for its calendar");
        if (root.feed !== null)
            return Translation.tr("Phone away");
        if (IiLinkService.phoneConnected)
            return Translation.tr("The phone isn't sharing its calendar");
        return Translation.tr("Waiting for the phone");
    }

    readonly property string statusDetail: {
        if (!root.options.enable)
            return Translation.tr("Turn it on to see the phone's events in the Timetable.");
        if (IiLinkService.calendarDev !== "" && CalendarService.phoneLive) {
            const when = Qt.formatTime(new Date(IiLinkService.calendarAt), Config.options?.time?.format ?? "hh:mm");
            const access = CalendarService.phoneCalendars.some(calendar => !calendar.readOnly)
                ? Translation.tr("editable from this PC")
                : Translation.tr("read-only");
            return Translation.tr("%1 events from %2 calendar(s), %3 · updated %4")
                .arg(String(root.eventCount)).arg(String(root.calendarCount)).arg(access).arg(when);
        }
        if (IiLinkService.calendarDev !== "")
            return Translation.tr("The list arrives in a moment.");
        if (root.feed !== null) {
            const when = Qt.formatDateTime(new Date(Number(root.feed.at ?? 0)), "dd/MM hh:mm");
            return Translation.tr("Showing the copy from %1, read-only until the phone is back.").arg(when);
        }
        if (IiLinkService.phoneConnected)
            return Translation.tr("On the phone, open ii tools → Calendar and allow calendar access.");
        return Translation.tr("Connect the phone with ii tools; its calendar shows here once it allows calendar access.");
    }

    title: Translation.tr("Phone calendar")
    symbol: "event_available"
    description: Translation.tr("Google, Samsung, Outlook and any other calendar on the phone, through ii tools: no khal or vdirsyncer needed.")

    AppSettingRow {
        symbol: CalendarService.phoneLive ? "event_available" : "event_busy"
        title: root.statusTitle
        description: root.statusDetail
    }

    AppToggleRow {
        symbol: "calendar_month"
        title: Translation.tr("Show the phone's calendar")
        description: Translation.tr("Its events join the Timetable, the widgets and the calendar panels")
        checked: root.options.enable
        onToggled: value => root.options.enable = value
    }

    AppToggleRow {
        visible: root.options.enable
        symbol: "edit_calendar"
        title: Translation.tr("Create and edit phone events here")
        description: IiLinkService.calendarDev !== "" && !IiLinkService.calendarWritable
            ? Translation.tr("The phone hasn't allowed edits: grant Edit calendar in ii tools → Calendar")
            : Translation.tr("New events can go to a phone calendar; changes reach its account like edits made on the phone")
        checked: root.options.write
        onToggled: value => root.options.write = value
    }

    AppToggleRow {
        visible: root.options.enable
        symbol: "join"
        title: Translation.tr("Hide duplicates")
        description: CalendarService.duplicatesHidden > 0
            ? Translation.tr("An event in both khal and the phone shows once (%1 hidden now)").arg(String(CalendarService.duplicatesHidden))
            : Translation.tr("An event in both khal and the phone (the same Google account, say) shows once")
        checked: root.options.dedupe
        onToggled: value => root.options.dedupe = value
    }

    AppChoiceRow {
        visible: root.options.enable && root.options.dedupe
        symbol: "rule"
        title: Translation.tr("Keep the copy from")
        currentValue: root.options.prefer
        options: [
            { "label": Translation.tr("khal"), "icon": "computer", "value": "khal" },
            { "label": Translation.tr("Phone"), "icon": "smartphone", "value": "phone" }
        ]
        onSelected: value => root.options.prefer = value
    }

    AppToggleRow {
        visible: root.options.enable
        symbol: "palette"
        title: Translation.tr("Use the phone's calendar colors")
        description: Translation.tr("Off, phone events take the shell's colors")
        checked: root.options.colors
        onToggled: value => root.options.colors = value
    }

    AppToggleRow {
        visible: root.options.enable
        symbol: "event_busy"
        title: Translation.tr("Hide declined invitations")
        checked: root.options.hideDeclined
        onToggled: value => root.options.hideDeclined = value
    }

    AppToggleRow {
        visible: root.options.enable
        symbol: "notifications"
        title: Translation.tr("Remind phone events on this PC too")
        description: Translation.tr("Off, the phone reminds them itself, and its notification reaches the PC")
        checked: root.options.notify
        onToggled: value => root.options.notify = value
    }

    Repeater {
        model: root.options.enable ? CalendarService.phoneCalendars : []

        delegate: AppToggleRow {
            required property var modelData
            symbol: modelData.readOnly ? "calendar_month" : "edit_calendar"
            title: modelData.displayName
            description: [modelData.account, root.providerLabel(modelData.provider), modelData.readOnly ? Translation.tr("read-only") : ""]
                .filter(part => String(part).length > 0).join(" · ")
            checked: modelData.shown
            onToggled: value => CalendarService.setPhoneCalendarShown(modelData.phoneId, value)
        }
    }

    AppSettingRow {
        visible: CalendarService.phoneMutationError.length > 0
        symbol: "error"
        title: Translation.tr("Last change didn't reach the phone")
        description: CalendarService.phoneMutationError
    }
}
