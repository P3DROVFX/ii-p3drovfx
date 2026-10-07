import QtQuick
import qs
import qs.services
import qs.modules.common

/*
 * The To-Do widgets' view of the Todo service: the open tasks in the user's
 * order, today's finished count, and completion with a beat of delay so the
 * row can show its check before it leaves the list.
 */
QtObject {
    id: root

    // Completion waits this long, so the check and the strike are seen.
    property int completeDelay: 650
    // Ids being completed; the row reads it to draw itself checked.
    property var completing: ({})

    readonly property var openTasks: Array.from(Todo.list ?? []).filter(task => task && task.done !== true)
    readonly property int openCount: root.openTasks.length
    readonly property int doneToday: {
        const start = new Date();
        start.setHours(0, 0, 0, 0);
        return Array.from(Todo.doneTasks ?? []).filter(task => Number(task?.completedAt ?? 0) >= start.getTime()).length;
    }

    function keyOf(task) {
        return String(task?.id || task?.content || "");
    }

    function isCompleting(task) {
        return root.completing[root.keyOf(task)] === true;
    }

    function complete(task) {
        const key = root.keyOf(task);
        if (!key || root.completing[key])
            return;
        const next = Object.assign({}, root.completing);
        next[key] = true;
        root.completing = next;
        const timer = Qt.createQmlObject("import QtQuick; Timer { repeat: false }", root);
        timer.interval = root.completeDelay;
        timer.triggered.connect(() => {
            Todo.markDone(task);
            const after = Object.assign({}, root.completing);
            delete after[key];
            root.completing = after;
            timer.destroy();
        });
        timer.start();
    }

    function add(text) {
        const clean = String(text ?? "").trim();
        if (clean.length > 0)
            Todo.addTask(clean);
    }

    function dueOf(task) {
        if (!task?.hasDate || !task?.date)
            return null;
        const date = task.date instanceof Date ? task.date : new Date(task.date);
        return isNaN(date.getTime()) ? null : date;
    }

    function isOverdue(task) {
        const due = root.dueOf(task);
        if (!due)
            return false;
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const day = new Date(due);
        day.setHours(0, 0, 0, 0);
        return day < today;
    }

    function dueLabel(task) {
        const due = root.dueOf(task);
        if (!due)
            return "";
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const day = new Date(due);
        day.setHours(0, 0, 0, 0);
        const diff = Math.round((day - today) / 86400000);
        if (diff === 0)
            return Translation.tr("Today");
        if (diff === 1)
            return Translation.tr("Tomorrow");
        if (diff === -1)
            return Translation.tr("Yesterday");
        return Qt.locale().toString(due, "ddd d MMM").replace(/\./g, "");
    }
}
