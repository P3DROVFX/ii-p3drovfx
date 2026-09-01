import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import "TimetableHelpers.js" as H

/**
 * Shared right rail: a day, an event, or the editor for one.
 *
 * Replaces the modal sheets the month view used to raise. A panel that takes
 * room from the grid instead of covering it keeps the date you are working on
 * visible, which is the whole point of editing from a calendar.
 *
 * Time and date are never typed here: the rows open pickers, which the month
 * view owns so they can centre over the whole view rather than over this rail.
 * The three pages are inline rather than reusable components on purpose — the
 * editor's inputs have to be written imperatively when a page opens, and an
 * inline component would put their ids out of reach.
 */
Item {
    id: root

    /** "" (closed) | "day" | "details" | "edit" | "create" | "sources" */
    property string mode: ""
    property var event: null
    property date day: new Date()
    property bool detailsOnly: false
    /** Restricts the day browser to ESPN games (used by the compact week view). */
    property bool sportsListOnly: false

    readonly property bool editing: root.mode === "edit" || root.mode === "create"
    readonly property bool open: root.mode !== ""

    // ─── Editor state ───
    property date formDate: new Date()
    property string formTitle: ""
    property string formDescription: ""
    property int formStartMinutes: 9 * 60
    property int formEndMinutes: 10 * 60
    property bool formAllDay: false
    property string createKind: "event"
    property string formUrl: ""
    property string formLocation: ""
    property string formCalendar: ""
    property string formStatus: "CONFIRMED"
    property string formColorToken: ""
    property list<string> formCategories: []
    property string formRepeat: ""
    property string formRepeatUntil: ""
    property list<string> formRepeatByDay: []
    property list<string> formAlarms: []
    property var eventDetails: null
    property var upcomingOccurrences: []
    property bool showExceptions: false
    property var pendingPayload: null
    property var pendingMutationFields: null
    property string pendingAction: ""
    property var pendingMoveDate: null
    /** Open tasks with no due date; the month grid shows only their count. */
    readonly property var undatedTasks: Todo.getUndatedTasks()
    readonly property bool googleColorAvailable: GoogleCalendarService.colorsEnabled
        && !root.sportsEvent
        && !root.birthdayEvent
        && !root.eventReadOnly
        && GoogleCalendarService.knowsEvent(root.event?.uid ?? "")
    readonly property string googleColorId: GoogleCalendarService.colorIdForUid(root.event?.uid ?? "")
    property bool showCalendarSelector: false
    property string sourceUrlDraft: ""
    property string sourcesStatusText: ""
    property string outlookClientIdDraft: ""
    readonly property bool calendarSourcesEnabled: Config.options.calendar.timetable.imports.enable
    readonly property bool gmailIcsEnabled: Config.options.calendar.timetable.imports.gmailIcs.enable
    readonly property bool outlookEnabled: Config.options.calendar.timetable.imports.outlook.enable
    readonly property bool outlookIcsEnabled: Config.options.calendar.timetable.imports.outlook.icsAttachments.enable

    readonly property bool rangeValid: root.formAllDay || root.formEndMinutes > root.formStartMinutes
    readonly property bool canSave: root.formTitle.trim().length > 0 && root.rangeValid
    readonly property bool sportsEvent: root.event?.sportEvent === true
    readonly property bool birthdayEvent: root.event?.birthdayEvent === true
    readonly property var sportsGame: root.sportsEvent ? (SportsService.gameById(root.event?.id) ?? root.event) : null
    readonly property var sportsDetails: root.sportsEvent ? SportsService.detailsForGame(root.event?.id) : null
    readonly property bool sportsDetailsLoading: root.sportsEvent && SportsService.detailsLoadingForGame(root.event?.id)
    readonly property string sportsDetailsError: root.sportsEvent ? SportsService.detailsErrorForGame(root.event?.id) : ""

    signal saveRequested(var payload)
    signal taskCreateRequested(var task)
    signal deleteRequested(var eventData, string scope)
    signal eventFieldsMutationRequested(var eventData, var fields, string scope)
    signal moveRequested(var eventData, var newDate, string scope)
    signal closeRequested
    signal taskCompletionRequested(var task)
    signal timePickerRequested(string which, int startHour, int startMinute)
    signal datePickerRequested(string purpose, var date)

    // ─── Entry points ───
    function showDay(date) {
        if (root.sportsEvent)
            SportsService.clearFocusedGame(root.event?.id);
        root.day = H.startOfDay(date);
        root.event = null;
        root.setMode("day");
    }

    function showSportsDay(date) {
        root.showDay(date);
    }

    function showSources() {
        if (root.sportsEvent)
            SportsService.clearFocusedGame(root.event?.id);
        root.event = null;
        root.sourcesStatusText = "";
        root.outlookClientIdDraft = OutlookService.clientId;
        root.setMode("sources");
    }

    function connectOutlook() {
        if (!OutlookService.beginAuthorization(root.outlookClientIdDraft))
            root.sourcesStatusText = OutlookService.lastError;
    }

    function importSourceFile(path) {
        if (!root.calendarSourcesEnabled)
            return;
        CalendarIcsFileImport.importSourceFile(path);
    }

    function addSourceSubscription() {
        if (!root.calendarSourcesEnabled)
            return;
        if (CalendarSubscriptions.addSubscription(root.sourceUrlDraft)) {
            root.sourceUrlDraft = "";
            sourceSubscriptionInput.textField.clear();
        }
    }

    function showEvent(eventData) {
        if (!eventData)
            return;
        root.event = eventData;
        root.day = H.startOfDay(eventData.startDate);
        root.eventDetails = null;
        root.upcomingOccurrences = [];
        root.showExceptions = false;
        if (eventData.sportEvent === true) {
            SportsService.focusGame(eventData);
        } else if (eventData.birthdayEvent !== true) {
            CalendarService.readEvent(eventData.uid, reply => {
                if (!reply?.ok || root.event !== eventData)
                    return;
                root.eventDetails = reply.event;
                root.loadUpcomingOccurrences(eventData);
            });
        }
        root.setMode("details");
    }

    function loadUpcomingOccurrences(eventData) {
        if (!eventData?.uid)
            return;
        const from = eventData.startDate ?? root.day;
        const to = new Date(from.getFullYear() + 1, from.getMonth(), from.getDate() + 1);
        CalendarService.expandEvent(eventData.uid, from, to, reply => {
            if (!reply?.ok || root.event !== eventData)
                return;
            root.upcomingOccurrences = (reply.occurrences ?? []).slice(0, 5);
        });
    }

    function localCalendarDate(value) {
        const match = String(value ?? "").match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?/);
        if (!match)
            return new Date(value);
        return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4] ?? 0), Number(match[5] ?? 0), Number(match[6] ?? 0));
    }

    function occurrenceLabel(occurrence) {
        const date = root.localCalendarDate(occurrence?.start ?? occurrence?.recurrenceId ?? "");
        if (isNaN(date.getTime()))
            return String(occurrence?.recurrenceId ?? "");
        return root.eventAllDay
            ? Qt.formatDate(date, "ddd, d MMM yyyy")
            : Qt.formatDateTime(date, "ddd, d MMM yyyy · hh:mm");
    }

    function restoreException(rawDate) {
        if (!root.event?.uid)
            return;
        const restored = String(rawDate ?? "");
        const exdates = (root.eventDetails?.exdates ?? []).filter(value => String(value) !== restored);
        root.eventDetails = Object.assign({}, root.eventDetails, { exdates: exdates });
        CalendarService.saveEventFields(root.event, { exdates: exdates });
        root.loadUpcomingOccurrences(root.event);
    }

    function requestTimedMutation(eventData, fields, action) {
        if (!eventData?.uid || eventData.readOnly === true)
            return;
        root.event = eventData;
        if (String(eventData.repeatSymbol ?? "").length > 0) {
            root.pendingAction = action;
            root.pendingMutationFields = fields;
            root.setMode("scope");
            return;
        }
        root.eventFieldsMutationRequested(eventData, fields, "all");
        root.close();
    }

    /**
     * Move an event to another day.  A recurring master cannot be rewritten
     * silently: `save` on it would shift every occurrence, so the scope page
     * asks first, exactly like delete does.
     */
    function requestMove(eventData, date) {
        if (!eventData?.uid || eventData.readOnly === true || !date)
            return;
        root.event = eventData;
        if (String(eventData.repeatSymbol ?? "").length > 0) {
            root.pendingAction = "move";
            root.pendingMoveDate = H.startOfDay(date);
            root.setMode("scope");
            return;
        }
        root.moveRequested(eventData, date, "all");
        root.close();
    }

    // ─── In-module integrations ──────────────────────────────────────────

    EventNotesStore {
        id: eventNotes
    }

    /** Stable identity used by the event→note mapping. */
    readonly property string eventNoteKey: {
        const event = root.event;
        if (!event || event.sportEvent === true)
            return "";
        if (event.uid)
            return "uid:" + String(event.uid);
        return "k:" + String(event.content ?? "") + "@" + String(event.startDate?.getTime?.() ?? 0);
    }

    /** Resolves the stored link against live notes so tab deletion degrades gracefully. */
    function attachedNoteIndex() {
        const title = root.eventNoteKey.length > 0 ? eventNotes.titleFor(root.eventNoteKey) : "";
        if (title.length === 0)
            return -1;
        const tabs = NotesService.tabsData?.tabs ?? [];
        for (let i = 0; i < tabs.length; i++) {
            if (String(tabs[i]?.title ?? "") === title)
                return i;
        }
        return -1;
    }

    function attachNote() {
        const event = root.event;
        if (!event || event.sportEvent === true || root.eventNoteKey.length === 0)
            return;
        const title = String(event.content ?? Translation.tr("Event")).slice(0, 120);
        let header = Qt.formatDateTime(event.startDate, "dddd, d MMM yyyy · hh:mm");
        if (String(event.location ?? "").length > 0)
            header += "\n" + String(event.location);
        const created = NotesService.create(title, header, null);
        if (!created.ok)
            return;
        eventNotes.setLink(root.eventNoteKey, created.title);
    }

    function openAttachedNote() {
        const index = root.attachedNoteIndex();
        if (index < 0)
            return;
        Persistent.states.overlay.notes.tabIndex = index;
        GlobalStates.notesOpen = true;
    }

    /** Starts a countdown matching the event's remaining time (Focus action). */
    function focusOnEvent() {
        const event = root.event;
        if (!event)
            return;
        const remainingMs = event.endDate.getTime() - DateTime.clock.date.getTime();
        const minutes = Math.max(1, Math.ceil(remainingMs / 60000));
        TimerService.addCountdown(minutes, Translation.tr("Focus") + " · " + String(event.content ?? "").slice(0, 40));
    }

    function exceptionLabel(value) {
        const date = root.localCalendarDate(value);
        return isNaN(date.getTime()) ? String(value ?? "") : Qt.formatDate(date, "ddd, d MMM yyyy");
    }

    function startCreate(date) {
        root.startCreateAt(date, -1, -1);
    }

    function showUndatedTasks() {
        root.setMode("tasks");
    }

    function startCreateTask(date) {
        root.startCreateAt(date, -1, -1);
        root.createKind = "task";
    }

    function startCreateAt(date, startMinutes, endMinutes) {
        if (root.sportsEvent)
            SportsService.clearFocusedGame(root.event?.id);
        const now = DateTime.clock.date;
        const startHour = H.sameDate(date, now) ? Math.min(22, now.getHours() + 1) : 9;
        root.event = null;
        root.formDate = H.startOfDay(date);
        root.formAllDay = false;
        root.createKind = "event";
        root.formStartMinutes = startMinutes >= 0 ? startMinutes : startHour * 60;
        root.formEndMinutes = endMinutes > root.formStartMinutes
            ? endMinutes
            : Math.min(24 * 60, root.formStartMinutes + 60);
        titleInput.text = "";
        notesInput.text = "";
        linkInput.text = "";
        locationInput.text = "";
        root.formCalendar = CalendarService.defaultCalendar;
        root.formStatus = "CONFIRMED";
        root.formColorToken = "";
        root.formCategories = [];
        categoryInput.text = "";
        root.formRepeat = "";
        root.formRepeatUntil = "";
        root.formRepeatByDay = [];
        root.formAlarms = [];
        root.setMode("create");
        titleInput.forceActiveFocus();
    }

    function startEdit(eventData) {
        if (!eventData)
            return;
        root.event = eventData;
        root.formDate = H.startOfDay(eventData.startDate);
        root.formAllDay = CalendarService.isAllDayEvent(eventData);
        root.formStartMinutes = eventData.startDate.getHours() * 60 + eventData.startDate.getMinutes();
        root.formEndMinutes = eventData.endDate.getHours() * 60 + eventData.endDate.getMinutes();
        if (root.formEndMinutes <= root.formStartMinutes)
            root.formEndMinutes = Math.min(24 * 60, root.formStartMinutes + 60);
        titleInput.text = eventData.content ?? "";
        notesInput.text = eventData.description ?? "";
        linkInput.text = eventData.url ?? "";
        locationInput.text = eventData.location ?? "";
        categoryInput.text = "";
        root.formCalendar = eventData.calendar ?? CalendarService.defaultCalendar;
        root.formStatus = eventData.status ?? "CONFIRMED";
        root.formColorToken = eventData.colorToken ?? "";
        root.formCategories = eventData.categories ?? [];
        root.formRepeat = root.eventDetails?.recurrence?.freq ?? (eventData.repeatSymbol ? "WEEKLY" : "");
        root.formRepeatUntil = root.eventDetails?.recurrence?.until ?? "";
        root.formRepeatByDay = root.eventDetails?.recurrence?.byDay ?? [];
        root.formAlarms = (root.eventDetails?.alarms ?? []).map(alarm => String(alarm.minutesBefore));
        CalendarService.readEvent(eventData.uid, reply => {
            if (!reply?.ok) return;
            root.eventDetails = reply.event;
            root.formRepeat = reply.event.recurrence?.freq ?? "";
            root.formRepeatUntil = reply.event.recurrence?.until ?? "";
            root.formRepeatByDay = reply.event.recurrence?.byDay ?? [];
            root.formColorToken = reply.event.color ?? "";
            root.formCategories = reply.event.categories ?? [];
            root.formAlarms = (reply.event.alarms ?? []).map(alarm => String(alarm.minutesBefore));
        });
        root.setMode("edit");
    }

    function close() {
        // Backing out of the scope page must not leave a mutation armed for the
        // next event the rail opens.
        root.pendingPayload = null;
        root.pendingMutationFields = null;
        root.pendingMoveDate = null;
        root.pendingAction = "";
        if (root.sportsEvent)
            SportsService.clearFocusedGame(root.event?.id);
        root.setMode("");
        root.closeRequested();
    }

    /** Fade the outgoing page, swap, slide the incoming one in from the right. */
    function setMode(next) {
        if (next === root.mode)
            return;
        root.mode = next;
        if (next === "")
            return;
        pageAnim.stop();
        root.pageShift = 28;
        root.pageOpacity = 0;
        pageAnim.start();
    }

    property real pageShift: 0
    property real pageOpacity: 1

    ParallelAnimation {
        id: pageAnim

        NumberAnimation {
            target: root
            property: "pageShift"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }

        NumberAnimation {
            target: root
            property: "pageOpacity"
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    // ─── Picker results ───
    function applyPickedTime(which, pickedHour, pickedMinute) {
        const value = Math.max(0, Math.min(24 * 60, pickedHour * 60 + pickedMinute));
        if (which === "start") {
            const span = Math.max(15, root.formEndMinutes - root.formStartMinutes);
            root.formStartMinutes = value;
            root.formEndMinutes = Math.min(24 * 60, value + span);
            return;
        }
        root.formEndMinutes = value;
    }

    function applyPickedDate(purpose, date) {
        if (purpose === "reschedule") {
            root.requestMove(root.event, date);
            return;
        }
        if (purpose === "repeatUntil") {
            root.formRepeatUntil = Qt.formatDate(H.startOfDay(date), "yyyy-MM-dd");
            return;
        }
        root.formDate = H.startOfDay(date);
    }

    function defaultRepeatDay(date = root.formDate) {
        return ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][date.getDay()];
    }

    function selectRepeat(freq) {
        root.formRepeat = freq;
        if (freq === "WEEKLY" && root.formRepeatByDay.length === 0)
            root.formRepeatByDay = [root.defaultRepeatDay()];
        if (freq !== "WEEKLY")
            root.formRepeatByDay = [];
    }

    function toggleRepeatDay(day) {
        const next = root.formRepeatByDay.slice();
        const index = next.indexOf(day);
        if (index >= 0)
            next.splice(index, 1);
        else
            next.push(day);
        root.formRepeatByDay = next;
    }

    function addCategory() {
        const category = categoryInput.text.trim();
        if (!category || category.startsWith("ii/color=") || root.formCategories.includes(category))
            return;
        root.formCategories = root.formCategories.concat([category]);
        categoryInput.text = "";
    }

    function removeCategory(category) {
        root.formCategories = root.formCategories.filter(item => item !== category);
    }

    function setDuration(minutes) {
        root.formAllDay = false;
        root.formEndMinutes = Math.min(24 * 60, root.formStartMinutes + minutes);
    }

    function submit() {
        if (!root.canSave)
            return;
        if (root.mode === "create" && root.createKind === "task") {
            root.taskCreateRequested({
                content: root.formTitle.trim(),
                date: H.startOfDay(root.formDate),
                dueDate: Qt.formatDate(root.formDate, "yyyy-MM-dd"),
                hasDate: true,
                done: false
            });
            root.close();
            return;
        }
        const payload = {
            editMode: root.mode === "edit",
            event: root.event,
            date: root.formDate,
            title: root.formTitle.trim(),
            description: root.formDescription.trim(),
            allDay: root.formAllDay,
            start: H.minutesToKhalTimeStr(root.formStartMinutes),
            end: H.minutesToKhalTimeStr(root.formEndMinutes),
            url: root.formUrl.trim(), location: root.formLocation.trim(), calendar: root.formCalendar,
            status: root.formStatus,
            color: root.formColorToken,
            categories: root.formCategories,
            recurrence: root.formRepeat ? {
                freq: root.formRepeat,
                interval: 1,
                byDay: root.formRepeat === "WEEKLY" ? root.formRepeatByDay : [],
                until: root.formRepeatUntil || null
            } : null,
            alarms: root.formAlarms.map(minutes => ({ minutesBefore: Number(minutes), action: "DISPLAY" }))
        };
        if (payload.editMode && (root.eventDetails?.recurrence || root.event?.repeatSymbol)) {
            root.pendingPayload = payload;
            root.pendingAction = "save";
            root.setMode("scope");
            return;
        }
        root.saveRequested(payload);
        root.close();
    }

    function requestDelete() {
        if (root.eventDetails?.recurrence || root.event?.repeatSymbol) {
            root.pendingAction = "delete";
            root.pendingPayload = null;
            root.setMode("scope");
            return;
        }
        root.deleteRequested(root.event, "all");
        root.close();
    }

    function chooseScope(scope) {
        if (root.pendingAction === "delete") root.deleteRequested(root.event, scope);
        else if (root.pendingMoveDate) root.moveRequested(root.event, root.pendingMoveDate, scope);
        else if (root.pendingMutationFields) root.eventFieldsMutationRequested(root.event, root.pendingMutationFields, scope);
        else if (root.pendingPayload) { root.pendingPayload.scope = scope; root.saveRequested(root.pendingPayload); }
        root.pendingPayload = null;
        root.pendingMutationFields = null;
        root.pendingMoveDate = null;
        root.pendingAction = "";
        root.close();
    }

    // ─── Derived ───
    readonly property var dayCalendarEvents: CalendarService.eventsByDay[H.dayKeyOf(root.day)] ?? []
    readonly property var dayBirthdays: BirthdaysService.birthdaysForDate(root.day)
    readonly property var daySports: SportsService.gamesForDate(root.day)
    readonly property var dayEvents: root.sportsListOnly ? root.daySports : root.dayCalendarEvents.concat(root.dayBirthdays, root.daySports)
    readonly property var dayHolidays: (Config.options.calendar.holidays.enable && Config.options.calendar.holidays.showInMonthView) ? (Holidays.byDayKey[H.dayKeyOf(root.day)] ?? []) : []
    readonly property color accent: (root.sportsEvent || root.birthdayEvent)
        ? Appearance.colors.colTertiary
        : (root.event ? H.chipColor(root.event, Appearance.colors, GoogleCalendarService.colorForEvent(root.event)) : Appearance.colors.colPrimary)
    readonly property bool isDayToday: H.sameDate(root.day, DateTime.clock.date)

    readonly property bool eventAllDay: root.birthdayEvent || (root.event ? CalendarService.isAllDayEvent(root.event) : false)
    readonly property bool eventReadOnly: root.event?.readOnly === true
    readonly property int eventStartMinutes: root.event ? root.event.startDate.getHours() * 60 + root.event.startDate.getMinutes() : 0
    readonly property int eventEndMinutes: root.event ? root.event.endDate.getHours() * 60 + root.event.endDate.getMinutes() : 0

    readonly property string headerTitle: {
        switch (root.mode) {
        case "create":
            return Translation.tr("New event");
        case "edit":
            return Translation.tr("Edit event");
        case "details":
            if (root.sportsEvent) return Translation.tr("Match details");
            if (root.birthdayEvent) return Translation.tr("Birthday details");
            return Translation.tr("Event details");
        case "scope":
            if (root.pendingAction === "delete") return Translation.tr("Delete recurring event");
            if (root.pendingAction === "move") return Translation.tr("Move recurring event");
            if (root.pendingAction === "resize") return Translation.tr("Resize recurring event");
            return Translation.tr("Edit recurring event");
        case "sources":
            return Translation.tr("Calendar sources");
        default:
            return root.sportsListOnly ? Translation.tr("Sports") : Qt.formatDate(root.day, "MMMM yyyy");
        }
    }

    function timeLabel(minutes) {
        return H.minutesToTimeStr(minutes, Config.options?.time.format);
    }

    function durationLabel(minutes) {
        const total = Math.max(0, minutes);
        const hours = Math.floor(total / 60);
        const rest = total % 60;
        if (hours === 0)
            return Translation.tr("%1 min").arg(String(rest));
        if (rest === 0)
            return Translation.tr("%1 h").arg(String(hours));
        return Translation.tr("%1 h %2 min").arg(String(hours)).arg(String(rest));
    }

    // ─── Surface ───
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // ─── Header ───
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    text: root.headerTitle
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                RippleButton {
                    id: backToDetails
                    visible: !root.detailsOnly && root.mode === "details" && (root.sportsListOnly ? root.daySports.length > 0 : root.dayEvents.length > 1)
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.sportsListOnly ? root.showSportsDay(root.day) : root.showDay(root.day)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "list"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip {
                        extraVisibleCondition: backToDetails.hovered
                        text: root.sportsListOnly ? Translation.tr("Sports") : Translation.tr("All events this day")
                    }
                }

                RippleButton {
                    id: deleteButton
                    visible: (root.mode === "details" || root.mode === "edit") && !root.eventReadOnly
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colErrorContainer
                    onClicked: root.requestDelete()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.larger
                        color: deleteButton.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colError
                    }

                    StyledToolTip {
                        extraVisibleCondition: deleteButton.hovered
                        text: Translation.tr("Delete event")
                    }
                }

                RippleButton {
                    id: focusButton
                    visible: root.mode === "details" && !root.sportsEvent
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.focusOnEvent()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "timer"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip {
                        extraVisibleCondition: focusButton.hovered
                        text: Translation.tr("Start a countdown for the time left in this event")
                    }
                }

                RippleButton {
                    id: noteButton
                    readonly property bool hasNote: root.attachedNoteIndex() >= 0
                    visible: root.mode === "details" && !root.sportsEvent && !root.birthdayEvent
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: noteButton.hasNote ? root.openAttachedNote() : root.attachNote()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: noteButton.hasNote ? "description" : "note_add"
                        iconSize: Appearance.font.pixelSize.larger
                        color: noteButton.hasNote ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip {
                        extraVisibleCondition: noteButton.hovered
                        text: noteButton.hasNote ? Translation.tr("Open attached note") : Translation.tr("Attach a note to this event")
                    }
                }

                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.close()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            // ─── Pages ───
            Item {
                id: pageHost
                Layout.fillWidth: true
                Layout.fillHeight: true

                opacity: root.pageOpacity
                transform: Translate {
                    x: root.pageShift
                }

                // ══ Day ══
                Item {
                    anchors.fill: parent
                    visible: root.mode === "day"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 62
                                Layout.preferredHeight: 62
                                radius: Appearance.rounding.normal
                                color: root.isDayToday ? Appearance.colors.colPrimary : Appearance.m3colors.m3surfaceContainerHighest

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: -4

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Qt.formatDate(root.day, "ddd").toUpperCase()
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                        color: root.isDayToday ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: String(root.day.getDate())
                                        font.family: Appearance.font.family.numbers
                                        font.pixelSize: 30
                                        font.weight: Font.Bold
                                        color: root.isDayToday ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.sportsListOnly
                                        ? Translation.tr("Sports") + " · " + String(root.daySports.length)
                                        : (root.dayEvents.length === 0 ? Translation.tr("Nothing scheduled") : Translation.tr("%1 event(s)").arg(String(root.dayEvents.length)))
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Qt.formatDate(root.day, "dddd, d MMMM")
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        DayBriefingCard {
                            visible: !root.sportsListOnly && H.sameDate(root.day, DateTime.clock.date)
                            day: root.day
                            Layout.fillWidth: true
                        }

                        Repeater {
                            model: root.sportsListOnly ? [] : root.dayHolidays

                            delegate: Rectangle {
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colTertiaryContainer

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "celebration"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colOnTertiaryContainer
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.localName || modelData.name || ""
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnTertiaryContainer
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        StyledFlickable {
                            id: dayList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.dayEvents.length > 0
                            clip: true
                            contentWidth: width
                            contentHeight: daySections.implicitHeight

                            ColumnLayout {
                                id: daySections
                                width: dayList.width
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    visible: !root.sportsListOnly && root.dayCalendarEvents.length > 0
                                    text: Translation.tr("Appointments").toUpperCase()
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurfaceVariant
                                }

                                Repeater {
                                    model: root.sportsListOnly ? [] : root.dayCalendarEvents

                                    delegate: MonthDayEventRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        eventData: modelData
                                        onActivated: root.showEvent(modelData)
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 12
                                    visible: !root.sportsListOnly && root.dayCalendarEvents.length > 0 && root.dayBirthdays.length > 0
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: !root.sportsListOnly && root.dayBirthdays.length > 0
                                    text: Translation.tr("Birthdays").toUpperCase()
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colTertiary
                                }

                                Repeater {
                                    model: root.sportsListOnly ? [] : root.dayBirthdays

                                    delegate: BirthdayChip {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 40
                                        birthdayData: modelData
                                        compact: false
                                        onActivated: birthday => root.showEvent(birthday)
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 12
                                    visible: !root.sportsListOnly && root.daySports.length > 0
                                        && (root.dayCalendarEvents.length > 0 || root.dayBirthdays.length > 0)
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.daySports.length > 0
                                    text: Translation.tr("Sports").toUpperCase()
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colTertiary
                                }

                                Repeater {
                                    model: root.daySports

                                    delegate: MonthDayEventRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        eventData: modelData
                                        onActivated: root.showEvent(modelData)
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.dayEvents.length === 0

                            PagePlaceholder {
                                icon: root.sportsListOnly ? "sports_score" : "event_available"
                                shape: "Cookie9Sided"
                                title: root.sportsListOnly ? Translation.tr("Sports") : Translation.tr("Free day")
                                description: Translation.tr("Nothing here yet")
                                titlePixelSize: Appearance.font.pixelSize.normal
                                descriptionPixelSize: Appearance.font.pixelSize.smallie
                                iconSize: 32
                                iconPadding: 9
                            }
                        }

                        PrimaryAction {
                            visible: !root.sportsListOnly
                            label: Translation.tr("New event")
                            symbol: "add"
                            onTriggered: root.startCreate(root.day)
                        }
                    }
                }

                // ══ Tasks with no date ══
                Item {
                    anchors.fill: parent
                    visible: root.mode === "tasks"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 62
                                Layout.preferredHeight: 62
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colSecondaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "checklist"
                                    iconSize: 32
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("No date")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.undatedTasks.length === 0
                                        ? Translation.tr("Nothing left over")
                                        : Translation.tr("%1 task(s) waiting for a day").arg(String(root.undatedTasks.length))
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        StyledFlickable {
                            id: undatedList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: width
                            contentHeight: undatedColumn.implicitHeight

                            ColumnLayout {
                                id: undatedColumn
                                width: undatedList.width
                                spacing: 4

                                Repeater {
                                    model: root.undatedTasks

                                    delegate: TaskChip {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 42
                                        taskData: modelData
                                        onCompletionRequested: task => root.taskCompletionRequested(task)
                                    }
                                }
                            }
                        }

                        PrimaryAction {
                            label: Translation.tr("New task")
                            symbol: "add_task"
                            onTriggered: root.startCreateTask(root.day)
                        }
                    }
                }

                // ══ Calendar sources ══
                Item {
                    anchors.fill: parent
                    visible: root.mode === "sources"

                    StyledFlickable {
                        anchors.fill: parent
                        clip: true
                        contentWidth: width
                        contentHeight: sourcesColumn.implicitHeight

                        ColumnLayout {
                            id: sourcesColumn
                            width: parent.width
                            spacing: 12

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Import local files or add read-only ICS links.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.Wrap
                            }

                            GoogleCalendarSetupGuide {
                                Layout.fillWidth: true
                            }

                            ConfigSwitch {
                                Layout.fillWidth: true
                                buttonIcon: "calendar_add_on"
                                text: Translation.tr("Enable calendar sources")
                                checked: Config.options.calendar.timetable.imports.enable
                                onCheckedChanged: Config.options.calendar.timetable.imports.enable = checked
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("When disabled, saved links are disconnected and local imports cannot modify your calendar.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                opacity: root.calendarSourcesEnabled ? 1 : 0.7
                                wrapMode: Text.Wrap
                            }

                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                centerContent: true
                                materialIcon: "upload_file"
                                mainText: Translation.tr("Import ICS file")
                                enabled: root.calendarSourcesEnabled && CalendarService.khalAvailable
                                colText: Appearance.colors.colOnPrimaryContainer
                                colBackground: Appearance.colors.colPrimaryContainer
                                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                colRipple: Appearance.colors.colPrimaryContainerActive
                                onClicked: CalendarIcsFileImport.open()
                            }

                            ConfigTextField {
                                id: sourceSubscriptionInput
                                Layout.fillWidth: true
                                enabled: root.calendarSourcesEnabled
                                icon: "link"
                                text: Translation.tr("Calendar ICS URL")
                                placeholderText: "https://…/calendar.ics"
                                inputText: root.sourceUrlDraft
                                textField.onTextChanged: root.sourceUrlDraft = textField.text
                                textField.onAccepted: root.addSourceSubscription()
                            }

                            RippleButtonWithIcon {
                                Layout.alignment: Qt.AlignRight
                                implicitHeight: 40
                                centerContent: true
                                materialIcon: "add"
                                mainText: Translation.tr("Add URL")
                                enabled: root.calendarSourcesEnabled && !CalendarSubscriptions.applying && root.sourceUrlDraft.trim().length > 0
                                colText: Appearance.colors.colOnPrimaryContainer
                                colBackground: Appearance.colors.colPrimaryContainer
                                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                colRipple: Appearance.colors.colPrimaryContainerActive
                                onClicked: root.addSourceSubscription()
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.sourcesStatusText.length > 0 || CalendarSubscriptions.lastError.length > 0 || CalendarIcsFileImport.lastStatus.length > 0
                                text: CalendarSubscriptions.lastError.length > 0
                                    ? CalendarSubscriptions.lastError
                                    : (CalendarIcsFileImport.lastStatus.length > 0 ? CalendarIcsFileImport.lastStatus : root.sourcesStatusText)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: CalendarSubscriptions.lastError.length > 0 ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.Wrap
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: CalendarSubscriptions.applying
                                    ? Translation.tr("Updating calendar configuration…")
                                    : (CalendarSubscriptions.syncInProgress
                                        ? Translation.tr("Synchronizing subscribed calendars…")
                                        : Translation.tr("Links are always read-only."))
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.Wrap
                            }

                            ConfigSwitch {
                                Layout.fillWidth: true
                                enabled: root.calendarSourcesEnabled
                                buttonIcon: "mail"
                                text: Translation.tr("Import ICS attachments from Gmail")
                                checked: Config.options.calendar.timetable.imports.gmailIcs.enable
                                onCheckedChanged: Config.options.calendar.timetable.imports.gmailIcs.enable = checked
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Checks calendar attachments in the active Gmail account and remembers each imported attachment.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                opacity: root.gmailIcsEnabled ? 1 : 0.7
                                wrapMode: Text.Wrap
                            }

                            RippleButtonWithIcon {
                                Layout.alignment: Qt.AlignRight
                                implicitHeight: 40
                                centerContent: true
                                materialIcon: GmailCalendarImport.scanning ? "sync" : "refresh"
                                mainText: GmailCalendarImport.scanning ? Translation.tr("Checking Gmail…") : Translation.tr("Check Gmail now")
                                enabled: root.calendarSourcesEnabled && root.gmailIcsEnabled
                                    && EmailService.authenticated && !GmailCalendarImport.scanning
                                colText: Appearance.colors.colOnSecondaryContainer
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                colRipple: Appearance.colors.colSecondaryContainerActive
                                onClicked: GmailCalendarImport.scanNow()
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: GmailCalendarImport.lastStatus.length > 0 || GmailCalendarImport.lastError.length > 0
                                text: GmailCalendarImport.lastError.length > 0 ? GmailCalendarImport.lastError : GmailCalendarImport.lastStatus
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: GmailCalendarImport.lastError.length > 0 ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.Wrap
                            }

                            ConfigSwitch {
                                Layout.fillWidth: true
                                enabled: root.calendarSourcesEnabled
                                buttonIcon: "event_available"
                                text: Translation.tr("Sync Outlook calendar")
                                checked: Config.options.calendar.timetable.imports.outlook.enable
                                onCheckedChanged: Config.options.calendar.timetable.imports.outlook.enable = checked
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Mirrors Outlook events into a local read-only calendar. Microsoft access is used only for calendar and ICS attachment reading.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                opacity: root.outlookEnabled ? 1 : 0.7
                                wrapMode: Text.Wrap
                            }

                            ConfigTextField {
                                id: outlookClientIdInput
                                Layout.fillWidth: true
                                visible: root.outlookEnabled && !OutlookService.deviceFlowActive
                                enabled: root.calendarSourcesEnabled && !OutlookService.authenticating
                                icon: "key"
                                text: Translation.tr("Microsoft application (client) ID")
                                placeholderText: Translation.tr("Paste the public client ID from Microsoft Entra")
                                inputText: root.outlookClientIdDraft
                                textField.onTextChanged: root.outlookClientIdDraft = textField.text
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.outlookEnabled && !OutlookService.deviceFlowActive
                                spacing: 8

                                RippleButtonWithIcon {
                                    Layout.fillWidth: true
                                    implicitHeight: 40
                                    centerContent: true
                                    materialIcon: OutlookService.authenticated ? "person_add" : "login"
                                    mainText: OutlookService.authenticated ? Translation.tr("Reconnect Outlook") : Translation.tr("Connect Outlook")
                                    enabled: root.calendarSourcesEnabled && !OutlookService.authenticating && root.outlookClientIdDraft.trim().length > 0
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
                                    enabled: root.calendarSourcesEnabled && !OutlookCalendarImport.syncing
                                    colText: Appearance.colors.colOnErrorContainer
                                    colBackground: Appearance.colors.colErrorContainer
                                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                                    colRipple: Appearance.colors.colErrorContainerActive
                                    onClicked: OutlookService.disconnect()
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.outlookEnabled && OutlookService.deviceFlowActive
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: OutlookService.deviceMessage || Translation.tr("Open Microsoft sign-in and enter this code:")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSurfaceVariant
                                    wrapMode: Text.Wrap
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

                            RippleButtonWithIcon {
                                Layout.alignment: Qt.AlignRight
                                implicitHeight: 40
                                visible: root.outlookEnabled && OutlookService.authenticated && !OutlookService.deviceFlowActive
                                centerContent: true
                                materialIcon: OutlookCalendarImport.syncing ? "sync" : "refresh"
                                mainText: OutlookCalendarImport.syncing ? Translation.tr("Synchronizing Outlook…") : Translation.tr("Sync Outlook now")
                                enabled: root.calendarSourcesEnabled && !OutlookCalendarImport.syncing
                                colText: Appearance.colors.colOnSecondaryContainer
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                colRipple: Appearance.colors.colSecondaryContainerActive
                                onClicked: OutlookCalendarImport.syncNow()
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: OutlookService.lastError.length > 0 || OutlookCalendarImport.lastStatus.length > 0 || OutlookCalendarImport.lastError.length > 0
                                text: OutlookService.lastError.length > 0
                                    ? OutlookService.lastError
                                    : (OutlookCalendarImport.lastError.length > 0 ? OutlookCalendarImport.lastError : OutlookCalendarImport.lastStatus)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: OutlookService.lastError.length > 0 || OutlookCalendarImport.lastError.length > 0
                                    ? Appearance.colors.colError
                                    : Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.Wrap
                            }

                            ConfigSwitch {
                                Layout.fillWidth: true
                                visible: root.outlookEnabled
                                enabled: root.calendarSourcesEnabled
                                buttonIcon: "attach_email"
                                text: Translation.tr("Import ICS attachments from Outlook")
                                checked: Config.options.calendar.timetable.imports.outlook.icsAttachments.enable
                                onCheckedChanged: Config.options.calendar.timetable.imports.outlook.icsAttachments.enable = checked
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.outlookEnabled
                                text: Translation.tr("Checks only bounded .ics and calendar attachments in the connected Outlook mailbox, then remembers each successful import.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                opacity: root.outlookIcsEnabled ? 1 : 0.7
                                wrapMode: Text.Wrap
                            }

                            RippleButtonWithIcon {
                                Layout.alignment: Qt.AlignRight
                                implicitHeight: 40
                                visible: root.outlookEnabled && OutlookService.authenticated
                                centerContent: true
                                materialIcon: OutlookIcsImport.scanning ? "sync" : "refresh"
                                mainText: OutlookIcsImport.scanning ? Translation.tr("Checking Outlook…") : Translation.tr("Check Outlook attachments")
                                enabled: root.calendarSourcesEnabled && root.outlookIcsEnabled && !OutlookIcsImport.scanning
                                colText: Appearance.colors.colOnSecondaryContainer
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                colRipple: Appearance.colors.colSecondaryContainerActive
                                onClicked: OutlookIcsImport.scanNow()
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.outlookEnabled && (OutlookIcsImport.lastStatus.length > 0 || OutlookIcsImport.lastError.length > 0)
                                text: OutlookIcsImport.lastError.length > 0 ? OutlookIcsImport.lastError : OutlookIcsImport.lastStatus
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: OutlookIcsImport.lastError.length > 0 ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.Wrap
                            }

                            Repeater {
                                model: Config.options.calendar.timetable.subscriptions

                                delegate: Rectangle {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: Appearance.rounding.normal
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
                                            id: removeSourceSubscriptionButton
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
                                                color: removeSourceSubscriptionButton.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ══ Details ══
                Item {
                    anchors.fill: parent
                    visible: root.mode === "details"

                    StyledFlickable {
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            bottom: root.eventReadOnly ? parent.bottom : detailsActions.top
                            bottomMargin: root.eventReadOnly ? 0 : 12
                        }
                        clip: true
                        contentWidth: width
                        contentHeight: detailsColumn.implicitHeight

                        ColumnLayout {
                            id: detailsColumn
                            width: parent.width
                            spacing: 12

                            SportsEventDetails {
                                Layout.fillWidth: true
                                visible: root.sportsEvent
                                game: root.sportsGame
                                details: root.sportsDetails
                                loading: root.sportsDetailsLoading
                                error: root.sportsDetailsError
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.birthdayEvent
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    MaterialShapeWrappedMaterialSymbol {
                                        text: "cake"
                                        iconSize: Appearance.font.pixelSize.huge
                                        padding: Appearance.rounding.small
                                        shape: MaterialShape.Shape.Clover4Leaf
                                        color: Appearance.colors.colTertiary
                                        colSymbol: Appearance.colors.colOnTertiary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.event?.content ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.huge
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSurface
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }
                                }

                                InfoRow {
                                    Layout.fillWidth: true
                                    symbol: "cake"
                                    caption: Translation.tr("Birthday")
                                    value: Qt.formatDate(root.event?.startDate ?? root.day, "d MMMM")
                                }

                                InfoRow {
                                    Layout.fillWidth: true
                                    visible: Number(root.event?.age ?? -1) >= 0
                                    symbol: "celebration"
                                    caption: Translation.tr("Turning")
                                    value: Translation.tr("%1 years old").arg(String(root.event?.age ?? ""))
                                }

                                RippleButtonWithIcon {
                                    readonly property var contact: PhoneContactsService.contactById(root.event?.contactId ?? "")
                                    readonly property string phoneNumber: contact?.phones?.[0]?.value ?? ""
                                    Layout.fillWidth: true
                                    visible: phoneNumber.length > 0
                                    implicitHeight: 40
                                    buttonRadius: Appearance.rounding.full
                                    centerContent: true
                                    materialIcon: "contact_phone"
                                    mainText: Translation.tr("Contact %1").arg(root.event?.contactName ?? "")
                                    colText: Appearance.colors.colOnSecondaryContainer
                                    colBackground: Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                    onClicked: PhoneContactsService.openDialer(phoneNumber)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !root.sportsEvent && !root.birthdayEvent
                                spacing: 12

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                MaterialShapeWrappedMaterialSymbol {
                                    text: "event"
                                    iconSize: 26
                                    padding: 11
                                    shape: MaterialShape.Shape.Clover4Leaf
                                    color: root.accent
                                    colSymbol: ColorUtils.getContrastingTextColor(root.accent)
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.event?.content ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                InfoChip {
                                    visible: root.eventReadOnly
                                    symbol: "lock"
                                    label: Translation.tr("Read-only")
                                }

                                InfoChip {
                                    symbol: "calendar_month"
                                    label: Qt.formatDate(root.event?.startDate ?? root.day, "ddd, d MMM yyyy")
                                }

                                InfoChip {
                                    symbol: "schedule"
                                    label: root.eventAllDay ? Translation.tr("All day") : root.timeLabel(root.eventStartMinutes) + " – " + root.timeLabel(root.eventEndMinutes)
                                }

                                InfoChip {
                                    visible: !root.eventAllDay
                                    symbol: "timelapse"
                                    label: root.durationLabel(root.eventEndMinutes - root.eventStartMinutes)
                                }
                            }

                            InfoRow {
                                Layout.fillWidth: true
                                visible: (root.event?.calendar ?? "").length > 0
                                symbol: "folder"
                                caption: Translation.tr("Calendar")
                                value: root.event?.calendar ?? ""
                            }

                            InfoRow { Layout.fillWidth: true; visible: (root.event?.location ?? "").length > 0; symbol: "place"; caption: Translation.tr("Location"); value: root.event?.location ?? "" }
                            InfoRow { Layout.fillWidth: true; visible: (root.event?.url ?? "").length > 0; symbol: "link"; caption: Translation.tr("Link"); value: root.event?.url ?? ""; multiline: true }
                            InfoRow { Layout.fillWidth: true; visible: (root.event?.status ?? "").length > 0; symbol: "task_alt"; caption: Translation.tr("Status"); value: root.event?.status ?? "" }
                            Flow {
                                Layout.fillWidth: true
                                visible: (root.event?.categories?.length ?? 0) > 0
                                spacing: 6
                                Repeater {
                                    model: root.event?.categories ?? []
                                    delegate: InfoChip {
                                        required property string modelData
                                        symbol: "label"
                                        label: modelData
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: (root.eventDetails?.exdates?.length ?? 0) > 0
                                spacing: 6

                                RippleButtonWithIcon {
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    buttonRadius: Appearance.rounding.full
                                    centerContent: true
                                    materialIcon: root.showExceptions ? "expand_less" : "expand_more"
                                    mainText: Translation.tr("%1 exceptions").arg(String(root.eventDetails?.exdates?.length ?? 0))
                                    colText: Appearance.colors.colOnErrorContainer
                                    colBackground: Appearance.colors.colErrorContainer
                                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                                    onClicked: root.showExceptions = !root.showExceptions
                                }

                                Repeater {
                                    model: root.showExceptions ? (root.eventDetails?.exdates ?? []) : []

                                    delegate: RippleButtonWithIcon {
                                        Layout.fillWidth: true
                                        implicitHeight: 40
                                        buttonRadius: Appearance.rounding.normal
                                        centerContent: true
                                        materialIcon: "event_available"
                                        mainText: Translation.tr("Restore %1").arg(root.exceptionLabel(modelData))
                                        colText: Appearance.colors.colOnSecondaryContainer
                                        colBackground: Appearance.colors.colSecondaryContainer
                                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                        onClicked: root.restoreException(modelData)
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: Boolean(root.eventDetails?.recurrence || root.event?.repeatSymbol)
                                    && root.upcomingOccurrences.length > 0
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Next occurrences")
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                }

                                Repeater {
                                    model: root.upcomingOccurrences

                                    delegate: InfoChip {
                                        required property var modelData
                                        symbol: "event_repeat"
                                        label: root.occurrenceLabel(modelData)
                                    }
                                }
                            }
                            InfoRow { Layout.fillWidth: true; visible: (root.eventDetails?.organizer ?? "").length > 0; symbol: "person"; caption: Translation.tr("Organizer"); value: root.eventDetails?.organizer ?? "" }
                            InfoRow { Layout.fillWidth: true; visible: (root.eventDetails?.attendees?.length ?? 0) > 0; symbol: "group"; caption: Translation.tr("Guests"); value: (root.eventDetails?.attendees ?? []).join(", "); multiline: true }

                            InfoRow {
                                Layout.fillWidth: true
                                visible: (root.event?.description ?? "").length > 0
                                symbol: "notes"
                                caption: Translation.tr("Notes")
                                value: root.event?.description ?? ""
                                multiline: true
                            }

                            // Writing back to Google needs the API's own event
                            // id, which only the colour scan carries — so this
                            // appears exactly for events that scan reached.
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.googleColorAvailable
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Google colour")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurfaceVariant
                                }

                                ColorPickerRow {
                                    Layout.fillWidth: true
                                    googleMode: true
                                    currentColorId: root.googleColorId
                                    onGoogleColorSelected: colorId => GoogleCalendarService.setEventColor(root.event?.uid ?? "", colorId)
                                }
                            }
                            }
                        }
                    }

                    ColumnLayout {
                        id: detailsActions
                        visible: !root.eventReadOnly
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        spacing: 8

                        SecondaryAction {
                            label: Translation.tr("Reschedule")
                            symbol: "event_repeat"
                            onTriggered: root.datePickerRequested("reschedule", root.event?.startDate ?? root.day)
                        }

                        PrimaryAction {
                            label: Translation.tr("Edit event")
                            symbol: "edit"
                            onTriggered: root.startEdit(root.event)
                        }
                    }
                }

                // ══ Editor ══
                Item {
                    anchors.fill: parent
                    visible: root.editing

                    StyledFlickable {
                        id: editorFlick
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            bottom: editorActions.top
                            bottomMargin: 12
                        }
                        clip: true
                        contentWidth: width
                        contentHeight: editorColumn.implicitHeight

                        ColumnLayout {
                            id: editorColumn
                            width: editorFlick.width
                            spacing: 10

                            // Title
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 66
                                radius: Appearance.rounding.small
                                color: Appearance.m3colors.m3surfaceContainerHighest

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    MaterialShapeWrappedMaterialSymbol {
                                        text: "title"
                                        iconSize: 18
                                        padding: 9
                                        shape: MaterialShape.Shape.Cookie7Sided
                                        color: Appearance.colors.colPrimaryContainer
                                        colSymbol: Appearance.colors.colOnPrimaryContainer
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr("Title")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }

                                        StyledTextInput {
                                            id: titleInput
                                            Layout.fillWidth: true
                                            clip: true
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnSurface
                                            onTextChanged: root.formTitle = text
                                            onAccepted: root.submit()
                                            Keys.onEscapePressed: root.close()

                                            StyledText {
                                                anchors.fill: parent
                                                visible: titleInput.text.length === 0
                                                verticalAlignment: Text.AlignVCenter
                                                text: Translation.tr("What is happening?")
                                                font.pixelSize: Appearance.font.pixelSize.normal
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }
                                        }
                                    }
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                visible: root.mode === "create"
                                spacing: 6

                                DurationChip {
                                    label: Translation.tr("Event")
                                    selected: root.createKind === "event"
                                    onTriggered: root.createKind = "event"
                                }

                                DurationChip {
                                    label: Translation.tr("Task")
                                    selected: root.createKind === "task"
                                    onTriggered: root.createKind = "task"
                                }
                            }

                            // All day
                            Rectangle {
                                id: allDayRow
                                visible: root.createKind === "event"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                radius: Appearance.rounding.small
                                color: root.formAllDay ? Appearance.colors.colSecondaryContainer : Appearance.m3colors.m3surfaceContainerHighest

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(allDayRow)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.formAllDay = !root.formAllDay
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    MaterialShapeWrappedMaterialSymbol {
                                        text: "brightness_5"
                                        iconSize: 18
                                        padding: 9
                                        shape: MaterialShape.Shape.Sunny
                                        color: root.formAllDay ? Appearance.colors.colTertiary : Appearance.colors.colPrimaryContainer
                                        colSymbol: root.formAllDay ? Appearance.colors.colOnTertiary : Appearance.colors.colOnPrimaryContainer
                                        rotation: root.formAllDay ? 30 : 0
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("All day")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: root.formAllDay ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledSwitch {
                                        checked: root.formAllDay
                                        onToggled: root.formAllDay = checked
                                    }
                                }
                            }

                            // Date
                            PickerRow {
                                Layout.fillWidth: true
                                symbol: "calendar_month"
                                shapeKind: MaterialShape.Shape.Cookie12Sided
                                caption: Translation.tr("Date")
                                value: Qt.formatDate(root.formDate, "dddd, d MMMM yyyy")
                                onTriggered: root.datePickerRequested("form", root.formDate)
                            }

                            // Times
                            RowLayout {
                                id: timeRow
                                visible: root.createKind === "event"
                                Layout.fillWidth: true
                                spacing: 8
                                opacity: root.formAllDay ? 0.35 : 1
                                enabled: !root.formAllDay

                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(timeRow)
                                }

                                TimeTile {
                                    Layout.fillWidth: true
                                    caption: Translation.tr("Starts")
                                    value: root.timeLabel(root.formStartMinutes)
                                    invalid: !root.rangeValid
                                    onTriggered: root.timePickerRequested("start", Math.floor(root.formStartMinutes / 60), root.formStartMinutes % 60)
                                }

                                TimeTile {
                                    Layout.fillWidth: true
                                    caption: Translation.tr("Ends")
                                    value: root.timeLabel(root.formEndMinutes)
                                    invalid: !root.rangeValid
                                    onTriggered: root.timePickerRequested("end", Math.floor(root.formEndMinutes / 60), root.formEndMinutes % 60)
                                }
                            }

                            // Quick durations
                            Flow {
                                id: durationFlow
                                visible: root.createKind === "event"
                                Layout.fillWidth: true
                                spacing: 6
                                opacity: root.formAllDay ? 0.35 : 1
                                enabled: !root.formAllDay

                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(durationFlow)
                                }

                                Repeater {
                                    model: [
                                        {
                                            "minutes": 30,
                                            "label": "30m"
                                        },
                                        {
                                            "minutes": 60,
                                            "label": "1h"
                                        },
                                        {
                                            "minutes": 90,
                                            "label": "1h30"
                                        },
                                        {
                                            "minutes": 120,
                                            "label": "2h"
                                        }
                                    ]

                                    delegate: DurationChip {
                                        required property var modelData

                                        label: modelData.label
                                        selected: root.formEndMinutes - root.formStartMinutes === modelData.minutes
                                        onTriggered: root.setDuration(modelData.minutes)
                                    }
                                }
                            }

                            // Native event metadata is kept inline with the editor so it
                            // remains usable without covering the month grid.
                            PickerRow {
                                Layout.fillWidth: true
                                visible: root.createKind === "event"
                                symbol: "folder"
                                caption: Translation.tr("Calendar")
                                value: root.formCalendar || Translation.tr("Default calendar")
                                onTriggered: root.showCalendarSelector = true
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.createKind === "event"
                                text: Translation.tr("Color")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            ColorPickerRow {
                                Layout.fillWidth: true
                                visible: root.createKind === "event"
                                currentToken: root.formColorToken
                                onTokenSelected: token => root.formColorToken = token
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.createKind === "event"
                                text: Translation.tr("Labels")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                visible: root.createKind === "event"
                                Layout.preferredHeight: 46
                                radius: Appearance.rounding.small
                                color: Appearance.m3colors.m3surfaceContainerHighest

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "label"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }

                                    StyledTextInput {
                                        id: categoryInput
                                        Layout.fillWidth: true
                                        color: Appearance.colors.colOnSurface
                                        Keys.onReturnPressed: root.addCategory()

                                        StyledText {
                                            anchors.fill: parent
                                            visible: categoryInput.text.length === 0
                                            verticalAlignment: Text.AlignVCenter
                                            text: Translation.tr("Add a label")
                                            color: Appearance.colors.colOnLayer1Inactive
                                        }
                                    }

                                    RippleButton {
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colPrimaryContainer
                                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                        enabled: categoryInput.text.trim().length > 0
                                        onClicked: root.addCategory()

                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "add"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                    }
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                visible: root.createKind === "event" && root.formCategories.length > 0
                                spacing: 6

                                Repeater {
                                    model: root.formCategories
                                    delegate: DurationChip {
                                        required property string modelData
                                        label: modelData
                                        selected: true
                                        onTriggered: root.removeCategory(modelData)
                                    }
                                }
                            }

                            Rectangle {
                                visible: root.createKind === "event"
                                Layout.fillWidth: true; Layout.preferredHeight: 66
                                radius: Appearance.rounding.small; color: Appearance.m3colors.m3surfaceContainerHighest
                                RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 10
                                    MaterialShapeWrappedMaterialSymbol { text: "link"; iconSize: 18; padding: 9; shape: MaterialShape.Shape.Cookie7Sided; color: Appearance.colors.colPrimaryContainer; colSymbol: Appearance.colors.colOnPrimaryContainer }
                                    StyledTextInput {
                                        id: linkInput
                                        Layout.fillWidth: true
                                        text: root.formUrl
                                        onTextChanged: root.formUrl = text
                                        color: Appearance.colors.colOnSurface

                                        StyledText {
                                            anchors.fill: parent
                                            visible: linkInput.text.length === 0
                                            verticalAlignment: Text.AlignVCenter
                                            text: Translation.tr("Add meeting link")
                                            color: Appearance.colors.colOnLayer1Inactive
                                        }
                                    }
                                    RippleButton { visible: EmailDetections.detectAll(root.formUrl).meetings.length > 0; implicitWidth: 34; implicitHeight: 34; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colPrimaryContainer; onClicked: Qt.openUrlExternally(root.formUrl); contentItem: MaterialSymbol { anchors.centerIn: parent; text: "video_call"; color: Appearance.colors.colOnPrimaryContainer } }
                                }
                            }

                            Rectangle {
                                visible: root.createKind === "event"
                                Layout.fillWidth: true; Layout.preferredHeight: 66
                                radius: Appearance.rounding.small; color: Appearance.m3colors.m3surfaceContainerHighest
                                RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 10
                                    MaterialShapeWrappedMaterialSymbol { text: "place"; iconSize: 18; padding: 9; shape: MaterialShape.Shape.Cookie7Sided; color: Appearance.colors.colPrimaryContainer; colSymbol: Appearance.colors.colOnPrimaryContainer }
                                    StyledTextInput {
                                        id: locationInput
                                        Layout.fillWidth: true
                                        text: root.formLocation
                                        onTextChanged: root.formLocation = text
                                        color: Appearance.colors.colOnSurface

                                        StyledText {
                                            anchors.fill: parent
                                            visible: locationInput.text.length === 0
                                            verticalAlignment: Text.AlignVCenter
                                            text: Translation.tr("Add location")
                                            color: Appearance.colors.colOnLayer1Inactive
                                        }
                                    }
                                    RippleButton { visible: root.formLocation.length > 0; implicitWidth: 34; implicitHeight: 34; buttonRadius: Appearance.rounding.full; colBackground: "transparent"; onClicked: Quickshell.execDetached(["xdg-open", "https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(root.formLocation)]); contentItem: MaterialSymbol { anchors.centerIn: parent; text: "map"; color: Appearance.colors.colPrimary } }
                                }
                            }

                            StyledText { Layout.fillWidth: true; visible: root.createKind === "event"; text: Translation.tr("Repeats"); font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.Bold; color: Appearance.colors.colOnSurfaceVariant }
                            Flow { Layout.fillWidth: true; visible: root.createKind === "event"; spacing: 6
                                Repeater { model: [["", Translation.tr("Never")], ["DAILY", Translation.tr("Daily")], ["WEEKLY", Translation.tr("Weekly")], ["MONTHLY", Translation.tr("Monthly")], ["YEARLY", Translation.tr("Yearly")]]
                                    delegate: DurationChip { required property var modelData; label: modelData[1]; selected: root.formRepeat === modelData[0]; onTriggered: root.selectRepeat(modelData[0]) }
                                }
                            }
                            Flow {
                                Layout.fillWidth: true
                                visible: root.createKind === "event" && root.formRepeat === "WEEKLY"
                                spacing: 6
                                Repeater {
                                    model: [["MO", Translation.tr("Mon")], ["TU", Translation.tr("Tue")], ["WE", Translation.tr("Wed")], ["TH", Translation.tr("Thu")], ["FR", Translation.tr("Fri")], ["SA", Translation.tr("Sat")], ["SU", Translation.tr("Sun")]]
                                    delegate: DurationChip {
                                        required property var modelData
                                        label: modelData[1]
                                        selected: root.formRepeatByDay.includes(modelData[0])
                                        onTriggered: root.toggleRepeatDay(modelData[0])
                                    }
                                }
                            }
                            PickerRow {
                                Layout.fillWidth: true
                                visible: root.createKind === "event" && root.formRepeat !== ""
                                symbol: "event_upcoming"
                                caption: Translation.tr("Repeats until")
                                value: root.formRepeatUntil ? Qt.formatDate(new Date(root.formRepeatUntil + "T00:00:00"), "dd MMM yyyy") : Translation.tr("No end date")
                                onTriggered: root.datePickerRequested("repeatUntil", root.formRepeatUntil ? new Date(root.formRepeatUntil + "T00:00:00") : root.formDate)
                            }
                            DurationChip {
                                visible: root.createKind === "event" && root.formRepeat !== "" && root.formRepeatUntil !== ""
                                label: Translation.tr("No end date")
                                selected: false
                                onTriggered: root.formRepeatUntil = ""
                            }
                            StyledText { Layout.fillWidth: true; visible: root.createKind === "event"; text: Translation.tr("Reminders"); font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.Bold; color: Appearance.colors.colOnSurfaceVariant }
                            Flow { Layout.fillWidth: true; visible: root.createKind === "event"; spacing: 6
                                Repeater { model: [["0", Translation.tr("At time")], ["5", "5m"], ["15", "15m"], ["60", "1h"], ["1440", "1d"]]
                                    delegate: DurationChip { required property var modelData; label: modelData[1]; selected: root.formAlarms.includes(modelData[0]); onTriggered: { const next = root.formAlarms.slice(); const index = next.indexOf(modelData[0]); if (index >= 0) next.splice(index, 1); else next.push(modelData[0]); root.formAlarms = next; } }
                                }
                            }
                            StyledText { Layout.fillWidth: true; visible: root.createKind === "event"; text: Translation.tr("Status"); font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.Bold; color: Appearance.colors.colOnSurfaceVariant }
                            Flow { Layout.fillWidth: true; visible: root.createKind === "event"; spacing: 6
                                Repeater { model: [["CONFIRMED", Translation.tr("Confirmed")], ["TENTATIVE", Translation.tr("Tentative")], ["CANCELLED", Translation.tr("Cancelled")]]
                                    delegate: DurationChip { required property var modelData; label: modelData[1]; selected: root.formStatus === modelData[0]; onTriggered: root.formStatus = modelData[0] }
                                }
                            }

                            // Notes
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 116
                                radius: Appearance.rounding.small
                                color: Appearance.m3colors.m3surfaceContainerHighest

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10

                                    MaterialShapeWrappedMaterialSymbol {
                                        Layout.alignment: Qt.AlignTop
                                        text: "notes"
                                        iconSize: 18
                                        padding: 9
                                        shape: MaterialShape.Shape.Pill
                                        color: Appearance.colors.colPrimaryContainer
                                        colSymbol: Appearance.colors.colOnPrimaryContainer
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr("Notes")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }

                                        StyledFlickable {
                                            id: notesFlick
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            contentWidth: width
                                            contentHeight: notesInput.implicitHeight

                                            StyledTextArea {
                                                id: notesInput
                                                width: notesFlick.width
                                                placeholderText: Translation.tr("Add details (optional)")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: Appearance.colors.colOnSurface
                                                wrapMode: TextEdit.Wrap
                                                padding: 0
                                                background: null
                                                onTextChanged: root.formDescription = text
                                                Keys.onEscapePressed: root.close()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: editorActions
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        spacing: 8

                        SecondaryAction {
                            label: Translation.tr("Cancel")
                            symbol: "close"
                            onTriggered: {
                                if (root.mode === "edit" && root.event)
                                    root.showEvent(root.event);
                                else
                                    root.close();
                            }
                        }

                        PrimaryAction {
                            label: root.mode === "edit" ? Translation.tr("Save changes") : (root.createKind === "task" ? Translation.tr("Create task") : Translation.tr("Create event"))
                            symbol: root.mode === "edit" ? "check" : (root.createKind === "task" ? "checklist" : "add")
                            enabled: root.canSave
                            onTriggered: root.submit()
                        }
                    }
                }

                // ══ Recurrence scope ══
                Item {
                    anchors.fill: parent
                    visible: root.mode === "scope"
                    ColumnLayout {
                        anchors.centerIn: parent; width: Math.min(parent.width, 300); spacing: 10
                        StyledText { Layout.fillWidth: true; text: root.headerTitle; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.Bold; wrapMode: Text.Wrap; color: Appearance.colors.colOnSurface }
                        StyledText { Layout.fillWidth: true; text: root.pendingMutationFields ? Translation.tr("Only this event becomes an exception in the series.") : Translation.tr("Choose how much of this series changes."); wrapMode: Text.Wrap; color: Appearance.colors.colOnSurfaceVariant }
                        SecondaryAction { Layout.fillWidth: true; label: Translation.tr("Only this event"); symbol: "event"; onTriggered: root.chooseScope("this") }
                        SecondaryAction { Layout.fillWidth: true; label: Translation.tr("This and future"); symbol: "event_repeat"; onTriggered: root.chooseScope("future") }
                        PrimaryAction { Layout.fillWidth: true; label: Translation.tr("Entire series"); symbol: "all_inclusive"; onTriggered: root.chooseScope("all") }
                    }
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.showCalendarSelector
        visible: root.showCalendarSelector
        z: 20

        sourceComponent: SelectionDialog {
            titleText: Translation.tr("Choose calendar")
            items: CalendarService.calendars.filter(calendar => !calendar.readOnly).map(calendar => calendar.name)
            defaultChoice: root.formCalendar
            enableSearch: true
            onCanceled: root.showCalendarSelector = false
            onSelected: result => {
                root.showCalendarSelector = false;
                if (result)
                    root.formCalendar = String(result);
            }
        }
    }


    // ─── Local pieces ───
    // Both actions ride on RippleButtonWithIcon rather than setting their own
    // contentItem: a Control stretches whatever it is given to the full content
    // width, so a bare RowLayout ends up with the icon pinned left and the
    // label adrift. `centerContent` is the wrapper that keeps the pair tight
    // and centred.
    component PrimaryAction: RippleButtonWithIcon {
        id: primaryAction
        property string label: ""
        property string symbol: ""

        signal triggered

        Layout.fillWidth: true
        implicitHeight: 48
        buttonRadius: Appearance.rounding.full
        centerContent: true
        materialIcon: primaryAction.symbol
        materialIconFill: false
        mainText: primaryAction.label
        iconPixelSize: Appearance.font.pixelSize.larger
        textPixelSize: Appearance.font.pixelSize.small
        mainTextWeight: Font.Bold
        colText: Appearance.colors.colOnPrimary
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colBackgroundActive: Appearance.colors.colPrimaryActive
        onClicked: primaryAction.triggered()
    }

    component SecondaryAction: RippleButtonWithIcon {
        id: secondaryAction
        property string label: ""
        property string symbol: ""

        signal triggered

        Layout.fillWidth: true
        implicitHeight: 46
        buttonRadius: Appearance.rounding.full
        centerContent: true
        materialIcon: secondaryAction.symbol
        materialIconFill: false
        mainText: secondaryAction.label
        iconPixelSize: Appearance.font.pixelSize.large
        textPixelSize: Appearance.font.pixelSize.small
        mainTextWeight: Font.DemiBold
        colText: Appearance.colors.colPrimary
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.12)
        colBackgroundActive: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.2)
        onClicked: secondaryAction.triggered()

        DashedBorder {
            anchors.fill: parent
            color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.7)
            borderWidth: 1
            dashLength: 5
            gapLength: 4
            radius: Appearance.rounding.full
        }
    }

    component DurationChip: Rectangle {
        id: durationChip
        property string label: ""
        property bool selected: false

        signal triggered

        implicitWidth: durationChipLabel.implicitWidth + 26
        implicitHeight: 34
        width: implicitWidth
        height: implicitHeight
        radius: Appearance.rounding.full
        color: durationChip.selected ? Appearance.colors.colSecondaryContainer : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(durationChip)
        }

        DashedBorder {
            anchors.fill: parent
            visible: !durationChip.selected
            color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
            borderWidth: 1
            dashLength: 4
            gapLength: 3
            radius: Appearance.rounding.full
        }

        StyledText {
            id: durationChipLabel
            anchors.centerIn: parent
            text: durationChip.label
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.Bold
            color: durationChip.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: durationChip.triggered()
        }
    }

    component PickerRow: Rectangle {
        id: pickerRow
        property string symbol: ""
        property int shapeKind: MaterialShape.Shape.Circle
        property string caption: ""
        property string value: ""

        signal triggered

        implicitHeight: 62
        radius: Appearance.rounding.small
        color: pickerPointer.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.m3colors.m3surfaceContainerHighest

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pickerRow)
        }

        MouseArea {
            id: pickerPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pickerRow.triggered()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                text: pickerRow.symbol
                iconSize: 18
                padding: 9
                shape: pickerRow.shapeKind
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
                rotation: pickerPointer.containsMouse ? 18 : 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: pickerRow.caption
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: pickerRow.value
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                text: "chevron_right"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    component TimeTile: Rectangle {
        id: timeTile
        property string caption: ""
        property string value: ""
        property bool invalid: false

        signal triggered

        implicitHeight: 74
        radius: Appearance.rounding.small
        color: {
            if (timeTile.invalid)
                return ColorUtils.mix(Appearance.colors.colErrorContainer, Appearance.m3colors.m3surfaceContainerHighest, 0.35);
            if (timePointer.containsMouse)
                return Appearance.colors.colPrimaryContainer;
            return Appearance.m3colors.m3surfaceContainerHighest;
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(timeTile)
        }

        MouseArea {
            id: timePointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: timeTile.triggered()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                MaterialSymbol {
                    text: "schedule"
                    iconSize: Appearance.font.pixelSize.smallie
                    color: timePointer.containsMouse ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: timeTile.caption
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: timePointer.containsMouse ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: timeTile.value
                font.family: Appearance.font.family.numbers
                font.pixelSize: 24
                font.weight: Font.Bold
                color: timePointer.containsMouse ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }
        }
    }

    component InfoChip: Rectangle {
        id: infoChip
        property string symbol: ""
        property string label: ""

        implicitWidth: infoChipRow.implicitWidth + 22
        implicitHeight: 32
        width: implicitWidth
        height: implicitHeight
        radius: Appearance.rounding.full
        color: Appearance.m3colors.m3surfaceContainerHighest

        Row {
            id: infoChipRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: infoChip.symbol
                iconSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colPrimary
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: infoChip.label
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }
        }
    }

    component InfoRow: Rectangle {
        id: infoRow
        property string symbol: ""
        property string caption: ""
        property string value: ""
        property bool multiline: false

        implicitHeight: infoRowLayout.implicitHeight + 20
        radius: Appearance.rounding.small
        color: Appearance.m3colors.m3surfaceContainerHighest

        RowLayout {
            id: infoRowLayout
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: infoRow.symbol
                iconSize: 17
                padding: 8
                shape: MaterialShape.Shape.Cookie6Sided
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: infoRow.caption
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: infoRow.value
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurface
                    wrapMode: infoRow.multiline ? Text.Wrap : Text.NoWrap
                    elide: Text.ElideRight
                    maximumLineCount: infoRow.multiline ? 8 : 1
                }
            }
        }
    }
}
