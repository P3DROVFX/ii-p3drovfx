pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Slim RemindersService stand-in for standalone apps: reads the shell's
 * reminders.json for timetable projections and forwards completions via IPC.
 */
Singleton {
    id: root

    property var _items: []

    function timetableItems(fromDate, toDate) {
        if (!(fromDate instanceof Date) || !(toDate instanceof Date))
            return [];
        const fromMs = fromDate.getTime();
        const toMs = toDate.getTime();
        const out = [];
        for (const item of root._items) {
            if (!item || item.completed || item.archived)
                continue;
            const dueRaw = item.dueAt ?? item.nextTriggerAt ?? item.scheduledAt ?? item.dueDate;
            if (!dueRaw)
                continue;
            const dt = new Date(dueRaw);
            if (isNaN(dt.getTime()))
                continue;
            const ms = dt.getTime();
            if (ms < fromMs || ms >= toMs)
                continue;
            out.push({
                id: String(item.id ?? ""),
                title: String(item.title ?? item.content ?? ""),
                content: String(item.title ?? item.content ?? ""),
                notes: String(item.notes ?? item.description ?? ""),
                date: dt,
                startDate: dt,
                allDay: Boolean(item.allDay),
                priority: Number(item.priority ?? 0),
                reminderItem: true
            });
        }
        return out;
    }

    function completeTask(id) {
        const cleanId = String(id ?? "").trim();
        if (!cleanId)
            return;
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "reminders", "complete", cleanId]);
    }

    FileView {
        id: remindersFile
        path: Qt.resolvedUrl(Directories.remindersPath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(remindersFile.text());
                root._items = Array.isArray(parsed) ? parsed : (Array.isArray(parsed?.items) ? parsed.items : []);
            } catch (e) {
                root._items = [];
            }
        }
        onLoadFailed: root._items = []
    }
}
