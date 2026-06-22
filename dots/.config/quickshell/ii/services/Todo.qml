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

    // Use TickTick if available
    readonly property bool useTickTick: TickTickService.available

    // Unified task list: either from TickTick or local file
    property var list: root.useTickTick ? TickTickService.tasks : root.localList
    property var localList: []

    // Sync state (for UI indicator)
    readonly property bool syncing: TickTickService.syncing

    function addItem(item) {
        if (root.useTickTick) {
            TickTickService.createTask(item.content);
            return;
        }
        localList.push(item)
        root.localList = localList.slice(0)
        todoFileView.setText(JSON.stringify(root.localList))
    }

    function addTask(desc) {
        const item = {
            "content": desc,
            "done": false,
        }
        addItem(item)
    }

    function getTasksByDate(currentDate) {
        const res = [];

        const currentDay = currentDate.getDate();
        const currentMonth = currentDate.getMonth();
        const currentYear = currentDate.getFullYear();

        for (let i = 0; i < root.list.length; i++) {
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

    function markDone(index) {
        if (root.useTickTick) {
            let task = root.list[index];
            if (task && task.id) {
                TickTickService.completeTask(task.id, task.projectId);
            }
            return;
        }
        if (index >= 0 && index < localList.length) {
            localList[index].done = true
            root.localList = localList.slice(0)
            todoFileView.setText(JSON.stringify(root.localList))
        }
    }

    function markUnfinished(index) {
        if (root.useTickTick) {
            // TickTick API doesn't have a simple "uncomplete" — refresh instead
            TickTickService.refresh();
            return;
        }
        if (index >= 0 && index < localList.length) {
            localList[index].done = false
            root.localList = localList.slice(0)

            if(CalendarService.khalAvailable){
              return
            }
            todoFileView.setText(JSON.stringify(root.localList))
        }
    }

    function deleteItem(index) {
        if (root.useTickTick) {
            let task = root.list[index];
            if (task && task.id) {
                TickTickService.deleteTask(task.id, task.projectId);
            }
            return;
        }
        if (index >= 0 && index < localList.length) {
            let item = localList[index]
            localList.splice(index, 1)
            root.localList = localList.slice(0)
            todoFileView.setText(JSON.stringify(root.localList))
        }
    }

    function refresh() {
        if (root.useTickTick) {
            TickTickService.refresh();
            return;
        }
        todoFileView.reload()
    }

    Component.onCompleted: {
        refresh()
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
