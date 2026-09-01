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

    function addLocalItem(item) {
        root.localList.push(item);
        root.localList = root.localList.slice(0);
        todoFileView.setText(JSON.stringify(root.localList));
    }

    function setLocalTaskDone(index, done) {
        if (index >= 0 && index < root.localList.length) {
            root.localList[index].done = done;
            root.localList = root.localList.slice(0);
            if (!done && CalendarService.khalAvailable) {
                return;
            }
            todoFileView.setText(JSON.stringify(root.localList));
        }
    }

    function deleteLocalItem(index) {
        if (index >= 0 && index < root.localList.length) {
            root.localList.splice(index, 1);
            root.localList = root.localList.slice(0);
            todoFileView.setText(JSON.stringify(root.localList));
        }
    }

    function addItem(item) {
        if (!item)
            return;
        const dueDate = root.serializedDueDate(item);
        switch (root.provider) {
        case "ticktick":
            TickTickService.createTask(item.content, dueDate ? { dueDate: dueDate } : null);
            return;
        case "googleTasks":
            GoogleTasksService.createTask(item.content, dueDate);
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
            if (root.list[i]?.hasDate !== true)
                continue;
            const taskDate = new Date(root.list[i]['date']);
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
            if (!task?.hasDate || task.done)
                return false;
            const due = new Date(task.date);
            const dueDay = new Date(due.getFullYear(), due.getMonth(), due.getDate()).getTime();
            return !isNaN(dueDay) && dueDay < today;
        });
    }

    // Existing callers pass the position in Todo.list. Month chips deliberately
    // pass the task object: their filtered/overdue list has a different index.
    function markDone(taskOrIndex) {
        const task = typeof taskOrIndex === "number" ? root.list[taskOrIndex] : taskOrIndex;
        if (!task)
            return;

        switch (root.provider) {
        case "ticktick":
            TickTickService.setTaskDone(task, true);
            return;
        case "googleTasks":
            GoogleTasksService.setTaskDone(task, true);
            return;
        default: {
            const index = typeof taskOrIndex === "number"
                ? taskOrIndex
                : root.localList.findIndex(item => item === task || String(item?.id ?? "") === String(task?.id ?? ""));
            if (index >= 0)
                root.setLocalTaskDone(index, true);
            return;
        }
        }
    }

    function markUnfinished(index) {
        const task = root.list[index];
        if (!task)
            return;

        switch (root.provider) {
        case "ticktick":
            TickTickService.setTaskDone(task, false);
            return;
        case "googleTasks":
            GoogleTasksService.setTaskDone(task, false);
            return;
        default:
            root.setLocalTaskDone(index, false);
            return;
        }
    }

    function deleteItem(index) {
        const task = root.list[index];
        if (!task)
            return;

        switch (root.provider) {
        case "ticktick":
            TickTickService.deleteTask(task);
            return;
        case "googleTasks":
            GoogleTasksService.deleteTask(task);
            return;
        default:
            root.deleteLocalItem(index);
            return;
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

    Component.onCompleted: {
        refresh();
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
            root.localList = JSON.parse(fileContents)

            for (let i=0; i< root.localList.length; i++){
              let d = root.localList[i]['date'];
              root.localList[i]['date'] = d ? new Date(d) : new Date();
              root.localList[i]['hasDate'] = d !== undefined && d !== null;
            }

            console.log("[To Do] File loaded")
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
}
