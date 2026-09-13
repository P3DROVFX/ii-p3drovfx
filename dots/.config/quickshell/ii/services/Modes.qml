pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services
import qs.services.modes
import "modes/ModeSchema.js" as ModeSchema

/**
 * Modes & Routines engine (Samsung One UI style).
 *
 * Definitions live in Config.options.modes.{modes,routines}; runtime state
 * (which mode is active, what to revert, history) lives in
 * Persistent.states.modes so a config reset never strands an applied
 * snapshot.
 *
 * Rules:
 *  - One mode at a time. Starting B reverts A first.
 *  - Manual wins: a hand-started mode (or one a routine started) is never
 *    pre-empted by an automatic one.
 *  - List order is priority among automatic starts.
 *  - An auto-started mode ends once its triggers stay false for `graceSec`.
 *  - Stopping a mode by hand while its triggers still hold suppresses it until
 *    the triggers go false and true again (re-arm), so a scheduled mode does
 *    not restart a minute after being dismissed.
 *  - Revert replays the snapshot in reverse and skips entries the user
 *    changed by hand during the mode, unless the mode's `end.strict` is set.
 *
 * Routines share the trigger/action vocabulary and the snapshot path but are
 * not exclusive: any number can run next to a mode. `while` routines apply
 * on true and revert on false (same grace); `once` routines fire on the
 * false→true edge, never revert and honour a cooldown.
 */
