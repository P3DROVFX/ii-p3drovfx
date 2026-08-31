pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common

/**
 * The small, typed boundary around the shell's local time services.
 *
 * This adapter intentionally does not own a clock, alarms file, calendar
 * backend or weather request. It turns the existing singleton data into
 * bounded DTOs, and turns an approved reminder into the exact AlarmService
 * call that persists it.
 */
QtObject {
    id: root

    readonly property int maximumLabelLength: 160
    readonly property int maximumCalendarEvents: 20
    readonly property int maximumCalendarNotesLength: 4000
    readonly property int daysPerWeek: 7
    property var pendingCalendarOperations: ({})

    signal calendarMutationFinished(string key, string operationId, var outcome)

    function boundedText(value: var, maximum = root.maximumLabelLength): string {
        return String(value ?? "").trim().slice(0, maximum);
    }

    function dateKey(date: var): string {
        return Qt.formatDate(date, "yyyy-MM-dd");
    }

    function clockTime(date: var): string {
        return Qt.formatTime(date, "HH:mm");
    }

    function weekdayIndex(value: var): int {
        const key = String(value ?? "").trim().toLocaleLowerCase();
        const aliases = {
            "sunday": 0, "sun": 0, "domingo": 0,
            "monday": 1, "mon": 1, "segunda": 1, "segunda-feira": 1,
            "tuesday": 2, "tue": 2, "tues": 2, "terça": 2, "terca": 2, "terça-feira": 2, "terca-feira": 2,
            "wednesday": 3, "wed": 3, "quarta": 3, "quarta-feira": 3,
            "thursday": 4, "thu": 4, "thur": 4, "thurs": 4, "quinta": 4, "quinta-feira": 4,
            "friday": 5, "fri": 5, "sexta": 5, "sexta-feira": 5,
            "saturday": 6, "sat": 6, "sábado": 6, "sabado": 6
        };
        return aliases[key] === undefined ? -1 : aliases[key];
    }

    function weekdayLabels(days: var): string {
        const labels = [
            Translation.tr("Sunday"),
            Translation.tr("Monday"),
            Translation.tr("Tuesday"),
            Translation.tr("Wednesday"),
            Translation.tr("Thursday"),
            Translation.tr("Friday"),
            Translation.tr("Saturday")
        ];
        return Array.from(days ?? []).map((enabled, index) => enabled === true ? labels[index] : "")
            .filter(label => label.length > 0).join(", ");
    }

    function parseDateOnly(value: var): var {
        const text = String(value ?? "").trim();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(text))
            return null;
        const parts = text.split("-").map(Number);
        const result = new Date(parts[0], parts[1] - 1, parts[2]);
        if (root.dateKey(result) !== text)
            return null;
        return result;
    }

    function relativeMinutes(value: var): var {
        const text = String(value ?? "").trim().toLocaleLowerCase();
        const match = text.match(/^(\d+)\s*(m|min|mins|minute|minutes|minuto|minutos|h|hr|hrs|hour|hours|hora|horas|d|day|days|dia|dias)$/);
        if (!match)
            return null;
        const amount = Number(match[1]);
        const unit = match[2];
        const multiplier = ["h", "hr", "hrs", "hour", "hours", "hora", "horas"].includes(unit) ? 60
            : (["d", "day", "days", "dia", "dias"].includes(unit) ? 1440 : 1);
        const minutes = amount * multiplier;
        return Number.isInteger(minutes) && minutes >= 1 && minutes <= 525600 ? minutes : null;
    }

    /**
     * Converts the wire format to an immutable local minute. The alarm
     * service has minute precision, so a past minute is rejected rather than
     * silently becoming an alarm on a later day.
     */
    function normalizeReminder(args: var): var {
        const hasRelative = args?.whenRelative !== undefined && args?.whenRelative !== null;
        const hasAbsolute = String(args?.whenAbsolute ?? "").trim().length > 0;
        if (hasRelative === hasAbsolute)
            return { ok: false, reason: "chooseOneTime" };

        const label = root.boundedText(args?.label);
        if (label.length === 0)
            return { ok: false, reason: "missingLabel" };

        let target = null;
        if (hasRelative) {
            const minutes = root.relativeMinutes(args.whenRelative);
            if (minutes === null)
                return { ok: false, reason: "invalidRelativeTime" };
            target = new Date(Date.now() + minutes * 60 * 1000);
        } else {
            const raw = String(args.whenAbsolute).trim();
            // Date-only strings are UTC in JavaScript and omit the time the
            // user asked for. Require an ISO local date-time instead.
            if (!raw.includes("T"))
                return { ok: false, reason: "invalidAbsoluteTime" };
            target = new Date(raw);
            if (isNaN(target.getTime()))
                return { ok: false, reason: "invalidAbsoluteTime" };
        }

        target.setSeconds(0, 0);
        if (target.getTime() <= Date.now())
            return { ok: false, reason: "timeInPast" };

        return {
            ok: true,
            reminder: {
                label: label,
                date: root.dateKey(target),
                time: root.clockTime(target),
                whenAbsolute: target.toISOString(),
                displayTime: Qt.formatDateTime(target, "ddd dd MMM · HH:mm"),
                // No selected weekday: AlarmService turns it off after this
                // one local calendar date rings.
                days: [false, false, false, false, false, false, false]
            }
        };
    }

    /**
     * Recurring alarms are intentionally distinct from one-time reminders:
     * an empty weekday list would create an alarm that fires only once and
     * make a request such as "every weekday" look successful when it is not.
     */
    function normalizeAlarm(args: var): var {
        const time = String(args?.time ?? "").trim();
        if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(time))
            return { ok: false, reason: "invalidAlarmTime" };

        const label = root.boundedText(args?.label);
        if (label.length === 0)
            return { ok: false, reason: "missingLabel" };

        const selected = [];
        for (const rawDay of Array.from(args?.days ?? [])) {
            const index = root.weekdayIndex(rawDay);
            if (index < 0)
                return { ok: false, reason: "invalidAlarmDay" };
            if (selected.indexOf(index) < 0)
                selected.push(index);
        }
        if (selected.length === 0)
            return { ok: false, reason: "missingAlarmDays" };

        const days = Array.from({ length: root.daysPerWeek }, (_, index) => selected.indexOf(index) >= 0);
        return {
            ok: true,
            alarm: {
                label: label,
                time: time,
                date: "",
                days: days,
                recurring: true,
                displayTime: time + " · " + root.weekdayLabels(days)
            }
        };
    }

    function createReminder(args: var): var {
        const normalized = root.normalizeReminder(args);
        if (!normalized.ok)
            return normalized;
        if (!Persistent.ready)
            return { ok: false, reason: "alarmsNotReady" };

        const reminder = normalized.reminder;
        const created = AlarmService.addAlarm(reminder.time, reminder.label, reminder.days, reminder.date);
        if (!created)
            return { ok: false, reason: "alarmCreateFailed" };
        return { ok: true, reminder: reminder };
    }

    function createAlarm(args: var): var {
        const normalized = root.normalizeAlarm(args);
        if (!normalized.ok)
            return normalized;
        if (!Persistent.ready)
            return { ok: false, reason: "alarmsNotReady" };

        const alarm = normalized.alarm;
        const created = AlarmService.addAlarm(alarm.time, alarm.label, alarm.days);
        if (!created)
            return { ok: false, reason: "alarmCreateFailed" };
        return { ok: true, alarm: alarm };
    }

    function alarms(): var {
        const list = Array.from(AlarmService.alarms ?? []);
        const results = [];
        for (let i = 0; i < list.length && results.length < 20; i++) {
            const alarm = list[i] ?? ({});
            if (alarm.enabled !== true)
                continue;
            const days = Array.from(alarm.days ?? []);
            results.push({
                label: root.boundedText(alarm.label),
                time: String(alarm.time ?? ""),
                date: String(alarm.date ?? ""),
                repeats: days.some(day => day === true),
                days: root.weekdayLabels(days)
            });
        }
        return results;
    }

    function formatDuration(totalSeconds: var): string {
        const seconds = Math.max(0, Math.floor(Number(totalSeconds) || 0));
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const remainder = seconds % 60;
        if (hours > 0)
            return `${hours}:${String(minutes).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`;
        return `${minutes}:${String(remainder).padStart(2, "0")}`;
    }

    function timerStatus(): var {
        const pomodoroRemaining = Math.max(0, Number(TimerService.pomodoroSecondsLeft ?? 0));
        const pomodoroDuration = Math.max(0, Number(TimerService.pomodoroLapDuration ?? 0));
        const stopwatchElapsed = Math.max(0, Math.floor(Number(TimerService.stopwatchTime ?? 0) / 100));
        const pomodoroRunning = TimerService.pomodoroRunning === true;
        const stopwatchRunning = TimerService.stopwatchRunning === true;
        return {
            pomodoro: {
                kind: "pomodoro",
                running: pomodoroRunning,
                state: pomodoroRunning ? "running" : (pomodoroRemaining < pomodoroDuration ? "paused" : "idle"),
                phase: TimerService.pomodoroBreak === true
                    ? (TimerService.pomodoroLongBreak === true ? "longBreak" : "break") : "focus",
                secondsLeft: pomodoroRemaining,
                remaining: root.formatDuration(pomodoroRemaining),
                durationSeconds: pomodoroDuration,
                cycle: Number(TimerService.pomodoroCycle ?? 0)
            },
            stopwatch: {
                kind: "stopwatch",
                running: stopwatchRunning,
                state: stopwatchRunning ? "running" : (stopwatchElapsed > 0 ? "paused" : "idle"),
                elapsedSeconds: stopwatchElapsed,
                elapsed: root.formatDuration(stopwatchElapsed),
                laps: Array.from(TimerService.stopwatchLaps ?? []).length
            }
        };
    }

    function normalizeTimer(args: var): var {
        const kind = String(args?.kind ?? "").trim().toLowerCase();
        if (["pomodoro", "stopwatch"].indexOf(kind) < 0)
            return { ok: false, reason: "invalidTimerKind" };
        const status = root.timerStatus()[kind];
        return {
            ok: true,
            timer: {
                kind: kind,
                title: kind === "pomodoro" ? Translation.tr("Pomodoro") : Translation.tr("Stopwatch"),
                alreadyRunning: status.running === true,
                previousState: status.state,
                summary: status.running === true
                    ? Translation.tr("%1 is already running").arg(kind === "pomodoro" ? Translation.tr("Pomodoro") : Translation.tr("Stopwatch"))
                    : Translation.tr("Start %1").arg(kind === "pomodoro" ? Translation.tr("Pomodoro") : Translation.tr("Stopwatch"))
            }
        };
    }

    function startTimer(args: var): var {
        const normalized = root.normalizeTimer(args);
        if (!normalized.ok)
            return normalized;
        if (!Persistent.ready)
            return { ok: false, reason: "timerNotReady" };

        const kind = normalized.timer.kind;
        const before = root.timerStatus()[kind];
        if (!before.running) {
            if (kind === "pomodoro")
                TimerService.togglePomodoro();
            else
                TimerService.toggleStopwatch();
        }
        const after = root.timerStatus()[kind];
        return {
            ok: after.running === true,
            alreadyRunning: before.running === true,
            timer: after
        };
    }

    function calendarEventRef(event: var): var {
        const start = new Date(event?.startDate);
        const end = new Date(event?.endDate);
        if (isNaN(start.getTime()))
            return null;
        return {
            uid: String(event?.uid ?? ""),
            recurrenceId: CalendarService.recurrenceIdForEvent(event),
            title: root.boundedText(event?.content),
            start: Qt.formatDateTime(start, "yyyy-MM-dd HH:mm"),
            end: isNaN(end.getTime()) ? "" : Qt.formatDateTime(end, "yyyy-MM-dd HH:mm"),
            calendar: root.boundedText(event?.calendar, 80),
            allDay: CalendarService.isAllDayEvent(event),
            description: root.boundedText(event?.description, 240)
        };
    }

    function calendarEvents(args: var): var {
        if (!CalendarService.khalAvailable)
            return { available: false, events: [] };

        const now = new Date();
        let from = args?.from ? root.parseDateOnly(args.from) : new Date(now.getFullYear(), now.getMonth(), now.getDate());
        let to = args?.to ? root.parseDateOnly(args.to) : new Date(now.getFullYear(), now.getMonth(), now.getDate() + 7);
        if (!from || !to || to.getTime() < from.getTime())
            return { available: true, error: "invalidDateRange", events: [] };
        to.setHours(23, 59, 59, 999);

        const rangeDays = Math.floor((to.getTime() - from.getTime()) / (24 * 60 * 60 * 1000));
        if (rangeDays > 31)
            return { available: true, error: "dateRangeTooLarge", events: [] };

        const limit = Math.max(1, Math.min(root.maximumCalendarEvents, Number(args?.limit ?? 10) || 10));
        const events = [];
        for (let offset = 0; offset <= rangeDays && events.length < limit; offset++) {
            const day = new Date(from);
            day.setDate(day.getDate() + offset);
            for (const event of Array.from(CalendarService.getTasksByDate(day) ?? [])) {
                const ref = root.calendarEventRef(event);
                if (!ref)
                    continue;
                events.push(ref);
                if (events.length >= limit)
                    break;
            }
        }
        return {
            available: true,
            events: events.sort((left, right) => String(left.start).localeCompare(String(right.start)))
        };
    }

    function nextCalendarEvent(): var {
        if (!CalendarService.khalAvailable)
            return { available: false, event: null };

        const now = Date.now();
        const candidates = Array.from(CalendarService.events ?? []).map(event => {
            const start = new Date(event?.startDate);
            const end = new Date(event?.endDate);
            if (isNaN(start.getTime()) || (!isNaN(end.getTime()) && end.getTime() < now))
                return null;
            const ref = root.calendarEventRef(event);
            if (!ref)
                return null;
            ref.state = start.getTime() <= now ? "inProgress" : "upcoming";
            ref.startTimestamp = start.getTime();
            return ref;
        }).filter(event => event !== null).sort((left, right) => left.startTimestamp - right.startTimestamp);
        if (candidates.length === 0)
            return { available: true, event: null };
        const next = candidates[0];
        delete next.startTimestamp;
        return { available: true, event: next };
    }

    function allDayDate(value: var): string {
        const text = String(value ?? "").trim();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(text))
            return "";
        const parsed = root.parseDateOnly(text);
        return parsed ? text : "";
    }

    function localDateTime(value: var): string {
        const text = String(value ?? "").trim();
        if (!/^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.test(text))
            return "";
        const parsed = new Date(text);
        return isNaN(parsed.getTime()) ? "" : text;
    }

    function nextAllDayDate(value: string): string {
        const parsed = root.parseDateOnly(value);
        if (!parsed)
            return "";
        parsed.setDate(parsed.getDate() + 1);
        return root.dateKey(parsed);
    }

    function normalizedCalendarScope(value: var): var {
        const scope = String(value ?? "all").trim().toLowerCase();
        if (["all", "this", "future"].indexOf(scope) < 0)
            return { ok: false, error: qsTr("Calendar scope must be all, this, or future") };
        return {
            ok: true,
            scope: scope,
            label: scope === "this" ? qsTr("Only this occurrence")
                : (scope === "future" ? qsTr("This and future occurrences") : qsTr("All occurrences"))
        };
    }

    function calendarTiming(args: var, allDay: bool): var {
        const start = allDay ? root.allDayDate(args?.start) : root.localDateTime(args?.start);
        if (start.length === 0)
            return { ok: false, error: allDay ? qsTr("An all-day event needs a YYYY-MM-DD start date") : qsTr("A timed event needs a local ISO start time") };
        const rawEnd = String(args?.end ?? "").trim();
        let end = allDay ? root.allDayDate(rawEnd) : root.localDateTime(rawEnd);
        if (allDay && end.length === 0 && rawEnd.length === 0)
            end = root.nextAllDayDate(start);
        if (end.length === 0)
            return { ok: false, error: allDay ? qsTr("The all-day end date is not valid") : qsTr("A timed event needs a local ISO end time") };
        if (allDay ? end <= start : new Date(end).getTime() <= new Date(start).getTime())
            return { ok: false, error: qsTr("The event end must be after its start") };
        return {
            ok: true,
            start: start,
            end: end,
            allDay: allDay,
            startDisplay: allDay ? start : Qt.formatDateTime(new Date(start), "ddd dd MMM · HH:mm"),
            endDisplay: allDay ? end : Qt.formatDateTime(new Date(end), "ddd dd MMM · HH:mm")
        };
    }

    function calendarEventForUid(value: var, recurrenceId = ""): var {
        const uid = String(value ?? "").trim();
        if (uid.length === 0)
            return { ok: false, error: qsTr("A calendar event uid is required") };
        const rawRecurrenceId = String(recurrenceId ?? "").trim();
        const candidates = Array.from(CalendarService.events ?? []).filter(candidate => String(candidate?.uid ?? "") === uid);
        const event = rawRecurrenceId.length > 0
            ? candidates.find(candidate => CalendarService.recurrenceIdForEvent(candidate) === rawRecurrenceId)
            : candidates[0];
        if (!event)
            return { ok: false, error: qsTr("That calendar event is not in the loaded range. Read its date range first.") };
        if (event.readOnly === true)
            return { ok: false, error: qsTr("That calendar is read-only") };
        const occurrence = Object.assign({}, event);
        if (rawRecurrenceId.length > 0) {
            const dateOnly = root.allDayDate(rawRecurrenceId);
            const timed = root.localDateTime(rawRecurrenceId);
            if ((!CalendarService.isAllDayEvent(event) && timed.length === 0)
                    || (CalendarService.isAllDayEvent(event) && dateOnly.length === 0))
                return { ok: false, error: qsTr("The occurrence date is not valid") };
            if (dateOnly.length > 0) {
                const parts = dateOnly.split("-").map(Number);
                occurrence.startDate = new Date(parts[0], parts[1] - 1, parts[2]);
            } else {
                occurrence.startDate = new Date(timed);
            }
        }
        return {
            ok: true,
            event: event,
            occurrence: occurrence,
            uid: uid,
            title: root.boundedText(event.content),
            calendar: String(event.calendar ?? ""),
            allDay: CalendarService.isAllDayEvent(event),
            recurring: String(event.repeatSymbol ?? "").trim().length > 0
        };
    }

    function calendarCreatePreview(args: var): var {
        if (!CalendarService.khalAvailable)
            return { ok: false, error: qsTr("The khal calendar is not available") };
        const title = root.boundedText(args?.title);
        if (title.length === 0)
            return { ok: false, error: qsTr("An event needs a title") };
        const allDay = args?.allDay === true;
        const timing = root.calendarTiming(args, allDay);
        if (!timing.ok)
            return timing;
        return Object.assign({
            ok: true,
            operation: "create",
            title: title,
            calendar: root.boundedText(args?.calendar, 120) || String(CalendarService.defaultCalendar ?? ""),
            location: root.boundedText(args?.location, 500),
            url: root.boundedText(args?.url, 2000),
            notes: String(args?.notes ?? "").trim().slice(0, root.maximumCalendarNotesLength),
            scope: "all",
            scopeLabel: qsTr("One new event")
        }, timing);
    }

    function calendarMovePreview(args: var): var {
        if (!CalendarService.khalAvailable)
            return { ok: false, error: qsTr("The khal calendar is not available") };
        const reference = root.calendarEventForUid(args?.uid, args?.recurrenceId);
        if (!reference.ok)
            return reference;
        const scope = root.normalizedCalendarScope(args?.scope);
        if (!scope.ok)
            return scope;
        if ((scope.scope === "this" || scope.scope === "future") && String(args?.recurrenceId ?? "").trim().length === 0)
            return { ok: false, error: qsTr("A specific occurrence needs its recurrence id") };
        const allDay = args?.allDay === undefined ? reference.allDay : args.allDay === true;
        const timing = root.calendarTiming(args, allDay);
        if (!timing.ok)
            return timing;
        if ((scope.scope === "this" || scope.scope === "future") && !reference.recurring)
            return { ok: false, error: qsTr("That event does not repeat, so it has no occurrence scope") };
        return Object.assign({
            ok: true,
            operation: "move",
            uid: reference.uid,
            title: reference.title,
            calendar: reference.calendar,
            recurring: reference.recurring,
            recurrenceId: CalendarService.recurrenceIdForEvent(reference.occurrence),
            scope: scope.scope,
            scopeLabel: scope.label
        }, timing);
    }

    function calendarDeletePreview(args: var): var {
        if (!CalendarService.khalAvailable)
            return { ok: false, error: qsTr("The khal calendar is not available") };
        const reference = root.calendarEventForUid(args?.uid, args?.recurrenceId);
        if (!reference.ok)
            return reference;
        const scope = root.normalizedCalendarScope(args?.scope);
        if (!scope.ok)
            return scope;
        if ((scope.scope === "this" || scope.scope === "future") && String(args?.recurrenceId ?? "").trim().length === 0)
            return { ok: false, error: qsTr("A specific occurrence needs its recurrence id") };
        if ((scope.scope === "this" || scope.scope === "future") && !reference.recurring)
            return { ok: false, error: qsTr("That event does not repeat, so it has no occurrence scope") };
        return {
            ok: true,
            operation: "delete",
            uid: reference.uid,
            title: reference.title,
            calendar: reference.calendar,
            recurring: reference.recurring,
            recurrenceId: CalendarService.recurrenceIdForEvent(reference.occurrence),
            scope: scope.scope,
            scopeLabel: scope.label,
            allDay: reference.allDay,
            startDisplay: Qt.formatDateTime(reference.occurrence.startDate, reference.allDay ? "ddd dd MMM yyyy" : "ddd dd MMM · HH:mm"),
            endDisplay: ""
        };
    }

    function calendarMutationPreview(operation: string, args: var): var {
        if (operation === "create")
            return root.calendarCreatePreview(args);
        if (operation === "move")
            return root.calendarMovePreview(args);
        if (operation === "delete")
            return root.calendarDeletePreview(args);
        return { ok: false, error: qsTr("Unknown calendar change") };
    }

    function calendarMutationPayload(preview: var): var {
        const operation = String(preview?.operation ?? "");
        if (operation === "create") {
            return {
                op: "save",
                calendar: String(preview.calendar ?? ""),
                event: {
                    summary: String(preview.title ?? ""),
                    start: String(preview.start ?? ""),
                    end: String(preview.end ?? ""),
                    allDay: preview.allDay === true,
                    location: String(preview.location ?? ""),
                    url: String(preview.url ?? ""),
                    description: String(preview.notes ?? "")
                }
            };
        }
        const scope = String(preview?.scope ?? "all");
        if (operation === "move") {
            const fields = {
                uid: String(preview.uid ?? ""),
                start: String(preview.start ?? ""),
                end: String(preview.end ?? ""),
                allDay: preview.allDay === true
            };
            return scope === "this"
                ? { op: "overrideOccurrence", uid: fields.uid, recurrenceId: String(preview.recurrenceId ?? ""), fields: fields }
                : (scope === "future"
                    ? { op: "splitSeries", uid: fields.uid, recurrenceId: String(preview.recurrenceId ?? ""), fields: fields }
                    : { op: "save", calendar: String(preview.calendar ?? ""), event: fields });
        }
        if (operation === "delete") {
            return scope === "this"
                ? { op: "deleteOccurrence", uid: String(preview.uid ?? ""), recurrenceId: String(preview.recurrenceId ?? "") }
                : (scope === "future"
                    ? { op: "truncateSeries", uid: String(preview.uid ?? ""), recurrenceId: String(preview.recurrenceId ?? "") }
                    : { op: "deleteSeries", uid: String(preview.uid ?? "") });
        }
        return null;
    }

    function executeCalendarMutation(preview: var, key: string, operationId: string): var {
        const operation = String(preview?.operation ?? "");
        if (["create", "move", "delete"].indexOf(operation) < 0)
            return { status: "error", summary: qsTr("That calendar change is not valid"), data: { error: "invalidCalendarMutation" }, retryable: false };
        const payload = root.calendarMutationPayload(preview);
        if (!payload)
            return { status: "error", summary: qsTr("That calendar change is not valid"), data: { error: "invalidCalendarMutation" }, retryable: false };
        const pending = Object.assign({}, root.pendingCalendarOperations);
        pending[String(operationId)] = { key: String(key), operation: operation, preview: preview };
        root.pendingCalendarOperations = pending;
        CalendarService.enqueueCalendarRequest(payload, reply => {
            const current = root.pendingCalendarOperations[String(operationId)];
            if (!current)
                return;
            const next = Object.assign({}, root.pendingCalendarOperations);
            delete next[String(operationId)];
            root.pendingCalendarOperations = next;
            const success = reply?.ok === true;
            const pastTense = current.operation === "create" ? qsTr("Calendar event created")
                : (current.operation === "move" ? qsTr("Calendar event moved") : qsTr("Calendar event deleted"));
            root.calendarMutationFinished(current.key, String(operationId), {
                status: success ? "success" : "error",
                summary: success ? pastTense : qsTr("The calendar event could not be changed"),
                data: success
                    ? { operation: current.operation, uid: String(reply?.uid ?? current.preview.uid ?? ""), calendar: String(current.preview.calendar ?? "") }
                    : { operation: current.operation, error: String(reply?.error ?? "calendarMutationFailed") },
                operationId: String(operationId),
                retryable: false
            });
        });
        return { status: "pending", summary: qsTr("Calendar change queued"), data: { operation: operation }, retryable: false };
    }

    function weather(): var {
        // Weather owns caching and the actual request. Calling it here may
        // refresh stale data, so the tool's envelope always marks network use.
        Weather.getData();
        const current = Weather.data ?? ({});
        const forecast = Array.from(Weather.forecastData ?? []).slice(0, 3).map(day => ({
                    date: String(day?.date ?? ""),
                    minimum: Weather.useUSCS ? `${day?.minF ?? ""}°F` : `${day?.minC ?? ""}°C`,
                    maximum: Weather.useUSCS ? `${day?.maxF ?? ""}°F` : `${day?.maxC ?? ""}°C`,
                    condition: Weather.getWeatherDescription(day?.code)
                }));
        return {
            city: root.boundedText(current.city, 80),
            condition: root.boundedText(current.wDesc, 80),
            temperature: String(current.temp ?? ""),
            feelsLike: String(current.tempFeelsLike ?? ""),
            precipitation: String(current.precip ?? ""),
            humidity: String(current.humidity ?? ""),
            wind: String(current.wind ?? ""),
            forecast: forecast,
            refreshing: Weather.forecastLoading === true
        };
    }
}
