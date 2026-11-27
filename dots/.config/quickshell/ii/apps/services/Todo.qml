pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Slim Todo stand-in for standalone apps: watches the shell's todo.json directly
 * without booting GoogleTasksService, TickTickService, or Notifications.
 */
Singleton {
    id: root

    property var list: []
    property var tasksByDay: ({})

    function _dateKey(dateValue) {
        if (!dateValue)
            return "";
        if (dateValue instanceof Date)
            return isNaN(dateValue.getTime()) ? "" : Qt.formatDate(dateValue, "yyyy-MM-dd");
        const s = String(dateValue).trim();
        return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(0, 10) : "";
    }

    function _rebuildIndex() {
        const map = {};
        for (let i = 0; i < root.list.length; i++) {
            const item = root.list[i];
            if (!item)
                continue;
            const entry = Object.assign({ originalIndex: i }, item);
            const key = root._dateKey(item.dueDate);
            if (!key)
                continue;
            if (!map[key])
                map[key] = [];
            map[key].push(entry);
        }
        root.tasksByDay = map;
    }

    function _save() {
        todoFile.setText(JSON.stringify(root.list));
    }

    function getTasksByDate(date) {
        const key = root._dateKey(date);
        return key ? (root.tasksByDay[key] ?? []) : [];
    }

    function getOverdueTasks(referenceDate = new Date()) {
        const refKey = root._dateKey(referenceDate);
        if (!refKey)
            return [];
        const out = [];
        for (let i = 0; i < root.list.length; i++) {
            const item = root.list[i];
            if (!item || item.done)
                continue;
            const key = root._dateKey(item.dueDate);
            if (key && key < refKey)
                out.push(Object.assign({ originalIndex: i }, item));
        }
        return out;
    }

    function getUndatedTasks() {
        const out = [];
        for (let i = 0; i < root.list.length; i++) {
            const item = root.list[i];
            if (!item || item.done)
                continue;
            if (!root._dateKey(item.dueDate))
                out.push(Object.assign({ originalIndex: i }, item));
        }
        return out;
    }

    function addItem(content, dueDate = null, priority = 0) {
        const text = String(content ?? "").trim();
        if (!text)
            return;
        const next = Array.from(root.list);
        next.push({
            content: text,
            done: false,
            dueDate: dueDate ? root._dateKey(dueDate) : null,
            priority: Number(priority) || 0,
            createdAt: new Date().toISOString()
        });
        root.list = next;
        root._rebuildIndex();
        root._save();
    }

    function markDone(index) {
        const i = Number(index);
        if (isNaN(i) || i < 0 || i >= root.list.length)
            return;
        const next = Array.from(root.list);
        next[i] = Object.assign({}, next[i], { done: true });
        root.list = next;
        root._rebuildIndex();
        root._save();
    }

    FileView {
        id: todoFile
        path: Qt.resolvedUrl(Directories.todoPath)
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(todoFile.text());
                root.list = Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                root.list = [];
            }
            root._rebuildIndex();
        }
        onLoadFailed: {
            root.list = [];
            root._rebuildIndex();
        }
    }
}
