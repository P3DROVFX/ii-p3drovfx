// https://github.com/AvengeMedia/DankMaterialShell/blob/master/Services/CalendarService.qml

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import Qt.labs.platform
import qs.modules.common.functions
import qs.modules.common

Singleton {
    id: root

    readonly property string homePath: String(StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]).replace("file://", "")
    property bool khalAvailable: false
    // What khal lists. `events` is these merged with the phone's calendar (ii tools),
    // without the copies both sources have (see "Phone calendar" below).
    property var khalEvents: []
    readonly property var _merged: root._dedupe(root.khalEvents, root.phoneEvents)
    readonly property var events: root._merged.events
    /// Something gives events: khal, or the phone over ii link.
    readonly property bool eventsAvailable: root.khalAvailable || root.phoneCalendarActive
    /// Somewhere a new event can go: khal, or a phone calendar open for writing.
    readonly property bool canCreate: root.khalAvailable || root.phoneCalendars.some(calendar => calendar.readOnly !== true)
    // New events are rendered from this local projection before khal finishes
    // indexing their ICS file. The canonical event replaces it on the next
    // successful list response, keyed by the UID generated here.
    property list<var> optimisticEvents: []

    // Directories holding the .ics files of every configured khal calendar.
    // Read from khal's own config so deletion works wherever the user keeps their calendars.
    property var calendarPaths: [root.homePath + "/.calendars"]
    property string khalDbPath: root.homePath + "/.cache/khal/khal.db"
    readonly property string icsHelperPath: Directories.scriptPath + "/calendar/ics.py"
    readonly property string vdirsyncerSyncPath: Directories.scriptPath + "/calendar/vdirsyncer_sync.py"
    readonly property string vdirsyncerReauthPath: Directories.scriptPath + "/calendar/vdirsyncer_reauth.py"
    property bool googleAuthRequired: false
    property bool reauthenticatingGoogle: false
    // khal's calendars (ics.py) and, after them, the phone calendars the user shows.
    property list<var> khalCalendars: []
    readonly property var calendars: root.khalCalendars.concat(root.phoneCalendars.filter(calendar => calendar.shown))
    property string defaultCalendar: ""
    property list<var> calendarRequestQueue: []
    property var calendarCurrentRequest: null
    property var eventDetailsByUid: ({})
    property var eventDetailsFetchedAt: ({})
    readonly property int maximumEventDetailsEntries: 8
    readonly property int eventDetailsTtlMs: 15 * 60 * 1000
    property list<string> calendarSyncQueue: []
    property string lastCalendarSyncError: ""
    property string lastCalendarSyncStatus: ""
    property real lastCalendarSyncAt: 0

    function writableCalendar(name) {
        const requested = String(name ?? "").trim();
        if (!requested)
            return null;
        return root.calendars.find(calendar => String(calendar.name ?? "") === requested && calendar.readOnly !== true) ?? null;
    }

    function setDefaultCalendar(name, persist = true) {
        const calendar = root.writableCalendar(name);
        if (!calendar)
            return false;
        root.defaultCalendar = String(calendar.name);
        if (persist && Config.ready && Config.options.calendar.timetable.defaultCalendar !== root.defaultCalendar)
            Config.options.calendar.timetable.defaultCalendar = root.defaultCalendar;
        return true;
    }

    function newEventUid() {
        const timestamp = Date.now().toString(36);
        const entropy = Math.random().toString(36).slice(2);
        return "ii-" + timestamp + "-" + entropy + "@local";
    }

    function localDateFromIso(value) {
        const match = String(value ?? "").match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?$/);
        if (!match)
            return null;
        return new Date(
            Number(match[1]),
            Number(match[2]) - 1,
            Number(match[3]),
            Number(match[4] ?? 0),
            Number(match[5] ?? 0),
            Number(match[6] ?? 0)
        );
    }

    function optimisticEvent(calendar, fields) {
        const calendarData = root.calendars.find(item => String(item.name ?? "") === String(calendar ?? ""));
        const categories = Array.isArray(fields.categories) ? fields.categories.slice() : [];
        return {
            content: String(fields.summary ?? ""),
            startDate: root.localDateFromIso(fields.start),
            endDate: root.localDateFromIso(fields.end),
            color: root.getNextEventColor(),
            description: String(fields.description ?? ""),
            calendar: String(calendar ?? ""),
            readOnly: false,
            uid: String(fields.uid ?? ""),
            url: String(fields.url ?? ""),
            location: String(fields.location ?? ""),
            categories: categories,
            colorToken: String(fields.color ?? ""),
            repeatSymbol: fields.recurrence ? "↻" : "",
            status: String(fields.status ?? "CONFIRMED"),
            organizer: "",
            allDay: fields.allDay === true,
            calendarColor: String(calendarData?.color ?? ""),
            optimistic: true
        };
    }

    function addOptimisticEvent(event) {
        if (!event?.uid)
            return;
        root.optimisticEvents = root.optimisticEvents.concat([event]);
    }

    function removeOptimisticEvent(uid) {
        const target = String(uid ?? "");
        if (!target)
            return;
        root.optimisticEvents = root.optimisticEvents.filter(event => String(event?.uid ?? "") !== target);
    }

    readonly property var visibleEvents: {
        const persisted = root.events ?? [];
        const optimistic = root.optimisticEvents ?? [];
        if (optimistic.length === 0)
            return persisted;
        const projected = persisted.slice();
        for (const event of optimistic) {
            const uid = String(event?.uid ?? "");
            if (!persisted.some(saved => String(saved?.uid ?? "") === uid))
                projected.push(event);
        }
        return projected;
    }

    function pruneEventDetails(details = root.eventDetailsByUid, timestamps = root.eventDetailsFetchedAt) {
        const now = Date.now();
        const source = details ?? ({});
        const times = timestamps ?? ({});
        const keys = Object.keys(source)
            .filter(uid => {
                const fetchedAt = Number(times[uid] ?? 0);
                return fetchedAt > 0 && now - fetchedAt <= root.eventDetailsTtlMs;
            })
            .sort((left, right) => Number(times[right] ?? 0) - Number(times[left] ?? 0))
            .slice(0, root.maximumEventDetailsEntries);
        const nextDetails = ({});
        const nextTimes = ({});
        keys.forEach(uid => {
            nextDetails[uid] = source[uid];
            nextTimes[uid] = Number(times[uid]);
        });
        root.eventDetailsByUid = nextDetails;
        root.eventDetailsFetchedAt = nextTimes;
    }

    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: Object.keys(root.eventDetailsByUid ?? ({})).length > 0
        onTriggered: root.pruneEventDetails()
    }

    // Process for checking khal configuration
    Process {
        id: khalCheckProcess

        command: ["khal", "list", "today"]
        running: true
        onExited: exitCode => {
            root.khalAvailable = (exitCode === 0);
            if (root.khalAvailable) {
                khalPathsProcess.running = true;
                root.loadCalendarList();
            }
        }
    }

    function recheckKhal() {
        if (khalCheckProcess.running)
            return;
        khalCheckProcess.running = true;
    }

    Process {
        id: khalPathsProcess
        running: false
        // First line: sqlite cache path; following lines: one calendar directory (or glob) each
        command: ["python3", "-c", "from khal.settings import get_config\nimport os\ncfg = get_config()\nprint(os.path.expanduser(cfg['sqlite']['path']))\nfor c in cfg['calendars'].values():\n    print(os.path.expanduser(c['path']))"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").map(l => l.trim()).filter(l => l.length > 0);
                if (lines.length === 0)
                    return;
                root.khalDbPath = lines[0];
                const paths = lines.slice(1);
                if (paths.length === 0)
                    return;
                if (!paths.includes(root.homePath + "/.calendars"))
                    paths.push(root.homePath + "/.calendars");
                root.calendarPaths = paths;
            }
        }
    }

    function getTasksByDate(currentDate) {
        if (!khalAvailable) {
            return [];
        }
        const res = [];

        const currentDay = currentDate.getDate();
        const currentMonth = currentDate.getMonth();
        const currentYear = currentDate.getFullYear();

        for (let i = 0; i < root.events.length; i++) {
            const taskDate = new Date(root.events[i]['startDate']);
            if (taskDate.getDate() === currentDay && taskDate.getMonth() === currentMonth && taskDate.getFullYear() === currentYear) {
                res.push(root.events[i]);
            }
        }

        return res;
    }

    // Simple color list for events
    property var eventColors: [Appearance.m3colors.m3primary, Appearance.m3colors.m3secondary, Appearance.m3colors.m3tertiary, Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.colors.colTertiary]
    property int colorCounter: 0

    function getNextEventColor() {
        let color = eventColors[colorCounter % eventColors.length];
        colorCounter++;
        return color;
    }

    // ------------------------------------------------------------------
    // Fetch window
    // ------------------------------------------------------------------
    // khal is queried for a bounded date range. The window starts at -3/+3
    // months around today and only ever grows (see `ensureRangeCovers`), so
    // navigating far away in the calendar still yields events.

    function monthWindowStart(monthOffset) {
        const d = new Date();
        return new Date(d.getFullYear(), d.getMonth() + monthOffset, 1);
    }

    function monthWindowEnd(monthOffset) {
        const d = new Date();
        return new Date(d.getFullYear(), d.getMonth() + monthOffset + 1, 0);
    }

    property date rangeStart: root.monthWindowStart(-3)
    property date rangeEnd: root.monthWindowEnd(3)
    readonly property bool loading: getEventsProcess.running

    // Set when a reload is requested while a fetch is already in flight.
    property bool eventsReloadQueued: false

    // Rebuilds the khal command from the current window and starts the fetch.
    // `command` is assigned imperatively (no binding) so the window can change
    // without re-triggering a fetch on every intermediate value.
    function loadEvents() {
        if (!root.khalAvailable)
            return;
        if (getEventsProcess.running) {
            root.eventsReloadQueued = true;
            return;
        }
        getEventsProcess.command = ["khal", "list", "--json", "title", "--json", "start-date", "--json", "start-time", "--json", "end-time", "--json", "description", "--json", "calendar", "--json", "uid", "--json", "url", "--json", "location", "--json", "categories", "--json", "repeat-symbol", "--json", "status", "--json", "organizer", "--json", "all-day", "--json", "calendar-color", Qt.formatDate(root.rangeStart, "dd/MM/yyyy"), Qt.formatDate(root.rangeEnd, "dd/MM/yyyy")];
        getEventsProcess.running = true;
    }

    // Grows the fetch window so that `date` is covered, with 3 months of slack
    // in the direction that was extended. Never shrinks. Debounced so that
    // flicking through months does not spawn one khal process per month.
    function ensureRangeCovers(date) {
        if (!date)
            return;
        const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        let changed = false;
        if (d < root.rangeStart) {
            root.rangeStart = new Date(d.getFullYear(), d.getMonth() - 3, 1);
            changed = true;
        }
        if (d > root.rangeEnd) {
            root.rangeEnd = new Date(d.getFullYear(), d.getMonth() + 4, 0);
            changed = true;
        }
        if (changed)
            rangeDebounceTimer.restart();
    }

    Timer {
        id: rangeDebounceTimer
        interval: 150
        repeat: false
        onTriggered: root.loadEvents()
    }

    // ------------------------------------------------------------------
    // Per-day index
    // ------------------------------------------------------------------

    function dayKey(date) {
        if (!date)
            return "";
        return Qt.formatDate(date, "yyyy-MM-dd");
    }

    // true when the event spans a whole day: starts at 00:00 and ends at
    // 23:59 (khal's implicit all-day end) or 00:00.
    function isAllDayEvent(event) {
        if (!event || !event.startDate || !event.endDate)
            return false;
        if (event.allDay === true)
            return true;
        if (event.startDate.getHours() !== 0 || event.startDate.getMinutes() !== 0)
            return false;
        const endHours = event.endDate.getHours();
        const endMinutes = event.endDate.getMinutes();
        return (endHours === 23 && endMinutes === 59) || (endHours === 0 && endMinutes === 0);
    }

    // { "yyyy-MM-dd": [event, ...] } — all-day events first, then by start time.
    // khal always reports start and end on the same day, so one bucket per
    // event is enough (no multi-day expansion).
    readonly property var eventsByDay: {
        const map = {};
        const evts = root.visibleEvents;
        if (!evts)
            return map;
        for (let i = 0; i < evts.length; i++) {
            const evt = evts[i];
            if (!evt || !evt.startDate)
                continue;
            const key = root.dayKey(evt.startDate);
            if (key.length === 0)
                continue;
            if (!map[key])
                map[key] = [];
            map[key].push(evt);
        }
        for (const key in map) {
            map[key].sort((a, b) => {
                const aRank = root.isAllDayEvent(a) ? 0 : 1;
                const bRank = root.isAllDayEvent(b) ? 0 : 1;
                if (aRank !== bRank)
                    return aRank - bRank;
                return a.startDate.getTime() - b.startDate.getTime();
            });
        }
        return map;
    }

    function eventsForDay(date) {
        return root.eventsByDay[root.dayKey(date)] ?? [];
    }

    // Process for loading events
    Process {
        id: getEventsProcess
        running: false
        stdout: StdioCollector {

            onStreamFinished: {
                root.colorCounter = 0;  // Reset color counter for each reload
                let events = [];
                let lines = this.text.split('\n');
                for (let line of lines) {
                    line = line.trim();
                    if (!line || line === "[]")
                        continue;
                    let dayEvents;
                    try {
                        dayEvents = JSON.parse(line);
                    } catch (error) {
                        console.warn("[CalendarService] Ignoring invalid khal JSON:", error.message);
                        continue;
                    }
                    for (let event of dayEvents) {
                        if (!event['start-date'])
                            continue;
                        let startDateParts = event['start-date'].split('/');
                        let startTimeParts = event['start-time'] ? event['start-time'].split(':').map(Number) : [0, 0];

                        let endTimeParts = event['end-time'] ? event['end-time'].split(':').map(Number) : [23, 59]; // event is the whole day if start and end time are not set

                        let startDate = new Date(parseInt(startDateParts[2]), parseInt(startDateParts[1]) - 1, parseInt(startDateParts[0]), parseInt(startTimeParts[0]), parseInt(startTimeParts[1]));

                        let endDate = new Date(parseInt(startDateParts[2]), parseInt(startDateParts[1]) - 1, parseInt(startDateParts[0]), parseInt(endTimeParts[0]), parseInt(endTimeParts[1]));

                        const rawCategories = event['categories'];
                        const categoryValues = Array.isArray(rawCategories)
                            ? rawCategories
                            : (rawCategories ? String(rawCategories).split(',') : []);
                        const categories = [];
                        let colorToken = "";
                        for (let value of categoryValues) {
                            const category = String(value).trim();
                            if (!category)
                                continue;
                            if (category.startsWith("ii/color=")) {
                                colorToken = category.substring("ii/color=".length);
                                continue;
                            }
                            if (!categories.includes(category))
                                categories.push(category);
                        }

                        // The existing chip renderer still consumes a QColor.
                        // Phase 2 switches this fallback to the token palette;
                        // retain it here while keeping the token lossless.
                        let eventColor = root.getNextEventColor();

                        events.push({
                            "content": event['title'],
                            "startDate": startDate,
                            "endDate": endDate,
                            "color": eventColor,
                            "description": event['description'] ?? "",
                            "calendar": event['calendar'] || '',
                            "readOnly": root.isCalendarReadOnly(event['calendar']),
                            "uid": event['uid'] || '',
                            "url": event['url'] ?? "",
                            "location": event['location'] ?? "",
                            "categories": categories,
                            "colorToken": colorToken,
                            "repeatSymbol": event['repeat-symbol'] ?? "",
                            "status": event['status'] ?? "CONFIRMED",
                            "organizer": event['organizer'] ?? "",
                            "allDay": event['all-day'] === true || String(event['all-day']).toLowerCase() === "true",
                            "calendarColor": event['calendar-color'] ?? ""
                        });
                    }
                }
                root.khalEvents = events;
                root.optimisticEvents = root.optimisticEvents.filter(optimistic => !events.some(saved => String(saved?.uid ?? "") === String(optimistic?.uid ?? "")));
            }
        }
        onExited: {
            if (root.eventsReloadQueued) {
                root.eventsReloadQueued = false;
                rangeDebounceTimer.restart();
            }
        }
    }

    Timer {
        id: interval
        running: false
        interval: 10
        repeat: true
        onTriggered: {
            root.loadEvents();
            root.requestWritableCalendarSyncs();
            interval.interval = 900000; // 15 minutes
        }
    }

    Process {
        id: vdirsyncerProcess

        command: ["python3", root.vdirsyncerSyncPath]
        stdinEnabled: true
        running: false
        property string calendarName: ""
        property string responseText: ""

        onRunningChanged: {
            if (!running)
                return;
            write(JSON.stringify({ calendar: vdirsyncerProcess.calendarName }) + "\n");
            stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: vdirsyncerProcess.responseText = this.text.trim()
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim())
                    console.warn("[CalendarService] vdirsyncer helper:", this.text.trim());
            }
        }

        onExited: exitCode => {
            let reply;
            try {
                reply = JSON.parse(vdirsyncerProcess.responseText);
            } catch (error) {
                reply = { ok: false, error: Translation.tr("vdirsyncer sync returned an unreadable response.") };
            }
            if (exitCode !== 0 && reply?.ok)
                reply = { ok: false, error: Translation.tr("vdirsyncer exited with code %1.").arg(String(exitCode)) };
            root.finishCalendarSync(reply);
        }
    }

    function requestCalendarSync(calendar = "") {
        if (!root.khalAvailable)
            return false;
        const target = String(calendar ?? "").trim();
        if (vdirsyncerProcess.running) {
            const queue = root.calendarSyncQueue.slice();
            if (!queue.includes(target))
                queue.push(target);
            root.calendarSyncQueue = queue;
            return true;
        }
        root.lastCalendarSyncError = "";
        root.lastCalendarSyncStatus = Translation.tr("Synchronizing calendar…");
        vdirsyncerProcess.calendarName = target;
        vdirsyncerProcess.responseText = "";
        vdirsyncerProcess.stdinEnabled = true;
        vdirsyncerProcess.running = true;
        return true;
    }

    function requestWritableCalendarSyncs() {
        const calendars = root.calendars.filter(calendar => calendar.readOnly !== true).map(calendar => String(calendar.name));
        if (calendars.length === 0)
            return false;
        for (const calendar of calendars)
            root.requestCalendarSync(calendar);
        return true;
    }

    function finishCalendarSync(reply) {
        root.lastCalendarSyncAt = Date.now();
        if (reply?.ok) {
            root.lastCalendarSyncError = "";
            root.lastCalendarSyncStatus = Translation.tr("Calendar synchronized.");
            root.googleAuthRequired = false;
        } else {
            root.lastCalendarSyncError = String(reply?.error ?? Translation.tr("Could not synchronize calendar."));
            root.lastCalendarSyncStatus = "";
            console.warn("[CalendarService] vdirsyncer sync failed:", root.lastCalendarSyncError);
            const lowerErr = root.lastCalendarSyncError.toLowerCase();
            if (lowerErr.includes("invalid_grant") || lowerErr.includes("expired or revoked") || lowerErr.includes("token_refresh_failed") || lowerErr.includes("scope has changed") || lowerErr.includes("unauthorized") || lowerErr.includes("401")) {
                root.googleAuthRequired = true;
            }
        }
        root.loadEvents();
        if (root.calendarSyncQueue.length === 0)
            return;
        const queue = root.calendarSyncQueue.slice();
        const next = queue.shift();
        root.calendarSyncQueue = queue;
        Qt.callLater(function() { root.requestCalendarSync(next); });
    }

    Process {
        id: vdirsyncerReauthProcess

        command: ["python3", root.vdirsyncerReauthPath]
        running: false
        property string responseText: ""

        onRunningChanged: {
            if (!running)
                root.reauthenticatingGoogle = false;
        }

        stdout: StdioCollector {
            onStreamFinished: vdirsyncerReauthProcess.responseText = this.text.trim()
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim())
                    console.warn("[CalendarService] vdirsyncer reauth helper:", this.text.trim());
            }
        }

        onExited: exitCode => {
            root.reauthenticatingGoogle = false;
            let reply;
            try {
                reply = JSON.parse(vdirsyncerReauthProcess.responseText);
            } catch (e) {
                reply = { ok: false, error: Translation.tr("Authentication response could not be read.") };
            }
            if (exitCode === 0 && reply?.ok) {
                root.googleAuthRequired = false;
                root.lastCalendarSyncError = "";
                root.lastCalendarSyncStatus = Translation.tr("Google Calendar reconnected successfully.");
                root.requestWritableCalendarSyncs();
            } else if (root.googleAuthRequired) {
                root.lastCalendarSyncError = String(reply?.error ?? Translation.tr("Google Calendar reauthorization failed."));
                console.warn("[CalendarService] Google reauth failed:", root.lastCalendarSyncError);
            }
        }
    }

    IpcHandler {
        target: "calendar"
        function open(): void {
            GlobalStates.openCalendarApp("");
        }
        function openMode(mode: string): void {
            GlobalStates.openCalendarApp("", mode);
        }
        function openDate(date: string): void {
            GlobalStates.openCalendarApp(date, "month");
        }
        function quit(): void {
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("apps/calendar.qml"), "ipc", "call", "calendar", "quit"]);
        }
        function reload(): void {
            root.loadEvents();
        }
        function setConfig(path: string, valueJson: string): void {
            const clean = String(path ?? "").trim();
            if (!clean)
                return;
            let val;
            try {
                val = JSON.parse(valueJson);
            } catch (e) {
                return;
            }
            const keys = clean.split(".");
            let cursor = Config.options;
            for (let i = 0; i < keys.length - 1; i++) {
                if (!cursor || cursor[keys[i]] === undefined || cursor[keys[i]] === null)
                    return;
                cursor = cursor[keys[i]];
            }
            const leaf = keys[keys.length - 1];
            if (cursor && cursor[leaf] !== undefined)
                cursor[leaf] = val;
        }
        function sync() {
            root.requestWritableCalendarSyncs();
        }
        // What the phone's calendar adds, for checks from a terminal.
        function phoneStatus(): string {
            return JSON.stringify({
                enabled: root.phoneEnabled,
                active: root.phoneCalendarActive,
                live: root.phoneLive,
                writable: root.phoneCalendars.filter(calendar => !calendar.readOnly).length,
                calendars: root.phoneCalendars.map(calendar => calendar.name + (calendar.shown ? "" : " (hidden)")),
                phoneEvents: root.phoneEvents.length,
                khalEvents: root.khalEvents.length,
                events: root.events.length,
                duplicatesHidden: root.duplicatesHidden,
                defaultCalendar: root.defaultCalendar,
                lastError: root.phoneMutationError
            });
        }
        function onGoogleAuthComplete() {
            root.googleAuthRequired = false;
            root.reauthenticatingGoogle = false;
            root.lastCalendarSyncError = "";
            root.lastCalendarSyncStatus = Translation.tr("Google Calendar reconnected successfully.");
            root.requestWritableCalendarSyncs();
        }
        function importIcs(path: string, autoDelete: bool): void {
            root.importFromIcs(path, autoDelete);
        }
    }

    function startGoogleReauth() {
        if (root.reauthenticatingGoogle)
            return false;
        root.reauthenticatingGoogle = true;
        vdirsyncerReauthProcess.responseText = "";
        vdirsyncerReauthProcess.running = true;
        return true;
    }

    // A single helper process is serialized because khal owns one SQLite
    // index. Every event field stays JSON data on stdin, never a shell string.
    function enqueueCalendarRequest(payload, callback = null) {
        // khal-shaped requests (the AI's, say) for a phone event or calendar go to the phone.
        if (root.routePhoneRequest(payload, callback))
            return;
        const queue = root.calendarRequestQueue.slice();
        queue.push({ payload: payload, callback: callback });
        root.calendarRequestQueue = queue;
        root.startNextCalendarRequest();
    }

    function startNextCalendarRequest() {
        if (calendarHelperProcess.running || root.calendarCurrentRequest || root.calendarRequestQueue.length === 0)
            return;
        root.calendarCurrentRequest = root.calendarRequestQueue[0];
        root.calendarRequestQueue = root.calendarRequestQueue.slice(1);
        calendarHelperProcess.replyReceived = false;
        calendarHelperProcess.stdinEnabled = true;
        calendarHelperProcess.running = true;
    }

    function finishCalendarRequest(reply) {
        const current = root.calendarCurrentRequest;
        root.calendarCurrentRequest = null;
        if (!reply || !reply.ok) {
            console.warn("[CalendarService] Calendar request failed:", String(reply?.error ?? "No response from calendar helper."));
        } else if (current?.payload?.op === "read" && reply?.event?.uid) {
            const nextDetails = Object.assign({}, root.eventDetailsByUid);
            const uid = String(reply.event.uid);
            nextDetails[uid] = reply.event;
            const nextFetchedAt = Object.assign({}, root.eventDetailsFetchedAt);
            nextFetchedAt[uid] = Date.now();
            root.pruneEventDetails(nextDetails, nextFetchedAt);
        } else if ([
            "save", "deleteSeries", "deleteOccurrence", "overrideOccurrence",
            "splitSeries", "truncateSeries", "setCalendarColor", "importIcs"
        ].includes(String(current?.payload?.op ?? ""))) {
            root.eventDetailsByUid = ({});
            root.eventDetailsFetchedAt = ({});
            root.requestCalendarSync(String(current?.payload?.calendar ?? ""));
            root.loadEvents();
            if (current?.payload?.op === "setCalendarColor")
                root.loadCalendarList();
        }
        if (typeof current?.callback === "function")
            current.callback(reply);
        Qt.callLater(root.startNextCalendarRequest);
    }

    function loadCalendarList() {
        root.enqueueCalendarRequest({ op: "calendars" }, reply => {
            if (!reply?.ok)
                return;
            root.khalCalendars = reply.calendars ?? [];
            root.khalDefaultCalendar = String(reply.defaultCalendar ?? "").trim();
            root.ensureDefaultCalendar();
            if (!interval.running)
                interval.running = true;
            root.loadEvents();
        });
    }

    property string khalDefaultCalendar: ""
    readonly property string persistedDefaultCalendar: Config.ready ? String(Config.options.calendar.timetable.defaultCalendar ?? "") : ""
    onPersistedDefaultCalendarChanged: root.ensureDefaultCalendar()

    // The persisted choice, then khal's own default, then the first writable calendar:
    // khal's, else the phone's primary account calendar (one that syncs somewhere, not
    // the phone-only "My calendar"). A choice that is gone for now (phone away) is kept.
    function ensureDefaultCalendar() {
        const persisted = String(Config.options.calendar.timetable.defaultCalendar ?? "").trim();
        if (root.setDefaultCalendar(persisted, false) || root.setDefaultCalendar(root.khalDefaultCalendar, false))
            return;
        if (root.writableCalendar(root.defaultCalendar))
            return;
        const rank = calendar => calendar.source !== "phone" ? 0
            : (calendar.primary && calendar.provider !== "local" ? 1 : (calendar.provider !== "local" ? 2 : 3));
        const writable = root.calendars.filter(calendar => calendar.readOnly !== true)
            .sort((a, b) => rank(a) - rank(b))[0];
        root.defaultCalendar = writable?.name ?? "";
    }

    function isCalendarReadOnly(name) {
        return root.calendars.some(calendar => calendar.name === String(name ?? "") && calendar.readOnly === true);
    }

    Process {
        id: calendarHelperProcess
        command: ["python3", root.icsHelperPath]
        stdinEnabled: true
        property bool replyReceived: false
        onRunningChanged: {
            if (running && root.calendarCurrentRequest) {
                write(JSON.stringify(root.calendarCurrentRequest.payload) + "\n");
                stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let reply;
                try {
                    reply = JSON.parse(this.text.trim());
                } catch (error) {
                    reply = { ok: false, error: "Calendar helper returned invalid JSON: " + error.message };
                }
                calendarHelperProcess.replyReceived = true;
                root.finishCalendarRequest(reply);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim())
                    console.warn("[CalendarService] calendar helper:", this.text.trim());
            }
        }
        onExited: exitCode => {
            if (!calendarHelperProcess.replyReceived && root.calendarCurrentRequest)
                root.finishCalendarRequest({ ok: false, error: "Calendar helper exited with code " + exitCode + "." });
        }
    }

    function localIso(date, time = "00:00") {
        if (!date)
            return "";
        const normalizedTime = String(time || "00:00").length === 5 ? String(time) + ":00" : String(time);
        return Qt.formatDate(date, "yyyy-MM-dd") + "T" + normalizedTime;
    }

    function recurrenceIdForEvent(event) {
        if (!event?.startDate)
            return "";
        if (root.isAllDayEvent(event))
            return Qt.formatDate(event.startDate, "yyyy-MM-dd");
        return root.localIso(event.startDate, Qt.formatTime(event.startDate, "hh:mm:ss"));
    }

    function removeItem(item) {
        root.removeEventByUid(item?.uid ?? "", item?.calendar ?? "");
    }

    function removeEventByUid(uid, calendar = "") {
        if (!uid)
            return;
        if (root.isPhoneUid(uid)) {
            const event = root.phoneEvents.find(item => item.uid === String(uid));
            if (event)
                root.deleteEventWithScope(event, "all");
            return;
        }
        root.enqueueCalendarRequest({ op: "deleteSeries", uid: String(uid), calendar: String(calendar ?? "") });
    }

    // A summary is not an identifier. Callers that only have a title must
    // refresh and pick an event object first rather than risking a sibling.
    function removeEvent(title) {
        console.warn("[CalendarService] Refusing to delete an event by summary:", String(title ?? ""));
    }

    function readEvent(uid, callback) {
        if (!uid)
            return;
        if (root.isPhoneUid(uid)) {
            const reply = root.phoneEventDetails(uid);
            if (typeof callback === "function")
                Qt.callLater(() => callback(reply));
            return;
        }
        root.enqueueCalendarRequest({ op: "read", uid: String(uid) }, callback);
    }

    function eventDetailsForUid(uid) {
        return root.eventDetailsByUid[String(uid ?? "")] ?? null;
    }

    function expandEvent(uid, from, to, callback) {
        if (!uid || !from || !to)
            return;
        if (root.isPhoneUid(uid)) {
            const occurrences = root.phoneOccurrences(uid, from, to);
            if (typeof callback === "function")
                Qt.callLater(() => callback({ ok: true, occurrences: occurrences }));
            return;
        }
        const format = date => date instanceof Date
            ? Qt.formatDateTime(date, "yyyy-MM-ddTHH:mm:ss")
            : String(date);
        root.enqueueCalendarRequest({
            op: "expand",
            uid: String(uid),
            from: format(from),
            to: format(to)
        }, callback);
    }

    function saveEventFields(event, fields, scope = "all") {
        if (!event?.uid)
            return;
        if (event.source === "phone") {
            root.phoneEdit({ op: "update", event: event.phoneEvent, begin: event.phoneBegin, scope: scope, fields: root.phoneFields(fields) });
            return;
        }
        const payload = { uid: String(event.uid) };
        for (const key in fields)
            payload[key] = fields[key];
        const recurrenceId = fields.recurrenceId || root.recurrenceIdForEvent(event);
        const request = scope === "this"
            ? { op: "overrideOccurrence", uid: String(event.uid), calendar: event.calendar ?? "", recurrenceId: recurrenceId, fields: payload }
            : scope === "future"
                ? { op: "splitSeries", uid: String(event.uid), calendar: event.calendar ?? "", recurrenceId: recurrenceId, fields: payload }
                : { op: "save", calendar: event.calendar ?? "", event: payload };
        root.enqueueCalendarRequest(request);
    }

    function createEventFields(calendar, fields, callback = null) {
        const target = String(calendar || root.defaultCalendar).trim();
        const payload = Object.assign({}, fields);
        payload.uid = root.newEventUid();
        root.setDefaultCalendar(target);
        const phoneCalendar = root.phoneCalendars.find(item => item.name === target);
        if (phoneCalendar) {
            if (phoneCalendar.readOnly) {
                if (typeof callback === "function")
                    callback({ ok: false, error: Translation.tr("This phone calendar is read-only.") });
                return false;
            }
            const optimistic = root.optimisticEvent(target, payload);
            optimistic.source = "phone";
            optimistic.readOnly = true;
            root.addOptimisticEvent(optimistic);
            root.phoneEdit({ op: "create", calendar: phoneCalendar.phoneId, fields: root.phoneFields(payload) }, reply => {
                if (!reply?.ok)
                    root.removeOptimisticEvent(payload.uid);
                if (typeof callback === "function")
                    callback(reply);
            });
            return true;
        }
        root.addOptimisticEvent(root.optimisticEvent(target, payload));
        root.enqueueCalendarRequest({ op: "save", calendar: target, event: payload }, reply => {
            if (!reply?.ok)
                root.removeOptimisticEvent(payload.uid);
            if (typeof callback === "function")
                callback(reply);
        });
        return true;
    }

    function setCalendarColor(calendar, color) {
        if (!calendar || root.phoneCalendars.some(item => item.name === String(calendar)))
            return;
        root.enqueueCalendarRequest({ op: "setCalendarColor", calendar: String(calendar), color: String(color ?? "") });
    }

    function deleteEventWithScope(event, scope = "all") {
        if (!event?.uid)
            return;
        if (event.source === "phone") {
            root.phoneEdit({ op: "delete", event: event.phoneEvent, begin: event.phoneBegin, scope: scope });
            return;
        }
        const recurrenceId = root.recurrenceIdForEvent(event);
        const request = scope === "this"
            ? { op: "deleteOccurrence", uid: String(event.uid), calendar: event.calendar ?? "", recurrenceId: recurrenceId }
            : scope === "future"
                ? { op: "truncateSeries", uid: String(event.uid), calendar: event.calendar ?? "", recurrenceId: recurrenceId }
                : { op: "deleteSeries", uid: String(event.uid), calendar: event.calendar ?? "" };
        root.enqueueCalendarRequest(request);
    }

    /**
     * Move an event to another day, keeping its clock time.
     *
     * `scope` matters only for a recurring master: a plain `save` on it rewrites
     * DTSTART and therefore drags every occurrence along, so "this" writes an
     * override for the dragged date and "future" splits the series instead.
     */
    function moveEvent(event, newDate, scope = "all") {
        if (!event?.uid || !newDate)
            return;
        if (event.source === "phone") {
            root.movePhoneEvent(event, newDate, scope);
            return;
        }
        if (!root.khalAvailable)
            return;
        const allDay = root.isAllDayEvent(event);
        const oldStart = event.startDate;
        const oldEnd = event.endDate;
        const movedStart = new Date(newDate.getFullYear(), newDate.getMonth(), newDate.getDate(), oldStart.getHours(), oldStart.getMinutes());
        const movedEnd = new Date(newDate.getFullYear(), newDate.getMonth(), newDate.getDate(), oldEnd.getHours(), oldEnd.getMinutes());
        if (!allDay && movedEnd <= movedStart)
            movedEnd.setDate(movedEnd.getDate() + 1);
        const nextDay = new Date(newDate.getFullYear(), newDate.getMonth(), newDate.getDate() + 1);
        const fields = {
            uid: String(event.uid),
            allDay: allDay,
            start: allDay ? Qt.formatDate(newDate, "yyyy-MM-dd") : root.localIso(movedStart, Qt.formatTime(movedStart, "hh:mm")),
            end: allDay ? Qt.formatDate(nextDay, "yyyy-MM-dd") : root.localIso(movedEnd, Qt.formatTime(movedEnd, "hh:mm"))
        };
        root.saveEventFields(event, fields, scope);
    }

    function importFromIcs(path, autoDelete = false, calendar = "", callback = null) {
        const sourcePath = String(path ?? "").trim();
        const target = String(calendar || root.defaultCalendar).trim();
        if (!root.khalAvailable) {
            const reply = { ok: false, error: Translation.tr("Calendar service unavailable.") };
            if (typeof callback === "function")
                callback(reply);
            return false;
        }
        if (!sourcePath) {
            const reply = { ok: false, error: Translation.tr("Choose an ICS file to import.") };
            if (typeof callback === "function")
                callback(reply);
            return false;
        }
        root.enqueueCalendarRequest({
            op: "importIcs",
            path: sourcePath,
            deleteSource: Boolean(autoDelete),
            calendar: target
        }, callback);
        return true;
    }

    function importIcsBase64(contentsBase64, calendar = "", callback = null) {
        const payload = String(contentsBase64 ?? "").trim();
        const target = String(calendar || root.defaultCalendar).trim();
        if (!root.khalAvailable) {
            const reply = { ok: false, error: Translation.tr("Calendar service unavailable.") };
            if (typeof callback === "function")
                callback(reply);
            return false;
        }
        if (!payload) {
            const reply = { ok: false, error: Translation.tr("Calendar attachment is empty.") };
            if (typeof callback === "function")
                callback(reply);
            return false;
        }
        root.enqueueCalendarRequest({
            op: "importIcs",
            contentsBase64: payload,
            calendar: target
        }, callback);
        return true;
    }


    // ------------------------------------------------------------------
    // Phone calendar (ii tools)
    // ------------------------------------------------------------------
    // IiLinkService hands over what the phone sent (`calendar`, PROTOCOL.md): its
    // calendars, the instances in the window this service asked for, and per-event
    // details. They become the same DTOs khal's events are, with `source: "phone"`,
    // and are written back over the link (`calendarEdit`). With no phone, all of this
    // is empty and costs nothing.

    readonly property var phoneOptions: Config.options.iiTools.calendar
    readonly property bool phoneEnabled: Config.ready && (root.phoneOptions?.enable ?? true)
    /// { calendars, events, series, write, hash, from, to, at } from the phone, or null.
    property var phoneFeed: null
    /// The feed is from a phone that is connected now (else it is the cached copy).
    property bool phoneLive: false
    readonly property bool phoneCalendarActive: root.phoneEnabled && root.phoneFeed !== null
    /// How many of the phone's events were hidden as copies of khal's (or the reverse).
    readonly property int duplicatesHidden: root._merged.hidden

    function isPhoneUid(uid) {
        return String(uid ?? "").startsWith("phone:");
    }

    function setPhoneFeed(feed, live) {
        root.phoneFeed = feed ?? null;
        root.phoneLive = live === true;
        // A create shows from its projection until the phone's list carries it.
        if (root.phoneLive)
            root.optimisticEvents = root.optimisticEvents.filter(event => event.source !== "phone");
        root.ensureDefaultCalendar();
    }

    function phoneCalendarShown(calendar) {
        const id = String(calendar?.id ?? "");
        if ((root.phoneOptions?.hidden ?? []).includes(id))
            return false;
        if ((root.phoneOptions?.shown ?? []).includes(id))
            return true;
        // Never chosen: as the phone itself shows it.
        return calendar?.visible !== false;
    }

    function setPhoneCalendarShown(id, shown) {
        const key = String(id);
        const hidden = Array.from(root.phoneOptions.hidden ?? []).filter(item => item !== key);
        const visible = Array.from(root.phoneOptions.shown ?? []).filter(item => item !== key);
        if (shown)
            visible.push(key);
        else
            hidden.push(key);
        root.phoneOptions.hidden = hidden;
        root.phoneOptions.shown = visible;
    }

    readonly property var phoneCalendars: {
        const feed = root.phoneFeed;
        if (!root.phoneEnabled || !feed || !Array.isArray(feed.calendars))
            return [];
        const writes = feed.write === true && root.phoneLive && (root.phoneOptions?.write ?? true);
        const label = calendar => String(calendar.name || calendar.account || calendar.id);
        const counts = {};
        for (const calendar of feed.calendars)
            counts[label(calendar)] = (counts[label(calendar)] ?? 0) + 1;
        const taken = new Set(root.khalCalendars.map(calendar => String(calendar.name)));
        return feed.calendars.map(calendar => {
            let name = label(calendar);
            // Two accounts with a "Calendar" each, or a khal calendar of the same name.
            if (counts[name] > 1 && calendar.account)
                name += " · " + String(calendar.account);
            if (taken.has(name))
                name += " · " + Translation.tr("phone");
            return {
                name: name,
                displayName: label(calendar),
                color: "",
                phoneColor: String(calendar.color ?? ""),
                readOnly: !(writes && calendar.writable === true),
                source: "phone",
                phoneId: String(calendar.id),
                account: String(calendar.account ?? ""),
                provider: String(calendar.provider ?? ""),
                visible: calendar.visible !== false,
                primary: calendar.primary === true,
                shown: root.phoneCalendarShown(calendar)
            };
        });
    }

    function _phoneDate(value, allDay) {
        if (allDay)
            return root.localDateFromIso(String(value));
        return new Date(Number(value));
    }

    function _startOfDay(date) {
        return new Date(date.getFullYear(), date.getMonth(), date.getDate());
    }

    // Every instance as khal lists it: one entry per day it covers.
    readonly property var phoneEvents: {
        const feed = root.phoneFeed;
        const calendars = root.phoneCalendars;
        if (!feed || calendars.length === 0 || !Array.isArray(feed.events))
            return [];
        const byId = {};
        for (const calendar of calendars)
            byId[calendar.phoneId] = calendar;
        const series = feed.series ?? {};
        const useColors = root.phoneOptions?.colors ?? true;
        const hideDeclined = root.phoneOptions?.hideDeclined ?? true;
        const palette = root.eventColors;
        const out = [];
        let colorIndex = 0;
        for (const item of feed.events) {
            const calendar = byId[String(item.calendar)];
            if (!calendar || !calendar.shown || (hideDeclined && item.declined === true))
                continue;
            const allDay = item.allDay === true;
            const start = root._phoneDate(allDay ? item.start : item.begin, allDay);
            let end = root._phoneDate(allDay ? item.end : item.end, allDay);
            if (!start || isNaN(start.getTime()))
                continue;
            if (!end || isNaN(end.getTime()) || end < start)
                end = start;
            const details = series[String(item.event)] ?? {};
            const base = {
                content: String(item.title ?? ""),
                color: useColors && item.color ? String(item.color) : palette[colorIndex++ % palette.length],
                description: String(details.description ?? ""),
                calendar: calendar.name,
                readOnly: calendar.readOnly,
                uid: "phone:" + String(item.event),
                url: "",
                location: String(details.location ?? ""),
                categories: [],
                colorToken: "",
                repeatSymbol: item.recurring === true ? "↻" : "",
                status: String(details.status ?? "CONFIRMED"),
                organizer: String(details.organizer ?? ""),
                allDay: allDay,
                calendarColor: "",
                source: "phone",
                phoneEvent: String(item.event),
                phoneBegin: Number(item.begin),
                phoneCalendar: calendar.phoneId,
                icalUid: String(details.uid ?? ""),
                spanStart: start,
                spanEnd: end
            };
            // All day: one entry per date, the end being exclusive. Timed: cut at midnight.
            let day = root._startOfDay(start);
            const lastDay = allDay ? new Date(end.getFullYear(), end.getMonth(), end.getDate() - 1) : root._startOfDay(end);
            let guard = 0;
            do {
                const next = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
                const piece = Object.assign({}, base);
                if (allDay) {
                    piece.startDate = day;
                    piece.endDate = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 23, 59);
                } else {
                    piece.startDate = start > day ? start : day;
                    piece.endDate = end < next ? end : new Date(day.getFullYear(), day.getMonth(), day.getDate(), 23, 59);
                    // An event ending at midnight does not spill into the next day.
                    if (piece.startDate >= piece.endDate && day > root._startOfDay(start))
                        break;
                }
                out.push(piece);
                day = next;
            } while (day <= lastDay && ++guard < 62);
        }
        return out;
    }

    function _occurrenceTime(event) {
        if (!event?.startDate)
            return "";
        return root.isAllDayEvent(event)
            ? root.dayKey(event.startDate)
            : Qt.formatDateTime(event.startDate, "yyyy-MM-ddTHH:mm");
    }

    // Two sources hold the same event when its UID and start agree, or, for accounts
    // that hide the UID from the phone, its title and start.
    function _eventKeys(event) {
        const when = root._occurrenceTime(event);
        const keys = [];
        const uid = String(event?.icalUid ?? (event?.source === "phone" ? "" : event?.uid ?? "")).trim();
        if (uid && !root.isPhoneUid(uid))
            keys.push("u:" + uid.toLowerCase() + "|" + when);
        const title = String(event?.content ?? "").trim().toLowerCase().replace(/\s+/g, " ");
        if (title)
            keys.push("f:" + title + "|" + when);
        return keys;
    }

    function _dedupe(khal, phone) {
        const khalList = khal ?? [];
        const phoneList = phone ?? [];
        if (phoneList.length === 0 || khalList.length === 0 || !(root.phoneOptions?.dedupe ?? true))
            return { events: khalList.concat(phoneList), hidden: 0 };
        const preferPhone = (root.phoneOptions?.prefer ?? "khal") === "phone";
        const kept = preferPhone ? phoneList : khalList;
        const other = preferPhone ? khalList : phoneList;
        const seen = new Set();
        for (const event of kept)
            for (const key of root._eventKeys(event))
                seen.add(key);
        const rest = other.filter(event => !root._eventKeys(event).some(key => seen.has(key)));
        return { events: kept.concat(rest), hidden: other.length - rest.length };
    }

    function _isoLocal(date, allDay) {
        if (!date)
            return "";
        return allDay ? Qt.formatDate(date, "yyyy-MM-dd") : Qt.formatDateTime(date, "yyyy-MM-ddTHH:mm:ss");
    }

    // The same reply `ics.py read` gives, from what the phone already sent.
    function phoneEventDetails(uid) {
        const event = root.phoneEvents.find(item => item.uid === String(uid));
        if (!event)
            return { ok: false, error: Translation.tr("The phone no longer has this event.") };
        const details = root.phoneFeed?.series?.[event.phoneEvent] ?? {};
        return {
            ok: true,
            event: {
                uid: event.uid,
                calendar: event.calendar,
                summary: event.content,
                description: event.description,
                location: event.location,
                url: "",
                allDay: event.allDay,
                start: root._isoLocal(event.spanStart, event.allDay),
                end: root._isoLocal(event.spanEnd, event.allDay),
                timezone: String(details.timezone ?? ""),
                status: event.status,
                categories: [],
                color: "",
                recurrence: details.recurrence ?? null,
                exdates: Array.isArray(details.exdates) ? details.exdates : [],
                alarms: Array.isArray(details.alarms) ? details.alarms : [],
                organizer: event.organizer,
                attendees: [],
                readOnly: event.readOnly
            }
        };
    }

    function phoneOccurrences(uid, from, to) {
        const seen = new Set();
        const out = [];
        for (const event of root.phoneEvents) {
            if (event.uid !== String(uid) || event.spanStart < from || event.spanStart > to || seen.has(event.phoneBegin))
                continue;
            seen.add(event.phoneBegin);
            const start = root._isoLocal(event.spanStart, event.allDay);
            out.push({ start: start, end: root._isoLocal(event.spanEnd, event.allDay), recurrenceId: start });
        }
        return out.sort((a, b) => a.start.localeCompare(b.start));
    }

    // The editor's fields as the phone takes them: no categories, links or colour tokens.
    function phoneFields(fields) {
        const out = {};
        for (const key of ["summary", "description", "location", "status", "allDay", "start", "end", "recurrence", "alarms", "exdates", "uid"]) {
            if (fields && key in fields && fields[key] !== undefined)
                out[key] = fields[key];
        }
        return out;
    }

    property string phoneMutationError: ""

    function phoneErrorText(code) {
        switch (String(code ?? "")) {
        case "offline":
            return Translation.tr("The phone isn't connected.");
        case "timeout":
            return Translation.tr("The phone didn't answer.");
        case "readOnly":
            return Translation.tr("This phone calendar is read-only.");
        case "permission":
            return Translation.tr("The phone hasn't allowed edits: grant Edit calendar in ii tools.");
        case "disabled":
            return Translation.tr("The phone stopped sharing its calendar.");
        case "event":
            return Translation.tr("The phone no longer has this event.");
        default:
            return Translation.tr("The phone couldn't save the change (%1).").arg(String(code ?? ""));
        }
    }

    function phoneEdit(request, callback = null) {
        if (!root.phoneLive || root.phoneFeed?.write !== true || !(root.phoneOptions?.write ?? true)) {
            const reply = { ok: false, error: Translation.tr("The phone calendar can't be edited right now.") };
            root.phoneMutationError = reply.error;
            if (typeof callback === "function")
                callback(reply);
            return false;
        }
        IiLinkService.calendarEdit(request, raw => {
            const reply = raw?.ok ? raw : { ok: false, error: root.phoneErrorText(raw?.error) };
            root.phoneMutationError = reply.ok ? "" : reply.error;
            if (!reply?.ok)
                console.warn("[CalendarService] Phone calendar edit failed:", root.phoneMutationError);
            if (typeof callback === "function")
                callback(reply);
        });
        return true;
    }

    // Moving a day or an instance that was cut at midnight moves the whole span.
    function movePhoneEvent(event, newDate, scope) {
        const allDay = event.allDay === true;
        const shift = Math.round((root._startOfDay(newDate) - root._startOfDay(event.startDate)) / 86400000);
        const start = new Date(event.spanStart);
        const end = new Date(event.spanEnd);
        start.setDate(start.getDate() + shift);
        end.setDate(end.getDate() + shift);
        root.saveEventFields(event, {
            allDay: allDay,
            start: root._isoLocal(start, allDay),
            end: root._isoLocal(end, allDay)
        }, scope);
    }


    // A khal-shaped request (`ics.py` ops) aimed at the phone, carried out there.
    // Returns false when it is not the phone's.
    function routePhoneRequest(payload, callback) {
        const op = String(payload?.op ?? "");
        const uid = String(payload?.uid ?? payload?.event?.uid ?? "");
        const phoneCalendar = root.phoneCalendars.find(item => item.name === String(payload?.calendar ?? ""));
        if (!root.isPhoneUid(uid) && !(op === "save" && phoneCalendar))
            return false;
        const done = reply => {
            if (typeof callback === "function")
                callback(reply);
        };
        if (op === "read") {
            Qt.callLater(() => done(root.phoneEventDetails(uid)));
            return true;
        }
        if (op === "save" && !root.isPhoneUid(uid)) {
            const fields = Object.assign({}, payload.event ?? {});
            delete fields.uid;
            root.createEventFields(phoneCalendar.name, fields, done);
            return true;
        }
        const occurrences = root.phoneEvents.filter(item => item.uid === uid);
        const target = occurrences.find(item => {
            const id = root.recurrenceIdForEvent({ startDate: item.spanStart, endDate: item.spanEnd, allDay: item.allDay });
            return payload.recurrenceId && id === String(payload.recurrenceId);
        }) ?? occurrences[0];
        if (!target) {
            Qt.callLater(() => done({ ok: false, error: Translation.tr("The phone no longer has this event.") }));
            return true;
        }
        const scope = ({ overrideOccurrence: "this", deleteOccurrence: "this", splitSeries: "future", truncateSeries: "future" })[op] ?? "all";
        if (op === "save" || op === "overrideOccurrence" || op === "splitSeries")
            root.phoneEdit({ op: "update", event: target.phoneEvent, begin: target.phoneBegin, scope: scope, fields: root.phoneFields(payload.event ?? payload.fields ?? {}) }, done);
        else if (op === "deleteSeries" || op === "deleteOccurrence" || op === "truncateSeries")
            root.phoneEdit({ op: "delete", event: target.phoneEvent, begin: target.phoneBegin, scope: scope }, done);
        else
            Qt.callLater(() => done({ ok: false, error: Translation.tr("Phone calendars don't support this.") }));
        return true;
    }
}
