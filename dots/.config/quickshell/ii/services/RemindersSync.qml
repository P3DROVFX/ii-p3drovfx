pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Reminders ↔ Microsoft To Do, the bridge Samsung Reminder offers for reaching other
 * devices ("Sync with Microsoft To Do" on the phone, this on the desktop).
 *
 * Runs scripts/outlook/todo_sync.py with the whole store and a Graph token through the
 * Outlook sign-in, and hands the merged store back to RemindersService. Syncs on start,
 * a few seconds after each local edit, and every `intervalMinutes` — only while sync is
 * on and the account has granted To Do.
 *
 * An edit made while a sync is in flight is not lost: anything changed here after the
 * sync started keeps its local version (it is newer, and goes up next time).
 */
Singleton {
    id: root

    readonly property var options: Config.options.clockApp.reminders.todoSync
    readonly property bool enabled: root.options?.enable ?? false
    readonly property int intervalMinutes: Math.max(5, root.options?.intervalMinutes ?? 15)
    readonly property bool ready: root.enabled && OutlookService.authenticated && OutlookService.tasksConsented
    readonly property bool syncing: syncProcess.running || root.waitingForToken

    property bool waitingForToken: false
    property double startedAt: 0
    property var startedIds: []
    property int startedGraves: 0
    property string startedCategories: ""
    property string lastError: ""
    property var lastStats: null
    readonly property double lastSync: Number(RemindersService.syncState?.lastSync ?? 0)

    readonly property string statusText: {
        if (!root.enabled)
            return "";
        if (!OutlookService.authenticated)
            return Translation.tr("Not signed in");
        if (!OutlookService.tasksConsented)
            return Translation.tr("Needs To Do access");
        if (root.syncing)
            return Translation.tr("Syncing…");
        if (root.lastError.length > 0)
            return Translation.tr("Failed");
        if (root.lastSync > 0)
            return Translation.tr("Synced %1").arg(Qt.formatDateTime(new Date(root.lastSync), "HH:mm"));
        return "";
    }

    function syncNow(): void {
        if (!root.ready || root.syncing || !RemindersService.loaded)
            return;
        root.waitingForToken = true;
        OutlookService.withAccessToken(token => {
            root.waitingForToken = false;
            if (!token) {
                root.lastError = OutlookService.lastError || Translation.tr("Microsoft sign-in has expired.");
                return;
            }
            const store = RemindersService.snapshot();
            root.startedAt = Date.now();
            root.startedIds = store.reminders.map(item => item.id);
            root.startedGraves = store.tombstones.length;
            root.startedCategories = JSON.stringify(store.categories);
            syncProcess.payload = JSON.stringify({
                accessToken: token,
                store: store,
                now: root.startedAt,
                allDayTime: RemindersService.allDayTime
            });
            syncProcess.responseText = "";
            syncProcess.stdinEnabled = true;
            syncProcess.running = true;
        });
    }

    /** The script's store, minus whatever changed here while it ran. */
    function merge(remote) {
        const local = {};
        RemindersService.reminders.forEach(item => local[item.id] = item);
        const merged = [];
        const seen = {};
        for (const item of Array.from(remote.reminders ?? [])) {
            const mine = local[item.id];
            seen[item.id] = true;
            if (!mine) {
                // Deleted here for good while the sync ran: don't bring it back.
                if (root.startedIds.includes(item.id))
                    continue;
                merged.push(item);
            } else if (mine.modifiedAt > root.startedAt) {
                // Edited during the sync: ours, with the link the sync just made.
                const kept = JSON.parse(JSON.stringify(mine));
                if (!kept.remote && item.remote)
                    kept.remote = item.remote;
                merged.push(kept);
            } else {
                merged.push(item);
            }
        }
        // Created here during the sync.
        RemindersService.reminders.forEach(item => {
            if (!seen[item.id])
                merged.push(item);
        });
        // Graves dug during the sync wait for the next one (the list only ever grows here).
        const tombstones = Array.from(remote.tombstones ?? []).concat(RemindersService.tombstones.slice(root.startedGraves));
        // Categories edited during the sync stay as edited, with the links the sync made.
        let categories = remote.categories;
        if (JSON.stringify(RemindersService.categories) !== root.startedCategories) {
            const links = {};
            Array.from(remote.categories ?? []).forEach(category => links[category.id] = category.remote);
            categories = RemindersService.categories.map(category => Object.assign({}, category, {
                remote: category.remote ?? links[category.id] ?? null
            }));
        }
        return Object.assign({}, remote, { reminders: merged, tombstones: tombstones, categories: categories });
    }

    Process {
        id: syncProcess

        property string payload: ""
        property string responseText: ""

        command: ["python3", Directories.scriptPath + "/outlook/todo_sync.py"]
        stdinEnabled: true

        onRunningChanged: {
            if (!running)
                return;
            write(syncProcess.payload + "\n");
            syncProcess.payload = "";
            // true → false closes stdin, which is what lets the script read to EOF.
            stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: syncProcess.responseText = text.trim()
        }

        onExited: exitCode => {
            let reply = null;
            try {
                reply = JSON.parse(syncProcess.responseText);
            } catch (error) {
                reply = { ok: false, message: Translation.tr("Reminders sync returned an unreadable reply.") };
            }
            if (!reply?.ok) {
                root.lastError = String(reply?.message ?? Translation.tr("Reminders sync failed."));
                console.warn("[RemindersSync]", root.lastError);
                return;
            }
            root.lastError = "";
            root.lastStats = reply.stats ?? null;
            RemindersService.applySynced(root.merge(reply.store));
        }
    }

    // A local edit goes up a few seconds later, batched with whatever follows it.
    Connections {
        target: RemindersService
        enabled: root.ready
        function onEdited() {
            editDebounce.restart();
        }
        function onLoadedChanged() {
            if (RemindersService.loaded)
                startDelay.restart();
        }
    }

    Timer {
        id: editDebounce
        interval: 4000
        onTriggered: {
            if (root.syncing)
                editDebounce.restart();
            else
                root.syncNow();
        }
    }

    Timer {
        id: startDelay
        interval: 8000
        onTriggered: root.syncNow()
    }

    Timer {
        interval: root.intervalMinutes * 60000
        repeat: true
        running: root.ready
        onTriggered: root.syncNow()
    }

    onReadyChanged: {
        if (root.ready)
            startDelay.restart();
    }

    Component.onCompleted: {
        if (root.ready)
            startDelay.restart();
    }

    IpcHandler {
        target: "remindersSync"

        function sync(): void {
            root.syncNow();
        }
        function status(): string {
            return `${root.statusText} | ${root.lastError} | ${JSON.stringify(root.lastStats)}`;
        }
    }
}
