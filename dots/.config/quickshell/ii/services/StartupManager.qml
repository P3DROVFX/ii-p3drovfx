pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Front for scripts/startup/ii-startup.py, the backend of Settings → Startup & Services.
 *
 *  - Startup: the exec lines of ~/.config/hypr/custom/execs.lua (never touched by updates).
 *    Entries are addressed by line + hash, so an edit against a stale listing is refused.
 *  - Services: systemd user/system units, "mine" = unit files placed by hand.
 *
 * Commands run one at a time through a queue; every mutation re-reads what it changed.
 * Nothing runs until a page calls refresh.
 */
Singleton {
    id: root

    readonly property string script: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/startup/ii-startup.py"))

    // ── startup ──
    property var entries: []
    property var autostart: []
    property string execsPath: ""
    property bool execsLoaded: false
    readonly property int enabledCount: root.entries.filter(e => e.enabled).length

    // ── services ──
    property var userUnits: []
    property var systemUnits: []
    property bool userLoaded: false
    property bool systemLoaded: false
    property var detail: null
    property bool detailLoading: false

    // the entry the edit sheet works on (null = adding a new one)
    property var editTarget: null
    property var addPreset: null      // {name, command} prefilled from an autostart entry
    property string detailScope: "user"
    property string detailUnit: ""

    property bool busy: false
    property string lastError: ""
    signal failed(string message)
    signal succeeded(string kind)

    function unitsFor(scope) {
        return scope === "system" ? root.systemUnits : root.userUnits;
    }

    // ── queue ──
    property var _queue: []
    function _run(kind, args, stdin, onDone) {
        root._queue = root._queue.concat([{ kind, args, stdin: stdin ?? null, onDone: onDone ?? null }]);
        root._next();
    }
    function _next() {
        if (proc.running || root._queue.length === 0)
            return;
        const job = root._queue[0];
        root._queue = root._queue.slice(1);
        proc.job = job;
        proc.command = ["python3", root.script].concat(job.args);
        proc.stdinEnabled = job.stdin !== null;
        root.busy = true;
        proc.running = true;
    }

    Process {
        id: proc
        property var job: null
        stdout: StdioCollector {
            id: procOut
        }
        onRunningChanged: {
            if (proc.running && proc.job && proc.job.stdin !== null) {
                proc.write(proc.job.stdin);
                proc.stdinEnabled = false;
            }
        }
        onExited: (code, status) => {
            const job = proc.job;
            let res = null;
            try {
                res = JSON.parse(procOut.text.trim().split("\n").pop() || "null");
            } catch (e) {
                res = null;
            }
            if (!res)
                res = { ok: false, error: Translation.tr("The startup helper failed (exit %1).").arg(code) };
            if (!res.ok) {
                root.lastError = res.error ?? "";
                root.failed(root.lastError);
            } else {
                root.lastError = "";
            }
            if (job && job.onDone)
                job.onDone(res);
            proc.job = null;
            root.busy = root._queue.length > 0;
            Qt.callLater(root._next);
        }
    }

    // ── startup API ──
    function refreshExecs() {
        root._run("list", ["list"], null, res => {
            if (!res.ok)
                return;
            root.entries = res.entries ?? [];
            root.autostart = res.autostart ?? [];
            root.execsPath = res.path ?? "";
            root.execsLoaded = true;
        });
    }
    function _mutate(args) {
        root._run("mutate", args, null, res => {
            if (res.ok)
                root.succeeded(args[0]);
        });
        root.refreshExecs();
    }
    function add(name, command, delay) {
        root._mutate(["add", "--name", name ?? "", "--command", command, "--delay", String(delay ?? 0)]);
    }
    function setEnabled(entry, on) {
        root._mutate(["toggle", "--line", String(entry.line), "--hash", entry.hash, "--enabled", on ? "on" : "off"]);
    }
    function edit(entry, name, command) {
        root._mutate(["edit", "--line", String(entry.line), "--hash", entry.hash, "--name", name ?? "", "--command", command]);
    }
    function remove(entry) {
        root._mutate(["remove", "--line", String(entry.line), "--hash", entry.hash]);
    }
    function runNow(command) {
        Quickshell.execDetached(["bash", "-c", command]);
    }
    function displayName(entry) {
        return (entry?.name ?? "") !== "" ? entry.name : (entry?.derivedName ?? "");
    }
    // An app's desktop entry for a command, for its icon and name
    function desktopEntryFor(command) {
        const words = String(command ?? "").replace(/^\s*(sleep\s+\S+\s*&&\s*)+/, "").trim().split(/\s+/);
        let i = 0;
        while (i < words.length && (/^(env|exec|nohup|setsid|uwsm|app|--)$/.test(words[i]) || /^[A-Z_][A-Z0-9_]*=/.test(words[i])))
            i++;
        if (i >= words.length)
            return null;
        if (words[i] === "flatpak" && words[i + 1] === "run" && words[i + 2])
            return DesktopEntries.byId(words[i + 2]) ?? DesktopEntries.heuristicLookup(words[i + 2]);
        const bin = words[i].replace(/^['"]|['"]$/g, "").split("/").pop();
        if (!bin || bin === "bash" || bin === "sh" || bin === "gsettings" || bin === "hyprctl")
            return null;
        return DesktopEntries.heuristicLookup(bin);
    }

    // ── services API ──
    function refreshUnits(scope) {
        root._run("units", ["units", "--scope", scope], null, res => {
            if (!res.ok)
                return;
            if (scope === "system") {
                root.systemUnits = res.units ?? [];
                root.systemLoaded = true;
            } else {
                root.userUnits = res.units ?? [];
                root.userLoaded = true;
            }
        });
    }
    function showUnit(scope, unit) {
        if (root.detailUnit !== unit || root.detailScope !== scope)
            root.detail = null;
        root.detailScope = scope;
        root.detailUnit = unit;
        root.detailLoading = true;
        root._run("show", ["show", "--scope", scope, "--unit", unit], null, res => {
            root.detailLoading = false;
            if (res.ok && res.unit === root.detailUnit)
                root.detail = res;
        });
    }
    function unitAction(scope, unit, verb) {
        root._run("action", ["action", "--scope", scope, "--unit", unit, "--verb", verb], null, res => {
            if (res.ok)
                root.succeeded(verb);
        });
        root.refreshUnits(scope);
        if (root.detailUnit === unit)
            root.showUnit(scope, unit);
    }
    function saveUnit(scope, unit, path, content) {
        root._run("save", ["save-unit", "--scope", scope, "--path", path], content, res => {
            if (res.ok)
                root.succeeded("save");
        });
        root.showUnit(scope, unit);
    }
    function openInEditor(path) {
        Quickshell.execDetached(["xdg-open", path]);
    }
}
