pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick
import "reminders/RemindersLogic.js" as Logic

/**
 * Reminders, after Samsung Reminder: the list, its categories and recycle bin, and the
 * alerts.
 *
 * The list lives in its own file ($STATE/user/reminders.json), apart from the todo list:
 * reminders carry a time, an alert level, a checklist and attachments that the todo
 * providers would drop. This service is the file's only writer; To Do sync
 * (RemindersSync) hands its results back here instead of writing it.
 *
 * Alerts come from one one-shot timer aimed at the next one due, never further than a
 * minute ahead: a timer does not count time spent suspended, so the minute cap is how a
 * resume is noticed. An alert already fired for an occurrence is remembered on the
 * reminder, so a restart never fires it twice, and one found late after a long sleep
 * comes in as a quiet "missed" notification instead of ringing.
 *
 * Levels: "light" is a notification with Complete and Snooze; "medium" and "strong" take
 * the screen (ReminderAlertPopup, or the island when it owns reminders) — medium with one
 * short chime, strong ringing until answered or silenced.
 */
Singleton {
    id: root

    // ── Settings ────────────────────────────────────────────────────────
    readonly property var settings: Config.options.clockApp.reminders
    readonly property string defaultAlert: ["light", "medium", "strong"].includes(root.settings?.defaultAlert)
        ? root.settings.defaultAlert : "light"
    readonly property string allDayTime: String(root.settings?.allDayTime ?? "09:00")
    readonly property int snoozeMinutes: Math.max(1, Math.min(60, root.settings?.snoozeMinutes ?? 5))
    readonly property int autoSilenceMinutes: Math.max(0, root.settings?.autoSilenceMinutes ?? 1)
    readonly property int catchUpMinutes: Math.max(0, root.settings?.catchUpMinutes ?? 10)
    readonly property bool wakeFromSuspend: root.settings?.wakeFromSuspend ?? true
    readonly property int trashDays: Math.max(0, root.settings?.trashDays ?? 30)
    readonly property int autoDeleteCompletedDays: Math.max(0, root.settings?.autoDeleteCompletedDays ?? 0)
    /// The week's first day as Date.getDay(); the config counts from Monday.
    readonly property int firstDay: ((Config.options?.time?.firstDayOfWeek ?? 6) + 1) % 7

    // ── State ───────────────────────────────────────────────────────────
    property bool loaded: false
    property var categories: []
    property var reminders: []
    /// Remote copies to delete on the next sync: [{ kind, listId, taskId }].
    property var tombstones: []
    /// Titles typed before, for the editor's suggestions.
    property var recent: []
    /// Owned by RemindersSync: delta links and the last sync time.
    property var syncState: ({})

    readonly property var liveReminders: root.reminders.filter(reminder => !reminder.deletedAt)
    readonly property var trashed: root.reminders.filter(reminder => reminder.deletedAt > 0)
    readonly property int activeCount: root.liveReminders.filter(reminder => !reminder.completed).length

    /// The earliest alert still to come: { id, kind, at, key } or null.
    property var nextAlert: null
    /// The next reminder due within the hour, for the island and the bar: { reminder, at } or null.
    property var upcoming: null

    /**
     * Open reminders with a date, by day ("yyyy-MM-dd"), shaped like todo tasks so the
     * timetable draws them with its task chip: { id, reminderId, content, done, hasDate,
     * date }. Samsung Calendar shows reminders on their day the same way.
     */
    property var timetableMemo: ({})
    readonly property var timetableItems: {
        const byDay = {};
        if (!(root.settings?.showInTimetable ?? true))
            return ObjectUtils.keep(root.timetableMemo, "days", byDay);
        root.reminders.forEach(item => {
            if (!Logic.isLive(item) || !item.schedule)
                return;
            const due = Logic.dueAt(item, root.allDayTime);
            const label = item.schedule.time
                ? Qt.locale().toString(due, Config.options?.time?.format ?? "hh:mm") + " " + (item.title || Translation.tr("Reminder"))
                : (item.title || Translation.tr("Reminder"));
            (byDay[item.schedule.date] = byDay[item.schedule.date] ?? []).push({
                id: "reminder:" + item.id,
                reminderId: item.id,
                content: label,
                done: false,
                hasDate: true,
                date: due
            });
        });
        return ObjectUtils.keep(root.timetableMemo, "days", byDay);
    }

    /// The timetable's task chip asks to complete either kind; reminders answer here.
    function completeTask(task): bool {
        if (!task?.reminderId)
            return false;
        root.complete(task.reminderId);
        return true;
    }

    /// The reminder taking the screen, and how loudly.
    property string ringingId: ""
    property string ringingLevel: ""
    readonly property var ringing: root.ringingId.length > 0 ? root.reminder(root.ringingId) : null
    property var ringQueue: []

    /// Shell notification ids per reminder, so completing one in the app clears its notification.
    property var notificationIds: ({})

    signal edited()
    signal alerted(var reminder, string level)

    // ── Lookup ──────────────────────────────────────────────────────────
    function reminder(id) {
        return root.reminders.find(item => item.id === id) ?? null;
    }

    function category(id) {
        return root.categories.find(item => item.id === id) ?? root.categories[0] ?? null;
    }

    function categoryName(id): string {
        const found = root.category(id);
        if (!found)
            return "";
        return found.id === Logic.DEFAULT_CATEGORY && found.name === "My reminders" ? Translation.tr("My reminders") : found.name;
    }

    function categoryOrder() {
        const order = {};
        root.categories.forEach((category, index) => order[category.id] = index);
        return order;
    }

    function levelOf(reminder): string {
        return reminder?.alert && reminder.alert !== "default" ? reminder.alert : root.defaultAlert;
    }

    function dueAt(reminder) {
        return Logic.dueAt(reminder, root.allDayTime);
    }

    function isOverdue(reminder, now): bool {
        return Logic.isOverdue(reminder, now ?? new Date(), root.allDayTime);
    }

    /** "Today 18:00", "Tomorrow", "Fri, 9 Oct 10:30" — an all-day one shows only its day. */
    function whenText(reminder, now): string {
        const due = root.dueAt(reminder);
        if (!due)
            return "";
        const base = now ?? new Date();
        const today = new Date(base.getFullYear(), base.getMonth(), base.getDate());
        const day = new Date(due.getFullYear(), due.getMonth(), due.getDate());
        const diff = Math.round((day.getTime() - today.getTime()) / 86400000);
        const dayText = diff === 0 ? Translation.tr("Today")
            : diff === 1 ? Translation.tr("Tomorrow")
            : diff === -1 ? Translation.tr("Yesterday")
            : Qt.locale().toString(due, due.getFullYear() === base.getFullYear() ? "ddd, d MMM" : "d MMM yyyy");
        if (!reminder.schedule.time)
            return dayText;
        return dayText + " " + Qt.locale().toString(due, Config.options?.time?.format ?? "hh:mm");
    }

    /** "Every day", "Every 2 weeks on Tue, Thu", "Monthly on the 1st and 15th" … */
    function repeatText(repeat): string {
        if (!repeat)
            return Translation.tr("Don't repeat");
        const n = repeat.interval;
        const units = {
            minute: [Translation.tr("Every minute"), Translation.tr("Every %1 minutes")],
            hour: [Translation.tr("Every hour"), Translation.tr("Every %1 hours")],
            day: [Translation.tr("Every day"), Translation.tr("Every %1 days")],
            week: [Translation.tr("Every week"), Translation.tr("Every %1 weeks")],
            month: [Translation.tr("Every month"), Translation.tr("Every %1 months")],
            year: [Translation.tr("Every year"), Translation.tr("Every %1 years")]
        };
        const pair = units[repeat.unit] ?? units.day;
        let text = n === 1 ? pair[0] : pair[1].arg(String(n));
        if (repeat.unit === "week" && repeat.weekdays.includes(true)) {
            const names = [];
            for (let i = 0; i < 7; i++) {
                const day = (root.firstDay + i) % 7;
                if (repeat.weekdays[day])
                    names.push(Qt.locale().dayName(day, Locale.ShortFormat));
            }
            text += " · " + names.join(", ");
        } else if (repeat.unit === "month" && repeat.monthDays.length > 0) {
            text += " · " + repeat.monthDays.join(", ");
        } else if (repeat.unit === "year" && repeat.yearDates.length > 0) {
            text += " · " + repeat.yearDates.map(key => {
                const parts = key.split("-").map(Number);
                return Qt.locale().toString(new Date(2000, parts[0] - 1, parts[1]), "d MMM");
            }).join(", ");
        }
        if (repeat.end.kind === "count")
            text += " · " + Translation.tr("%1 times").arg(String(repeat.end.count));
        else if (repeat.end.kind === "until")
            text += " · " + Translation.tr("until %1").arg(Qt.locale().toString(Logic.parseDay(repeat.end.until), "d MMM yyyy"));
        return text;
    }

    // ── Editing ─────────────────────────────────────────────────────────
    function commit(next, fromSync): void {
        root.reminders = next;
        root.saveSoon();
        root.reschedule();
        if (!fromSync)
            root.edited();
    }

    function replaceOne(id, edit): void {
        const index = root.reminders.findIndex(item => item.id === id);
        if (index < 0)
            return;
        const copy = root.reminders.slice();
        copy[index] = edit(root.reminders[index]);
        root.commit(copy);
    }

    function rememberTitle(title): void {
        const text = String(title ?? "").trim();
        if (text.length === 0)
            return;
        root.recent = [text].concat(root.recent.filter(item => item.toLowerCase() !== text.toLowerCase())).slice(0, 30);
    }

    /**
     * A time set in the past (Samsung allows it) is not an alert waiting to happen: mark
     * whatever is already behind us as fired, so saving it doesn't ring or report it
     * missed.
     */
    function settle(reminder, now): var {
        const key = Logic.occurrenceKey(reminder);
        if (key.length === 0)
            return reminder;
        const due = Logic.dueAt(reminder, root.allDayTime);
        if (due && due.getTime() <= now && reminder.snoozedUntil <= 0)
            reminder.firedFor = key;
        const early = Logic.earlyAt(reminder, root.allDayTime);
        if (early && early.getTime() <= now)
            reminder.earlyFiredFor = key;
        return reminder;
    }

    /** Adds a reminder from a draft (any subset of the fields) and returns its id. */
    function create(draft): string {
        const now = Date.now();
        const source = Object.assign({ categoryId: root.settings?.defaultCategory ?? Logic.DEFAULT_CATEGORY }, draft ?? {});
        delete source.id;
        delete source.remote;
        source.createdAt = now;
        source.modifiedAt = now;
        const reminder = root.settle(Logic.normalizeReminder(source, now), now);
        if (!root.categories.some(category => category.id === reminder.categoryId))
            reminder.categoryId = Logic.DEFAULT_CATEGORY;
        root.rememberTitle(reminder.title);
        root.commit(root.reminders.concat([reminder]));
        return reminder.id;
    }

    /**
     * Applies `fields` to one reminder. A changed time or early alert re-arms its alerts
     * (a reminder moved to later must alert again even if this occurrence already did).
     */
    function update(id, fields): void {
        root.replaceOne(id, old => {
            const now = Date.now();
            const merged = Object.assign({}, old, fields ?? {}, { id: old.id, modifiedAt: now, remote: old.remote });
            const next = Logic.normalizeReminder(merged, now);
            if (JSON.stringify(old.schedule) !== JSON.stringify(next.schedule)
                    || JSON.stringify(old.early) !== JSON.stringify(next.early)) {
                next.firedFor = "";
                next.earlyFiredFor = "";
                next.snoozedUntil = 0;
                if (next.schedule && old.schedule && next.schedule.repeat
                        && JSON.stringify(old.schedule.repeat) !== JSON.stringify(next.schedule.repeat)) {
                    next.schedule.occurrence = 0;
                    next.schedule.repeat.anchor = next.schedule.date;
                }
                root.settle(next, now);
            }
            if (fields && fields.title !== undefined)
                root.rememberTitle(next.title);
            return next;
        });
    }

    function complete(id): void {
        root.clearNotification(id);
        if (root.ringingId === id)
            root.stopRinging(false);
        root.replaceOne(id, old => Logic.complete(old, Date.now(), root.firstDay));
    }

    /** Back from Completed (or the bin) into the open list. */
    function restore(id): void {
        root.replaceOne(id, old => Logic.restore(old, Date.now()));
    }

    function toggleComplete(id): void {
        const item = root.reminder(id);
        if (!item)
            return;
        if (item.completed)
            root.restore(id);
        else
            root.complete(id);
    }

    function setImportant(id, important): void {
        root.update(id, { important: Boolean(important) });
    }

    function toggleChecklistItem(id, itemId): void {
        const item = root.reminder(id);
        if (!item)
            return;
        root.update(id, {
            checklist: item.checklist.map(entry => entry.id === itemId ? { id: entry.id, text: entry.text, done: !entry.done } : entry)
        });
    }

    function snooze(id, minutes): void {
        const length = Math.max(1, Math.round(minutes || root.snoozeMinutes));
        root.clearNotification(id);
        if (root.ringingId === id)
            root.stopRinging(false);
        root.replaceOne(id, old => {
            const next = Logic.normalizeReminder(old, Date.now());
            next.snoozedUntil = Date.now() + length * 60000;
            next.firedFor = Logic.occurrenceKey(next);
            return next;
        });
    }

    /** Into the recycle bin; restorable for `trashDays`. */
    function trash(ids): void {
        const set = Array.from(ids ?? []);
        const now = Date.now();
        set.forEach(id => root.clearNotification(id));
        if (set.includes(root.ringingId))
            root.stopRinging(false);
        root.commit(root.reminders.map(item => {
            if (!set.includes(item.id))
                return item;
            const next = Logic.normalizeReminder(item, now);
            next.deletedAt = now;
            next.modifiedAt = now;
            next.snoozedUntil = 0;
            return next;
        }));
    }

    function restoreFromTrash(ids): void {
        const set = Array.from(ids ?? []);
        const now = Date.now();
        root.commit(root.reminders.map(item => {
            if (!set.includes(item.id))
                return item;
            const next = Logic.normalizeReminder(item, now);
            next.deletedAt = 0;
            next.modifiedAt = now;
            // Restored into a category that was deleted meanwhile: the default one.
            if (!root.categories.some(category => category.id === next.categoryId))
                next.categoryId = Logic.DEFAULT_CATEGORY;
            return next;
        }));
    }

    /** Gone for good, and from To Do on the next sync. */
    function deleteForever(ids): void {
        const set = Array.from(ids ?? []);
        const graves = [];
        root.reminders.forEach(item => {
            const todo = item.remote?.todo;
            if (set.includes(item.id) && todo?.taskId)
                graves.push({ kind: "task", listId: String(todo.listId ?? ""), taskId: String(todo.taskId) });
        });
        if (graves.length > 0)
            root.tombstones = root.tombstones.concat(graves);
        root.commit(root.reminders.filter(item => !set.includes(item.id)));
        root.pruneAttachments();
    }

    function emptyTrash(): void {
        root.deleteForever(root.trashed.map(item => item.id));
    }

    function clearCompleted(): void {
        root.trash(root.liveReminders.filter(item => item.completed).map(item => item.id));
    }

    function duplicate(id): string {
        const item = root.reminder(id);
        if (!item)
            return "";
        const copy = JSON.parse(JSON.stringify(item));
        copy.completed = false;
        copy.completedAt = 0;
        copy.deletedAt = 0;
        copy.firedFor = "";
        copy.earlyFiredFor = "";
        copy.snoozedUntil = 0;
        copy.checklist = copy.checklist.map(entry => ({ id: entry.id, text: entry.text, done: false }));
        if (copy.schedule)
            copy.schedule.occurrence = 0;
        return root.create(copy);
    }

    function move(ids, categoryId): void {
        const set = Array.from(ids ?? []);
        if (!root.categories.some(category => category.id === categoryId))
            return;
        const now = Date.now();
        root.commit(root.reminders.map(item => {
            if (!set.includes(item.id) || item.categoryId === categoryId)
                return item;
            const next = Logic.normalizeReminder(item, now);
            next.categoryId = categoryId;
            next.modifiedAt = now;
            return next;
        }));
    }

    function completeMany(ids): void {
        Array.from(ids ?? []).forEach(id => {
            const item = root.reminder(id);
            if (item && !item.completed)
                root.complete(id);
        });
    }

    // ── Categories ──────────────────────────────────────────────────────
    function commitCategories(next, fromSync): void {
        root.categories = Logic.sortCategories(next);
        root.saveSoon();
        if (!fromSync)
            root.edited();
    }

    function addCategory(name, color, icon): string {
        const text = String(name ?? "").trim();
        if (text.length === 0)
            return "";
        const order = root.categories.reduce((max, category) => Math.max(max, category.order), 0) + 1;
        const category = Logic.normalizeCategory({ name: text, color: color, icon: icon || "list", order: order }, order);
        root.commitCategories(root.categories.concat([category]));
        return category.id;
    }

    function updateCategory(id, fields): void {
        root.commitCategories(root.categories.map(category => {
            if (category.id !== id)
                return category;
            const merged = Object.assign({}, category, fields ?? {}, { id: category.id, remote: category.remote });
            return Logic.normalizeCategory(merged, category.order);
        }));
    }

    /** Its reminders go to the bin with it; the default category stays. */
    function deleteCategory(id): void {
        if (id === Logic.DEFAULT_CATEGORY)
            return;
        const doomed = root.categories.find(category => category.id === id);
        if (!doomed)
            return;
        root.trash(root.reminders.filter(item => item.categoryId === id && !item.deletedAt).map(item => item.id));
        if (doomed.remote?.todo?.listId)
            root.tombstones = root.tombstones.concat([{ kind: "list", listId: String(doomed.remote.todo.listId), taskId: "" }]);
        root.commitCategories(root.categories.filter(category => category.id !== id));
    }

    /** Moves a category one step up (-1) or down (+1) among the non-default ones. */
    function moveCategory(id, delta): void {
        const list = root.categories.filter(category => category.id !== Logic.DEFAULT_CATEGORY);
        const index = list.findIndex(category => category.id === id);
        const target = index + delta;
        if (index < 0 || target < 0 || target >= list.length || list[index].pinned !== list[target].pinned)
            return;
        const swapped = list.slice();
        swapped[index] = list[target];
        swapped[target] = list[index];
        const reordered = swapped.map((category, order) => Object.assign({}, category, { order: order + 1 }));
        root.commitCategories(root.categories.filter(category => category.id === Logic.DEFAULT_CATEGORY).concat(reordered));
    }

    // ── Attachments ─────────────────────────────────────────────────────
    /**
     * Copies a picked image into the reminders' own folder and calls back with the copy's
     * path (or "" on failure), so the thumbnail survives the original being moved.
     */
    function importImage(path, callback): void {
        const source = FileUtils.trimFileProtocol(String(path ?? ""));
        if (source.length === 0) {
            callback("");
            return;
        }
        const extension = (source.match(/\.[A-Za-z0-9]{1,5}$/) ?? [".png"])[0].toLowerCase();
        const target = `${Directories.reminderAttachmentsDir}/${Logic.makeId("img")}${extension}`;
        const process = importProcess.createObject(root, {
            command: ["sh", "-c", 'mkdir -p "$(dirname "$2")" && cp -f -- "$1" "$2"', "sh", source, target],
            target: target,
            callback: callback
        });
        process.running = true;
    }

    Component {
        id: importProcess

        Process {
            id: proc
            property string target
            property var callback
            onExited: exitCode => {
                if (typeof proc.callback === "function")
                    proc.callback(exitCode === 0 ? proc.target : "");
                proc.destroy();
            }
        }
    }

    /** Removes copied images nothing points at any more. */
    function pruneAttachments(): void {
        const keep = [];
        root.reminders.forEach(item => item.attachments.forEach(attachment => {
            if (attachment.kind === "image" && attachment.path.startsWith(Directories.reminderAttachmentsDir))
                keep.push(attachment.path.slice(attachment.path.lastIndexOf("/") + 1));
        }));
        const script = 'cd "$1" 2>/dev/null || exit 0; shift; for f in *; do [ -f "$f" ] || continue; '
            + 'case " $* " in *" $f "*) ;; *) rm -f -- "$f" ;; esac; done';
        Quickshell.execDetached(["sh", "-c", script, "sh", Directories.reminderAttachmentsDir].concat(keep));
    }

    // ── Alerts ──────────────────────────────────────────────────────────
    function reschedule(): void {
        if (!root.loaded)
            return;
        const next = Logic.nextAlert(root.reminders, root.allDayTime);
        root.nextAlert = next;
        root.refreshUpcoming();
        if (!next) {
            alertTimer.stop();
        } else {
            alertTimer.interval = Math.max(250, Math.min(next.at - Date.now(), 60000));
            alertTimer.restart();
        }
        wakeDebounce.restart();
    }

    function refreshUpcoming(): void {
        const now = Date.now();
        let best = null;
        root.reminders.forEach(item => {
            if (!Logic.isLive(item) || !item.schedule)
                return;
            const at = item.snoozedUntil > 0 ? item.snoozedUntil : Logic.dueAt(item, root.allDayTime).getTime();
            if (at >= now && at - now <= 3600000 && (!best || at < best.at))
                best = { reminder: item, at: at };
        });
        const same = best && root.upcoming && best.reminder.id === root.upcoming.reminder.id && best.at === root.upcoming.at
            && best.reminder === root.upcoming.reminder;
        if (!same && !(best === null && root.upcoming === null))
            root.upcoming = best;
    }

    function checkAlerts(): void {
        if (!root.loaded)
            return;
        const now = Date.now();
        const due = Logic.dueAlerts(root.reminders, now, root.allDayTime);
        if (due.length > 0) {
            const fired = {};
            for (const alert of due) {
                const item = root.reminder(alert.id);
                if (!item)
                    continue;
                const late = now - alert.at > root.catchUpMinutes * 60000;
                if (alert.kind === "early") {
                    if (!late)
                        root.notifyEarly(item);
                } else if (late) {
                    root.notify(item, true);
                } else {
                    root.fire(item);
                }
                fired[alert.id] = Object.assign(fired[alert.id] ?? {}, alert.kind === "early"
                    ? { earlyFiredFor: alert.key } : { firedFor: alert.key, snoozedUntil: 0 });
            }
            root.commit(root.reminders.map(item => fired[item.id]
                ? Object.assign(Logic.normalizeReminder(item, now), fired[item.id]) : item), true);
        } else {
            root.reschedule();
        }
    }

    function fire(item): void {
        const level = root.levelOf(item);
        root.alerted(item, level);
        if (level === "light") {
            root.notify(item, false);
            return;
        }
        if (root.ringingId.length > 0 && root.ringingId !== item.id) {
            if (!root.ringQueue.includes(item.id))
                root.ringQueue = root.ringQueue.concat([item.id]);
            return;
        }
        root.ringingId = item.id;
        root.ringingLevel = level;
        SoundService.stopLoop();
        if (root.settings?.alertSound ?? true) {
            SoundService.startLoop("alarm", "alarm-clock-elapsed", 0);
            if (level === "medium")
                chimeTimer.restart();
        }
    }

    /**
     * The full-screen alert answered: `dismissed` leaves the reminder open with a
     * notification behind (it was seen, not done); otherwise the caller completed or
     * snoozed it already.
     */
    function stopRinging(dismissed): void {
        const id = root.ringingId;
        if (id.length === 0)
            return;
        chimeTimer.stop();
        SoundService.stopLoop();
        root.ringingId = "";
        root.ringingLevel = "";
        if (dismissed) {
            const item = root.reminder(id);
            if (item)
                root.notify(item, false, true);
        }
        Qt.callLater(root.ringNextQueued);
    }

    function ringNextQueued(): void {
        while (root.ringingId.length === 0 && root.ringQueue.length > 0) {
            const id = root.ringQueue[0];
            root.ringQueue = root.ringQueue.slice(1);
            const item = root.reminder(id);
            if (item && Logic.isLive(item)) {
                root.fire(item);
                return;
            }
        }
    }

    function notificationBody(item): string {
        const parts = [];
        const when = root.whenText(item, new Date());
        if (when)
            parts.push(when);
        if (item.notes)
            parts.push(item.notes);
        if (item.checklist.length > 0) {
            const done = item.checklist.filter(entry => entry.done).length;
            parts.push(Translation.tr("Checklist %1/%2").arg(String(done)).arg(String(item.checklist.length)));
        }
        return parts.join("\n");
    }

    function notify(item, missed, silent): void {
        root.clearNotification(item.id);
        const id = Notifications.publishInternalNotification({
            appName: "Reminder",
            appIcon: "appointment-soon",
            summary: missed ? Translation.tr("Missed reminder · %1").arg(item.title || Translation.tr("Reminder"))
                : (item.title || Translation.tr("Reminder")),
            body: root.notificationBody(item),
            urgency: missed ? "normal" : "critical",
            actions: [
                { identifier: "__qs_reminder_complete", text: Translation.tr("Complete") },
                { identifier: "__qs_reminder_snooze", text: Translation.tr("Snooze %1 min").arg(String(root.snoozeMinutes)) },
                { identifier: "__qs_reminder_open", text: Translation.tr("Open") }
            ],
            actionPayload: { id: item.id },
            sound: !missed && !silent && (root.settings?.alertSound ?? true)
        });
        if (id !== null && id !== undefined) {
            const ids = Object.assign({}, root.notificationIds);
            ids[item.id] = id;
            root.notificationIds = ids;
        }
    }

    function notifyEarly(item): void {
        Notifications.publishInternalNotification({
            appName: "Reminder",
            appIcon: "appointment-soon",
            summary: Translation.tr("Coming up · %1").arg(item.title || Translation.tr("Reminder")),
            body: root.whenText(item, new Date()),
            actions: [
                { identifier: "__qs_reminder_complete", text: Translation.tr("Complete") },
                { identifier: "__qs_reminder_open", text: Translation.tr("Open") }
            ],
            actionPayload: { id: item.id },
            sound: false
        });
    }

    function clearNotification(id): void {
        const notificationId = root.notificationIds[id];
        if (notificationId === undefined)
            return;
        const ids = Object.assign({}, root.notificationIds);
        delete ids[id];
        root.notificationIds = ids;
        Notifications.discardNotification(notificationId);
    }

    /** Opens the clock app on Reminders, with this reminder's editor when one is named. */
    function open(id): void {
        GlobalStates.reminderToOpen = String(id ?? "");
        GlobalStates.openClockApp("reminders");
    }

    Connections {
        target: Notifications
        function onInternalActionInvoked(identifier, notificationId, payload) {
            if (!String(identifier).startsWith("__qs_reminder_"))
                return;
            const id = String(payload?.id ?? "");
            const ids = Object.assign({}, root.notificationIds);
            delete ids[id];
            root.notificationIds = ids;
            if (identifier === "__qs_reminder_complete")
                root.complete(id);
            else if (identifier === "__qs_reminder_snooze")
                root.snooze(id, root.snoozeMinutes);
            else if (identifier === "__qs_reminder_open")
                root.open(id);
            Notifications.discardNotification(notificationId);
        }
    }

    Timer {
        id: alertTimer
        repeat: false
        onTriggered: root.checkAlerts()
    }

    // "medium" rings once: a few seconds of the alarm sound, then quiet.
    Timer {
        id: chimeTimer
        interval: 4000
        onTriggered: SoundService.stopLoop()
    }

    // A "strong" reminder nobody answers goes quiet and leaves a notification.
    Timer {
        interval: Math.max(1, root.autoSilenceMinutes) * 60000
        running: root.ringingId.length > 0 && root.autoSilenceMinutes > 0
        onTriggered: root.stopRinging(true)
    }

    // The recycle bin and old completed reminders are cleared out a few times a day.
    Timer {
        interval: 6 * 3600000
        repeat: true
        running: root.loaded && (root.trashDays > 0 || root.autoDeleteCompletedDays > 0)
        onTriggered: root.expire()
    }

    function expire(): void {
        const doomed = Logic.expired(root.reminders, Date.now(), root.trashDays, root.autoDeleteCompletedDays);
        if (doomed.length === 0)
            return;
        // Completed ones go to the bin first; the bin itself empties for good.
        const binned = doomed.filter(id => (root.reminder(id)?.deletedAt ?? 0) > 0);
        const completed = doomed.filter(id => !binned.includes(id));
        if (binned.length > 0)
            root.deleteForever(binned);
        if (completed.length > 0)
            root.trash(completed);
    }

    onAllDayTimeChanged: root.reschedule()
    onDefaultAlertChanged: wakeDebounce.restart()

    // ── Wake from suspend ───────────────────────────────────────────────
    // Same mechanism as AlarmService (a transient systemd user timer with WakeSystem),
    // and only for reminders that take the screen: a notification can wait for the lid.
    readonly property string wakeUnit: "ii-reminder-wake"
    property string scheduledWakeKey: "#unsynced"

    function scheduleWake(): void {
        let wakeAt = null;
        if (root.wakeFromSuspend) {
            root.reminders.forEach(item => {
                if (root.levelOf(item) === "light")
                    return;
                const alerts = Logic.pendingAlerts(item, root.allDayTime).filter(alert => alert.kind === "main");
                if (alerts.length > 0 && (!wakeAt || alerts[0].at < wakeAt.getTime()))
                    wakeAt = new Date(alerts[0].at - 60000);
            });
        }
        if (wakeAt && wakeAt.getTime() <= Date.now() + 30000)
            wakeAt = null;
        const key = wakeAt ? Qt.formatDateTime(wakeAt, "yyyy-MM-dd HH:mm:ss") : "";
        if (key === root.scheduledWakeKey)
            return;
        root.scheduledWakeKey = key;
        const unit = root.wakeUnit;
        let script = `systemctl --user stop ${unit}.timer 2>/dev/null; systemctl --user reset-failed ${unit}.timer ${unit}.service 2>/dev/null;`;
        if (key.length > 0)
            script += ` systemd-run --user --quiet --unit=${unit} --on-calendar='${key}' --timer-property=WakeSystem=true --timer-property=AccuracySec=1s /bin/true`;
        wakeProc.command = ["sh", "-c", script];
        wakeProc.running = false;
        wakeProc.running = true;
    }

    Process {
        id: wakeProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0)
                    console.warn("[Reminders] wake timer:", this.text.trim());
            }
        }
    }

    Timer {
        id: wakeDebounce
        interval: 2000
        onTriggered: root.scheduleWake()
    }

    // ── Persistence ─────────────────────────────────────────────────────
    function snapshot() {
        return {
            version: 1,
            categories: root.categories,
            reminders: root.reminders,
            tombstones: root.tombstones,
            recent: root.recent,
            sync: root.syncState
        };
    }

    /** RemindersSync hands back the merged store; nothing it returns counts as a local edit. */
    function applySynced(store): void {
        const normalized = Logic.normalizeStore(store, Date.now(), "My reminders");
        root.tombstones = normalized.tombstones;
        root.syncState = normalized.sync;
        // Keep the alert bookkeeping this machine owns: To Do knows nothing of it.
        const local = {};
        root.reminders.forEach(item => local[item.id] = item);
        const now = Date.now();
        const merged = normalized.reminders.map(item => {
            const mine = local[item.id];
            // New from the phone, or moved there: what is already past was the phone's
            // to ring, not a pile of "missed" notices here.
            if (!mine)
                return root.settle(item, now);
            const sameOccurrence = Logic.occurrenceKey(item) === Logic.occurrenceKey(mine);
            item.firedFor = sameOccurrence ? mine.firedFor : "";
            item.earlyFiredFor = sameOccurrence ? mine.earlyFiredFor : "";
            if (!sameOccurrence)
                root.settle(item, now);
            item.snoozedUntil = mine.snoozedUntil;
            return JSON.stringify(item) === JSON.stringify(mine) ? mine : item;
        });
        root.commitCategories(normalized.categories, true);
        root.commit(merged, true);
    }

    function setSyncState(state): void {
        root.syncState = state ?? ({});
        root.saveSoon();
    }

    function setTombstones(list): void {
        root.tombstones = Array.from(list ?? []);
        root.saveSoon();
    }

    function saveSoon(): void {
        if (root.loaded)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: storeFile.setText(JSON.stringify(root.snapshot(), null, 1))
    }

    property double initTimestamp: Date.now()

    FileView {
        id: storeFile
        path: Qt.resolvedUrl(Directories.remindersPath)
        atomicWrites: true
        onLoaded: {
            let parsed = null;
            try {
                parsed = JSON.parse(storeFile.text());
            } catch (error) {
                console.warn("[Reminders] Unreadable reminders file, keeping it untouched:", error);
                return;
            }
            const store = Logic.normalizeStore(parsed, Date.now(), "My reminders");
            // Anything added before the file was read (an IPC call at startup) is kept.
            const early = root.reminders.filter(item => !store.reminders.some(stored => stored.id === item.id));
            root.categories = store.categories;
            root.reminders = store.reminders.concat(early);
            root.tombstones = store.tombstones;
            root.recent = store.recent;
            root.syncState = store.sync;
            root.loaded = true;
            root.expire();
            root.checkAlerts();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                console.warn("[Reminders] Could not read the reminders file:", error);
                return;
            }
            // Transiently missing during a hot reload: look again before starting empty.
            if (Date.now() - root.initTimestamp < 3000) {
                retryTimer.restart();
                return;
            }
            const store = Logic.normalizeStore({ categories: root.categories, reminders: root.reminders }, Date.now(), "My reminders");
            root.categories = store.categories;
            root.reminders = store.reminders;
            root.loaded = true;
            root.saveSoon();
            root.reschedule();
        }
    }

    Timer {
        id: retryTimer
        interval: 1000
        onTriggered: storeFile.reload()
    }

    // ── IPC ─────────────────────────────────────────────────────────────
    IpcHandler {
        target: "reminders"

        function add(title: string): string {
            return root.create({ title: title });
        }
        /// `when` is "yyyy-MM-dd HH:mm" (or "yyyy-MM-dd" for all day); `level` "" means the default.
        function addAt(title: string, when: string, level: string): string {
            const parts = String(when).trim().split(/\s+/);
            return root.create({ title: title, schedule: { date: parts[0], time: parts[1] ?? "" }, alert: level || "default" });
        }
        function list(): string {
            return root.liveReminders.map(item => [item.id, item.completed ? "x" : "-", item.title,
                root.whenText(item, new Date()), root.levelOf(item)].join(" | ")).join("\n");
        }
        function complete(id: string): void {
            root.complete(id);
        }
        function remove(id: string): void {
            root.trash([id]);
        }
        /// Gone for good, skipping the bin (and from To Do on the next sync).
        function purge(id: string): void {
            root.deleteForever([id]);
        }
        /// Forgets the typed titles the editor suggests from.
        function clearHistory(): void {
            root.recent = [];
            root.saveSoon();
        }
        function next(): string {
            const next = root.nextAlert;
            return next ? `${next.id} ${next.kind} ${Qt.formatDateTime(new Date(next.at), "yyyy-MM-dd HH:mm:ss")}` : "";
        }
        /// Fires a reminder's alert now, at its own level. For testing.
        function fire(id: string): void {
            const item = root.reminder(id);
            if (item)
                root.fire(item);
        }
        function ringing(): string {
            return root.ringingId.length > 0 ? `${root.ringingId} ${root.ringingLevel} | queued ${root.ringQueue.length}` : "-";
        }
        function dismiss(): void {
            root.stopRinging(true);
        }
        function snooze(minutes: int): void {
            if (root.ringingId.length > 0)
                root.snooze(root.ringingId, minutes);
        }
        function open(id: string): void {
            root.open(id);
        }
        function wake(): string {
            return root.scheduledWakeKey;
        }
    }
}
