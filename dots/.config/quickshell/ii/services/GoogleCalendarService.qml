pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property bool credentialsConfigured: false
    property bool authenticating: false
    property bool reauthorizationRequired: false
    property string refreshToken: ""
    property string accessToken: ""
    property int accessTokenExpiry: 0
    property string activeAccountEmail: ""
    property string activeAccountAvatar: ""
    property list<var> calendars: []
    property var events: []
    property bool syncing: false
    property string lastErrorCode: ""
    property string lastErrorMessage: ""
    property int lastHttpStatus: 0
    property string mutationState: "idle"
    property string mutationMessage: ""
    property int mutationRevision: 0

    property var _pendingAction: null
    property var _eventQueue: []
    property var _fetchedEvents: []

    readonly property bool hasRefreshToken: root.refreshToken.length > 0
    readonly property bool available: root.credentialsConfigured && root.hasRefreshToken && !root.reauthorizationRequired

    // ── Event colours ─────────────────────────────────────────────
    // Google exports no COLOR property over CalDAV, so the colour a user picked
    // in Google Calendar cannot be read from the .ics files vdirsyncer stores.
    // It lives only as `colorId` on the API resource, resolved against the
    // account palette from /colors.
    readonly property bool colorsEnabled: Config.options.calendar.timetable.googleColors?.enable ?? false
    property var colorPalette: ({})
    property var colorByUid: ({})
    property bool colorsSyncing: false
    property real colorsFetchedAt: 0
    property var _colorQueue: []
    property var _colorAccumulator: ({})

    readonly property var colorOptions: {
        const entries = [];
        for (const id in root.colorPalette)
            entries.push({ id: String(id), background: String(root.colorPalette[id]?.background ?? ""), foreground: String(root.colorPalette[id]?.foreground ?? "") });
        return entries.sort((left, right) => Number(left.id) - Number(right.id));
    }

    /** Background hex for one calendar UID, or "" when Google has no colour. */
    function colorForUid(uid) {
        const entry = root.colorByUid[String(uid ?? "")];
        if (!entry)
            return "";
        return String(root.colorPalette[String(entry.colorId ?? "")]?.background ?? "");
    }

    function colorIdForUid(uid) {
        return String(root.colorByUid[String(uid ?? "")]?.colorId ?? "");
    }

    /** Whether a PATCH can address this UID, i.e. the scan saw the event. */
    function knowsEvent(uid) {
        return String(root.colorByUid[String(uid ?? "")]?.eventId ?? "").length > 0;
    }

    /** Hex for a khal DTO, or "" when the feature is off or Google has none. */
    function colorForEvent(event) {
        if (!root.colorsEnabled)
            return "";
        return root.colorForUid(event?.uid ?? "");
    }

    function refreshColors(force = false) {
        if (!root.available || !root.colorsEnabled || root.colorsSyncing)
            return;
        const staleAfter = Math.max(1, Config.options.calendar.timetable.googleColors?.refreshHours ?? 6) * 3600000;
        if (!force && root.colorsFetchedAt > 0 && Date.now() - root.colorsFetchedAt < staleAfter)
            return;
        root.colorsSyncing = true;
        root._ensureValidToken({ operation: "colors" });
    }

    /**
     * Push a colour back to Google.
     *
     * Addressing needs the API's own event id, which only the colour scan
     * carries; a calendar file knows the iCalUID and nothing else.
     */
    function setEventColor(uid, colorId) {
        const entry = root.colorByUid[String(uid ?? "")];
        if (!root.available || !entry?.eventId)
            return false;
        root._pendingColorWrite = { uid: String(uid), colorId: String(colorId ?? "") };
        root._ensureValidToken({
            operation: "colorPatch",
            calendarId: String(entry.calendarId ?? "primary"),
            eventId: String(entry.eventId),
            body: { colorId: String(colorId ?? "") || null }
        });
        return true;
    }

    property var _pendingColorWrite: null

    function startOAuth() {
        if (root.authenticating)
            return;
        root.authenticating = true;
        root.lastErrorCode = "";
        root.lastErrorMessage = "";
        oauthProcess.command = [
            "python3", Directories.scriptPath + "/google/oauth.py", "--scope",
            "https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/calendar.events email profile",
            "--port", "42071"
        ];
        oauthProcess.running = true;
    }

    function disconnect() {
        root.refreshToken = "";
        root.accessToken = "";
        root.accessTokenExpiry = 0;
        root.activeAccountEmail = "";
        root.activeAccountAvatar = "";
        root.calendars = [];
        root.events = [];
        root.reauthorizationRequired = false;
        KeyringStorage.setNestedField(["google_calendar_account"], ({}));
    }

    function refresh() {
        if (!root.available || root.syncing)
            return;
        root.syncing = true;
        root._ensureValidToken({ operation: "calendars" });
    }

    function createEvent(calendarId, fields) {
        if (!root.available)
            return false;
        const body = root.googleFields(fields);
        if (String(body.summary ?? "").trim().length === 0)
            return false;
        root.syncing = true;
        root.mutationState = "saving";
        root.mutationMessage = Translation.tr("Creating event…");
        root._ensureValidToken({ operation: "create", calendarId: calendarId || "primary", body: body });
        return true;
    }

    function updateEvent(event, fields) {
        if (!root.available || !event?.id)
            return false;
        root.syncing = true;
        root.mutationState = "saving";
        root.mutationMessage = Translation.tr("Saving event…");
        root._ensureValidToken({ operation: "update", calendarId: String(event.calendarId ?? "primary"), eventId: String(event.id), body: root.googleFields(fields) });
        return true;
    }

    function deleteEvent(event) {
        if (!root.available || !event?.id)
            return false;
        root.syncing = true;
        root.mutationState = "saving";
        root.mutationMessage = Translation.tr("Deleting event…");
        root._ensureValidToken({ operation: "delete", calendarId: String(event.calendarId ?? "primary"), eventId: String(event.id) });
        return true;
    }

    function googleFields(fields) {
        const start = String(fields?.start ?? "");
        const end = String(fields?.end ?? "");
        const allDay = fields?.allDay === true || (!start.includes("T") && start.length > 0);
        const body = {
            summary: String(fields?.summary ?? fields?.title ?? ""),
            description: String(fields?.description ?? ""),
            location: String(fields?.location ?? "")
        };
        if (allDay) {
            body.start = { date: start.slice(0, 10) };
            body.end = { date: end.slice(0, 10) };
        } else {
            body.start = { dateTime: start };
            body.end = { dateTime: end };
        }
        return body;
    }

    function _hasValidAccessToken() {
        return root.accessToken.length > 0 && Math.floor(Date.now() / 1000) < root.accessTokenExpiry - 30;
    }

    function _ensureValidToken(action) {
        root._pendingAction = action;
        if (root._hasValidAccessToken()) {
            root._runAction(action);
            return;
        }
        tokenRefreshProcess.stdinEnabled = true;
        tokenRefreshProcess.running = true;
    }

    function _runAction(action) {
        if (!action)
            return;
        if (action.operation === "calendars") {
            calendarsProcess.stdinEnabled = true;
            calendarsProcess.running = true;
            return;
        }
        // The colour path keeps its own processes so a colour write never
        // triggers the search panel's full event refetch, and vice versa.
        if (action.operation === "colors") {
            colorPaletteProcess.stdinEnabled = true;
            colorPaletteProcess.running = true;
            return;
        }
        if (action.operation === "colorCalendars") {
            colorCalendarsProcess.stdinEnabled = true;
            colorCalendarsProcess.running = true;
            return;
        }
        if (action.operation === "eventColors") {
            colorEventsProcess.stdinEnabled = true;
            colorEventsProcess.running = true;
            return;
        }
        if (action.operation === "colorPatch") {
            colorPatchProcess.stdinEnabled = true;
            colorPatchProcess.running = true;
            return;
        }
        mutationProcess.command = ["python3", Directories.scriptPath + "/google_calendar/api.py", action.operation];
        mutationProcess.stdinEnabled = true;
        mutationProcess.running = true;
    }

    function _apiError(result) {
        root.syncing = false;
        root.colorsSyncing = false;
        root.lastErrorCode = String(result?.code ?? "api_error");
        root.lastErrorMessage = String(result?.message ?? "");
        root.lastHttpStatus = Number(result?.http_status ?? 0);
        const operation = String(root._pendingAction?.operation ?? "");
        const willRetryToken = root.lastHttpStatus === 401;
        if (!willRetryToken && ["create", "update", "delete"].includes(operation)) {
            root.mutationState = "error";
            root.mutationMessage = root.lastErrorMessage || Translation.tr("Calendar change failed");
            root.mutationRevision++;
        }
        if (willRetryToken) {
            root.accessToken = "";
            root.accessTokenExpiry = 0;
            root._ensureValidToken(root._pendingAction);
        } else if (root.lastErrorCode === "invalid_grant") {
            root.reauthorizationRequired = true;
        }
    }

    function _colorError(result) {
        root.colorsSyncing = false;
        root._pendingColorWrite = null;
        root.lastErrorCode = String(result?.code ?? "api_error");
        root.lastErrorMessage = String(result?.message ?? "");
        root.lastHttpStatus = Number(result?.http_status ?? 0);
        if (root.lastErrorCode === "invalid_grant")
            root.reauthorizationRequired = true;
    }

    function _handleColorPalette(output) {
        try {
            const result = JSON.parse(output.trim());
            if (!result.ok) {
                root._colorError(result);
                return;
            }
            root.colorPalette = result.data?.event ?? ({});
            root._ensureValidToken({ operation: "colorCalendars" });
        } catch (error) {
            root._colorError({ code: "parse_error", message: error.message });
        }
    }

    function _handleColorCalendars(output) {
        try {
            const result = JSON.parse(output.trim());
            if (!result.ok) {
                root._colorError(result);
                return;
            }
            root._colorQueue = Array.from(result.data?.items ?? [])
                .map(calendar => String(calendar?.id ?? ""))
                .filter(id => id.length > 0);
            root._colorAccumulator = ({});
            root._fetchNextColorCalendar();
        } catch (error) {
            root._colorError({ code: "parse_error", message: error.message });
        }
    }

    function _fetchNextColorCalendar() {
        if (root._colorQueue.length === 0) {
            root.colorByUid = root._colorAccumulator;
            root.colorsFetchedAt = Date.now();
            root.colorsSyncing = false;
            root._persistColors();
            return;
        }
        colorEventsProcess.calendarId = String(root._colorQueue[0]);
        root._ensureValidToken({ operation: "eventColors" });
    }

    function _handleEventColors(output, calendarId) {
        // One unreadable calendar (a virtual holidays collection, a share that
        // was revoked) must not abort the scan for the others.
        try {
            const result = JSON.parse(output.trim());
            if (result.ok) {
                const map = root._colorAccumulator;
                for (const item of Array.from(result.data?.items ?? [])) {
                    const uid = String(item?.iCalUID ?? "");
                    if (uid.length === 0)
                        continue;
                    // The API id is recorded even without a colour: it is the
                    // only handle a PATCH can use, and a calendar file knows
                    // nothing but the iCalUID.
                    const colorId = String(item?.colorId ?? "");
                    const isException = String(item?.recurringEventId ?? "").length > 0;
                    // Google reuses the master's iCalUID for its exceptions, so
                    // the master is the one that describes the series.
                    if (map[uid] && isException)
                        continue;
                    map[uid] = { colorId: colorId, eventId: String(item?.id ?? ""), calendarId: calendarId };
                }
                root._colorAccumulator = map;
            } else {
                console.warn("[GoogleCalendar] colour scan skipped", calendarId, String(result.code ?? ""));
            }
        } catch (error) {
            console.warn("[GoogleCalendar] colour scan failed", calendarId, error.message);
        }
        root._colorQueue = root._colorQueue.slice(1);
        root._fetchNextColorCalendar();
    }

    function _handleColorPatch(output) {
        try {
            const result = JSON.parse(output.trim());
            if (!result.ok) {
                root._colorError(result);
                return;
            }
            const write = root._pendingColorWrite;
            root._pendingColorWrite = null;
            if (!write)
                return;
            const map = Object.assign({}, root.colorByUid);
            const entry = map[write.uid];
            if (entry) {
                if (write.colorId.length === 0)
                    delete map[write.uid];
                else
                    map[write.uid] = Object.assign({}, entry, { colorId: write.colorId });
                root.colorByUid = map;
                root._persistColors();
            }
        } catch (error) {
            root._colorError({ code: "parse_error", message: error.message });
        }
    }

    function _persistColors() {
        colorCacheView.setText(JSON.stringify({
            fetchedAt: root.colorsFetchedAt,
            palette: root.colorPalette,
            byUid: root.colorByUid
        }));
    }

    function _handleCalendars(output) {
        try {
            const result = JSON.parse(output.trim());
            if (!result.ok) {
                root._apiError(result);
                return;
            }
            const hidden = Array.from(Config.options.search.modules.calendar.hiddenCalendars ?? []);
            root.calendars = Array.from(result.data?.items ?? []).filter(calendar => !hidden.includes(String(calendar.id ?? "")));
            root._eventQueue = root.calendars.slice();
            root._fetchedEvents = [];
            root._fetchNextCalendar();
        } catch (error) {
            root._apiError({ code: "parse_error", message: error.message });
        }
    }

    function _fetchNextCalendar() {
        if (root._eventQueue.length === 0) {
            root.events = root._fetchedEvents.sort((left, right) => new Date(left.startDate) - new Date(right.startDate));
            root.syncing = false;
            return;
        }
        const calendar = root._eventQueue.shift();
        eventsProcess.calendar = calendar;
        eventsProcess.stdinEnabled = true;
        eventsProcess.running = true;
    }

    function _handleEvents(output, calendar) {
        try {
            const result = JSON.parse(output.trim());
            if (!result.ok) {
                root._apiError(result);
                return;
            }
            const values = Array.from(result.data?.items ?? []).map(event => root.normalizeEvent(event, calendar));
            root._fetchedEvents = root._fetchedEvents.concat(values);
            root._fetchNextCalendar();
        } catch (error) {
            root._apiError({ code: "parse_error", message: error.message });
        }
    }

    function normalizeEvent(event, calendar) {
        const startValue = String(event?.start?.dateTime ?? event?.start?.date ?? "");
        const endValue = String(event?.end?.dateTime ?? event?.end?.date ?? "");
        const allDay = !startValue.includes("T");
        return {
            id: String(event?.id ?? ""), uid: String(event?.iCalUID ?? event?.id ?? ""),
            title: String(event?.summary ?? Translation.tr("Untitled event")), content: String(event?.summary ?? Translation.tr("Untitled event")),
            description: String(event?.description ?? ""), location: String(event?.location ?? ""),
            startDate: new Date(startValue), endDate: new Date(endValue), allDay: allDay,
            status: String(event?.status ?? "confirmed"), calendar: String(calendar?.summary ?? ""),
            calendarId: String(calendar?.id ?? "primary"), color: String(event?.backgroundColor ?? calendar?.backgroundColor ?? Appearance.colors.colPrimary),
            url: String(event?.hangoutLink ?? event?.htmlLink ?? ""), htmlLink: String(event?.htmlLink ?? "")
        };
    }

    function _loadStoredAccount() {
        if (!KeyringStorage.loaded || !KeyringStorage.keyringData)
            return;
        const keyring = KeyringStorage.keyringData;
        // Only this feature's own grant works here. A refresh token carries the
        // scopes it was authorized with, so reusing the Google Tasks token makes
        // `available` true and then fails every call with 403 insufficient
        // scopes -- verified against the live API.
        const account = keyring.google_calendar_account ?? null;
        if (!account)
            return;
        root.refreshToken = String(account.refreshToken ?? "");
        root.activeAccountEmail = String(account.email ?? "");
        root.activeAccountAvatar = String(account.avatar ?? "");
    }

    Component.onCompleted: {
        credentialsProcess.running = true;
        root._loadStoredAccount();
    }

    Connections {
        target: KeyringStorage
        function onLoadedChanged() {
            if (KeyringStorage.loaded)
                root._loadStoredAccount();
        }
        function onDataChanged() {
            root._loadStoredAccount();
        }
    }

    Process {
        id: credentialsProcess
        command: ["python3", Directories.scriptPath + "/google/check_credentials.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.credentialsConfigured = JSON.parse(text.trim()).configured === true; }
                catch (error) { root.credentialsConfigured = false; }
            }
        }
    }

    Process {
        id: oauthProcess
        stdout: StdioCollector {
            onStreamFinished: {
                root.authenticating = false;
                try {
                    const result = JSON.parse(text.trim());
                    if (!result.ok) {
                        root._apiError(result);
                        return;
                    }
                    root.refreshToken = String(result.refresh_token ?? "");
                    root.accessToken = String(result.access_token ?? "");
                    root.accessTokenExpiry = Math.floor(Date.now() / 1000) + Number(result.expires_in ?? 3600);
                    root.activeAccountEmail = String(result.email ?? "");
                    root.activeAccountAvatar = String(result.picture ?? "");
                    root.reauthorizationRequired = false;
                    KeyringStorage.setNestedField(["google_calendar_account"], {
                        email: root.activeAccountEmail, avatar: root.activeAccountAvatar, refreshToken: root.refreshToken
                    });
                    root.refresh();
                } catch (error) { root._apiError({ code: "parse_error", message: error.message }); }
            }
        }
        onExited: root.authenticating = false
    }

    Process {
        id: tokenRefreshProcess
        command: ["python3", Directories.scriptPath + "/google/token_refresh.py"]
        stdinEnabled: true
        onRunningChanged: if (running) { write(root.refreshToken + "\n"); stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim());
                    if (!result.ok) { root._apiError(result); return; }
                    root.accessToken = String(result.access_token ?? "");
                    root.accessTokenExpiry = Math.floor(Date.now() / 1000) + Number(result.expires_in ?? 3600);
                    root._runAction(root._pendingAction);
                } catch (error) { root._apiError({ code: "parse_error", message: error.message }); }
            }
        }
    }

    Process {
        id: calendarsProcess
        command: ["python3", Directories.scriptPath + "/google_calendar/api.py", "calendars"]
        stdinEnabled: true
        onRunningChanged: if (running) { write(JSON.stringify({ accessToken: root.accessToken }) + "\n"); stdinEnabled = false; }
        stdout: StdioCollector { onStreamFinished: root._handleCalendars(text) }
    }

    Process {
        id: eventsProcess
        property var calendar: null
        command: ["python3", Directories.scriptPath + "/google_calendar/api.py", "events"]
        stdinEnabled: true
        onRunningChanged: if (running) {
            const start = new Date();
            const end = new Date(start.getTime() + Math.max(1, Config.options.search.modules.calendar.lookaheadDays) * 86400000);
            write(JSON.stringify({ accessToken: root.accessToken, calendarId: String(calendar?.id ?? "primary"), timeMin: start.toISOString(), timeMax: end.toISOString() }) + "\n");
            stdinEnabled = false;
        }
        stdout: StdioCollector { onStreamFinished: root._handleEvents(text, eventsProcess.calendar) }
    }

    Process {
        id: mutationProcess
        stdinEnabled: true
        onRunningChanged: if (running) {
            const action = root._pendingAction ?? ({});
            write(JSON.stringify({ accessToken: root.accessToken, calendarId: action.calendarId, eventId: action.eventId, body: action.body }) + "\n");
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim());
                    if (!result.ok) { root._apiError(result); return; }
                    const operation = String(root._pendingAction?.operation ?? "");
                    root.syncing = false;
                    root.mutationState = "success";
                    root.mutationMessage = operation === "delete"
                        ? Translation.tr("Event deleted")
                        : (operation === "update" ? Translation.tr("Event updated") : Translation.tr("Event created"));
                    root.mutationRevision++;
                    Qt.callLater(root.refresh);
                } catch (error) { root._apiError({ code: "parse_error", message: error.message }); }
            }
        }
    }

    Process {
        id: colorPaletteProcess
        command: ["python3", Directories.scriptPath + "/google_calendar/api.py", "colors"]
        stdinEnabled: true
        onRunningChanged: if (running) { write(JSON.stringify({ accessToken: root.accessToken }) + "\n"); stdinEnabled = false; }
        stdout: StdioCollector { onStreamFinished: root._handleColorPalette(text) }
    }

    Process {
        id: colorCalendarsProcess
        command: ["python3", Directories.scriptPath + "/google_calendar/api.py", "calendars"]
        stdinEnabled: true
        onRunningChanged: if (running) { write(JSON.stringify({ accessToken: root.accessToken }) + "\n"); stdinEnabled = false; }
        stdout: StdioCollector { onStreamFinished: root._handleColorCalendars(text) }
    }

    Process {
        id: colorEventsProcess
        property string calendarId: ""
        command: ["python3", Directories.scriptPath + "/google_calendar/api.py", "eventColors"]
        stdinEnabled: true
        onRunningChanged: if (running) { write(JSON.stringify({ accessToken: root.accessToken, calendarId: colorEventsProcess.calendarId }) + "\n"); stdinEnabled = false; }
        stdout: StdioCollector { onStreamFinished: root._handleEventColors(text, colorEventsProcess.calendarId) }
    }

    Process {
        id: colorPatchProcess
        command: ["python3", Directories.scriptPath + "/google_calendar/api.py", "update"]
        stdinEnabled: true
        onRunningChanged: if (running) {
            const action = root._pendingAction ?? ({});
            write(JSON.stringify({ accessToken: root.accessToken, calendarId: action.calendarId, eventId: action.eventId, body: action.body }) + "\n");
            stdinEnabled = false;
        }
        stdout: StdioCollector { onStreamFinished: root._handleColorPatch(text) }
    }

    // The map survives restarts so the timetable paints Google colours on the
    // first frame instead of waiting for a network round-trip.
    FileView {
        id: colorCacheView
        path: Directories.googleCalendarColorsPath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const cached = JSON.parse(colorCacheView.text());
                root.colorPalette = cached?.palette ?? ({});
                root.colorByUid = cached?.byUid ?? ({});
                root.colorsFetchedAt = Number(cached?.fetchedAt ?? 0);
            } catch (error) {
                root.colorPalette = ({});
                root.colorByUid = ({});
            }
        }
    }
}
