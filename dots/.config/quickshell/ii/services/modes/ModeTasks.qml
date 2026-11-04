import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import "ModeSchema.js" as ModeSchema

/**
 * Tracked shell commands: the `shell` action with `track` on.
 *
 * A tracked command runs detached through scripts/modes/run_task.sh, so it
 * outlives a shell reload, and leaves its output and exit status in a run
 * directory under the state dir. While any run is open this polls those
 * directories; when one finishes (or is found dead after a reboot) it records
 * the result in the Activity log as a `result` entry, sends a notification
 * and keeps the run for the Activity tab's detail sheet.
 *
 * A command reports more than its exit status by printing
 *   ::ii-report {"status":"ok|warn|error","title":"…","summary":"…",
 *                "details":[{"label":"…","value":"…","status":"ok|warn|error"}],
 *                "notes":["…"]}
 * — the last such line wins. Without it, exit 0 is ok and anything else an error.
 *
 * Runs live in Persistent.states.modes.taskRuns, newest first:
 *   {runId, owner, kind, label, command, dir, startedAt, endedAt,
 *    state: running|ok|warn|error, exitCode, lost, report}
 */
QtObject {
    id: root

    property var engine: null

    readonly property int keepRuns: 30
    readonly property string script: `${Directories.scriptPath}/modes/run_task.sh`
    readonly property string baseDir: FileUtils.trimFileProtocol(`${Directories.state}/modes/tasks`)

    readonly property var runs: root.engine?.ready ? ModeSchema.toArray(Persistent.states.modes.taskRuns) : []
    readonly property var openRuns: root.runs.filter(r => r.state === "running")
    readonly property bool busy: root.openRuns.length > 0
    // Bumped on every change, for views that hold a run by id.
    property int revision: 0

    signal finished(var run)

    function runById(runId) {
        return root.runs.find(r => r.runId === runId) ?? null;
    }

    // Newest run of an owner, or null.
    function lastRun(owner) {
        return root.runs.find(r => r.owner === owner) ?? null;
    }

    function isRunning(owner) {
        return root.openRuns.some(r => r.owner === owner);
    }

    function saveRuns(list) {
        Persistent.states.modes.taskRuns = list;
        root.revision += 1;
    }

    function updateRun(runId, patch) {
        const list = ModeSchema.toArray(Persistent.states.modes.taskRuns).map(r => ModeSchema.clone(r));
        const idx = list.findIndex(r => r.runId === runId);
        if (idx === -1)
            return null;
        list[idx] = Object.assign(list[idx], patch);
        root.saveRuns(list);
        return list[idx];
    }

    function safeId(text) {
        return String(text ?? "task").replace(/[^A-Za-z0-9_-]+/g, "-").slice(0, 40) || "task";
    }

    // Starts `command` for `owner` (a routine or mode id). One open run per
    // owner: a second start while the first is going is refused.
    function start(owner, kind, label, command) {
        if (!String(command ?? "").trim().length)
            throw new Error("empty command");
        if (root.isRunning(owner))
            throw new Error("still running from the last time");
        const now = Date.now();
        const runId = `${root.safeId(owner)}-${now}`;
        const dir = `${root.baseDir}/${runId}`;
        const run = {
            runId: runId, owner: owner, kind: kind, label: label ?? owner, command: command,
            dir: dir, startedAt: now, endedAt: 0, state: "running", exitCode: null, lost: false, report: null
        };
        const list = [run].concat(ModeSchema.toArray(Persistent.states.modes.taskRuns));
        const dropped = list.slice(root.keepRuns).filter(r => r.state !== "running");
        root.saveRuns(list.filter(r => !dropped.includes(r)));
        for (const r of dropped)
            root.removeDir(r.dir);
        Quickshell.execDetached([root.script, "start", dir, command]);
        console.log(`[Modes] task "${runId}" started for ${kind} "${owner}"`);
        pollTimer.restart();
        return runId;
    }

    function stop(runId) {
        const run = root.runById(runId);
        if (!run || run.state !== "running")
            return false;
        Quickshell.execDetached([root.script, "stop", run.dir]);
        Qt.callLater(root.poll);
        return true;
    }

    function removeDir(dir) {
        // Only ever inside our own directory.
        if (typeof dir === "string" && dir.startsWith(root.baseDir + "/") && !dir.includes(".."))
            Quickshell.execDetached(["rm", "-rf", "--", dir]);
    }

    // Drops finished runs of `owner` (every owner when empty); returns how many.
    function forget(owner) {
        const all = ModeSchema.toArray(Persistent.states.modes.taskRuns);
        const gone = all.filter(r => r.state !== "running" && (!owner || r.owner === owner));
        for (const r of gone)
            root.removeDir(r.dir);
        root.saveRuns(all.filter(r => !gone.includes(r)));
        return gone.length;
    }

    function clear() {
        const keep = ModeSchema.toArray(Persistent.states.modes.taskRuns).filter(r => r.state === "running");
        for (const r of ModeSchema.toArray(Persistent.states.modes.taskRuns))
            if (r.state !== "running")
                root.removeDir(r.dir);
        root.saveRuns(keep);
    }

    function poll() {
        if (statusProc.running || !root.busy)
            return;
        statusProc.command = [root.script, "status"].concat(root.openRuns.map(r => r.dir));
        statusProc.running = true;
    }

    function handleStatus(line) {
        let s;
        try {
            s = JSON.parse(line);
        } catch (e) {
            return;
        }
        const run = root.runs.find(r => r.dir === s.dir);
        if (!run || run.state !== "running" || s.state === "running")
            return;
        const report = (s.report && typeof s.report === "object") ? s.report : null;
        const lost = s.state === "lost";
        const exitCode = lost ? null : Number(s.exitCode);
        let state = report && ["ok", "warn", "error"].includes(report.status) ? report.status
            : (exitCode === 0 ? "ok" : "error");
        if (lost)
            state = "error";
        const done = root.updateRun(run.runId, {
            state: state, exitCode: exitCode, lost: lost, report: report,
            endedAt: Number(s.endedAt) > 0 ? Number(s.endedAt) : Date.now()
        });
        if (done)
            root.finish(done);
    }

    function titleOf(run) {
        if (run.state === "running")
            return Translation.tr("%1 is running").arg(run.label);
        if (run.report?.title)
            return String(run.report.title);
        if (run.lost)
            return Translation.tr("%1 was interrupted").arg(run.label);
        if (run.exitCode === 0)
            return Translation.tr("%1 finished").arg(run.label);
        return Translation.tr("%1 failed (exit %2)").arg(run.label).arg(run.exitCode);
    }

    function finish(run) {
        const title = root.titleOf(run);
        const lines = [];
        if (run.report?.summary)
            lines.push(String(run.report.summary));
        for (const d of ModeSchema.toArray(run.report?.details).slice(0, 6))
            lines.push(`${d.label}: ${d.value}`);
        if (run.lost)
            lines.push(Translation.tr("The command stopped without an exit status (shutdown or killed)."));
        const minutes = Math.max(0, Math.round((run.endedAt - run.startedAt) / 60000));
        console.log(`[Modes] task "${run.runId}" ${run.state} after ${minutes} min: ${title}`);
        root.engine?.appendHistory(run.kind, run.owner, "result", title, [],
            { task: run.runId, status: run.state });
        const args = ["notify-send", "-a", "Modes & Routines",
            "-u", run.state === "error" ? "critical" : "normal",
            "-i", run.state === "error" ? "dialog-error" : (run.state === "warn" ? "dialog-warning" : "emblem-ok-symbolic"),
            title];
        if (lines.length)
            args.push(lines.join("\n"));
        Quickshell.execDetached(args);
        root.finished(run);
    }

    property Process statusProc: Process {
        stdout: SplitParser {
            onRead: line => root.handleStatus(line)
        }
    }

    property Timer pollTimer: Timer {
        interval: 5000
        repeat: true
        running: root.busy
        triggeredOnStart: true
        onTriggered: root.poll()
    }
}
