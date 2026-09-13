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
     * persist the whole schema; TickTick's Open API accepts priority and a
     * notes body on create but not tags; Google Tasks only takes title, due
     * and notes. Surfaces hide the fields a provider cannot store instead of
     * silently dropping what the user typed.
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
            providerRefreshTimer.restart();
            root.refresh();
        } else {
            providerRefreshTimer.stop();
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
        running: true
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

    Timer {
        id: providerRefreshTimer
        interval: Math.max(1, (Config.options.todo ? Config.options.todo.refreshIntervalMinutes : 5)) * 60 * 1000
        repeat: true
        running: root.remoteEnabled && root.connected
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
