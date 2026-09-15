pragma Singleton

import QtQuick
import Quickshell
import Yunhai.Sys

/**
 * The task-manager half of the plugin, held until something looks at it.
 *
 * ProcessTable spends its flash of CPU work on `refresh()` calls, each one a full
 * snapshot of every process, and the shell has no reason to pay for that except when
 * a process list is on screen. So this singleton exists, the widgets ask *it*, and
 * nothing polls until the family's task-manager surface is actually open.
 */
Singleton {
    id: root

    readonly property int sortByCpu: 0
    readonly property int sortByMemory: 1
    readonly property int sortByName: 2

    property bool active: false
    property int interval: 2000
    property string filter: ""
    property int sortKey: root.sortByCpu
    property bool sortDescending: true

    readonly property var model: ProcessTable
    readonly property int visibleCount: ProcessTable.count
    readonly property int totalCount: ProcessTable.totalCount
    readonly property bool warmingUp: ProcessTable.warmingUp

    function killProcess(pid) {
        ProcessTable.killProcess(pid);
    }

    function forceKillProcess(pid) {
        ProcessTable.forceKillProcess(pid);
    }

    onActiveChanged: {
        if (root.active)
            prime.restart();
    }

    Timer {
        id: prime
        interval: 0
        onTriggered: {
            ProcessTable.refresh();
            if (ProcessTable.warmingUp)
                warmup.restart();
        }
    }

    Binding {
        target: ProcessTable
        property: "filter"
        value: root.filter
    }

    Binding {
        target: ProcessTable
        property: "sortKey"
        value: root.sortKey
    }

    Binding {
        target: ProcessTable
        property: "sortDescending"
        value: root.sortDescending
    }

    Timer {
        interval: root.interval
        running: root.active
        repeat: true
        onTriggered: ProcessTable.refresh()
    }

    Timer {
        id: warmup
        interval: 300
        onTriggered: ProcessTable.refresh()
    }
}