Singleton {
    id: root

    readonly property bool storesReady: Config.ready && Persistent.ready
    // Flips once the persisted state has been reconciled; watchers only start then.
    property bool ready: false
    readonly property bool enabled: Config.options.modes.enable
    readonly property int graceSec: Config.options.modes.graceSec

    // Normalized copies of the definitions. Always JS arrays, replaced only
    // when the content actually differs so watchers are not rebuilt for
    // no-op rewrites (Config reloads its own file after every write).
    property var modes: []
    property var routines: []

    // Saves are queued: Config writes its file ~75 ms after a change and
    // reloads it ~75 ms after that, and a second change landing inside that
    // window is overwritten by the reload. Until the flush, the pending
    // lists are what `modes` / `routines` show.
    property var pendingModes: null
    property var pendingRoutines: null

    function refreshDefinitions() {
        if (!root.storesReady)
            return;
        const nextModes = root.pendingModes ?? ModeSchema.normalizeModes(Config.options.modes.modes);
        if (!ModeSchema.valuesEqual(nextModes, root.modes))
            root.modes = nextModes;
        const nextRoutines = root.pendingRoutines
            ?? ModeSchema.normalizeRoutines(Config.options.modes.routines);
        if (!ModeSchema.valuesEqual(nextRoutines, root.routines))
            root.routines = nextRoutines;
    }

    function flushSaves() {
        if (root.pendingModes) {
            Config.options.modes.modes = root.pendingModes;
            root.pendingModes = null;
        }
        if (root.pendingRoutines) {
            Config.options.modes.routines = root.pendingRoutines;
            root.pendingRoutines = null;
        }
        root.refreshDefinitions();
    }

    readonly property var state: Persistent.states.modes
    readonly property string activeModeId: root.ready ? root.state.activeId : ""
    readonly property var activeMode: root.modeById(root.activeModeId)
    readonly property bool active: root.activeModeId.length > 0 && root.activeMode !== null
    readonly property string activeSource: root.state.activeSource
    readonly property bool activeIsManual: root.activeSource === "manual" || root.activeSource === "routine"
    readonly property real activeSince: root.state.activeSince
    readonly property real activeEndsAt: root.state.activeEndsAt
    readonly property string lastUsedModeId: root.state.lastUsedModeId
    readonly property var lastUsedMode: root.modeById(root.lastUsedModeId)
    readonly property var history: ModeSchema.toArray(root.state.history)
    // Running `while` routines: [{id, source, since, snapshot, failed}]
    readonly property var routineRuns: root.ready ? ModeSchema.toArray(root.state.routineRuns) : []
    readonly property var runningRoutineIds: root.routineRuns.map(r => r.id)

    readonly property ModeActions actions: ModeActions {
        engine: root
    }

    // Guards routine→routine / routine→mode→routine chains.
    property int runDepth: 0
    readonly property int maxRunDepth: 4

    signal modeStarted(string id, string source)
    signal modeEnded(string id, string reason)
    signal routineStarted(string id, string source)
    signal routineEnded(string id, string reason)
    signal routineFired(string id, string source)
    signal historyAppended(var entry)

    // ---------------------------------------------------------------- lookup

    function modeById(id) {
        if (!id)
            return null;
        for (const m of root.modes) {
            if (m.id === id)
                return m;
        }
        return null;
    }

    function modeIndex(id) {
        return root.modes.findIndex(m => m.id === id);
    }

    function watcherFor(id) {
        for (let i = 0; i < watchers.count; ++i) {
            const w = watchers.objectAt(i);
            if (w && w.modeId === id)
                return w;
        }
        return null;
    }

    function routineById(id) {
        if (!id)
            return null;
        for (const r of root.routines) {
            if (r.id === id)
                return r;
        }
        return null;
    }

    function routineRun(id) {
        return root.routineRuns.find(r => r.id === id) ?? null;
    }

    function isRoutineRunning(id) {
        return root.routineRun(id) !== null;
    }

    function routineWatcherFor(id) {
        for (let i = 0; i < routineWatchers.count; ++i) {
            const w = routineWatchers.objectAt(i);
            if (w && w.modeId === id)
                return w;
        }
        return null;
    }

    // Whether a watcher's triggers hold right now. Before its first commit
    // (just after a reload) the raw state is the best answer available.
    function triggersHold(w) {
        if (!w)
            return false;
        return w.evaluatedOnce ? w.satisfied : w.pending;
    }

    function isSuppressed(id) {
        return ModeSchema.toArray(root.state.suppressed).indexOf(id) !== -1;
    }

    function setSuppressed(id, on) {
        const list = ModeSchema.toArray(root.state.suppressed).filter(x => x !== id);
        if (on)
            list.push(id);
        root.state.suppressed = list;
    }

    function isRoutineSuppressed(id) {
        return ModeSchema.toArray(root.state.suppressedRoutines).indexOf(id) !== -1;
    }

    function setRoutineSuppressed(id, on) {
        const list = ModeSchema.toArray(root.state.suppressedRoutines).filter(x => x !== id);
        if (on)
            list.push(id);
        root.state.suppressedRoutines = list;
    }

    // ---------------------------------------------------------------- store

    function saveModes(list) {
        root.pendingModes = ModeSchema.normalizeModes(list);
        root.refreshDefinitions();
        saveTimer.restart();
    }

    function upsertMode(def) {
        const normalized = ModeSchema.normalizeMode(def);
        const list = root.modes.slice();
        const idx = list.findIndex(m => m.id === normalized.id);
        if (idx === -1)
            list.push(normalized);
        else
            list[idx] = normalized;
        root.saveModes(list);
        return normalized.id;
    }

    // A brand-new mode gets an id nobody holds yet; upsertMode would
    // otherwise overwrite an existing mode that slugifies to the same name.
    function addMode(def) {
        const m = ModeSchema.normalizeMode(def);
        m.id = ModeSchema.uniqueId(m.id, root.modes.map(x => x.id));
        root.saveModes(root.modes.concat([m]));
        return m.id;
    }

    function duplicateMode(id) {
        const def = root.modeById(id);
        if (!def)
            return "";
        const copy = ModeSchema.clone(def);
        copy.id = ModeSchema.uniqueId(`${def.id}-copy`, root.modes.map(m => m.id));
        copy.name = Translation.tr("%1 (copy)").arg(def.name);
        copy.preset = false;
        copy.auto = false;
        const list = root.modes.slice();
        list.splice(root.modeIndex(id) + 1, 0, copy);
        root.saveModes(list);
        return copy.id;
    }

    function removeMode(id) {
        if (root.activeModeId === id)
            root.deactivate("deleted");
        root.saveModes(root.modes.filter(m => m.id !== id));
        root.setSuppressed(id, false);
        if (root.state.lastUsedModeId === id)
            root.state.lastUsedModeId = "";
    }

    function moveMode(id, toIndex) {
        const list = root.modes.slice();
        const from = list.findIndex(m => m.id === id);
        if (from === -1)
            return;
        const [item] = list.splice(from, 1);
        list.splice(Math.max(0, Math.min(list.length, toIndex)), 0, item);
        root.saveModes(list);
    }

    // Adds any preset whose id is missing. Existing entries are left alone, so
    // a user-edited preset keeps its edits.
    function seedPresets() {
        const have = root.modes.map(m => m.id);
        const missing = ModeSchema.presets().filter(p => have.indexOf(p.id) === -1);
        if (missing.length)
            root.saveModes(root.modes.concat(missing));
        return missing.map(p => p.id);
    }

    function resetPreset(id) {
        const preset = ModeSchema.presets().find(p => p.id === id);
        if (!preset)
            return false;
        root.upsertMode(preset);
        return true;
    }

    function saveRoutines(list) {
        root.pendingRoutines = ModeSchema.normalizeRoutines(list);
        root.refreshDefinitions();
        saveTimer.restart();
    }

    function upsertRoutine(def) {
        const normalized = ModeSchema.normalizeRoutine(def);
        const list = root.routines.slice();
        const idx = list.findIndex(r => r.id === normalized.id);
        if (idx === -1)
            list.push(normalized);
        else
            list[idx] = normalized;
        root.saveRoutines(list);
        return normalized.id;
    }

    function removeRoutine(id) {
        if (root.isRoutineRunning(id))
            root.stopRoutine(id, "deleted");
        root.setStep("routine", id, null);
        root.saveRoutines(root.routines.filter(r => r.id !== id));
        root.setRoutineSuppressed(id, false);
        root.state.routineFired = ModeSchema.toArray(root.state.routineFired).filter(f => f.id !== id);
    }

    function moveRoutine(id, toIndex) {
        const list = root.routines.slice();
        const from = list.findIndex(r => r.id === id);
        if (from === -1)
            return;
        const [item] = list.splice(from, 1);
        list.splice(Math.max(0, Math.min(list.length, toIndex)), 0, item);
        root.saveRoutines(list);
    }

    function addRoutine(def) {
        const r = ModeSchema.normalizeRoutine(def);
        r.id = ModeSchema.uniqueId(r.id, root.routines.map(x => x.id));
        root.saveRoutines(root.routines.concat([r]));
        return r.id;
    }

    function duplicateRoutine(id) {
        const def = root.routineById(id);
        if (!def)
            return "";
        const copy = ModeSchema.clone(def);
        copy.id = ModeSchema.uniqueId(`${def.id}-copy`, root.routines.map(r => r.id));
        copy.name = Translation.tr("%1 (copy)").arg(def.name);
        copy.preset = false;
        copy.enabled = false;
        const list = root.routines.slice();
        list.splice(list.findIndex(r => r.id === id) + 1, 0, copy);
        root.saveRoutines(list);
        return copy.id;
    }

    // Copies a template in; the copy is an ordinary routine from then on.
    function addRoutineFromTemplate(key) {
        const tpl = ModeSchema.routineTemplate(key);
        if (!tpl)
            return "";
        return root.addRoutine(tpl);
    }

    function routineIndex(id) {
        return root.routines.findIndex(r => r.id === id);
    }

    // Would `actions`, run as routine `ownerId`, end up running it again?
    // Returns the routine ids on the way back, or null.
    function routineLoop(ownerId, actions) {
        return ModeSchema.routineLoop(ownerId, actions, root.routines);
    }

    // Editor / list button: a running routine stops, anything else runs.
    function toggleRoutine(id) {
        if (root.isRoutineRunning(id))
            return root.stopRoutine(id, "manual");
        return root.runRoutine(id, "manual");
    }

    // A running `while` routine was edited: the old snapshot is reverted and
    // the new definition applied, keeping the source. No banners.
    function restartRoutine(id) {
        const run = root.routineRun(id);
        if (!run)
            return false;
        const source = run.source;
        root.quietRestart = true;
        try {
            root.stopRoutine(id, "edited");
            return root.runRoutine(id, source);
        } finally {
            root.quietRestart = false;
        }
    }

    // ---------------------------------------------------------------- history

    function appendHistory(kind, id, event, why, failed) {
        const entry = { t: Date.now(), kind: kind, id: id, event: event, why: why ?? "" };
        if (failed && failed.length)
            entry.failed = ModeSchema.toArray(failed);
        const list = ModeSchema.toArray(root.state.history);
        list.unshift(entry);
        if (list.length > ModeSchema.HISTORY_MAX)
            list.length = ModeSchema.HISTORY_MAX;
        root.state.history = list;
        root.historyAppended(entry);
    }

    // Failures that surfaced after a pause land on the entry that started
    // the sequence, so the Activity tab shows them where the run is.
    function amendHistoryFailed(kind, id, failed) {
        const list = ModeSchema.toArray(root.state.history);
        const idx = list.findIndex(h => h.kind === kind && h.id === id
            && (h.event === "start" || h.event === "run"));
        if (idx === -1)
            return;
        const entry = ModeSchema.clone(list[idx]);
        const next = ModeSchema.toArray(failed);
        if (ModeSchema.valuesEqual(ModeSchema.toArray(entry.failed), next))
            return;
        if (next.length)
            entry.failed = next;
        else
            delete entry.failed;
        list[idx] = entry;
        root.state.history = list;
    }

    function clearHistory() {
        root.state.history = [];
    }

    // ---------------------------------------------------------------- engine

    // Runs `actions` in order from `start`. `persist(snapshot)` is called
    // after every successful apply so a crash loses at most one entry. A
    // failure never stops the rest; a wait step or a delayed action does:
    // the rest is handed back as `deferred` for the step queue to resume.
    // `resumed` means the first action's delay has already elapsed.
    function applyActions(ownerId, actions, persist, start = 0, snapshot = [], failed = [], resumed = false) {
        snapshot = snapshot.slice();
        failed = failed.slice();
        for (let i = start; i < actions.length; ++i) {
            const action = actions[i];
            if (action.type === "wait") {
                const sec = ModeSchema.actionPauseSec(action);
                return {
                    snapshot: snapshot, failed: failed,
                    deferred: { index: i + 1, dueAt: Date.now() + sec * 1000, resumed: false }
                };
            }
            const delay = ModeSchema.actionPauseSec(action);
            if (delay > 0 && !(resumed && i === start)) {
                return {
                    snapshot: snapshot, failed: failed,
                    deferred: { index: i, dueAt: Date.now() + delay * 1000, resumed: true }
                };
            }
            const entry = root.actions.get(action.type);
            if (!entry || !entry.apply) {
                failed.push(`${action.type}: unknown action`);
                continue;
            }
            if (!root.actions.isAvailable(action.type)) {
                failed.push(`${action.type}: not available on this machine`);
                continue;
            }
            try {
                const was = entry.read ? entry.read(action) : null;
                const extra = entry.extra ? entry.extra(action) : null;
                const set = entry.normalize ? entry.normalize(action.value, action) : action.value;
                entry.apply(action.value, action);
                snapshot.push({ type: action.type, was: was, set: set, extra: extra, action: action });
                if (persist)
                    persist(ModeSchema.clone(snapshot));
            } catch (e) {
                console.warn(`[Modes] ${ownerId}: action ${action.type} failed: ${e}`);
                failed.push(`${action.type}: ${e}`);
            }
        }
        return { snapshot: snapshot, failed: failed, deferred: null };
    }

    // Replays a snapshot in reverse. Entries whose value no longer matches
    // what we set were changed by hand in the meantime and are kept, unless
    // `strict`.
    function revertSnapshot(ownerId, snapshot, strict) {
        for (let i = snapshot.length - 1; i >= 0; --i) {
            const e = snapshot[i];
            const entry = root.actions.get(e.type);
            if (!entry || !entry.revert)
                continue;
            // Routines can keep an action's effect on purpose ("undo at end" off).
            if (e.action?.revert === false)
                continue;
            try {
                if (!strict && entry.read) {
                    const current = entry.read(e.action);
                    if (!ModeSchema.valuesEqual(current, e.set)) {
                        console.log(`[Modes] ${ownerId}: ${e.type} changed by hand in the meantime, kept`);
                        continue;
                    }
                }
                entry.revert(e.was, e.action, e.extra);
            } catch (err) {
                console.warn(`[Modes] ${ownerId}: revert of ${e.type} failed: ${err}`);
            }
        }
    }

    function activate(id, source = "manual") {
        const def = root.modeById(id);
        if (!def) {
            console.warn(`[Modes] activate: unknown mode "${id}"`);
            return false;
        }
        if (!root.enabled && source !== "manual")
            return false;
        if (root.activeModeId === id)
            return true;
        if (root.active)
            root.endActive(`replaced by ${id}`, false);

        root.state.activeId = id;
        root.state.activeSource = source;
        root.state.activeSince = Date.now();
        root.state.activeEndsAt = 0;
        root.state.snapshot = [];
        root.state.failed = [];

        const result = root.applyActions(id, def.actions, snap => { root.state.snapshot = snap; });
        const failed = result.failed;
        root.state.failed = failed;
        root.setStep("mode", id, result.deferred, source, failed);

        if (def.end.autoOffMin > 0) {
            root.state.activeEndsAt = Date.now() + def.end.autoOffMin * 60000;
        } else {
            const w = root.watcherFor(id);
            root.state.activeEndsAt = w?.scheduleEndsAt ?? 0;
        }
        root.state.lastUsedModeId = id;
        if (source === "manual")
            root.setSuppressed(id, false);
        graceTimer.stop();
        root.armAutoOff();
        root.appendHistory("mode", id, "start", source);
        const skipped = failed.length ? `, skipped: ${failed.join("; ")}` : "";
        console.log(`[Modes] started "${id}" (${source})${skipped}`);
        const ends = root.state.activeEndsAt > 0
            ? Translation.tr("Ends %1").arg(root.clockText(root.state.activeEndsAt, "hh:mm")) + " · "
            : "";
        if (def.notify)
            root.flash("mode", def, Translation.tr("%1 mode on").arg(def.name), ends + root.sourceText(source));
        root.modeStarted(id, source);
        return true;
    }

    function deactivate(reason = "manual") {
        if (!root.active)
            return false;
        root.endActive(reason, true);
        // Nothing is active any more: a lower-priority mode whose triggers
        // still hold may take over.
        Qt.callLater(root.reevaluateAll);
        return true;
    }

    // Reverts the active mode's snapshot and clears the active state.
    function endActive(reason, reevaluate) {
        const id = root.state.activeId;
        const def = root.modeById(id);
        const snapshot = ModeSchema.toArray(root.state.snapshot);
        const revertAll = def ? def.end.revert : true;
        const strict = def ? def.end.strict : false;

        if (revertAll)
            root.revertSnapshot(id, snapshot, strict);

        // Stopped by hand while the triggers still hold: stay quiet until they
        // go false and true again.
        if (reason === "manual" && root.triggersHold(root.watcherFor(id)))
            root.setSuppressed(id, true);

        graceTimer.stop();
        autoOffTimer.stop();
        root.setStep("mode", id, null);
        root.state.activeId = "";
        root.state.activeSource = "";
        root.state.activeSince = 0;
        root.state.activeEndsAt = 0;
        root.state.snapshot = [];
        root.state.failed = [];
        root.appendHistory("mode", id, "end", reason);
        console.log(`[Modes] ended "${id}" (${reason})`);
        if (def && def.end.notify)
            root.flash("mode", def, Translation.tr("%1 mode off").arg(def.name), root.reasonText(reason));
        root.modeEnded(id, reason);
    }

    function toggle(id) {
        if (root.activeModeId === id)
            return root.deactivate("manual");
        return root.activate(id, "manual");
    }

    // Pill click: stop what is running, else start the last used mode.
    function toggleLast() {
        if (root.active)
            return root.deactivate("manual");
        if (!root.lastUsedMode)
            return false;
        return root.activate(root.lastUsedModeId, "manual");
    }

    // The active mode was edited: revert what the old definition set and
    // apply the new one, keeping the start source. No banner for either half.
    function restartActive() {
        if (!root.active)
            return false;
        const id = root.activeModeId;
        const source = root.activeSource;
        root.quietRestart = true;
        try {
            root.endActive("edited", false);
            return root.activate(id, source);
        } finally {
            root.quietRestart = false;
        }
    }

    // ---------------------------------------------------------------- flash

    property bool quietRestart: false

    function sourceText(source) {
        switch (source) {
        case "manual":
            return Translation.tr("by you");
        case "routine":
            return Translation.tr("by a routine");
        case "auto":
        case "":
        case undefined:
            return Translation.tr("automatically");
        }
        const meta = ModeSchema.TRIGGER_TYPES[source];
        return Translation.tr("by %1").arg((meta?.label ?? source).toLowerCase());
    }

    function reasonText(reason) {
        switch (reason) {
        case "manual":
            return Translation.tr("Turned off by you");
        case "routine":
            return Translation.tr("Turned off by a routine");
        case "triggers ended":
            return Translation.tr("Conditions no longer met");
        case "schedule end":
            return Translation.tr("Schedule ended");
        case "timer":
            return Translation.tr("Timer ran out");
        case "edited":
            return Translation.tr("Restarted after an edit");
        case "deleted":
        case "definition missing":
            return Translation.tr("Deleted");
        }
        if (String(reason).startsWith("replaced by ")) {
            const other = root.modeById(String(reason).slice(12));
            return Translation.tr("Replaced by %1").arg(other?.name ?? String(reason).slice(12));
        }
        return String(reason ?? "");
    }

    // Transient banner on start and end, drawn by the island or the popup.
    function flash(kind, def, title, subtitle) {
        if (root.quietRestart || Config.options.modes.flash === "off" || !def)
            return;
        GlobalStates.modeFlashPayload = {
            kind: kind,
            id: def.id,
            icon: def.icon,
            color: def.color ?? "",
            title: title,
            subtitle: subtitle ?? ""
        };
        GlobalStates.modeFlashActive = true;
        flashTimer.restart();
    }

    Timer {
        id: flashTimer
        interval: 3000
        repeat: false
        onTriggered: GlobalStates.modeFlashActive = false
    }

    function tryAutoStart(id, source) {
        if (!root.enabled)
            return;
        const def = root.modeById(id);
        if (!def || !def.auto)
            return;
        if (root.activeModeId === id)
            return;
        if (root.isSuppressed(id))
            return;
        if (root.active) {
            if (root.activeIsManual)
                return;
            if (root.modeIndex(id) >= root.modeIndex(root.activeModeId))
                return;
        }
        root.activate(id, source || "auto");
    }

    function handleEvaluation(id, satisfied, initial) {
        if (!root.ready)
            return;
        if (satisfied) {
            if (root.activeModeId === id) {
                graceTimer.stop();
                return;
            }
            root.tryAutoStart(id, root.watcherFor(id)?.source);
            return;
        }
        // Triggers went false: the suppression from a manual stop is spent.
        if (root.isSuppressed(id))
            root.setSuppressed(id, false);
        if (root.activeModeId !== id || root.activeIsManual)
            return;
        graceTimer.modeId = id;
        graceTimer.interval = Math.max(0, root.graceSec) * 1000;
        graceTimer.restart();
    }

    // Samsung: a mode started by hand that has a schedule still ends with it.
    function handleScheduleEnded(id) {
        if (!root.ready || root.activeModeId !== id || !root.activeIsManual)
            return;
        root.deactivate("schedule end");
    }

    function reevaluateAll() {
        if (!root.ready || root.active)
            return;
        for (let i = 0; i < watchers.count; ++i) {
            const w = watchers.objectAt(i);
            if (!w || !w.evaluatedOnce || !w.satisfied)
                continue;
            root.tryAutoStart(w.modeId, w.source);
            if (root.active)
                return;
        }
    }

    function armAutoOff() {
        autoOffTimer.stop();
        const def = root.activeMode;
        if (!def || def.end.autoOffMin <= 0 || root.state.activeEndsAt <= 0)
            return;
        // A little late rather than a hair early, or checkAutoOff() sees a
        // deadline that is still a few ms away and waits for the minute tick.
        autoOffTimer.interval = Math.max(1000, root.state.activeEndsAt - Date.now() + 250);
        autoOffTimer.start();
    }

    // Timers do not tick through suspend; the clock does.
    function checkAutoOff() {
        const def = root.activeMode;
        if (!def || def.end.autoOffMin <= 0)
            return;
        if (root.state.activeEndsAt > 0 && Date.now() >= root.state.activeEndsAt)
            root.deactivate("timer");
    }

    // ---------------------------------------------------------------- routines

    function setRoutineRun(id, run) {
        const list = ModeSchema.toArray(root.state.routineRuns).filter(r => r.id !== id);
        if (run)
            list.push(run);
        root.state.routineRuns = list;
    }

    function routineLastFired(id) {
        return ModeSchema.toArray(root.state.routineFired).find(f => f.id === id)?.t ?? 0;
    }

    function markRoutineFired(id) {
        const list = ModeSchema.toArray(root.state.routineFired).filter(f => f.id !== id);
        list.push({ id: id, t: Date.now() });
        root.state.routineFired = list;
    }

    // Starts a `while` routine or fires a `once` routine. A manual run
    // ignores the cooldown and the enabled switch.
    function runRoutine(id, source = "manual") {
        const def = root.routineById(id);
        if (!def) {
            console.warn(`[Modes] runRoutine: unknown routine "${id}"`);
            return false;
        }
        if (source !== "manual" && (!root.enabled || !def.enabled))
            return false;
        if (root.runDepth >= root.maxRunDepth) {
            console.warn(`[Modes] routine "${id}": chain deeper than ${root.maxRunDepth}, stopped`);
            return false;
        }
        if (def.kind === "once") {
            const since = Date.now() - root.routineLastFired(id);
            if (source !== "manual" && def.cooldownSec > 0 && since < def.cooldownSec * 1000) {
                console.log(`[Modes] routine "${id}" in cooldown (${Math.round(since / 1000)} s), skipped`);
                return false;
            }
            root.markRoutineFired(id);
            root.runDepth += 1;
            let result;
            try {
                result = root.applyActions(id, def.actions, null);
            } finally {
                root.runDepth -= 1;
            }
            root.setStep("routine", id, result.deferred, source, result.failed);
            root.appendHistory("routine", id, "run", source, result.failed);
            const skipped = result.failed.length ? `, skipped: ${result.failed.join("; ")}` : "";
            console.log(`[Modes] routine "${id}" ran (${source})${skipped}`);
            if (def.notify)
                root.flash("routine", def, Translation.tr("%1 ran").arg(def.name), root.sourceText(source));
            root.routineFired(id, source);
            return true;
        }
        if (root.isRoutineRunning(id))
            return true;
        const run = { id: id, source: source, since: Date.now(), snapshot: [], failed: [] };
        root.setRoutineRun(id, run);
        root.runDepth += 1;
        let result;
        try {
            result = root.applyActions(id, def.actions, snap => {
                run.snapshot = snap;
                root.setRoutineRun(id, ModeSchema.clone(run));
            });
        } finally {
            root.runDepth -= 1;
        }
        run.snapshot = result.snapshot;
        run.failed = result.failed;
        root.setRoutineRun(id, ModeSchema.clone(run));
        root.setStep("routine", id, result.deferred, source, result.failed);
        root.routineWatcherFor(id)?.grace.stop();
        if (source === "manual")
            root.setRoutineSuppressed(id, false);
        root.appendHistory("routine", id, "start", source, result.failed);
        const skipped = result.failed.length ? `, skipped: ${result.failed.join("; ")}` : "";
        console.log(`[Modes] routine "${id}" started (${source})${skipped}`);
        if (def.notify)
            root.flash("routine", def, Translation.tr("%1 started").arg(def.name), root.sourceText(source));
        root.routineStarted(id, source);
        return true;
    }

    function stopRoutine(id, reason = "manual") {
        const run = root.routineRun(id);
        if (!run)
            return false;
        const def = root.routineById(id);
        const revert = def ? def.end.revert : true;
        const strict = def ? def.end.strict : false;
        if (revert)
            root.revertSnapshot(id, ModeSchema.toArray(run.snapshot), strict);
        const w = root.routineWatcherFor(id);
        w?.grace.stop();
        // Stopped by hand while the triggers still hold: wait for them to go
        // false and true again, like a mode.
        if (reason === "manual" && root.triggersHold(w))
            root.setRoutineSuppressed(id, true);
        root.setStep("routine", id, null);
        root.setRoutineRun(id, null);
        root.appendHistory("routine", id, "end", reason);
        console.log(`[Modes] routine "${id}" ended (${reason})`);
        if (def && def.end.notify)
            root.flash("routine", def, Translation.tr("%1 ended").arg(def.name), root.reasonText(reason));
        root.routineEnded(id, reason);
        return true;
    }

    function stopAllRoutines(reason) {
        for (const id of root.runningRoutineIds.slice())
            root.stopRoutine(id, reason);
    }

    function handleRoutineEvaluation(id, satisfied, initial) {
        if (!root.ready)
            return;
        const def = root.routineById(id);
        if (!def)
            return;
        const w = root.routineWatcherFor(id);
        if (def.kind === "once") {
            // Edge-triggered: the state at startup is not an edge.
            if (satisfied && !initial)
                root.runRoutine(id, w?.source ?? "auto");
            return;
        }
        const run = root.routineRun(id);
        if (satisfied) {
            w?.grace.stop();
            if (!run && !root.isRoutineSuppressed(id))
                root.runRoutine(id, w?.source ?? "auto");
            return;
        }
        if (root.isRoutineSuppressed(id))
            root.setRoutineSuppressed(id, false);
        if (!run || run.source === "manual")
            return;
        if (!w) {
            root.stopRoutine(id, "triggers ended");
            return;
        }
        w.grace.interval = Math.max(0, root.graceSec) * 1000;
        w.grace.restart();
    }

    // ---------------------------------------------------------------- steps

    // Sequences paused on a wait or a delayed action, one entry per owner.
    readonly property var pendingSteps: root.ready ? ModeSchema.toArray(root.state.pendingSteps) : []

    function stepFor(kind, id) {
        return root.pendingSteps.find(s => s.kind === kind && s.id === id) ?? null;
    }

    // Replaces (or with `deferred` null, drops) the pending step of an owner.
    function setStep(kind, id, deferred, source, failed) {
        const list = ModeSchema.toArray(root.state.pendingSteps).filter(s => !(s.kind === kind && s.id === id));
        if (deferred) {
            list.push({
                kind: kind, id: id, index: deferred.index, dueAt: deferred.dueAt,
                resumed: deferred.resumed === true, source: source ?? "manual",
                failed: ModeSchema.toArray(failed)
            });
        }
        if (list.length === 0 && ModeSchema.toArray(root.state.pendingSteps).length === 0)
            return;
        root.state.pendingSteps = list;
        root.armSteps();
    }

    function armSteps() {
        stepTimer.stop();
        let due = 0;
        for (const s of ModeSchema.toArray(root.state.pendingSteps)) {
            if (due === 0 || s.dueAt < due)
                due = s.dueAt;
        }
        if (due === 0)
            return;
        stepTimer.interval = Math.max(250, due - Date.now() + 50);
        stepTimer.start();
    }

    // Timers do not tick through suspend; the clock tick calls this too.
    function runDueSteps() {
        if (!root.ready)
            return;
        const now = Date.now();
        for (const step of ModeSchema.toArray(root.state.pendingSteps)) {
            if (step.dueAt > now)
                continue;
            root.setStep(step.kind, step.id, null);
            root.resumeStep(step);
        }
        root.armSteps();
    }

    // Picks a sequence up where it paused. The owner must still be on;
    // anything else has been cleaned up by whoever ended it.
    function resumeStep(step) {
        if (step.kind === "mode") {
            const def = root.modeById(step.id);
            if (!def || root.activeModeId !== step.id)
                return;
            const result = root.applyActions(step.id, def.actions, snap => { root.state.snapshot = snap; },
                step.index, ModeSchema.toArray(root.state.snapshot), ModeSchema.toArray(root.state.failed),
                step.resumed === true);
            root.state.snapshot = result.snapshot;
            root.state.failed = result.failed;
            root.setStep("mode", step.id, result.deferred, step.source, result.failed);
            root.amendHistoryFailed("mode", step.id, result.failed);
            root.logStep(step, result);
            return;
        }
        const def = root.routineById(step.id);
        if (!def)
            return;
        if (def.kind === "once") {
            const result = root.applyActions(step.id, def.actions, null, step.index, [],
                ModeSchema.toArray(step.failed), step.resumed === true);
            root.setStep("routine", step.id, result.deferred, step.source, result.failed);
            root.amendHistoryFailed("routine", step.id, result.failed);
            root.logStep(step, result);
            return;
        }
        const run = root.routineRun(step.id);
        if (!run)
            return;
        const result = root.applyActions(step.id, def.actions, snap => {
            run.snapshot = snap;
            root.setRoutineRun(step.id, ModeSchema.clone(run));
        }, step.index, ModeSchema.toArray(run.snapshot), ModeSchema.toArray(run.failed), step.resumed === true);
        run.snapshot = result.snapshot;
        run.failed = result.failed;
        root.setRoutineRun(step.id, ModeSchema.clone(run));
        root.setStep("routine", step.id, result.deferred, step.source, result.failed);
        root.amendHistoryFailed("routine", step.id, result.failed);
        root.logStep(step, result);
    }

    function logStep(step, result) {
        const next = result.deferred
            ? `, paused again until ${root.clockText(result.deferred.dueAt, "hh:mm:ss")}` : ", done";
        console.log(`[Modes] ${step.kind} "${step.id}" resumed at action ${step.index + 1}${next}`);
    }

    // Drops steps whose owner is no longer on (after a reload or a crash).
    function pruneSteps() {
        const kept = ModeSchema.toArray(root.state.pendingSteps).filter(s => {
            if (s.kind === "mode")
                return root.state.activeId === s.id && root.modeById(s.id) !== null;
            const def = root.routineById(s.id);
            if (!def)
                return false;
            return def.kind === "once" || root.isRoutineRunning(s.id);
        });
        if (kept.length !== ModeSchema.toArray(root.state.pendingSteps).length)
            root.state.pendingSteps = kept;
    }

    Timer {
        id: stepTimer
        repeat: false
        onTriggered: root.runDueSteps()
    }

    // ---------------------------------------------------------------- startup

    // Pushes back what the services do not persist themselves; everything
    // else survived the reload on its own.
    function reapplyVolatile(ownerId, snapshot) {
        for (const e of ModeSchema.toArray(snapshot)) {
            const entry = root.actions.get(e.type);
            if (!entry || !entry.volatile)
                continue;
            try {
                entry.apply(e.action?.value ?? e.set, e.action);
            } catch (err) {
                console.warn(`[Modes] ${ownerId}: re-apply of ${e.type} after reload failed: ${err}`);
            }
        }
    }

    function reconcile() {
        if (root.ready || !root.storesReady)
            return;
        root.refreshDefinitions();
        if (!Config.options.modes.presetsSeeded) {
            root.seedPresets();
            Config.options.modes.presetsSeeded = true;
        }
        // Read the definitions straight from Config: the `modes` / `routines`
        // bindings are not guaranteed to have re-evaluated before this runs.
        const defs = ModeSchema.normalizeModes(Config.options.modes.modes);
        const routineDefs = ModeSchema.normalizeRoutines(Config.options.modes.routines);
        const id = root.state.activeId;
        if (id) {
            const def = defs.find(m => m.id === id) ?? null;
            if (!def) {
                console.log(`[Modes] "${id}" was active but no longer exists, reverting what it set`);
                root.endActive("definition missing", false);
            } else {
                // Keep the old snapshot.
                root.reapplyVolatile(id, root.state.snapshot);
                console.log(`[Modes] "${id}" still active after reload (${root.state.activeSource})`);
            }
        }
        for (const run of ModeSchema.toArray(root.state.routineRuns)) {
            const def = routineDefs.find(r => r.id === run.id) ?? null;
            if (!def) {
                console.log(`[Modes] routine "${run.id}" was running but no longer exists, reverting`);
                root.revertSnapshot(run.id, ModeSchema.toArray(run.snapshot), false);
                root.setRoutineRun(run.id, null);
                root.appendHistory("routine", run.id, "end", "definition missing");
                continue;
            }
            root.reapplyVolatile(run.id, run.snapshot);
            console.log(`[Modes] routine "${run.id}" still running after reload (${run.source})`);
        }
        root.ready = true;
        root.armAutoOff();
        root.checkAutoOff();
        root.pruneSteps();
        root.runDueSteps();
    }

    onStoresReadyChanged: root.reconcile()
    Component.onCompleted: root.reconcile()

    Connections {
        target: Config.options.modes
        function onModesChanged() {
            root.refreshDefinitions();
        }
        function onRoutinesChanged() {
            root.refreshDefinitions();
        }
    }

    Timer {
        id: saveTimer
        interval: 300
        repeat: false
        onTriggered: root.flushSaves()
    }

    // Bumped whenever the watcher set is rebuilt, so a UI that holds a
    // watcher can look it up again instead of keeping a destroyed one.
    property int watchersRevision: 0

    Instantiator {
        id: watchers
        model: root.ready ? root.modes : []
        delegate: ModeWatcher {
            required property var modelData
            modeDef: modelData
            onEvaluated: (satisfied, initial) => root.handleEvaluation(modeId, satisfied, initial)
            onScheduleEnded: root.handleScheduleEnded(modeId)
        }
        onObjectAdded: (index, object) => root.watchersRevision += 1
        onObjectRemoved: (index, object) => {
            root.watchersRevision += 1;
            // Definitions were edited: the active mode may have been deleted.
            if (root.ready && root.active && !root.modeById(root.activeModeId))
                root.deactivate("deleted");
        }
    }

    Instantiator {
        id: routineWatchers
        model: root.ready ? root.routines : []
        delegate: ModeWatcher {
            id: routineWatcher
            required property var modelData
            modeDef: modelData
            // Per-routine grace, since several can be winding down at once.
            readonly property Timer grace: Timer {
                repeat: false
                onTriggered: {
                    if (routineWatcher.satisfied)
                        return;
                    root.stopRoutine(routineWatcher.modeId, "triggers ended");
                }
            }
            onEvaluated: (satisfied, initial) => root.handleRoutineEvaluation(modeId, satisfied, initial)
        }
        onObjectAdded: (index, object) => root.watchersRevision += 1
        onObjectRemoved: (index, object) => {
            root.watchersRevision += 1;
            if (!root.ready)
                return;
            for (const id of root.runningRoutineIds.slice()) {
                if (!root.routineById(id))
                    root.stopRoutine(id, "deleted");
            }
        }
    }

    Timer {
        id: graceTimer
        property string modeId: ""
        repeat: false
        onTriggered: {
            if (root.activeModeId !== graceTimer.modeId || root.activeIsManual)
                return;
            const w = root.watcherFor(graceTimer.modeId);
            if (w && w.satisfied)
                return;
            root.deactivate("triggers ended");
        }
    }

    Timer {
        id: autoOffTimer
        repeat: false
        onTriggered: root.checkAutoOff()
    }

    Connections {
        target: DateTime.clock
        function onDateChanged() {
            root.checkAutoOff();
            root.runDueSteps();
        }
    }

    // ---------------------------------------------------------------- ipc

    function clockText(epochMs, format) {
        return new Date(epochMs).toLocaleString(Qt.locale(), format);
    }

    function historyLine(h) {
        const failed = h.failed && h.failed.length ? ` [skipped ${h.failed.length}]` : "";
        return `${h.kind} ${h.id} ${h.event} (${h.why})${failed}`;
    }

    // One line per trigger of a mode or routine watcher, with the live verdict.
    function triggerLines(w) {
        const lines = [];
        if (!w)
            return lines;
        for (let i = 0; i < w.conditions.count; ++i) {
            const loader = w.conditionAt(i);
            const type = loader?.conditionType ?? "?";
            const item = loader?.item ?? null;
            const verdict = !loader?.supported ? "unsupported"
                : (item ? (item.satisfied ? "on" : "off") : "loading");
            const reason = item?.reason ? ` (${item.reason})` : "";
            const inverted = loader?.modelData?.not ? " [inverted]" : "";
            const dwell = (loader?.forSec ?? 0) > 0
                ? ` [for ${loader.forSec}s: ${loader.held ? "held" : (loader.counting ? "counting" : "idle")}]` : "";
            lines.push(`  ${type}: ${verdict}${reason}${inverted}${dwell}`);
        }
        return lines;
    }

    function describeRoutine(r) {
        const flags = [];
        if (r.preset)
            flags.push("preset");
        if (!r.enabled)
            flags.push("disabled");
        if (root.isRoutineSuppressed(r.id))
            flags.push("suppressed");
        if (r.cooldownSec > 0)
            flags.push(`cooldown ${r.cooldownSec}s`);
        const w = root.routineWatcherFor(r.id);
        const trig = r.triggers.length ? r.triggers.map(t => t.type).join(",") : "manual";
        const sat = w ? (w.evaluatedOnce ? (w.satisfied ? "on" : "off") : "…") : "-";
        const mark = root.isRoutineRunning(r.id) ? "*" : " ";
        const suffix = flags.length ? ` (${flags.join(", ")})` : "";
        return `${mark} ${r.id.padEnd(14)} ${r.name.padEnd(16)} ${r.kind.padEnd(5)} `
            + `triggers=${trig} [${sat}] actions=${r.actions.length}${suffix}`;
    }

    function describeMode(m) {
        const flags = [];
        if (m.preset)
            flags.push("preset");
        if (m.auto)
            flags.push("auto");
        if (root.isSuppressed(m.id))
            flags.push("suppressed");
        const w = root.watcherFor(m.id);
        const trig = m.triggers.length ? m.triggers.map(t => t.type).join(",") : "manual";
        const sat = w ? (w.evaluatedOnce ? (w.satisfied ? "on" : "off") : "…") : "-";
        const mark = m.id === root.activeModeId ? "*" : " ";
        const suffix = flags.length ? ` (${flags.join(", ")})` : "";
        return `${mark} ${m.id.padEnd(14)} ${m.name.padEnd(16)} triggers=${trig} [${sat}] `
            + `actions=${m.actions.length}${suffix}`;
    }

    function statusText() {
        const lines = [];
        lines.push(`ready=${root.ready} enabled=${root.enabled} modes=${root.modes.length}`);
        if (root.active) {
            const since = root.clockText(root.activeSince, "hh:mm:ss");
            const ends = root.activeEndsAt > 0 ? root.clockText(root.activeEndsAt, "hh:mm") : "open";
            lines.push(`active: ${root.activeModeId} source=${root.activeSource} since=${since} `
                + `ends=${ends}`);
            for (const e of ModeSchema.toArray(root.state.snapshot))
                lines.push(`  ${e.type}: ${JSON.stringify(e.was)} -> ${JSON.stringify(e.set)}`);
            for (const f of ModeSchema.toArray(root.state.failed))
                lines.push(`  skipped ${f}`);
        } else {
            lines.push(`active: none (last used: ${root.lastUsedModeId || "-"})`);
        }
        for (const run of root.routineRuns) {
            const since = root.clockText(run.since, "hh:mm:ss");
            lines.push(`routine: ${run.id} source=${run.source} since=${since}`);
            for (const e of ModeSchema.toArray(run.snapshot))
                lines.push(`  ${e.type}: ${JSON.stringify(e.was)} -> ${JSON.stringify(e.set)}`);
            for (const f of ModeSchema.toArray(run.failed))
                lines.push(`  skipped ${f}`);
        }
        for (const s of root.pendingSteps) {
            lines.push(`paused: ${s.kind} ${s.id} resumes at action ${s.index + 1} `
                + `at ${root.clockText(s.dueAt, "hh:mm:ss")}`);
        }
        const h = root.history[0];
        if (h)
            lines.push(`last event: ${root.clockText(h.t, "hh:mm:ss")} ${root.historyLine(h)}`);
        return lines.join("\n");
    }

    IpcHandler {
        target: "modes"

        function status(): string {
            return root.statusText();
        }

        function list(): string {
            return root.modes.map(m => root.describeMode(m)).join("\n");
        }

        function activate(id: string): string {
            return root.activate(id, "manual") ? `started ${id}` : `no such mode: ${id}`;
        }

        function deactivate(): string {
            const id = root.activeModeId;
            return root.deactivate("manual") ? `stopped ${id}` : "nothing active";
        }

        function toggleMode(id: string): string {
            const wasActive = root.activeModeId === id;
            const ok = root.toggle(id);
            if (!ok)
                return `no such mode: ${id}`;
            return wasActive ? `stopped ${id}` : `started ${id}`;
        }

        function toggleLast(): string {
            if (root.active) {
                const id = root.activeModeId;
                root.deactivate("manual");
                return `stopped ${id}`;
            }
            return root.toggleLast() ? `started ${root.activeModeId}` : "no last used mode";
        }

        function history(): string {
            return root.history.slice(0, 30)
                .map(h => `${root.clockText(h.t, "dd/MM hh:mm:ss")} ${root.historyLine(h)}`)
                .join("\n") || "empty";
        }

        function clearHistory(): void {
            root.clearHistory();
        }

        function seedPresets(): string {
            const added = root.seedPresets();
            return added.length ? `added ${added.join(", ")}` : "all presets present";
        }

        function resetPreset(id: string): string {
            return root.resetPreset(id) ? `reset ${id}` : `not a preset: ${id}`;
        }

        // Scripting / testing surface for definitions.
        function upsert(json: string): string {
            try {
                const id = root.upsertMode(JSON.parse(json));
                return `saved ${id}`;
            } catch (e) {
                return `invalid mode json: ${e}`;
            }
        }

        function remove(id: string): string {
            if (!root.modeById(id))
                return `no such mode: ${id}`;
            root.removeMode(id);
            return `removed ${id}`;
        }

        function setAuto(id: string, on: bool): string {
            const def = root.modeById(id);
            if (!def)
                return `no such mode: ${id}`;
            def.auto = on;
            root.upsertMode(def);
            return `${id} auto=${on}`;
        }

        function show(id: string): string {
            const def = root.modeById(id);
            return def ? JSON.stringify(def, null, 2) : `no such mode: ${id}`;
        }

        // Live trigger verdicts of one mode or routine.
        function triggers(id: string): string {
            const w = root.watcherFor(id) ?? root.routineWatcherFor(id);
            if (!w)
                return `no such mode or routine: ${id}`;
            const verdict = w.evaluatedOnce ? (w.satisfied ? "satisfied" : "not satisfied") : "evaluating";
            const head = `${id}: ${verdict} (match ${w.matchAll ? "all" : "any"}, source ${w.source})`;
            return [head].concat(root.triggerLines(w)).join("\n");
        }

        function actions(): string {
            return root.actions.types().map(t => root.actions.describe(t)).join("\n");
        }

        function game(): string {
            return GameDetector.statusText();
        }

        // "Treat this window class as a game" / undo.
        function addGameClass(cls: string): string {
            return GameDetector.addExtraClass(cls) ? `added ${cls}` : `${cls} already listed or empty`;
        }

        function removeGameClass(cls: string): string {
            GameDetector.removeExtraClass(cls);
            return `removed ${cls}`;
        }

        // ---- routines
        function routines(): string {
            return root.routines.map(r => root.describeRoutine(r)).join("\n") || "no routines";
        }

        function runRoutine(id: string): string {
            if (!root.routineById(id))
                return `no such routine: ${id}`;
            return root.runRoutine(id, "manual") ? `ran ${id}` : `${id} not run`;
        }

        function stopRoutine(id: string): string {
            return root.stopRoutine(id, "manual") ? `stopped ${id}` : `${id} is not running`;
        }

        function upsertRoutine(json: string): string {
            try {
                const id = root.upsertRoutine(JSON.parse(json));
                return `saved routine ${id}`;
            } catch (e) {
                return `invalid routine json: ${e}`;
            }
        }

        function removeRoutine(id: string): string {
            if (!root.routineById(id))
                return `no such routine: ${id}`;
            root.removeRoutine(id);
            return `removed routine ${id}`;
        }

        function setRoutineEnabled(id: string, on: bool): string {
            const def = root.routineById(id);
            if (!def)
                return `no such routine: ${id}`;
            def.enabled = on;
            root.upsertRoutine(def);
            return `${id} enabled=${on}`;
        }

        function showRoutine(id: string): string {
            const def = root.routineById(id);
            return def ? JSON.stringify(def, null, 2) : `no such routine: ${id}`;
        }

        function templates(): string {
            return ModeSchema.routineTemplates().map(t => `${t.template.padEnd(20)} ${t.name}`).join("\n");
        }

        function addTemplate(key: string): string {
            const id = root.addRoutineFromTemplate(key);
            return id.length ? `added routine ${id}` : `no such template: ${key}`;
        }

        // Overlay controls; the overlay itself lands in phase 2.
        function open(): void {
            GlobalStates.modesOpen = true;
        }

        function close(): void {
            GlobalStates.modesOpen = false;
        }

        function toggle(): void {
            GlobalStates.modesOpen = !GlobalStates.modesOpen;
        }
    }
}
