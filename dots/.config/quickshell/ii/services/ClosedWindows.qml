pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.modules.common
import "closedWindows/ClosedWindowsLogic.js" as Logic

/**
 * Reopen a closed window, like a browser's Ctrl+Shift+T for the whole desktop.
 *
 * Hyprland's `closewindow` event carries the address and nothing else, and by then the
 * process has usually exited, taking /proc/<pid>/cmdline with it. So every window is
 * written down while it lives: its record follows the window list (workspace, size,
 * floating), and a probe reads its process once, when its pid first shows up. A close
 * moves the record onto a short stack; `reopen()` starts the app again with exec rules
 * that put the window back on its workspace, at its size when it floated.
 *
 * The stack lives in memory only: command lines can carry tokens and private paths.
 * What the start command is, which closes count and the rules: ClosedWindowsLogic.js.
 */
Singleton {
    id: root

    readonly property var opts: Config.options.reopenClosedWindow
    readonly property bool enabled: Config.ready && (root.opts?.enable ?? true)

    /// Newest last. Each entry: { record, launch, appName, closedAt }.
    property var stack: []
    readonly property int count: root.stack.length

    // address -> record, for every window in the last window list.
    property var known: ({})
    // address -> record of windows that left the list before their closewindow event was
    // read (a refresh started by an earlier event can land in between), with `goneAt`.
    property var gone: ({})
    // pid -> what the probe found; dropped once no window of the pid is left.
    property var procs: ({})
    property int selfPid: 0
    property var probeQueue: []
    // Addresses of windows a reopen brought back, until they close.
    property var reopenedAddresses: ({})
    // pid -> true once the process has shown two tiled windows at once (kitty -1, a browser):
    // its floating windows are real windows, not dialogs. Dropped with the pid.
    property var multiWindowPids: ({})

    // A reopen waiting for its window: { record, deadline }.
    property var pending: null
    readonly property int pendingTimeoutMs: 15000
    readonly property int goneKeepMs: 5000

    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
            return;
        }
        root.stack = [];
        root.pending = null;
    }

    function desktopEntryFor(appClass: string): var {
        const entry = TaskbarApps.getCachedDesktopEntry(appClass);
        if (!entry)
            return null;
        return {
            "name": String(entry.name ?? ""),
            "command": Array.from(entry.command ?? []).map(word => String(word)),
            "workingDirectory": String(entry.workingDirectory ?? "")
        };
    }

    function refresh(): void {
        const now = Date.now();
        const next = {};
        const pids = {};
        for (const client of (HyprlandData.windowList ?? [])) {
            const address = Logic.normalisedAddress(client.address);
            const record = Logic.recordFor(client, root.known[address] ?? null, HyprlandData.monitors, now);
            if (root.reopenedAddresses[address])
                record.reopened = true;
            next[address] = record;
            if (record.pid > 0)
                pids[record.pid] = true;
        }

        const gone = {};
        for (const address of Object.keys(root.gone)) {
            if (now - root.gone[address].goneAt < root.goneKeepMs && !next[address])
                gone[address] = root.gone[address];
        }
        for (const address of Object.keys(root.known)) {
            if (!next[address])
                gone[address] = Object.assign({}, root.known[address], { "goneAt": now });
        }
        for (const address of Object.keys(gone))
            pids[gone[address].pid] = true;

        const procs = {};
        for (const pid of Object.keys(root.procs)) {
            if (pids[pid])
                procs[pid] = root.procs[pid];
        }
        const multiWindowPids = {};
        for (const pid of Object.keys(root.multiWindowPids)) {
            if (pids[pid])
                multiWindowPids[pid] = true;
        }
        for (const pid of Logic.tiledPids(Object.values(next)))
            multiWindowPids[pid] = true;
        const queue = root.probeQueue.slice();
        for (const pid of Object.keys(pids)) {
            if (Number(pid) > 0 && !procs[pid] && queue.indexOf(Number(pid)) === -1)
                queue.push(Number(pid));
        }

        root.known = next;
        root.gone = gone;
        root.procs = procs;
        root.multiWindowPids = multiWindowPids;
        root.probeQueue = queue;
        root.runProbe();
    }

    function runProbe(): void {
        if (probe.running || root.probeQueue.length === 0)
            return;
        probe.pids = root.probeQueue.map(String);
        root.probeQueue = [];
        probe.running = true;
    }

    function windowClosed(address: string): void {
        const record = root.known[address] ?? root.gone[address] ?? null;
        if (root.reopenedAddresses[address]) {
            // Hyprland reuses addresses: the next window here is a new one.
            const reopened = Object.assign({}, root.reopenedAddresses);
            delete reopened[address];
            root.reopenedAddresses = reopened;
        }
        if (!record)
            return;
        const known = Object.assign({}, root.known);
        delete known[address];
        root.known = known;
        if (root.gone[address]) {
            const gone = Object.assign({}, root.gone);
            delete gone[address];
            root.gone = gone;
        }

        const proc = root.procs[record.pid] ?? null;
        const reason = Logic.skipReason(record, proc, Object.values(root.known), root.opts, Date.now(), root.selfPid, root.multiWindowPids);
        if (reason.length > 0)
            return;
        const entry = root.desktopEntryFor(record.appClass);
        const launch = Logic.launchFor(proc, entry);
        if (!launch)
            return;
        root.stack = Logic.pushed(root.stack, {
            "record": record,
            "launch": launch,
            "appName": entry?.name || record.appClass,
            "closedAt": Date.now()
        }, root.opts?.depth ?? 10);
    }

    function reopen(): void {
        if (!root.enabled)
            return;
        if (root.stack.length === 0) {
            GlobalStates.osdNoticeRequested("history", "", Translation.tr("Nothing to reopen"));
            return;
        }
        const entry = root.stack[root.stack.length - 1];
        root.stack = root.stack.slice(0, -1);
        Hyprland.dispatch(Logic.execDispatch(entry.launch.command, Logic.placementRules(entry.record)));
        root.pending = {
            "record": entry.record,
            "deadline": Date.now() + root.pendingTimeoutMs
        };
        pendingExpiry.restart();
        GlobalStates.osdNoticeRequested("history", Translation.tr("Reopened"), entry.appName);
    }

    function windowOpened(data: string): void {
        if (!root.pending)
            return;
        const opened = Logic.parseOpenWindow(data);
        const verdict = Logic.pendingVerdict(root.pending, opened, Date.now());
        if (verdict.length === 0)
            return;
        const record = root.pending.record;
        root.pending = null;
        pendingExpiry.stop();
        root.reopenedAddresses = Object.assign({}, root.reopenedAddresses, { [opened.address]: true });
        if (root.known[opened.address])
            root.known[opened.address].reopened = true;
        if (verdict === "move") {
            for (const dispatch of Logic.fallbackDispatches(opened.address, record))
                Hyprland.dispatch(dispatch);
        }
    }

    Timer {
        id: pendingExpiry
        interval: root.pendingTimeoutMs
        onTriggered: root.pending = null
    }

    Connections {
        target: HyprlandData
        enabled: root.enabled
        function onWindowListChanged() {
            root.refresh();
        }
        function onMonitorsChanged() {
            root.refresh();
        }
    }

    Connections {
        target: Hyprland
        enabled: root.enabled
        function onRawEvent(event) {
            // Straight off the event socket, before HyprlandData's refresh drops the window.
            if (event.name === "closewindow")
                root.windowClosed(Logic.normalisedAddress(event.data));
            else if (event.name === "openwindow")
                root.windowOpened(event.data);
        }
    }

    // One run per batch of new pids. $PPID is the shell itself: its own windows (the clock,
    // the notes) must never be relaunched as a second shell.
    Process {
        id: probe
        property list<string> pids: []
        command: ["bash", "-c", `
            printf 'self\\x1d%s\\x1e' "$PPID"
            for p in "$@"; do
                [ -r "/proc/$p/cmdline" ] || continue
                argv=$(tr '\\0' '\\037' < "/proc/$p/cmdline"); argv=\${argv%$'\\037'}
                cwd=$(readlink "/proc/$p/cwd" 2>/dev/null)
                fp=$(sed -n 's/^name=//p' "/proc/$p/root/.flatpak-info" 2>/dev/null | head -n1)
                ai=$(tr '\\0' '\\n' < "/proc/$p/environ" 2>/dev/null | sed -n 's/^APPIMAGE=//p' | head -n1)
                cg=$(tail -n1 "/proc/$p/cgroup" 2>/dev/null); cg=\${cg##*/}
                a0=\${argv%%$'\\037'*}
                ok=0
                case $a0 in
                    /*) [ -x "$a0" ] && ok=1 ;;
                    */*) [ -x "$cwd/$a0" ] && ok=1 ;;
                    ?*) command -v -- "$a0" >/dev/null 2>&1 && ok=1 ;;
                esac
                printf '%s\\x1d%s\\x1d%s\\x1d%s\\x1d%s\\x1d%s\\x1d%s\\x1e' "$p" "$argv" "$cwd" "$fp" "$ai" "$cg" "$ok"
            done`, "probe", ...probe.pids]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = Logic.parseProbe(text);
                if (parsed.selfPid > 0)
                    root.selfPid = parsed.selfPid;
                root.procs = Object.assign({}, root.procs, parsed.procs);
            }
        }
        onExited: root.runProbe()
    }

    GlobalShortcut {
        name: "reopenClosedWindow"
        description: "Reopen the last closed window where it was"
        onPressed: root.reopen()
    }

    IpcHandler {
        target: "closedWindows"

        function reopen(): void {
            root.reopen();
        }

        /** The stack, newest first: app, title, workspace and how it would start. */
        function list(): string {
            return JSON.stringify(root.stack.slice().reverse().map(entry => ({
                "app": entry.appName,
                "title": entry.record.title,
                "workspace": entry.record.workspaceName,
                "source": entry.launch.source,
                "command": entry.launch.command
            })), null, 2);
        }

        function clear(): void {
            root.stack = [];
        }
    }
}
