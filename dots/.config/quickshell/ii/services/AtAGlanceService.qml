pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.services

/*
 * At a Glance engine, modelled on Smartspacer (github.com/KieronQuinn/Smartspacer).
 *
 * Three kinds of item, each a user-ordered list in the widget's config:
 *  - Targets: pages (title, subtitle, icon, a template, a tap action). One
 *    target can produce several pages (one per event, per notification…).
 *  - Complications: small icon + short text chips. Date, Greeting and Blank
 *    targets have room for two of them; the rest spill onto extra pages after
 *    the targets, or sit next to the date when no target is left.
 *  - Requirements: conditions on a target or complication, in an "All of" and
 *    an "Any of" group, each one invertible.
 *
 * Everything the widget draws comes from `pages` / `complications`; the
 * Settings page reads the catalogues below.
 */
Singleton {
    id: root

    readonly property var options: Config.options.background.widgets.at_a_glance
    // Settings previews count as a viewer, so the page shows real content even
    // before the widget is placed.
    property int previewViewers: 0
    readonly property bool widgetActive: Config.ready && (root.previewViewers > 0 || Config.isWidgetActive("at_a_glance"))
    readonly property date now: DateTime.clock.date
    readonly property bool locked: GlobalStates.screenLocked

    // ── Catalogues ─────────────────────────────────────────────────────────────
    readonly property var targetTypes: [
        { type: "glance", name: Translation.tr("At a Glance"), icon: "auto_awesome", single: true,
          description: Translation.tr("Smart context from the shell: timers, alarms, reminders, sports, birthdays, calls, transfers and more") },
        { type: "date", name: Translation.tr("Date"), icon: "today", single: false,
          description: Translation.tr("Shows the current date, with space for two Complications") },
        { type: "greeting", name: Translation.tr("Greeting"), icon: "waving_hand", single: false,
          description: Translation.tr("Shows a short greeting, with space for two Complications") },
        { type: "calendar", name: Translation.tr("Calendar"), icon: "event", single: false,
          description: Translation.tr("Shows upcoming Calendar events") },
        { type: "music", name: Translation.tr("Music"), icon: "music_note", single: true,
          description: Translation.tr("Displays the currently playing music track") },
        { type: "notifications", name: Translation.tr("Notifications"), icon: "notifications", single: false,
          description: Translation.tr("Shows notifications from an app") },
        { type: "weather", name: Translation.tr("Weather Forecast"), icon: "partly_cloudy_day", single: true,
          description: Translation.tr("Displays the current weather and the forecast for the next hours") },
        { type: "wellbeing", name: Translation.tr("Digital Wellbeing"), icon: "hourglass_top", single: true,
          description: Translation.tr("Shows the screen time and top 3 apps") },
        { type: "nightLight", name: Translation.tr("Night Light"), icon: "nightlight", single: true,
          description: Translation.tr("Show a reminder when Night Light is enabled") },
        { type: "clock", name: Translation.tr("Clock"), icon: "schedule", single: false,
          description: Translation.tr("Shows the current time") },
        { type: "blank", name: Translation.tr("Blank Target"), icon: "check_box_outline_blank", single: false,
          description: Translation.tr("Ultra minimal, can be used to show nothing at all or only Complications") }
    ]

    readonly property var complicationTypes: [
        { type: "weather", name: Translation.tr("Weather"), icon: "partly_cloudy_day",
          description: Translation.tr("Shows the current weather") },
        { type: "date", name: Translation.tr("Date"), icon: "today",
          description: Translation.tr("Shows the current date") },
        { type: "clock", name: Translation.tr("Clock"), icon: "schedule",
          description: Translation.tr("Shows the current time") },
        { type: "alarm", name: Translation.tr("Next Alarm"), icon: "alarm",
          description: Translation.tr("Shows the next alarm set, within the next 12 hours") },
        { type: "wellbeing", name: Translation.tr("Digital Wellbeing"), icon: "hourglass_top",
          description: Translation.tr("Shows today's screen time") },
        { type: "email", name: Translation.tr("Email Unread"), icon: "mail",
          description: Translation.tr("Show the number of unread emails") },
        { type: "sms", name: Translation.tr("SMS Unread"), icon: "sms",
          description: Translation.tr("Show the number of unread SMS/RCS messages from your phone") },
        { type: "missedCalls", name: Translation.tr("Missed Calls"), icon: "phone_missed",
          description: Translation.tr("Show the number of missed calls from your phone") },
        { type: "battery", name: Translation.tr("Battery"), icon: "battery_full",
          description: Translation.tr("Shows the battery level of this device") },
        { type: "phoneBattery", name: Translation.tr("Phone Battery"), icon: "mobile_screenshot",
          description: Translation.tr("Shows the battery level of your connected phone") },
        { type: "todo", name: Translation.tr("Tasks"), icon: "task_alt",
          description: Translation.tr("Shows the number of pending tasks") },
        { type: "blank", name: Translation.tr("Blank Complication"), icon: "check_box_outline_blank",
          description: Translation.tr("Useful for minimal setups or spacers") }
    ]

    readonly property var requirementTypes: [
        { type: "time", name: Translation.tr("Time & Date"), icon: "schedule" },
        { type: "wifi", name: Translation.tr("Wi-Fi Network"), icon: "wifi" },
        { type: "bluetooth", name: Translation.tr("Bluetooth Device Connected"), icon: "bluetooth" },
        { type: "music", name: Translation.tr("Music Playing"), icon: "music_note" },
        { type: "app", name: Translation.tr("App Open"), icon: "apps" },
        { type: "focusedApp", name: Translation.tr("App In Focus"), icon: "ad_units" },
        { type: "charging", name: Translation.tr("Charging"), icon: "battery_charging_full" },
        { type: "location", name: Translation.tr("Location"), icon: "location_on" }
    ]

    // The categories of the At a Glance target, each hideable like Smartspacer's
    // "Hide default Targets" list.
    readonly property var glanceCategories: [
        { key: "timers", name: Translation.tr("Timer & Stopwatch"), icon: "timer",
          description: Translation.tr("Running countdown timers, the stopwatch and Pomodoro") },
        { key: "alarms", name: Translation.tr("Alarms"), icon: "alarm",
          description: Translation.tr("Upcoming, snoozed and ringing alarms") },
        { key: "bedtime", name: Translation.tr("Bedtime"), icon: "bedtime",
          description: Translation.tr("Wind down and bedtime reminders") },
        { key: "reminders", name: Translation.tr("Reminders"), icon: "notifications_active",
          description: Translation.tr("Reminders due within the next hour") },
        { key: "todo", name: Translation.tr("Tasks"), icon: "task_alt",
          description: Translation.tr("Your next pending task") },
        { key: "sports", name: Translation.tr("Sports"), icon: "sports_soccer",
          description: Translation.tr("Live match scores") },
        { key: "personal", name: Translation.tr("Birthdays & Dates"), icon: "cake",
          description: Translation.tr("Birthdays from your contacts and public holidays") },
        { key: "communication", name: Translation.tr("Calls"), icon: "call",
          description: Translation.tr("Ongoing and incoming phone calls") },
        { key: "email", name: Translation.tr("Email"), icon: "mail",
          description: Translation.tr("Unread emails in your inbox") },
        { key: "transfers", name: Translation.tr("File Transfers"), icon: "share",
          description: Translation.tr("LocalSend transfers in progress") },
        { key: "phone", name: Translation.tr("Phone"), icon: "smartphone",
          description: Translation.tr("Low battery on your connected phone") },
        { key: "battery", name: Translation.tr("Battery"), icon: "battery_alert",
          description: Translation.tr("Low battery on this device") },
        { key: "privacy", name: Translation.tr("Camera & Microphone"), icon: "videocam",
          description: Translation.tr("Apps using your camera, microphone or screen") }
    ]

    function typeInfo(kind, type) {
        const list = kind === "complication" ? root.complicationTypes : kind === "requirement" ? root.requirementTypes : root.targetTypes;
        return list.find(t => t.type === type) ?? { type: type, name: type, icon: "help", description: "" };
    }

    function defaultSettings(kind, type) {
        if (kind === "target") {
            switch (type) {
            case "date": return { dateFormat: "" };
            case "greeting": return { name: "", hideIfNoComplications: false, openExpandedOnClick: false };
            case "calendar": return { showAllDay: false, showLocation: true, showUnconfirmed: true, preEventMinutes: 60, postEventMinutes: -1, dismissedEvents: [] };
            case "music": return { showAlbumArt: true, showWhenPaused: false, dismissedApps: [] };
            case "notifications": return { apps: "", includePhone: true, trimNewLines: true, maxCount: 3 };
            case "weather": return { columns: 4 };
            case "nightLight": return { showWhenOff: false };
            case "clock": return { timeFormat: "" };
            case "blank": return { showComplications: true, hideIfNoComplications: false };
            case "glance": return { hidden: [], sportsWindowHours: 12 };
            }
            return {};
        }
        if (kind === "complication") {
            switch (type) {
            case "date": return { dateFormat: "" };
            case "clock": return { timeFormat: "" };
            case "weather": return { showCondition: false };
            case "alarm": return { hoursAhead: 12, includePhone: true };
            case "sms": return { apps: "Messages, Mensagens, Google Messages, Samsung Messages" };
            case "missedCalls": return { apps: "Phone, Telefone, Dialer, Google Phone" };
            case "battery": return { onlyWhenLow: false };
            }
            return {};
        }
        switch (type) {
        case "time": return { start: "09:00", end: "17:00", days: [true, true, true, true, true, true, true] };
        case "wifi": return { ssid: "" };
        case "bluetooth": return { device: "" };
        case "app": return { appClass: "" };
        case "focusedApp": return { appClass: "" };
        case "location": return { city: "" };
        }
        return {};
    }

    function newId(prefix) {
        return prefix + "-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e6).toString(36);
    }

    function newItem(kind, type) {
        return {
            id: root.newId(kind === "complication" ? "c" : "t"),
            type: type,
            enabled: true,
            showOnDesktop: true,
            showOnLock: true,
            disableSubComplication: false,
            requireAll: [],
            requireAny: [],
            settings: root.defaultSettings(kind, type)
        };
    }

    function newRequirement(type) {
        return Object.assign({ type: type, invert: false }, root.defaultSettings("requirement", type));
    }

    // Config lists of objects read back as sequence wrappers; a JSON round trip
    // gives plain, writable JS objects.
    function plain(value) {
        if (value === undefined || value === null)
            return value;
        return JSON.parse(JSON.stringify(value));
    }

    function listOf(value) {
        if (!value || typeof value.length !== "number")
            return [];
        return root.plain(Array.from(value));
    }

    function settingOf(item, key, fallback) {
        const s = item?.settings;
        if (!s || s[key] === undefined || s[key] === null)
            return fallback;
        return s[key];
    }

    function splitNames(text) {
        return String(text ?? "").split(",").map(s => s.trim().toLowerCase()).filter(s => s.length > 0);
    }

    // ── Formatting helpers ─────────────────────────────────────────────────────
    readonly property bool use12h: {
        const fmt = String(Config.options?.time?.format ?? "hh:mm");
        return fmt.includes("ap") || fmt.includes("AP");
    }

    function formatTime(date) {
        return Qt.locale().toString(date, Config.options?.time?.format ?? "hh:mm");
    }

    function formatDate(date, custom) {
        const fmt = String(custom ?? "").trim();
        // Smartspacer's automatic format is the "EEEMMMd" skeleton: "Thu, Nov 20".
        return Qt.locale().toString(date, fmt.length > 0 ? fmt : "ddd, MMM d");
    }

    function formatDuration(seconds) {
        const total = Math.max(0, Math.round(seconds / 60));
        const h = Math.floor(total / 60);
        const m = total % 60;
        if (h > 0 && m > 0)
            return Translation.tr("%1h %2m").arg(h).arg(m);
        if (h > 0)
            return Translation.tr("%1h").arg(h);
        return Translation.tr("%1m").arg(m);
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function ellipsis(text, max) {
        const s = String(text ?? "");
        return s.length > max ? s.substring(0, max - 1) + "…" : s;
    }

    function weatherIconUrl(code) {
        const hour = (root.now || new Date()).getHours();
        return WeatherIcons.getWeatherIcon(code, hour < 6 || hour >= 19);
    }

    // ── Live sources the targets read ──────────────────────────────────────────
    // Seconds only matter while a timer or stopwatch is on a page.
    property int secondTick: 0
    readonly property bool needsSeconds: root.widgetActive && (TimerService.stopwatchRunning
        || Array.from(TimerService.countdowns ?? []).some(c => !c.paused)
        || TimerService.pomodoroRunning)
    Timer {
        interval: 1000
        repeat: true
        running: root.needsSeconds
        onTriggered: root.secondTick++
    }

    // Screen time is only counted while someone watches it.
    readonly property bool wantsScreenTime: root.widgetActive && (root.hasEnabled("target", "wellbeing") || root.hasEnabled("complication", "wellbeing"))
    onWantsScreenTimeChanged: ScreenTimeLimits.watch(root.wantsScreenTime)
    Component.onCompleted: if (root.wantsScreenTime) ScreenTimeLimits.watch(true)

    function hasEnabled(kind, type) {
        const list = root.listOf(kind === "complication" ? root.options?.complications : root.options?.targets);
        return list.some(i => i.type === type && i.enabled !== false);
    }

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool mediaPlaying: root.player !== null && root.player.playbackState === MprisPlaybackState.Playing

    // Kept for the Timetable's day briefing card.
    readonly property var todayEvents: {
        if (!CalendarService.eventsAvailable || !CalendarService.events)
            return [];
        const today = root.now || new Date();
        return CalendarService.events.filter(e => root.sameDay(new Date(e.startDate), today))
            .sort((a, b) => new Date(a.startDate) - new Date(b.startDate));
    }
    readonly property var nextEvent: {
        const t = (root.now || new Date()).getTime();
        return root.todayEvents.find(e => new Date(e.endDate).getTime() > t) ?? null;
    }

    // ── Requirements ───────────────────────────────────────────────────────────
    function parseHm(text) {
        const parts = String(text ?? "0:0").split(":");
        return (parseInt(parts[0]) || 0) * 60 + (parseInt(parts[1]) || 0);
    }

    function requirementMet(req) {
        let met = false;
        const now = root.now || new Date();
        switch (req?.type) {
        case "time": {
            const days = Array.from(req.days ?? []);
            const dayOk = days.length < 7 || days[now.getDay()] !== false;
            const m = now.getHours() * 60 + now.getMinutes();
            const s = root.parseHm(req.start);
            const e = root.parseHm(req.end);
            const inRange = s <= e ? (m >= s && m < e) : (m >= s || m < e);
            met = dayOk && inRange;
            break;
        }
        case "wifi": {
            const want = String(req.ssid ?? "").trim().toLowerCase();
            met = NetworkState.wifiConnected && (want === "" || String(NetworkState.wifiNetworkName).toLowerCase() === want);
            break;
        }
        case "bluetooth": {
            const want = String(req.device ?? "").trim().toLowerCase();
            met = Array.from(BluetoothStatus.connectedDevices ?? []).some(d => {
                const name = String(d?.name ?? d?.deviceName ?? "").toLowerCase();
                return want === "" || name === want || name.includes(want);
            });
            break;
        }
        case "music":
            met = root.mediaPlaying;
            break;
        case "app": {
            const want = String(req.appClass ?? "").trim().toLowerCase();
            met = want !== "" && Array.from(HyprlandData.windowList ?? []).some(w =>
                String(w?.class ?? "").toLowerCase().includes(want) || String(w?.initialClass ?? "").toLowerCase().includes(want));
            break;
        }
        case "focusedApp": {
            const want = String(req.appClass ?? "").trim().toLowerCase();
            const active = String(ToplevelManager.activeToplevel?.appId ?? "").toLowerCase();
            met = want !== "" && active.includes(want);
            break;
        }
        case "charging":
            met = Battery.available ? Battery.isPluggedIn : true;
            break;
        case "location": {
            const want = String(req.city ?? "").trim().toLowerCase();
            met = want !== "" && String(Weather.data?.city ?? "").toLowerCase().includes(want);
            break;
        }
        default:
            met = true;
        }
        return req?.invert === true ? !met : met;
    }

    function requirementsMet(item) {
        const all = root.listOf(item?.requireAll);
        const any = root.listOf(item?.requireAny);
        if (!all.every(r => root.requirementMet(r)))
            return false;
        return any.length === 0 || any.some(r => root.requirementMet(r));
    }

    function requirementSummary(req) {
        const inv = req?.invert === true;
        let text = "";
        switch (req?.type) {
        case "time": {
            const names = [Translation.tr("Sun"), Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"), Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat")];
            const days = Array.from(req.days ?? []);
            const on = names.filter((_, i) => days[i] !== false);
            text = on.length === 7
                ? Translation.tr("Only show between %1 and %2 every day").arg(req.start).arg(req.end)
                : Translation.tr("Only show between %1 and %2 on %3").arg(req.start).arg(req.end).arg(on.join(", "));
            break;
        }
        case "wifi":
            text = String(req.ssid ?? "") === "" ? Translation.tr("Only show when connected to Wi-Fi")
                : Translation.tr("Only show when connected to %1").arg(req.ssid);
            break;
        case "bluetooth":
            text = String(req.device ?? "") === "" ? Translation.tr("Only show when a Bluetooth device is connected")
                : Translation.tr("Only show when connected to a Bluetooth device named %1").arg(req.device);
            break;
        case "music":
            text = Translation.tr("Only show when music is playing");
            break;
        case "app":
            text = Translation.tr("Only show when %1 is open").arg(req.appClass || "…");
            break;
        case "focusedApp":
            text = Translation.tr("Only show when %1 is in focus").arg(req.appClass || "…");
            break;
        case "charging":
            text = Translation.tr("Only show when charging");
            break;
        case "location":
            text = Translation.tr("Only show when at or near %1").arg(req.city || "…");
            break;
        }
        return inv ? Translation.tr("Inverted: %1").arg(text) : text;
    }

    function itemVisible(item) {
        if (!item || item.enabled === false)
            return false;
        if (root.locked ? item.showOnLock === false : item.showOnDesktop === false)
            return false;
        return root.requirementsMet(item);
    }

    // ── Actions ────────────────────────────────────────────────────────────────
    function runAction(action) {
        if (!action)
            return;
        switch (action.kind) {
        case "calendar":
            GlobalStates.openTimetableAt(root.now || new Date());
            break;
        case "cheatsheet":
            GlobalStates.cheatsheetOpen = true;
            break;
        case "clockApp":
            GlobalStates.openClockApp(action.tab ?? "");
            break;
        case "usageApp":
            GlobalStates.openUsageApp(action.tab ?? "");
            break;
        case "mediaRaise": {
            const p = root.player;
            if (p && p.canRaise)
                p.raise();
            else if (p)
                p.togglePlaying();
            break;
        }
        case "mediaToggle":
            if (root.player)
                root.player.togglePlaying();
            break;
        case "notification":
            if (action.id !== undefined)
                Notifications.attemptInvokeAction(action.id, "default");
            break;
        case "nightLight":
            Hyprsunset.toggleTemperature();
            break;
        case "weather":
            Weather.getData(true);
            break;
        case "pomodoro":
            TimerService.togglePomodoro();
            break;
        case "countdown":
            TimerService.toggleCountdown(action.id);
            break;
        case "stopwatch":
            TimerService.toggleStopwatch();
            break;
        case "snoozeAlarm":
            AlarmService.snooze();
            break;
        case "stopAlarm":
            AlarmService.stopRinging();
            break;
        case "answerCall":
            PhoneCallService.answer();
            break;
        }
    }

    // Dismissal is stored on the target, like Smartspacer's dismissed
    // events/apps lists, so it survives restarts and can be cleared in Settings.
    function dismiss(page) {
        const d = page?.dismiss;
        if (!d)
            return;
        if (d.kind === "notification") {
            Notifications.discardNotification(d.id);
            return;
        }
        const targets = root.listOf(root.options.targets);
        const item = targets.find(t => t.id === page.itemId);
        if (!item)
            return;
        item.settings = item.settings ?? {};
        const key = d.kind === "event" ? "dismissedEvents" : d.kind === "app" ? "dismissedApps" : "dismissed";
        const list = Array.from(item.settings[key] ?? []);
        if (!list.includes(d.id))
            list.push(d.id);
        // Calendar ids pile up; keep the newest 200.
        item.settings[key] = list.slice(-200);
        root.options.targets = targets;
    }

    // ── Target providers ───────────────────────────────────────────────────────
    function page(item, extra) {
        return Object.assign({
            key: item.id,
            itemId: item.id,
            type: item.type,
            template: "basic",
            title: "",
            subtitle: "",
            icon: "",
            iconImage: "",
            image: "",
            items: [],
            columns: [],
            header: "",
            home: null,
            away: null,
            buttonIcon: "",
            buttonText: "",
            buttonAction: null,
            sensitive: false,
            action: null,
            dismiss: null,
            takesComplications: false,
            hideIfNoComplications: false,
            subComplication: null,
            expandedOptions: false,
            openExpanded: false,
            complications: []
        }, extra);
    }

    function datePages(item) {
        return [root.page(item, {
            template: "date",
            title: root.formatDate(root.now || new Date(), root.settingOf(item, "dateFormat", "")),
            takesComplications: true,
            // Smartspacer: "In the event there's no targets or complications, a date will be shown anyway".
            hideIfNoComplications: true,
            action: { kind: "calendar" }
        })];
    }

    function greetingText(name) {
        const h = (root.now || new Date()).getHours();
        const n = String(name ?? "").trim();
        if (h >= 3 && h < 12)
            return n ? Translation.tr("Good morning, %1").arg(n) : Translation.tr("Good morning");
        if (h >= 12 && h < 18)
            return n ? Translation.tr("Good afternoon, %1").arg(n) : Translation.tr("Good afternoon");
        if (h >= 18 && h < 22)
            return n ? Translation.tr("Good evening, %1").arg(n) : Translation.tr("Good evening");
        return n ? Translation.tr("Good night, %1").arg(n) : Translation.tr("Good night");
    }

    function greetingPages(item) {
        return [root.page(item, {
            template: "date",
            title: root.greetingText(root.settingOf(item, "name", "")),
            takesComplications: true,
            hideIfNoComplications: root.settingOf(item, "hideIfNoComplications", false),
            openExpanded: root.settingOf(item, "openExpandedOnClick", false)
        })];
    }

    function blankPages(item) {
        return [root.page(item, {
            template: "date",
            title: "",
            takesComplications: root.settingOf(item, "showComplications", true),
            hideIfNoComplications: root.settingOf(item, "hideIfNoComplications", false)
        })];
    }

    function clockPages(item) {
        const fmt = String(root.settingOf(item, "timeFormat", "")).trim();
        return [root.page(item, {
            template: "date",
            title: fmt ? Qt.locale().toString(root.now || new Date(), fmt) : root.formatTime(root.now || new Date()),
            takesComplications: true
        })];
    }

    function eventKey(e) {
        return String(e.uid || e.id || "") + "@" + new Date(e.startDate).getTime();
    }

    function calendarSubtitle(e, now) {
        const start = new Date(e.startDate);
        const end = new Date(e.endDate);
        if (e.allDay === true)
            return Translation.tr("All Day");
        const s = root.formatTime(start);
        const f = root.formatTime(end);
        const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
        const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
        const dateOf = d => Qt.locale().toString(d, "ddd, MMM d");
        if (root.sameDay(start, now) && root.sameDay(end, now))
            return `${s} – ${f}`;
        if (root.sameDay(start, yesterday))
            return Translation.tr("Yesterday, %1 – %2").arg(s).arg(f);
        if (root.sameDay(end, tomorrow))
            return Translation.tr("%1 – Tomorrow, %2").arg(s).arg(f);
        if (root.sameDay(start, now))
            return Translation.tr("%1 – %2, %3").arg(s).arg(dateOf(end)).arg(f);
        if (root.sameDay(end, now))
            return Translation.tr("%1, %2 – %3").arg(dateOf(start)).arg(s).arg(f);
        return `${s} – ${f}`;
    }

    function calendarPages(item) {
        if (!CalendarService.eventsAvailable || !CalendarService.events)
            return [];
        const now = root.now || new Date();
        const t = now.getTime();
        const pre = Math.max(1, root.settingOf(item, "preEventMinutes", 60)) * 60000;
        const post = root.settingOf(item, "postEventMinutes", -1);
        const showAllDay = root.settingOf(item, "showAllDay", false);
        const showLocation = root.settingOf(item, "showLocation", true);
        const showUnconfirmed = root.settingOf(item, "showUnconfirmed", true);
        const dismissed = Array.from(root.settingOf(item, "dismissedEvents", []));
        const out = [];
        for (const e of CalendarService.events) {
            const start = new Date(e.startDate).getTime();
            const end = new Date(e.endDate).getTime();
            if (e.allDay === true) {
                if (!showAllDay || !(start <= t && end > t))
                    continue;
            } else {
                const until = post < 0 ? end : Math.min(end, start + post * 60000);
                if (!(t >= start - pre && t < until))
                    continue;
            }
            if (!showUnconfirmed && ["tentative", "needs-action", "declined"].includes(String(e.status ?? e.partstat ?? "").toLowerCase()))
                continue;
            const key = root.eventKey(e);
            if (dismissed.includes(key))
                continue;
            let title = String(e.content || "").trim() || Translation.tr("Untitled Event");
            const minutes = start >= t ? Math.ceil((start - t) / 60000) : 0;
            if (e.allDay !== true && minutes >= 1 && minutes <= 60)
                title = Translation.tr("%1 in %2m").arg(root.ellipsis(title, 20)).arg(minutes);
            const location = String(e.location ?? "").trim();
            out.push(root.page(item, {
                key: item.id + ":" + key,
                title: title,
                subtitle: root.calendarSubtitle(e, now),
                icon: "event",
                sensitive: true,
                action: { kind: "calendar" },
                dismiss: { kind: "event", id: key },
                subComplication: showLocation && location !== "" && item.disableSubComplication !== true
                    ? { icon: "location_on", text: location } : null,
                startsAt: start
            }));
        }
        return out.sort((a, b) => a.startsAt - b.startsAt);
    }

    function musicPages(item) {
        const p = root.player;
        if (!p || String(p.trackTitle || "") === "")
            return [];
        if (!root.mediaPlaying && !root.settingOf(item, "showWhenPaused", false))
            return [];
        const appKey = String(p.desktopEntry || p.identity || "").toLowerCase();
        if (Array.from(root.settingOf(item, "dismissedApps", [])).includes(appKey))
            return [];
        const art = root.settingOf(item, "showAlbumArt", true) ? String(MprisController.artUrl || "") : "";
        const artist = String(p.trackArtist || "").trim();
        return [root.page(item, {
            template: art !== "" ? "image" : "basic",
            title: String(p.trackTitle),
            subtitle: artist !== "" ? artist : String(p.identity || Translation.tr("Music")),
            icon: root.mediaPlaying ? "music_note" : "pause",
            image: art,
            action: { kind: "mediaRaise" },
            buttonAction: { kind: "mediaToggle" },
            dismiss: { kind: "app", id: appKey }
        })];
    }

    function notificationPages(item) {
        const apps = root.splitNames(root.settingOf(item, "apps", ""));
        const includePhone = root.settingOf(item, "includePhone", true);
        const trim = root.settingOf(item, "trimNewLines", true);
        const max = Math.max(1, root.settingOf(item, "maxCount", 3));
        const list = Array.from(Notifications.list ?? []).filter(n => {
            if (!n || (n.phone && !includePhone))
                return false;
            if (String(n.summary || n.body || "") === "")
                return false;
            return apps.length === 0 || apps.includes(String(n.appName ?? "").toLowerCase());
        }).sort((a, b) => b.time - a.time).slice(0, max);
        return list.map(n => {
            let body = String(n.body ?? "");
            body = body.replace(/<[^>]*>/g, "");
            if (trim)
                body = body.replace(/\s*\n+\s*/g, " ");
            const icon = String(n.image || n.appIcon || "");
            return root.page(item, {
                key: item.id + ":" + n.notificationId,
                title: String(n.summary || n.appName),
                subtitle: body !== "" ? body : String(n.appName ?? ""),
                icon: "notifications",
                iconImage: icon.startsWith("/") || icon.includes("://") ? icon : (icon !== "" ? Quickshell.iconPath(icon, true) : ""),
                sensitive: true,
                action: { kind: "notification", id: n.notificationId },
                dismiss: { kind: "notification", id: n.notificationId }
            });
        });
    }

    function weatherPages(item) {
        if (!Weather.data || String(Weather.data.temp ?? "") === "")
            return [];
        const useF = String(Weather.data.temp).includes("F");
        const hourNow = (root.now || new Date()).getHours();
        const columns = [];
        const max = Math.max(2, Math.min(4, root.settingOf(item, "columns", 4)));
        for (const h of Array.from(Weather.hourlyData ?? [])) {
            if (columns.length >= max)
                break;
            const hour = Math.floor((parseInt(h.time) || 0) / 100);
            if (columns.length === 0 && hour <= hourNow)
                continue;
            const d = new Date();
            d.setHours(hour, 0, 0, 0);
            columns.push({
                upper: root.use12h ? Qt.locale().toString(d, "h ap") : Qt.locale().toString(d, "HH:mm"),
                icon: WeatherIcons.getWeatherIcon(h.code, hour < 6 || hour >= 19),
                lower: (useF ? h.tempF : h.tempC) + "°"
            });
        }
        return [root.page(item, {
            template: columns.length > 0 ? "carousel" : "basic",
            title: String(Weather.data.temp) + (Weather.data.wDesc ? " · " + Weather.data.wDesc : ""),
            subtitle: String(Weather.data.city ?? ""),
            iconImage: root.weatherIconUrl(Weather.data.wCode),
            columns: columns,
            action: { kind: "weather" },
            expandedOptions: true
        })];
    }

    function wellbeingPages(item) {
        const apps = ScreenTimeLimits.todayApps().slice(0, 3);
        const total = ScreenTimeLimits.totalUsed();
        if (total < 60)
            return [];
        const nameOf = key => {
            const entry = DesktopEntries.heuristicLookup(key);
            return entry?.name ?? key;
        };
        return [root.page(item, {
            template: apps.length > 0 ? "list" : "basic",
            title: Translation.tr("Screen time: %1").arg(root.formatDuration(total)),
            subtitle: Translation.tr("Digital Wellbeing"),
            icon: "hourglass_top",
            items: apps.map(a => root.ellipsis(nameOf(a.key), 14) + "  " + root.formatDuration(a.seconds)),
            action: { kind: "usageApp", tab: "apps" },
            expandedOptions: true
        })];
    }

    function nightLightPages(item) {
        const on = Hyprsunset.temperatureActive;
        if (!on && !root.settingOf(item, "showWhenOff", false))
            return [];
        return [root.page(item, {
            title: on ? Translation.tr("Night Light on") : Translation.tr("Night Light off"),
            subtitle: on ? Translation.tr("Tap to turn off") : Translation.tr("Tap to turn on"),
            icon: on ? "nightlight" : "light_mode",
            action: { kind: "nightLight" }
        })];
    }

    // The At a Glance target: what Google's At a Glance would push on a phone,
    // sourced from the shell's own services.
    function glancePages(item) {
        const hidden = Array.from(root.settingOf(item, "hidden", []));
        const on = key => !hidden.includes(key);
        const now = root.now || new Date();
        const out = [];
        const add = (key, extra) => out.push(root.page(item, Object.assign({ key: item.id + ":" + key }, extra)));

        if (on("communication") && PhoneCallService.active) {
            const ringing = PhoneCallService.callState === "ringing";
            add("call", {
                title: PhoneCallService.displayName || PhoneCallService.number || Translation.tr("Phone call"),
                subtitle: ringing ? Translation.tr("Incoming call") : Translation.tr("Ongoing call"),
                icon: ringing ? "ring_volume" : "call",
                template: ringing && PhoneCallService.controllable ? "button" : "basic",
                buttonIcon: "call",
                buttonText: Translation.tr("Answer"),
                buttonAction: { kind: "answerCall" },
                sensitive: true
            });
        }

        if (on("alarms")) {
            const ringing = AlarmService.ringingAlarm;
            if (ringing) {
                add("alarm-ringing", {
                    template: "button",
                    title: String(ringing.label || Translation.tr("Alarm")),
                    subtitle: root.formatTime(now),
                    icon: "alarm",
                    buttonIcon: "snooze",
                    buttonText: Translation.tr("Snooze"),
                    buttonAction: { kind: "snoozeAlarm" },
                    action: { kind: "stopAlarm" }
                });
            } else if (AlarmService.upcomingAlarm) {
                const up = AlarmService.upcomingAlarm;
                add("alarm", {
                    title: Translation.tr("Alarm at %1").arg(root.formatTime(up.at)),
                    subtitle: String(up.alarm?.label || AlarmService.untilText(up.alarm, now)),
                    icon: "alarm",
                    action: { kind: "clockApp", tab: "alarms" }
                });
            }
        }

        if (on("timers")) {
            void root.secondTick;
            for (const c of Array.from(TimerService.countdowns ?? [])) {
                const left = TimerService.countdownSecondsLeft(c);
                if (left <= 0 && !c.paused)
                    continue;
                add("countdown-" + c.id, {
                    template: "button",
                    title: TimerService.formatCountdownDuration(left),
                    subtitle: String(c.label || Translation.tr("Timer")),
                    icon: "timer",
                    buttonIcon: c.paused ? "play_arrow" : "pause",
                    buttonText: c.paused ? Translation.tr("Resume") : Translation.tr("Pause"),
                    buttonAction: { kind: "countdown", id: c.id },
                    action: { kind: "clockApp", tab: "timer" }
                });
            }
            if (TimerService.pomodoroRunning) {
                add("pomodoro", {
                    template: "button",
                    title: TimerService.formatCountdownDuration(TimerService.pomodoroSecondsLeft),
                    subtitle: TimerService.pomodoroLongBreak ? Translation.tr("Long break")
                        : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus"),
                    icon: "timer",
                    buttonIcon: "pause",
                    buttonText: Translation.tr("Pause"),
                    buttonAction: { kind: "pomodoro" },
                    action: { kind: "clockApp", tab: "timer" }
                });
            }
            if (TimerService.stopwatchRunning) {
                const secs = Math.floor(TimerService.stopwatchTime / 100);
                add("stopwatch", {
                    template: "button",
                    title: TimerService.formatCountdownDuration(secs),
                    subtitle: Translation.tr("Stopwatch"),
                    icon: "timer",
                    buttonIcon: "pause",
                    buttonText: Translation.tr("Pause"),
                    buttonAction: { kind: "stopwatch" },
                    action: { kind: "clockApp", tab: "timer" }
                });
            }
        }

        if (on("bedtime") && BedtimeService.enabled && BedtimeService.phase !== "none") {
            const target = BedtimeService.tonightTarget;
            add("bedtime", {
                title: BedtimeService.phase === "bedtime" ? Translation.tr("It's bedtime") : Translation.tr("Time to wind down"),
                subtitle: target ? Translation.tr("Bedtime at %1").arg(root.formatTime(target)) : "",
                icon: "bedtime"
            });
        }

        if (on("reminders") && RemindersService.upcoming) {
            const r = RemindersService.upcoming;
            add("reminder", {
                title: String(r.reminder?.title || Translation.tr("Reminder")),
                subtitle: Translation.tr("Today %1").arg(root.formatTime(new Date(r.at))),
                icon: "notifications_active",
                sensitive: true
            });
        }

        if (on("sports") && SportsService.enabled) {
            const game = SportsService.currentGame;
            const windowMs = Math.max(0, root.settingOf(item, "sportsWindowHours", 12)) * 3600000;
            const startMs = game ? new Date(game.startDate || game.date || 0).getTime() : 0;
            const soon = game && game.state === "pre" && startMs > 0 && startMs - now.getTime() <= windowMs;
            if (game && (game.state === "in" || soon)) {
                add("sports", {
                    template: "headToHead",
                    title: `${game.home?.name ?? ""} vs ${game.away?.name ?? ""}`,
                    subtitle: (game.state === "in" ? Translation.tr("Live") + " · " : "") + String(game.league ?? ""),
                    header: String(game.status ?? ""),
                    icon: "sports_soccer",
                    home: { name: String(game.home?.abbreviation || game.home?.name || ""), score: String(game.home?.score ?? ""), logo: String(game.home?.logo ?? "") },
                    away: { name: String(game.away?.abbreviation || game.away?.name || ""), score: String(game.away?.score ?? ""), logo: String(game.away?.logo ?? "") }
                });
            }
        }

        if (on("personal")) {
            const birthdays = BirthdaysService.birthdaysForDate(now);
            if (birthdays.length > 0) {
                add("birthday", {
                    title: String(birthdays[0].content),
                    subtitle: birthdays.length > 1 ? Translation.tr("+%1 more birthdays today").arg(birthdays.length - 1) : Translation.tr("Birthday today"),
                    icon: "cake",
                    action: { kind: "calendar" }
                });
            }
            const holiday = Holidays.enabled ? Holidays.holidayNameForDate(now) : "";
            if (holiday !== "") {
                add("holiday", {
                    title: holiday,
                    subtitle: Translation.tr("Holiday"),
                    icon: "celebration",
                    action: { kind: "calendar" }
                });
            }
        }

        if (on("todo") && Todo.list) {
            const pending = Array.from(Todo.list).filter(t => !(t.done || t.status === 2));
            if (pending.length > 0) {
                const top = pending[0];
                add("todo", {
                    template: pending.length > 1 ? "list" : "basic",
                    title: String(top.content || top.title || Translation.tr("Task")),
                    subtitle: pending.length === 1 ? Translation.tr("1 task") : Translation.tr("%1 tasks").arg(pending.length),
                    icon: "task_alt",
                    items: pending.slice(1, 4).map(t => root.ellipsis(String(t.content || t.title || ""), 22)),
                    action: { kind: "cheatsheet" },
                    sensitive: true,
                    expandedOptions: pending.length > 1
                });
            }
        }

        if (on("email") && EmailService.authenticated && (EmailService.inboxUnreadCount ?? 0) > 0) {
            const n = EmailService.inboxUnreadCount;
            add("email", {
                title: n === 1 ? Translation.tr("1 unread email") : Translation.tr("%1 unread emails").arg(n),
                subtitle: String(EmailService.userEmail || Translation.tr("Inbox")),
                icon: "mail",
                action: { kind: "cheatsheet" },
                sensitive: true
            });
        }

        if (on("transfers") && LocalSend.available && (LocalSend.currentTransfer !== null || LocalSend.sending)) {
            add("localsend", {
                title: LocalSend.sending ? Translation.tr("Sending file…") : Translation.tr("Receiving file…"),
                subtitle: Translation.tr("LocalSend"),
                icon: "share"
            });
        }

        if (on("phone") && KdeConnectService.available && KdeConnectService.activeDevice) {
            const dev = KdeConnectService.activeDevice;
            const charge = dev.batteryCharge ?? -1;
            const reachable = (dev.isReachable ?? dev.reachable) ?? false;
            if (reachable && charge >= 0 && charge < 20 && !(dev.batteryCharging ?? dev.isCharging ?? false)) {
                add("phone", {
                    title: Translation.tr("%1 battery low").arg(KdeConnectService.activeDeviceDisplayName),
                    subtitle: charge + "%",
                    icon: "battery_alert"
                });
            }
        }

        if (on("battery") && Battery.available && Battery.isLowAndUnplugged) {
            add("battery", {
                title: Translation.tr("Battery low"),
                subtitle: Translation.tr("%1% · Plug in your charger").arg(Battery.percent),
                icon: "battery_alert"
            });
        }

        if (on("privacy") && Privacy.active) {
            add("privacy", {
                title: Privacy.summaryTitle(),
                subtitle: Privacy.activeItems.map(i => String(i.app ?? i.name ?? "")).filter(s => s !== "").join(", "),
                icon: Privacy.iconFor(Privacy.activeKinds[0])
            });
        }
        return out;
    }

    function targetPages(item) {
        switch (item.type) {
        case "date": return root.datePages(item);
        case "greeting": return root.greetingPages(item);
        case "blank": return root.blankPages(item);
        case "clock": return root.clockPages(item);
        case "calendar": return root.calendarPages(item);
        case "music": return root.musicPages(item);
        case "notifications": return root.notificationPages(item);
        case "weather": return root.weatherPages(item);
        case "wellbeing": return root.wellbeingPages(item);
        case "nightLight": return root.nightLightPages(item);
        case "glance": return root.glancePages(item);
        }
        return [];
    }

    // ── Complication providers ─────────────────────────────────────────────────
    function phoneNotificationCount(apps, match) {
        const names = root.splitNames(apps);
        return Array.from(Notifications.list ?? []).filter(n => n && n.phone
            && names.includes(String(n.appName ?? "").toLowerCase())
            && (!match || match(n))).length;
    }

    function complicationOf(item) {
        const base = { key: item.id, itemId: item.id, type: item.type, icon: "", iconImage: "", text: "", action: null, isWeather: false };
        const now = root.now || new Date();
        switch (item.type) {
        case "weather": {
            if (!Weather.data || String(Weather.data.temp ?? "") === "")
                return null;
            const cond = root.settingOf(item, "showCondition", false) && Weather.data.wDesc ? " " + Weather.data.wDesc : "";
            return Object.assign(base, { iconImage: root.weatherIconUrl(Weather.data.wCode), text: String(Weather.data.temp) + cond, action: { kind: "weather" }, isWeather: true });
        }
        case "date":
            return Object.assign(base, { icon: "today", text: root.formatDate(now, root.settingOf(item, "dateFormat", "")), action: { kind: "calendar" } });
        case "clock": {
            const fmt = String(root.settingOf(item, "timeFormat", "")).trim();
            return Object.assign(base, { icon: "schedule", text: fmt ? Qt.locale().toString(now, fmt) : root.formatTime(now) });
        }
        case "alarm": {
            const limit = Math.max(1, root.settingOf(item, "hoursAhead", 12)) * 3600000;
            let at = null;
            const next = AlarmService.nextAlarm(now);
            if (next)
                at = next.at;
            if (root.settingOf(item, "includePhone", true) && PhoneAlarmService.enabled && PhoneAlarmService.nextAt
                && (!at || PhoneAlarmService.nextAt.getTime() < at.getTime()))
                at = PhoneAlarmService.nextAt;
            if (!at || at.getTime() - now.getTime() > limit || at.getTime() < now.getTime())
                return null;
            return Object.assign(base, { icon: "alarm", text: root.formatTime(at), action: { kind: "clockApp", tab: "alarms" } });
        }
        case "wellbeing": {
            const total = ScreenTimeLimits.totalUsed();
            if (total < 60)
                return null;
            return Object.assign(base, { icon: "hourglass_top", text: root.formatDuration(total) });
        }
        case "email": {
            const n = EmailService.authenticated ? (EmailService.inboxUnreadCount ?? 0) : 0;
            return n > 0 ? Object.assign(base, { icon: "mail", text: String(n), action: { kind: "cheatsheet" } }) : null;
        }
        case "sms": {
            const n = root.phoneNotificationCount(root.settingOf(item, "apps", ""));
            return n > 0 ? Object.assign(base, { icon: "sms", text: String(n) }) : null;
        }
        case "missedCalls": {
            const n = root.phoneNotificationCount(root.settingOf(item, "apps", ""), n => /missed|perdida|perdidas/i.test(String(n.summary) + " " + String(n.body)));
            return n > 0 ? Object.assign(base, { icon: "phone_missed", text: String(n) }) : null;
        }
        case "battery": {
            if (!Battery.available)
                return null;
            if (root.settingOf(item, "onlyWhenLow", false) && !Battery.isLow)
                return null;
            const icon = Battery.isPluggedIn ? "battery_charging_full" : Battery.isLow ? "battery_alert" : "battery_full";
            return Object.assign(base, { icon: icon, text: Battery.percent + "%" });
        }
        case "phoneBattery": {
            const dev = KdeConnectService.available ? KdeConnectService.activeDevice : null;
            const charge = dev ? (dev.batteryCharge ?? -1) : -1;
            if (charge < 0 || !((dev.isReachable ?? dev.reachable) ?? false))
                return null;
            return Object.assign(base, { icon: "mobile_screenshot", text: charge + "%" });
        }
        case "todo": {
            const n = Todo.list ? Array.from(Todo.list).filter(t => !(t.done || t.status === 2)).length : 0;
            return n > 0 ? Object.assign(base, { icon: "task_alt", text: String(n), action: { kind: "cheatsheet" } }) : null;
        }
        case "blank":
            return Object.assign(base, { text: "" });
        }
        return null;
    }

    // ── Assembly ───────────────────────────────────────────────────────────────
    readonly property var complications: {
        if (!root.widgetActive)
            return [];
        return root.listOf(root.options?.complications)
            .filter(i => root.itemVisible(i))
            .map(i => root.complicationOf(i))
            .filter(c => c !== null);
    }

    readonly property string hideSensitive: root.options?.hideSensitive ?? "none"
    readonly property string complicationOnDate: root.options?.complicationOnDate ?? "always"

    readonly property var pages: {
        if (!root.widgetActive)
            return [];
        const items = root.listOf(root.options?.targets).filter(i => root.itemVisible(i));
        let out = [];
        for (const item of items) {
            for (const p of root.targetPages(item)) {
                if (root.locked && p.sensitive) {
                    if (root.hideSensitive === "target")
                        continue;
                    if (root.hideSensitive === "contents") {
                        p.title = Translation.tr("Contents hidden");
                        p.subtitle = "";
                        p.items = [];
                        p.image = "";
                        p.subComplication = null;
                    }
                }
                out.push(p);
            }
        }

        // Hand complications out the way Smartspacer does: two per page that has
        // room for them, the rest on their own pages after the targets.
        const queue = root.complications.slice();
        for (const p of out) {
            if (!p.takesComplications || queue.length === 0)
                continue;
            const onDate = p.type === "date" ? root.complicationOnDate : "always";
            if (onDate === "never")
                continue;
            const taken = [];
            for (let i = 0; i < queue.length && taken.length < 2;) {
                if (onDate === "weather" && !queue[i].isWeather) {
                    i++;
                    continue;
                }
                taken.push(queue.splice(i, 1)[0]);
            }
            p.complications = taken;
        }

        const hasOthers = out.some(p => !p.hideIfNoComplications || p.complications.length > 0);
        out = out.filter(p => !p.hideIfNoComplications || p.complications.length > 0 || (!hasOthers && p.type === "date"));

        for (let i = 0; i < queue.length; i += 2) {
            const chunk = queue.slice(i, i + 2);
            if (out.length === 0) {
                out.push(root.page({ id: "__date", type: "date" }, {
                    template: "date",
                    title: root.formatDate(root.now || new Date(), ""),
                    takesComplications: true,
                    complications: chunk,
                    action: { kind: "calendar" }
                }));
            } else {
                out.push(root.page({ id: "__complications-" + i, type: "complications" }, {
                    template: "complications",
                    complications: chunk
                }));
            }
        }

        // Nothing to show at all: the date, like an empty Smartspace.
        if (out.length === 0)
            out.push(root.fallbackDatePage());
        return out;
    }

    function fallbackDatePage() {
        return root.page({ id: "__date", type: "date" }, {
            template: "date",
            title: root.formatDate(root.now || new Date(), ""),
            action: { kind: "calendar" }
        });
    }

    // Widget pinning: "None (cycle through all)", "Pin to Page Position",
    // "Pin to Specific Target", with the "When Unavailable" fallback.
    readonly property var shownPages: {
        const all = root.pages;
        const mode = root.options?.pinMode ?? "none";
        if (mode === "none")
            return (root.options?.singlePage ?? false) ? all.slice(0, 1) : all;
        let pinned = [];
        if (mode === "position") {
            const index = Math.max(1, root.options?.pinPosition ?? 1) - 1;
            pinned = index < all.length ? [all[index]] : [];
        } else if (mode === "target") {
            const id = String(root.options?.pinTargetId ?? "");
            pinned = all.filter(p => p.itemId === id).slice(0, 1);
        }
        if (pinned.length > 0)
            return pinned;
        const fallback = root.options?.whenUnavailable ?? "date";
        if (fallback === "first")
            return all.slice(0, 1);
        if (fallback === "hide")
            return [];
        return [root.fallbackDatePage()];
    }

    // Weather on first open: the forecast target needs hourly data.
    onWidgetActiveChanged: if (root.widgetActive && (Weather.hourlyData ?? []).length === 0) Weather.getData(false)
}
