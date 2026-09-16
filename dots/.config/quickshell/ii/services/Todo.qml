pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import qs.services
import Quickshell.Io;
import QtQuick;
import qs.modules.common.functions


/**
 * Simple to-do list manager.
 * Each item is an object with "content" and "done" properties.
 * When TickTick is available, syncs with the TickTick API.
 */
Singleton {
    id: root
    property var filePath: Directories.todoPath
    property var doneHistoryPath: Directories.todoDoneHistoryPath
    property var doneHistoryList: []

    // See Config.qml for the rationale on these guards (avoid clobbering user
    // data during transient file inaccessibility; write atomically).
    property real initTimestamp: Date.now()
    property int missingFileGracePeriod: 2000
    property int missingFileRetryInterval: 1500

    // Provider resolution
    function resolveProvider() {
        const configured = Config.options.todo ? Config.options.todo.provider : "local";
        if (configured === "ticktick" || configured === "googleTasks" || configured === "local")
            return configured;
        return "local";
    }

    readonly property string configuredProvider: Config.options.todo ? Config.options.todo.provider : "local"
    readonly property string provider: root.resolveProvider()
    readonly property bool remoteEnabled: provider === "ticktick" || provider === "googleTasks"

    readonly property bool connected: {
        if (provider === "ticktick")
            return TickTickService.available;
        if (provider === "googleTasks")
            return GoogleTasksService.available;
        return true;
    }

    readonly property bool syncing: {
        if (provider === "ticktick")
            return TickTickService.syncing;
        if (provider === "googleTasks")
            return GoogleTasksService.syncing;
        return false;
    }

    readonly property string providerName: {
        if (provider === "ticktick")
            return "TickTick";
        if (provider === "googleTasks")
            return "Google Tasks";
        return Translation.tr("Local");
    }

    // Unified task list: either from TickTick, Google Tasks or local file
    property var list: {
        if (root.provider === "ticktick")
            return TickTickService.tasks;
        if (root.provider === "googleTasks")
            return GoogleTasksService.tasks;
        return root.localList;
    }
    property var localList: []

    readonly property bool hasDatedOpenTasks: Array.from(root.list ?? [])
        .some(task => task && task.done !== true && task.hasDate === true && task.date)

    onListChanged: {
        dueTasksNotifyTimer.restart();
    }

    readonly property var doneTasks: {
        const seen = new Set();
        const combined = [];
        const history = root.doneHistoryList ?? [];
        for (let i = 0; i < history.length; i++) {
            const item = history[i];
            if (!item) continue;
            const key = String(item.id || (String(item.content || "") + "|" + String(item.date || "")));
            if (!seen.has(key)) {
                seen.add(key);
                combined.push(item);
            }
        }
        const source = root.list ?? [];
        for (let i = 0; i < source.length; i++) {
            const item = source[i];
            if (!item || !item.done) continue;
            const key = String(item.id || (String(item.content || "") + "|" + String(item.date || "")));
            if (!seen.has(key)) {
                seen.add(key);
                combined.push(item);
            }
        }
        return combined.slice(0, 30);
    }

    function persistDoneHistory(next) {
        root.doneHistoryList = Array.from(next ?? []).slice(0, 30);
        todoDoneHistoryFileView.setText(JSON.stringify(root.doneHistoryList));
    }

    // AI's local provider remains deliberately independent from the user's
    // display/sync provider. Remote AI mutations use their provider contracts
    // directly; these operations only ever touch the local JSON list.
    readonly property string aiProviderId: "local"
    readonly property string aiListId: "local"

    function persistLocalTasks(next) {
        root.localList = Array.from(next ?? []);
        todoFileView.setText(JSON.stringify(root.localList));
    }

    function aiListTaskLists() {
        return [{
            id: root.aiListId,
            name: qsTr("Local tasks"),
            accountId: qsTr("This device")
        }];
    }

    function aiListTasks(filters = null) {
        const query = String(filters?.query ?? "").trim().toLowerCase();
        return root.localList.filter(task => {
            if (filters?.includeCompleted !== true && task?.done === true)
                return false;
            if (String(filters?.listId ?? "").length > 0 && String(filters.listId) !== root.aiListId)
                return false;
            if (query.length === 0)
                return true;
            return String(task?.content ?? task?.title ?? "").toLowerCase().includes(query)
                || String(task?.notes ?? "").toLowerCase().includes(query);
        }).map(task => Object.assign({}, task, {
            provider: root.aiProviderId,
            accountId: qsTr("This device"),
            listId: root.aiListId,
            listName: qsTr("Local tasks"),
            taskId: String(task?.id ?? "")
        }));
    }

    function aiCreateTask(input) {
        const title = String(input?.title ?? input?.content ?? "").trim();
        if (title.length === 0)
            return { ok: false, error: "A task needs a title" };
        const task = {
            id: "local-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8),
            provider: root.aiProviderId,
            accountId: qsTr("This device"),
            listId: root.aiListId,
            listName: qsTr("Local tasks"),
            content: title,
            title: title,
            notes: String(input?.notes ?? input?.content ?? ""),
            dueDate: input?.dueDate ?? null,
            date: input?.dueDate ? new Date(input.dueDate) : new Date(),
            hasDate: !!input?.dueDate,
            done: false
        };
        root.persistLocalTasks(root.localList.concat([task]));
        return { ok: true, task: task };
    }

    function aiUpdateTask(ref, changes) {
        const taskId = String(ref?.taskId ?? ref?.id ?? "");
        const index = root.localList.findIndex(task => String(task?.id ?? "") === taskId);
        if (index < 0)
            return { ok: false, error: "Task was not found" };
        const next = root.localList.slice(0);
        const current = Object.assign({}, next[index]);
        if (changes?.title !== undefined || changes?.content !== undefined) {
            const title = String(changes.title ?? changes.content).trim();
            if (title.length === 0)
                return { ok: false, error: "A task needs a title" };
            current.title = title;
            current.content = title;
        }
        if (changes?.notes !== undefined || changes?.contentText !== undefined)
            current.notes = String(changes.notes ?? changes.contentText);
        if (changes?.dueDate !== undefined) {
            current.dueDate = changes.dueDate;
            current.date = changes.dueDate ? new Date(changes.dueDate) : new Date();
            current.hasDate = !!changes.dueDate;
        }
        if (changes?.done !== undefined)
            current.done = changes.done === true;
        next[index] = current;
        root.persistLocalTasks(next);
        return { ok: true, task: current };
    }

    function aiCompleteTask(ref) {
        return root.aiUpdateTask(ref, { done: true });
    }

    function aiDeleteTask(ref) {
        const taskId = String(ref?.taskId ?? ref?.id ?? "");
        const index = root.localList.findIndex(task => String(task?.id ?? "") === taskId);
        if (index < 0)
            return { ok: false, error: "Task was not found" };
        const next = root.localList.slice(0);
        const removed = next.splice(index, 1)[0];
        root.persistLocalTasks(next);
        return { ok: true, task: removed };
    }

    function resolveLocalTaskIndex(taskOrIdOrIndex) {
        if (typeof taskOrIdOrIndex === "number") {
            return taskOrIdOrIndex;
        }
        if (typeof taskOrIdOrIndex === "string") {
            return root.localList.findIndex(item => String(item?.id ?? "") === taskOrIdOrIndex);
        }
        if (taskOrIdOrIndex && typeof taskOrIdOrIndex === "object") {
            const targetId = String(taskOrIdOrIndex.id ?? "");
            if (targetId.length > 0) {
                const idx = root.localList.findIndex(item => String(item?.id ?? "") === targetId);
                if (idx >= 0)
                    return idx;
            }
            if (taskOrIdOrIndex.originalIndex !== undefined && Number.isInteger(taskOrIdOrIndex.originalIndex)) {
                if (root.localList[taskOrIdOrIndex.originalIndex] === taskOrIdOrIndex)
                    return taskOrIdOrIndex.originalIndex;
            }
            return root.localList.findIndex(item => item === taskOrIdOrIndex
                || (String(item?.content ?? "") === String(taskOrIdOrIndex.content ?? "") && item?.date === taskOrIdOrIndex.date));
        }
        return -1;
    }

    function addLocalItem(item) {
        root.localList = root.localList.concat([root.normalizeTask(item)]);
        todoFileView.setText(JSON.stringify(root.localList));
    }

    function setLocalTaskDone(index, done) {
        if (index >= 0 && index < root.localList.length) {
            const next = root.localList.slice(0);
            next[index] = Object.assign({}, next[index], { done: done === true });
            root.localList = next;
            todoFileView.setText(JSON.stringify(root.localList));
        }
    }

    function deleteLocalItem(index) {
        if (index >= 0 && index < root.localList.length) {
            const next = root.localList.slice(0);
            next.splice(index, 1);
            root.localList = next;
            todoFileView.setText(JSON.stringify(root.localList));
        }
    }

    /**
     * What each field of the creation form is allowed to exist. Local tasks
     * persist the whole schema; the TickTick form exposes priority and notes,
     * while Google Tasks only takes title, due and notes. Surfaces hide the
     * fields this integration does not store.
     */
    readonly property bool supportsDate: true
    readonly property bool supportsNotes: true
    readonly property bool supportsPriority: root.provider !== "googleTasks"
    readonly property bool supportsTags: root.provider === "local"

    function parseLocalDate(value) {
        if (!value)
            return null;
        if (value instanceof Date)
            return isNaN(value.getTime()) ? null : value;
        const str = String(value).trim();
        const match = str.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T\s](\d{2}):(\d{2})(?::(\d{2}))?)?/);
        if (match) {
            const year = Number(match[1]);
            const month = Number(match[2]) - 1;
            const day = Number(match[3]);
            const hours = match[4] !== undefined ? Number(match[4]) : 0;
            const minutes = match[5] !== undefined ? Number(match[5]) : 0;
            const seconds = match[6] !== undefined ? Number(match[6]) : 0;
            if (!match[4] || (hours === 0 && minutes === 0 && seconds === 0)) {
                return new Date(year, month, day, 0, 0, 0);
            }
            const parsed = new Date(str);
            return isNaN(parsed.getTime()) ? new Date(year, month, day) : parsed;
        }
        const d = new Date(str);
        return isNaN(d.getTime()) ? null : d;
    }

    /**
     * One schema for a task, wherever it ends up. Extra fields the caller
     * passed are kept for local persistence; remote providers map only what
     * they accept, so a tag typed for a Google task is not silently "saved".
     */
    function normalizeTask(item) {
        const next = Object.assign({}, item);
        next.id = String(item?.id || ("local-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8)));
        next.content = String(item?.content ?? item?.title ?? "");
        next.done = item?.done === true;
        const rawDate = item?.dueDate ?? item?.date;
        const date = root.parseLocalDate(rawDate);
        const hasExplicitHasDate = typeof item?.hasDate === "boolean";
        next.hasDate = hasExplicitHasDate ? (item.hasDate && date !== null && !isNaN(date.getTime())) : (date !== null && !isNaN(date.getTime()));
        next.date = next.hasDate ? date : null;
        next.notes = String(item?.notes ?? "");
        next.priority = Number.isInteger(item?.priority) ? item.priority : 0;
        next.tags = Array.isArray(item?.tags) ? item.tags.map(String) : [];
        if (item?.completedAt)
            next.completedAt = item.completedAt;
        return next;
    }

    function addItem(item) {
        if (!item)
            return;
        const dueDate = root.serializedDueDate(item);
        switch (root.provider) {
        case "ticktick": {
            const extra = {};
            if (dueDate)
                extra.dueDate = dueDate;
            if (item.notes && item.notes.length > 0)
                extra.content = item.notes;
            if (item.priority)
                extra.priority = item.priority;
            TickTickService.createTask(item.content, Object.keys(extra).length > 0 ? extra : null);
            return;
        }
        case "googleTasks":
            GoogleTasksService.createTask(item.content, dueDate, item.notes ?? "");
            return;
        default:
            root.addLocalItem(item);
            return;
        }
    }

    function addTask(desc) {
        const item = {
            "content": desc,
            "done": false,
        };
        addItem(item);
    }

    function serializedDueDate(item) {
        const value = item?.dueDate ?? item?.date;
        if (!value)
            return "";
        const date = value instanceof Date ? value : new Date(value);
        if (isNaN(date.getTime()))
            return "";
        return Qt.formatDate(date, "yyyy-MM-dd") + "T00:00:00.000Z";
    }

    /**
     * Tasks due on one day.
     *
     * `hasDate` is the gate, not `date`: providers fill `date` with *now* for a
     * task that has no due date, so matching on the date alone pins the whole
     * undated backlog onto today.
     */
    function getTasksByDate(currentDate) {
        const res = [];

        const currentDay = currentDate.getDate();
        const currentMonth = currentDate.getMonth();
        const currentYear = currentDate.getFullYear();

        for (let i = 0; i < root.list.length; i++) {
            if (root.list[i]?.hasDate !== true || !root.list[i]?.date)
                continue;
            const taskDate = root.list[i]['date'] instanceof Date
                ? root.list[i]['date']
                : root.parseLocalDate(root.list[i]['date']);
            if (!taskDate || isNaN(taskDate.getTime()))
                continue;
            if (
                taskDate.getDate() === currentDay &&
                taskDate.getMonth() === currentMonth &&
                taskDate.getFullYear() === currentYear
              ) {
                res.push(root.list[i]);
              }
        }

        return res;
    }

    /** Open tasks with no due date, which belong to no day in the calendar. */
    function getUndatedTasks() {
        return root.list.filter(task => task && task.hasDate !== true && !task.done);
    }

    function getOverdueTasks(currentDate = new Date()) {
        const today = new Date(currentDate.getFullYear(), currentDate.getMonth(), currentDate.getDate()).getTime();
        return root.list.filter(task => {
            if (!task?.hasDate || !task?.date || task.done)
                return false;
            const due = task.date instanceof Date ? task.date : root.parseLocalDate(task.date);
            if (!due || isNaN(due.getTime()))
                return false;
            const dueDay = new Date(due.getFullYear(), due.getMonth(), due.getDate()).getTime();
            return !isNaN(dueDay) && dueDay < today;
        });
    }

    // Callers can pass an index, a task object, or an id.
    function markDone(taskOrIndex) {
        let task = (typeof taskOrIndex === "object" && taskOrIndex !== null)
            ? taskOrIndex
            : (typeof taskOrIndex === "number" ? root.list[taskOrIndex] : null);

        if (!task && typeof taskOrIndex === "string") {
            task = (root.list ?? []).find(item => String(item?.id ?? "") === taskOrIndex);
        }

        const normalized = task ? root.normalizeTask(task) : null;
        if (normalized) {
            normalized.done = true;
            normalized.completedAt = Date.now();
            const targetKey = String(normalized.id || normalized.content);
            const remaining = (root.doneHistoryList ?? []).filter(item => {
                const itemKey = String(item?.id || item?.content || "");
                return itemKey !== targetKey;
            });
            root.persistDoneHistory([normalized].concat(remaining).slice(0, 30));
        }

        switch (root.provider) {
        case "ticktick":
            if (task)
                TickTickService.setTaskDone(task, true);
            return;
        case "googleTasks":
            if (task)
                GoogleTasksService.setTaskDone(task, true);
            return;
        default: {
            const index = root.resolveLocalTaskIndex(taskOrIndex);
            if (index >= 0)
                root.setLocalTaskDone(index, true);
            return;
        }
        }
    }

    function markUnfinished(taskOrIndex) {
        let task = (typeof taskOrIndex === "object" && taskOrIndex !== null)
            ? taskOrIndex
            : (typeof taskOrIndex === "number" ? (root.doneTasks[taskOrIndex] || root.list[taskOrIndex]) : null);

        const targetId = typeof taskOrIndex === "object" ? String(taskOrIndex?.id ?? "") : (typeof taskOrIndex === "string" ? taskOrIndex : (task ? String(task?.id ?? "") : ""));
        const targetContent = typeof taskOrIndex === "object" ? String(taskOrIndex?.content ?? "") : (task ? String(task?.content ?? "") : "");

        const remaining = (root.doneHistoryList ?? []).filter(item => {
            if (targetId.length > 0 && String(item?.id ?? "") === targetId)
                return false;
            if (targetContent.length > 0 && String(item?.content ?? "") === targetContent)
                return false;
            return true;
        });
        if (remaining.length !== (root.doneHistoryList ?? []).length) {
            root.persistDoneHistory(remaining);
        }

        switch (root.provider) {
        case "ticktick":
            if (task)
                TickTickService.setTaskDone(task, false);
            return;
        case "googleTasks":
            if (task)
                GoogleTasksService.setTaskDone(task, false);
            return;
        default: {
            const index = root.resolveLocalTaskIndex(taskOrIndex);
            if (index >= 0)
                root.setLocalTaskDone(index, false);
            return;
        }
        }
    }

    function deleteItem(taskOrIndex) {
        const task = (typeof taskOrIndex === "object" && taskOrIndex !== null)
            ? taskOrIndex
            : (typeof taskOrIndex === "number" ? root.list[taskOrIndex] : null);

        const targetId = typeof taskOrIndex === "object" ? String(taskOrIndex?.id ?? "") : (typeof taskOrIndex === "string" ? taskOrIndex : (task ? String(task?.id ?? "") : ""));
        const targetContent = typeof taskOrIndex === "object" ? String(taskOrIndex?.content ?? "") : (task ? String(task?.content ?? "") : "");

        const remaining = (root.doneHistoryList ?? []).filter(item => {
            if (targetId.length > 0 && String(item?.id ?? "") === targetId)
                return false;
            if (targetContent.length > 0 && String(item?.content ?? "") === targetContent)
                return false;
            return true;
        });
        if (remaining.length !== (root.doneHistoryList ?? []).length) {
            root.persistDoneHistory(remaining);
        }

        switch (root.provider) {
        case "ticktick":
            if (task)
                TickTickService.deleteTask(task);
            return;
        case "googleTasks":
            if (task)
                GoogleTasksService.deleteTask(task);
            return;
        default: {
            const index = root.resolveLocalTaskIndex(taskOrIndex);
            if (index >= 0)
                root.deleteLocalItem(index);
            return;
        }
        }
    }

    /**
     * Whether the edit form may save this task.
     *
     * Identity check first: the task must still resolve in the live list of
     * its own provider, so a form left open across a provider or account
     * switch cannot save into whatever is now selected. A done-history entry
     * from a provider the user has since left fails the lookup and is not
     * editable, instead of being routed at the currently selected account.
     */
    function canEditTask(task) {
        if (!task || typeof task !== "object")
            return false;
        const provider = String(task.provider ?? root.provider);
        if (provider === "local")
            return root.provider === "local" && root.resolveLocalTaskIndex(task) >= 0;
        if (provider === "ticktick")
            return root.provider === "ticktick" && TickTickService.available
                && (root._taskListContains(TickTickService.tasks, task.id)
                    || (task.done === true && !!task.containerId && root._taskListContains(root.doneHistoryList, task.id)));
        if (provider === "googleTasks")
            return root.provider === "googleTasks" && GoogleTasksService.available
                && task.accountId === GoogleTasksService.activeAccountEmail
                && root._taskListContains(GoogleTasksService.tasks, task.id);
        return false;
    }

    function _taskListContains(tasks, id) {
        const target = String(id ?? "");
        if (target.length === 0)
            return false;
        return Array.from(tasks ?? []).some(item => item && String(item?.id ?? "") === target);
    }

    /** Calendar day of a due value as "yyyy-MM-dd", null for no date, undefined for an unusable value. */
    function _dueDay(value) {
        if (value === null || value === undefined || String(value).length === 0)
            return null;
        const parsed = root.parseLocalDate(value);
        if (!parsed || isNaN(parsed.getTime()))
            return undefined;
        return Qt.formatDate(parsed, "yyyy-MM-dd");
    }

    /**
     * Reduces the full form payload to what actually differs from the task.
     *
     * Remote providers patch individual fields, and re-sending an identical
     * dueDate would rewrite a date the user never touched. Only `content`,
     * `notes`, `date`, `priority` and `tags` are compared; anything else the
     * form sends is ignored. `date: null` means "remove the due date".
     */
    function _taskChangeset(task, changes) {
        const result = {
            empty: true
        };
        const trimmed = value => String(value ?? "").trim();

        if (changes?.content !== undefined) {
            const title = trimmed(changes.content);
            if (title !== trimmed(task?.content ?? task?.title ?? "")) {
                result.title = title;
                result.empty = false;
            }
        }
        if (changes?.notes !== undefined) {
            const notes = String(changes.notes ?? "");
            if (notes.trim() !== trimmed(task?.notes ?? "")) {
                result.notes = notes;
                result.empty = false;
            }
        }
        if (changes?.date !== undefined) {
            const nextDay = root._dueDay(changes.date);
            const currentDay = root._dueDay((task?.hasDate === true && task?.date) ? task.date : null);
            if (nextDay !== undefined && nextDay !== currentDay) {
                result.date = nextDay === null ? null : root.parseLocalDate(changes.date);
                result.empty = false;
            }
        }
        if (changes?.priority !== undefined) {
            const priority = Number(changes.priority) || 0;
            if (priority !== (Number(task?.priority) || 0)) {
                result.priority = priority;
                result.empty = false;
            }
        }
        if (changes?.tags !== undefined) {
            const nextTags = Array.from(changes.tags ?? [], String);
            const currentTags = Array.from(task?.tags ?? [], String);
            if (nextTags.join("\u0000") !== currentTags.join("\u0000")) {
                result.tags = nextTags;
                result.empty = false;
            }
        }
        return result;
    }

    /**
     * Edits an existing task in place: no task is created, the existing id
     * travels to its provider.
     *
     * `task` is the object the form was opened with (a copy is fine as long
     * as it keeps `id`, plus `provider` for a history entry that came from
     * another provider). `changes` holds the form fields — every one optional;
     * `date: null` clears the due date, an empty `notes` string clears notes.
     * Returns true when the change was accepted for dispatch (an untouched
     * form is an accepted no-op); async failures surface through the
     * provider's existing error channel (`lastError` / `lastErrorMessage`).
     */
    function updateItem(task, changes) {
        if (!root.canEditTask(task) || !changes || typeof changes !== "object")
            return false;

        const changed = root._taskChangeset(task, changes);
        if (changed.title !== undefined && changed.title.length === 0)
            return false;

        switch (String(task.provider ?? root.provider)) {
        case "ticktick": {
            if (changed.empty)
                return true;
            // Keep the existing form's field capabilities; remote tags remain unchanged.
            return TickTickService.updateTask(task, {
                content: changed.title,
                notes: changed.notes,
                date: changed.date,
                priority: changed.priority
            });
        }
        case "googleTasks": {
            if (changed.empty)
                return true;
            // Google Tasks stores neither priority nor tags; those changes
            // are dropped the same way the creation form hides the fields.
            return GoogleTasksService.updateTask(task, {
                content: changed.title,
                notes: changed.notes,
                date: changed.date
            });
        }
        default:
            return root.updateLocalItem(task, changed);
        }
    }

    /**
     * Local edits persist the merged task directly. Unseen fields (anything
     * the schema does not name), `done`, `id`, `completedAt` and the provider
     * bookkeeping ride along untouched; `done` tasks keep their history entry
     * in step so the done list does not show the pre-edit text.
     */
    function updateLocalItem(task, changed) {
        const index = root.resolveLocalTaskIndex(task);
        if (index < 0)
            return false;
        if (changed.empty)
            return true;

        const merged = Object.assign({}, root.localList[index]);
        delete merged.originalIndex;
        if (changed.title !== undefined) {
            merged.title = changed.title;
            merged.content = changed.title;
        }
        if (changed.notes !== undefined)
            merged.notes = changed.notes;
        if (changed.date !== undefined) {
            merged.dueDate = changed.date === null ? null : root.serializedDueDate({
                date: changed.date
            });
            merged.date = changed.date === null ? null : changed.date;
            merged.hasDate = changed.date !== null;
        }
        if (changed.priority !== undefined)
            merged.priority = changed.priority;
        if (changed.tags !== undefined)
            merged.tags = changed.tags;

        const next = root.localList.slice(0);
        next[index] = merged;
        root.persistLocalTasks(next);
        root._syncDoneHistoryEntry(merged);
        return true;
    }

    /** Keeps a done task's history row matching the task after an edit. */
    function _syncDoneHistoryEntry(updated) {
        if (updated?.done !== true)
            return;
        const id = String(updated?.id ?? "");
        if (id.length === 0)
            return;
        const history = root.doneHistoryList ?? [];
        const index = history.findIndex(item => String(item?.id ?? "") === id);
        if (index < 0)
            return;
        const next = history.slice(0);
        next[index] = Object.assign({}, next[index], updated);
        root.persistDoneHistory(next);
    }

    Connections {
        target: GoogleTasksService
        function onTaskUpdated(task) { root._syncDoneHistoryEntry(task); }
    }

    Connections {
        target: TickTickService
        function onTaskUpdated(task) { root._syncDoneHistoryEntry(task); }
    }

    function refresh() {
        switch (root.provider) {
        case "ticktick":
            TickTickService.refresh();
            return;
        case "googleTasks":
            GoogleTasksService.refresh();
            return;
        default:
            todoFileView.reload();
            return;
        }
    }

    onProviderChanged: {
        if (root.remoteEnabled && root.connected) {
            root.refresh();
        }
    }

    function checkDueTasksNotifications() {
        if (!Persistent.ready)
            return;

        const now = new Date();
        const todayStr = Qt.formatDate(now, "yyyy-MM-dd");
        const currentYear = now.getFullYear();
        const currentMonth = now.getMonth();
        const currentDay = now.getDate();

        const notifiedKeys = Array.from(Persistent.states.sidebar.bottomGroup.todoNotifiedToday ?? []);
        let newlyNotified = false;
        const cutoffTime = now.getTime() - 48 * 60 * 60 * 1000;

        // Prune entries older than 48 hours
        const activeKeys = notifiedKeys.filter(key => {
            const parts = String(key).split("|");
            if (parts.length >= 2) {
                const d = new Date(parts[1] + "T00:00:00");
                return !isNaN(d.getTime()) && d.getTime() >= cutoffTime;
            }
            return false;
        });

        const activeSet = new Set(activeKeys);

        const tasks = root.list ?? [];
        for (let i = 0; i < tasks.length; i++) {
            const task = tasks[i];
            if (!task || task.done || !task.hasDate || !task.date)
                continue;

            const taskDate = task.date instanceof Date ? task.date : root.parseLocalDate(task.date);
            if (!taskDate || isNaN(taskDate.getTime()))
                continue;

            if (taskDate.getFullYear() === currentYear &&
                taskDate.getMonth() === currentMonth &&
                taskDate.getDate() === currentDay) {

                const taskKey = String(task.id || task.content) + "|" + todayStr;
                if (!activeSet.has(taskKey)) {
                    activeSet.add(taskKey);
                    activeKeys.push(taskKey);
                    newlyNotified = true;

                    const priorityTag = task.priority >= 5 ? ("[" + Translation.tr("High priority") + "] ") : (task.priority >= 3 ? ("[" + Translation.tr("Medium priority") + "] ") : "");
                    const bodyText = priorityTag + (task.notes ? task.notes : "");

                    Notifications.publishInternalNotification({
                        appName: "To Do",
                        appIcon: "task-due",
                        summary: Translation.tr("Task due today: %1").arg(task.content),
                        body: bodyText,
                        sound: true
                    });
                }
            }
        }

        if (newlyNotified || activeKeys.length !== notifiedKeys.length) {
            Persistent.states.sidebar.bottomGroup.todoNotifiedToday = activeKeys;
        }
    }

    Timer {
        id: dueTasksPeriodicTimer
        interval: 60 * 1000
        repeat: true
        running: root.hasDatedOpenTasks
        onTriggered: root.checkDueTasksNotifications()
    }

    Timer {
        id: dueTasksNotifyTimer
        interval: 500
        repeat: false
        onTriggered: root.checkDueTasksNotifications()
    }

    Component.onCompleted: {
        refresh();
        dueTasksNotifyTimer.restart();
    }

    // TickTick owns its own timer so it cannot be refreshed twice. Google
    // Tasks has no provider-local timer, so Todo keeps this single fallback
    // owner for Google only.
    Timer {
        id: providerRefreshTimer
        interval: Math.max(1, (Config.options.todo ? Config.options.todo.refreshIntervalMinutes : 5)) * 60 * 1000
        repeat: true
        running: root.provider === "googleTasks" && root.connected
        onTriggered: root.refresh()
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        atomicWrites: true
        onLoaded: {
            const fileContents = todoFileView.text()
            try {
                const parsed = JSON.parse(fileContents);
                if (Array.isArray(parsed)) {
                    root.localList = parsed.map(item => root.normalizeTask(item));
                } else {
                    root.localList = [];
                }
            } catch (e) {
                console.warn("[To Do] Error parsing todo file:", e);
                root.localList = [];
            }

            console.log("[To Do] File loaded, " + root.localList.length + " tasks.")
        }
        onLoadFailed: (error) => {
            if(error != FileViewError.FileNotFound) {
                console.log("[To Do] Error loading file: " + error)
                return
            }
            // File might be transiently missing during a shell hot-reload or
            // restart — retrying first avoids wiping the user's todo list with
            // an empty array.
            if (Date.now() - root.initTimestamp > root.missingFileGracePeriod) {
                console.log("[To Do] File not found after grace, creating new file.")
                root.localList = []
                todoFileView.setText(JSON.stringify(root.localList))
            } else {
                missingFileRetryTimer.restart()
            }
        }
    }

    Timer {
        id: missingFileRetryTimer
        interval: root.missingFileRetryInterval
        repeat: false
        onTriggered: todoFileView.reload()
    }

    FileView {
        id: todoDoneHistoryFileView
        path: Qt.resolvedUrl(root.doneHistoryPath)
        atomicWrites: true
        onLoaded: {
            const fileContents = todoDoneHistoryFileView.text();
            try {
                const parsed = JSON.parse(fileContents);
                if (Array.isArray(parsed)) {
                    root.doneHistoryList = parsed.map(item => root.normalizeTask(item)).slice(0, 30);
                } else {
                    root.doneHistoryList = [];
                }
            } catch (e) {
                console.warn("[To Do] Error parsing todo done history file:", e);
                root.doneHistoryList = [];
            }

            console.log("[To Do] Done history loaded, " + root.doneHistoryList.length + " tasks.");
        }
        onLoadFailed: (error) => {
            if (error != FileViewError.FileNotFound) {
                console.log("[To Do] Error loading done history file: " + error);
                return;
            }
            if (Date.now() - root.initTimestamp > root.missingFileGracePeriod) {
                root.doneHistoryList = [];
                todoDoneHistoryFileView.setText(JSON.stringify(root.doneHistoryList));
            } else {
                missingDoneFileRetryTimer.restart();
            }
        }
    }

    Timer {
        id: missingDoneFileRetryTimer
        interval: root.missingFileRetryInterval
        repeat: false
        onTriggered: todoDoneHistoryFileView.reload()
    }
}
