pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.dynamicIsland.core

/**
 * System Health: runs the `health_watch` helper and holds what it reports.
 *
 * The helper owns every measurement — systemd on both buses, the journal, UDisks2,
 * fwupd, the package log, pressure and thermals — and speaks the line protocol in
 * scripts/health/PROTOCOL.md. This side keeps the latest state of each message, turns
 * live critical findings into alerts (rate-limited, held while you are fullscreen or in
 * Do Not Disturb), and forwards the user's actions back. It is headless: the app, the
 * island strip and the assistant all read it, none of them talk to the helper.
 *
 * Nothing is spawned while `health.enable` is off, and nothing is built in QML until the
 * app opens: the window lives in a RetainedLoader like the clock's.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.health ?? null
    readonly property bool enabled: Config.ready && (root.opts?.enable ?? true)

    readonly property string helperDir: `${Directories.scriptPath}/health`
    readonly property string binaryPath: `${root.helperDir}/health_watch`
    readonly property string accessScript: `${root.helperDir}/crash-access.sh`
    readonly property string stateDir: FileUtils.trimFileProtocol(`${Directories.state}/user/health`)

    // ── Helper lifecycle ────────────────────────────────────────────────
    /// Assumed present until the probe says otherwise, so the app never flashes its
    /// setup page on a start where the binary is there.
    property bool binaryPresent: true
    property bool probed: false
    /// True once the helper announced itself.
    property bool running: false
    /// True once the helper finished its first full scan; findings before it are the
    /// starting state, after it they are live.
    property bool synced: false
    property bool _restarting: false

    readonly property RustHelperBuild helperBuild: RustHelperBuild {
        label: "SystemHealth"
        sourceDir: `${root.helperDir}/health_watch_src`
        crateName: "health_watch"
        onFinished: ok => {
            root.checkBinary();
            if (ok)
                root.restart();
        }
    }

    /// Once the helper exists, the Overview offers crash-dump access one time, the way
    /// the setup script does after its own build — whichever way the helper was built
    /// (the app, the setup script, a terminal). "Not now" is remembered.
    /// One offer at a time: it waits for the pacman hook's.
    readonly property bool offerDumpAccess: root.running && root.dumpAccess === "denied"
        && !(Persistent.states?.healthApp?.dumpAccessAsked ?? false) && !root.offerQtHook

    function answerDumpOffer(grant): void {
        if (Persistent.states?.healthApp)
            Persistent.states.healthApp.dumpAccessAsked = true;
        if (grant)
            root.setDumpAccess(true);
    }

    // ── What the helper reported ────────────────────────────────────────
    property var sources: ({})
    property string journalAccess: ""
    property string packageManager: ""
    /// "granted" | "denied" | "" (not known yet). Read from the ACL, never stored.
    property string dumpAccess: ""
    property string user: ""

    /// id → Finding, replaced as a whole on every change so bindings notice.
    property var findingsById: ({})
    /// Muted findings are still sent by the helper (the Journal and Crashes pages list
    /// them); everything that counts or alerts leaves them out.
    readonly property var findings: {
        const order = { critical: 0, warning: 1, info: 2 };
        return Object.values(root.findingsById).concat(root.localFindings).filter(f => f.muted !== true).sort((a, b) => (order[a.sev] ?? 3) - (order[b.sev] ?? 3) || Number(b.since ?? 0) - Number(a.since ?? 0));
    }
    /// What the hero counts: critical and warning findings, app launches and snoozed
    /// ones excluded.
    readonly property var attention: root.findings.filter(f => f.kind !== "appLaunch" && !root.isSnoozed(f) && (f.sev === "critical" || f.sev === "warning"))
    readonly property int attentionCount: root.attention.length
    /// Snoozed findings, for the Overview's folded "Snoozed" group.
    readonly property var snoozedFindings: root.findings.filter(f => root.isSnoozed(f))

    function isSnoozed(f): bool {
        return f?.snoozed !== null && f?.snoozed !== undefined;
    }

    /// Snoozes finding `id` until `until` (epoch ms), or until the next boot when
    /// `until` is "boot". The helper wakes it and keeps it quiet meanwhile.
    function snooze(id, until): void {
        if (until === "boot")
            root.send({ t: "snooze", id: String(id), untilBoot: true });
        else
            root.send({ t: "snooze", id: String(id), until: Math.round(Number(until)) });
    }
    function unsnooze(id): void { root.send({ t: "unsnooze", id: String(id) }); }

    // ── Findings the shell makes itself ─────────────────────────────────
    // The settings file is the shell's, not the helper's: a broken one is said here.
    property double configHealthSince: Date.now()
    readonly property string configState: Config.configHealthState
    onConfigStateChanged: root.configHealthSince = Date.now()
    readonly property var localFindings: {
        const s = root.configState;
        if (s === "ok" || s === "migrated" || s === "recovered")
            return [];
        return [{
            id: "config", kind: "config", sev: s === "malformed" ? "critical" : "info", since: root.configHealthSince,
            count: 1, fp: "", muted: false, snoozed: null, alert: false,
            data: { state: s, keys: Array.from(Config.configHealthKeys ?? []) }
        }];
    }

    /// Findings that went away in the last week, newest last: { id, kind, sev,
    /// data, since, resolvedAt, by } ("restart" and the like, or "self").
    property var resolved: []
    /// One row per boot, oldest first: phases in ms and the slowest units.
    property var boots: []
    /// The latest `hardware` message: batteries, peripherals, gpus, cpu, memory,
    /// fans and this boot's hardware events. Null until the first one.
    property var hardware: null
    /// The rebuild scan: whether it is running, and when it last started or finished.
    /// It runs after every package transaction, so a rebuild clears its own entry.
    property var rebuildScan: ({ running: false, at: 0, count: 0 })

    /// "Checking again…" or "Checked at 14:05": whether the rebuild list is current.
    function rebuildScanText(): string {
        if (root.rebuildScan.running)
            return Translation.tr("Checking again…");
        if (!(root.rebuildScan.at > 0))
            return "";
        return Translation.tr("Checked at %1, and again after every package install.").arg(Qt.formatTime(new Date(root.rebuildScan.at), "hh:mm"));
    }

    /// The last `days` daily values of a history field, oldest first, null for a day
    /// without a row (or, with `zeroIsGap`, a row whose value is 0: "not measured").
    function historySeries(field, zeroIsGap, days): var {
        const n = days ?? 30;
        const byDate = {};
        for (const d of root.history)
            byDate[d.date] = d;
        const out = [];
        const today = new Date();
        for (let i = n - 1; i >= 0; i--) {
            const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() - i);
            const row = byDate[Qt.formatDate(d, "yyyy-MM-dd")];
            const v = row ? Number(row[field] ?? 0) : null;
            out.push(v === null || (zeroIsGap && !(v > 0)) ? null : v);
        }
        return out;
    }

    property var crashGroups: []
    property var updateTransactions: []
    property var journal: ({ access: "", groups: [], noise: { knownGroups: 0, knownLines: 0, mutedGroups: 0 } })
    property var drives: []
    property var vitals: null
    property var system: null
    property var history: []
    property double lastMessageAt: 0

    function findingsOfKind(kinds): var {
        const set = Array.isArray(kinds) ? kinds : [kinds];
        return root.findings.filter(f => set.includes(f.kind));
    }

    function finding(id): var {
        return root.findingsById[String(id)] ?? root.localFindings.find(f => f.id === String(id)) ?? null;
    }

    /// Whether the subject of an assistant key ("finding:<id>", "journal:<fp>",
    /// "crash:<exe>", "overview") is still there. Only meaningful once `synced`.
    function subjectExists(key): bool {
        key = String(key ?? "");
        if (key.startsWith("finding:"))
            return root.finding(key.slice(8)) !== null;
        if (key.startsWith("journal:"))
            return root.journal.groups.some(g => g.fp === key.slice(8));
        if (key.startsWith("crash:"))
            return root.crashGroup(key.slice(6)) !== null;
        return true;
    }

    /// The assistant key a finding's answer is kept under: crashes and journal groups
    /// are asked about on their own pages, under keys equal to their finding ids.
    function answerKey(f): string {
        if (!f)
            return "";
        return f.kind === "crash" || f.kind === "journal" ? String(f.id) : `finding:${f.id}`;
    }

    /// Opens the app on an assistant key's subject: crash and journal keys are
    /// finding ids already.
    function openSubject(key): void {
        key = String(key ?? "");
        if (key.startsWith("finding:"))
            root.openFinding(key.slice(8));
        else if (key.startsWith("journal:") || key.startsWith("crash:"))
            root.openFinding(key);
        else
            GlobalStates.openHealthApp("overview", "");
    }

    // ── Talking to the helper ───────────────────────────────────────────
    property int _req: 0
    property var _callbacks: ({})

    function send(obj): void {
        if (!helper.running)
            return;
        helper.write(JSON.stringify(obj) + "\n");
    }

    /// Asks the helper something; `callback(ok, data, error)` runs with its reply.
    function query(what, args, callback): void {
        root._request(Object.assign({ t: "query", what: what }, args ?? {}), callback);
    }

    /// Runs a unit or drive action (restart, stop, start, resetFailed, disable, enable,
    /// selftest). System units go through polkit, so the shell's agent asks.
    function act(verb, args, callback): void {
        root._request(Object.assign({ t: "act", verb: verb }, args ?? {}), callback);
    }

    function _request(obj, callback): void {
        if (!helper.running) {
            if (callback)
                callback(false, null, "not-running");
            return;
        }
        const req = ++root._req;
        if (callback) {
            const next = Object.assign({}, root._callbacks);
            next[req] = callback;
            root._callbacks = next;
        }
        obj.req = req;
        root.send(obj);
    }

    function mute(fp): void { root.send({ t: "mute", fp: String(fp) }); }
    function unmute(fp): void { root.send({ t: "unmute", fp: String(fp) }); }
    function markKnown(fp): void { root.send({ t: "markKnown", fp: String(fp) }); }
    function muteProgram(exe): void { root.send({ t: "muteProgram", exe: String(exe) }); }
    function unmuteProgram(exe): void { root.send({ t: "unmuteProgram", exe: String(exe) }); }
    function dismiss(id): void { root.send({ t: "dismiss", id: String(id) }); }
    function resetNoise(): void { root.send({ t: "resetNoise" }); }

    function rescan(): void {
        root.synced = false;
        root._rescanning = true;
        root.send({ t: "rescan" });
        root.refreshDumpAccess();
    }

    /// A "Check now" finished. Findings that did not change are not re-sent, so a
    /// list with nothing new looks the same: the app says so instead.
    signal rescanned()
    property bool _rescanning: false

    /// The app tells the helper when it is on screen, for 2 s vitals instead of 15 s.
    property bool appVisible: false
    onAppVisibleChanged: root.send({ t: "visible", app: root.appVisible })

    function handleLine(line): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            console.warn("[Health] unreadable line from helper:", line);
            return;
        }
        root.lastMessageAt = Date.now();
        switch (msg.t) {
        case "ready":
            root.running = true;
            root.synced = false;
            root.sources = msg.sources ?? {};
            root.journalAccess = String(msg.sources?.journal ?? "");
            root.packageManager = String(msg.sources?.packages ?? "");
            root.dumpAccess = String(msg.dumpAccess ?? "");
            root.user = String(msg.user ?? "");
            root.findingsById = {};
            if (root.appVisible)
                root.send({ t: "visible", app: true });
            break;
        case "synced":
            root.synced = true;
            if (root._rescanning) {
                root._rescanning = false;
                root.rescanned();
            }
            break;
        case "access":
            root.dumpAccess = String(msg.dumpAccess ?? root.dumpAccess);
            break;
        case "finding":
            root.applyFinding(msg);
            break;
        case "crashes":
            root.crashGroups = Array.from(msg.groups ?? []);
            break;
        case "updates":
            root.updateTransactions = Array.from(msg.transactions ?? []);
            break;
        case "journal":
            root.journal = {
                access: String(msg.access ?? ""),
                groups: Array.from(msg.groups ?? []),
                noise: msg.noise ?? { knownGroups: 0, knownLines: 0, mutedGroups: 0 }
            };
            break;
        case "drives":
            root.drives = Array.from(msg.drives ?? []);
            break;
        case "vitals":
            root.vitals = msg;
            break;
        case "system":
            root.system = msg;
            break;
        case "history":
            root.history = Array.from(msg.days ?? []);
            break;
        case "resolved":
            root.resolved = Array.from(msg.items ?? []);
            break;
        case "boot":
            root.boots = Array.from(msg.boots ?? []);
            break;
        case "hardware":
            root.hardware = msg;
            break;
        case "rebuildScan":
            root.rebuildScan = { running: msg.running === true, at: Number(msg.at ?? 0), count: Number(msg.count ?? 0) };
            break;
        case "reply": {
            const cb = root._callbacks[msg.req];
            if (cb) {
                const next = Object.assign({}, root._callbacks);
                delete next[msg.req];
                root._callbacks = next;
                try {
                    cb(msg.ok === true, msg.data ?? null, String(msg.error ?? ""), String(msg.message ?? ""));
                } catch (e) {
                    console.warn("[Health] reply handler failed:", e);
                }
            }
            break;
        }
        case "log":
            console.warn(`[Health] helper: ${msg.msg ?? ""}`);
            break;
        }
    }

    function applyFinding(msg): void {
        const next = Object.assign({}, root.findingsById);
        if (msg.op === "resolve") {
            if (!(msg.id in next))
                return;
            delete next[msg.id];
            root.findingsById = next;
            root.dropHeld(String(msg.id));
            root._actionResolved(String(msg.id));
            return;
        }
        const f = msg.f;
        if (!f || !f.id)
            return;
        next[f.id] = f;
        root.findingsById = next;
        if (f.alert === true && f.muted !== true && root.synced)
            root.raiseAlert(f);
    }

    // ── Alerts ──────────────────────────────────────────────────────────
    /// The island shows the strip; its source listens here.
    signal islandAlert(var finding)

    readonly property var alertOpts: root.opts?.alerts ?? null
    readonly property bool islandOwnsAlerts: IslandPolicy.enabled && IslandPolicy.widgetEnabled("health") && (root.alertOpts?.island ?? true)
    /// Fullscreen, Do Not Disturb or a locked screen: alerts wait and arrive as one.
    readonly property bool quiet: GlobalStates.screenLocked
        || ((root.alertOpts?.holdInFullscreen ?? true) && ((ToplevelManager.activeToplevel?.fullscreen ?? false) || Notifications.effectiveSilent))
    property var _held: []
    property var _recentAlerts: []

    onQuietChanged: {
        if (!root.quiet && root._held.length > 0)
            releaseHeld.restart();
    }

    // Leaving fullscreen often lands in another fullscreen window a moment later
    // (a game's launcher, a video); a short beat avoids alerting in between.
    Timer {
        id: releaseHeld
        interval: 2500
        onTriggered: {
            if (root.quiet || root._held.length === 0)
                return;
            const held = root._held.filter(f => root.findingsById[f.id] !== undefined);
            root._held = [];
            if (held.length === 1)
                root.deliverAlert(held[0], 0);
            else if (held.length > 1)
                root.deliverAlert(held[0], held.length - 1);
        }
    }

    function dropHeld(id): void {
        if (root._held.some(f => f.id === id))
            root._held = root._held.filter(f => f.id !== id);
    }

    function raiseAlert(f): void {
        if (root.quiet) {
            if (!root._held.some(h => h.id === f.id))
                root._held = [...root._held, f];
            return;
        }
        const now = Date.now();
        const recent = root._recentAlerts.filter(t => now - t < 600000);
        const max = root.alertOpts?.maxPer10Min ?? 3;
        if (recent.length >= max) {
            // Over the budget: keep it for one summary once the window frees up.
            root._recentAlerts = recent;
            if (!root._held.some(h => h.id === f.id))
                root._held = [...root._held, f];
            budgetTimer.interval = Math.max(1000, 600000 - (now - recent[0]));
            budgetTimer.restart();
            return;
        }
        root._recentAlerts = [...recent, now];
        root.deliverAlert(f, 0);
    }

    Timer {
        id: budgetTimer
        onTriggered: releaseHeld.restart()
    }

    function deliverAlert(f, more): void {
        const payload = { finding: f, more: more };
        if (root.islandOwnsAlerts) {
            root.islandAlert(payload);
            return;
        }
        root.notifyAlert(payload);
    }

    /// The fallback when the island is off or refused the strip (its quiet window).
    function notifyAlert(payload): void {
        if (!(root.alertOpts?.notifyFallback ?? true))
            return;
        const f = payload.finding;
        const more = Number(payload.more ?? 0);
        const actions = [{ identifier: "__qs_health_open", text: Translation.tr("Details") }];
        const fix = root.primaryFix(f);
        if (fix)
            actions.unshift({ identifier: "__qs_health_fix", text: fix.label });
        Notifications.publishInternalNotification({
            appName: Translation.tr("System Health"),
            appIcon: "health_metrics",
            summary: more > 0 ? Translation.tr("%1 and %2 more").arg(HealthText.title(f)).arg(more) : HealthText.title(f),
            body: HealthText.detail(f, Date.now()),
            urgency: f.sev === "critical" ? "critical" : "normal",
            actions: actions,
            actionPayload: { id: f.id }
        });
    }

    Connections {
        target: Notifications
        function onInternalActionInvoked(identifier, notificationId, payload) {
            const id = String(payload?.id ?? "");
            if (identifier === "__qs_health_open")
                root.openFinding(id);
            else if (identifier === "__qs_health_fix")
                root.runPrimaryFix(id);
        }
    }

    // ── Fixes ───────────────────────────────────────────────────────────
    /// The one action an alert offers as its button, or null.
    function primaryFix(f): var {
        if (!f)
            return null;
        const d = f.data ?? {};
        switch (f.kind) {
        case "unit":
            // A missing program is not fixed by restarting it; stopping the retries is.
            if (d.why === "exec-missing" || d.why === "user")
                return { label: Translation.tr("Disable"), verb: "disable" };
            return { label: Translation.tr("Restart"), verb: "restart" };
        case "restartLoop":
            return { label: Translation.tr("Stop"), verb: "stop" };
        case "crash":
            return { label: Translation.tr("Copy report"), verb: "copyReport" };
        case "reboot":
            return { label: Translation.tr("Restart"), verb: "reboot" };
        case "rebuild": {
            const n = root.rebuildable(d).length + (Array.from(d.packages ?? []).some(p => p.reason === "quickshell") ? 1 : 0);
            return n > 0 ? { label: HealthText.plural(n, Translation.tr("Rebuild %1 in a terminal"), Translation.tr("Rebuild %1 in a terminal")), verb: "rebuild" }
                : { label: Translation.tr("Install the missing libraries"), verb: "findLibs" };
        }
        case "shellHelper":
            return { label: Translation.tr("Rebuild"), verb: "rebuildHelper" };
        case "config":
            return { label: Translation.tr("Open Settings"), verb: "openSettings" };
        default:
            return null;
        }
    }

    readonly property string guardDir: `${Directories.scriptPath}/quickshell-guard`

    /// The terminal command that rebuilds what a `rebuild` finding lists: Quickshell
    /// through qs-rebuild.sh (it knows a repository build from an AUR one), the rest
    /// with the AUR helper; `--rebuild`, or yay reinstalls its cached build, and
    /// `aur/`, or it offers a repository package that provides the same name.
    function rebuildCommand(d): var {
        const pkgs = Array.from(d?.packages ?? []);
        if (pkgs.some(p => p.reason === "quickshell"))
            return ["bash", `${root.guardDir}/qs-rebuild.sh`];
        const names = root.rebuildable(d).map(p => `aur/${p.name}`);
        const aur = String(d?.aurHelper ?? "") || "yay";
        return [aur, "-S", "--rebuild", ...names];
    }

    /// The packages a rebuild can fix: built on this machine. A prebuilt one (no
    /// build() in its PKGBUILD, or a -bin) would only download the same files again.
    function rebuildable(d): var {
        return Array.from(d?.packages ?? []).filter(p => p.reason !== "quickshell" && p.foreign !== false && p.prebuilt !== true);
    }

    /// Libraries the prebuilt packages miss: installing what provides them is the fix.
    function missingPrebuiltLibs(d): var {
        const libs = [];
        for (const p of Array.from(d?.packages ?? []).filter(p => p.prebuilt === true && p.reason === "lib"))
            for (const lib of Array.from(p.libs ?? []))
                if (!libs.includes(lib))
                    libs.push(lib);
        return libs;
    }

    /// Finds the packages that provide the missing libraries (pacman's file list,
    /// synced first) and installs them after asking: scripts/health/install-missing-libs.sh.
    function findLibsCommand(d): var {
        return ["bash", `${root.helperDir}/install-missing-libs.sh`, ...root.missingPrebuiltLibs(d)];
    }

    function runPrimaryFix(id, callback): void {
        const fix = root.primaryFix(root.finding(id));
        if (fix)
            root.runAction(id, fix.verb, callback);
    }

    // ── Actions and how they went ───────────────────────────────────────
    // Every button that changes something goes through runAction, so the row, the
    // sheet, the island strip and the assistant's card all show the same outcome.
    // A reply only says systemd queued the job; whether a restart fixed anything
    // shows when the finding resolves, so a restart waits for that.
    /// finding id → { verb, state, message, at }. state: "running", "waiting" (queued,
    /// watching the finding), "done", "stillFailing", "cancelled", "failed".
    property var actions: ({})
    /// How long a restart may take to clear its finding before it counts as failing.
    readonly property int actionSettleMs: 15000

    function action(id): var {
        return root.actions[String(id)] ?? null;
    }

    /// An action reached its outcome: done, stillFailing, cancelled or failed. The app's
    /// snackbar says so, since a fixed finding's row is gone by then.
    signal actionSettled(string id, var action)

    function _setAction(id, fields): void {
        const next = Object.assign({}, root.actions);
        if (fields === null)
            delete next[id];
        else
            next[id] = Object.assign({}, next[id] ?? {}, fields, { at: Date.now() });
        root.actions = next;
        if (fields && ["done", "stillFailing", "cancelled", "failed"].includes(fields.state))
            root.actionSettled(id, next[id]);
    }

    function _actionResolved(id): void {
        const a = root.actions[id];
        if (a && (a.state === "running" || a.state === "waiting"))
            root._setAction(id, { state: "done" });
    }

    /// Runs `verb` on finding `id`; `callback(ok)` runs once the reply is in.
    function runAction(id, verb, callback): void {
        id = String(id);
        const f = root.finding(id);
        const d = f?.data ?? {};
        const finish = ok => {
            if (callback)
                callback(ok);
        };
        if (verb === "reboot") {
            GlobalStates.sessionOpen = true;
            finish(true);
            return;
        }
        // Handed to a terminal or another window: nothing to wait for here.
        if (verb === "rebuild" || verb === "findLibs" || verb === "rebuildHelper" || verb === "openSettings") {
            if (verb === "findLibs") {
                root.runInTerminal(root.findLibsCommand(d));
            } else if (verb === "rebuild") {
                const cmd = root.rebuildCommand(d);
                // qs-rebuild.sh asks and waits for Enter itself.
                if (cmd[0] === "bash")
                    root.openTerminal(cmd);
                else
                    root.runInTerminal(cmd);
            } else if (verb === "rebuildHelper") {
                root.runInTerminal(["bash", Directories.rustHelpersScriptPath, "build", String(d.name ?? "")]);
            } else {
                GlobalStates.openSettingsPage("", "", "");
            }
            finish(true);
            return;
        }
        // The title is kept: a restart that works takes the finding with it.
        root._setAction(id, { verb: verb, state: "running", message: "", title: f ? HealthText.title(f) : "" });
        if (verb === "copyReport") {
            root.copyCrashReport(String(d.exe ?? ""), () => {
                root._setAction(id, { state: "done" });
                finish(true);
            });
            return;
        }
        root.act(verb, { scope: d.scope, unit: d.unit, drive: d.path }, (ok, data, error, message) => {
            if (!ok) {
                // "denied" is polkit: the prompt was dismissed or the password refused.
                root._setAction(id, { state: error === "denied" ? "cancelled" : "failed", message: message || error });
                finish(false);
                return;
            }
            if (verb === "disable" && f) {
                // Disabling leaves the unit in its failed state; clearing it is the
                // rest of what "stop trying" means.
                root.act("resetFailed", { scope: d.scope, unit: d.unit });
            }
            const watch = (verb === "restart" || verb === "resetFailed" || verb === "disable") && root.finding(id) !== null;
            root._setAction(id, { state: watch ? "waiting" : "done" });
            finish(true);
        });
    }

    /// One line for an action's state, for every surface that shows it.
    function actionText(a): string {
        if (!a)
            return "";
        const v = a.verb;
        switch (a.state) {
        case "running":
        case "waiting":
            return v === "restart" ? Translation.tr("Restarting…") : v === "stop" ? Translation.tr("Stopping…")
                : v === "disable" ? Translation.tr("Disabling…") : v === "resetFailed" ? Translation.tr("Clearing…")
                : v === "selftest" ? Translation.tr("Starting a self-test…") : v === "copyReport" ? Translation.tr("Copying…")
                : Translation.tr("Working…");
        case "done":
            return v === "restart" ? Translation.tr("Restarted") : v === "stop" ? Translation.tr("Stopped")
                : v === "disable" ? Translation.tr("Disabled") : v === "resetFailed" ? Translation.tr("Cleared")
                : v === "selftest" ? Translation.tr("Self-test started") : v === "copyReport" ? Translation.tr("Report copied")
                : Translation.tr("Done");
        case "stillFailing":
            return v === "restart" ? Translation.tr("Restarted, but it failed again") : Translation.tr("Done, but it is still failing");
        case "cancelled":
            return Translation.tr("Cancelled: the password was not given");
        case "failed":
            return Translation.tr("It did not work: %1").arg(a.message || "?");
        default:
            return "";
        }
    }

    // Settles restarts that did not clear their finding, and lets finished states go:
    // a success after a few seconds, a failure after a minute.
    Timer {
        id: actionSweep
        interval: 1000
        repeat: true
        running: Object.keys(root.actions).length > 0
        onTriggered: {
            const now = Date.now();
            let changed = false;
            const next = Object.assign({}, root.actions);
            for (const id of Object.keys(next)) {
                const a = next[id];
                const age = now - (a.at ?? now);
                if (a.state === "waiting" && age > root.actionSettleMs) {
                    next[id] = Object.assign({}, a, { state: root.finding(id) ? "stillFailing" : "done", at: now });
                    changed = true;
                    Qt.callLater(() => root.actionSettled(id, next[id]));
                } else if ((a.state === "done" && age > 4000) || (a.state === "cancelled" && age > 6000)
                        || ((a.state === "failed" || a.state === "stillFailing") && age > 60000)) {
                    delete next[id];
                    changed = true;
                }
            }
            if (changed)
                root.actions = next;
        }
    }

    /// Kinds shown on the Hardware page (the "storage" tab: storage moved into it).
    readonly property var hardwareKinds: ["disk", "drive", "battery", "peripheralBattery", "mce", "gpu", "oom", "edac", "radioFw", "usb", "aer", "overheat", "fan"]

    function openFinding(id): void {
        const f = root.finding(id);
        const tab = !f ? "overview"
            : ["unit", "appLaunch", "restartLoop"].includes(f.kind) ? "services"
            : f.kind === "crash" ? "crashes"
            : f.kind === "journal" ? "journal"
            : root.hardwareKinds.includes(f.kind) ? "storage"
            : ["firmware", "security", "reboot", "deletedLibs", "pacnew", "timesync", "rebuild", "shellHelper", "shellMemory", "shellErrors", "slowBoot", "config"].includes(f.kind) ? "system"
            : "overview";
        GlobalStates.openHealthApp(tab, String(id ?? ""));
    }

    // ── Crash reports ───────────────────────────────────────────────────
    readonly property bool redact: root.opts?.assistant?.redact ?? true

    /// Puts this machine's names back into a command the assistant wrote with the
    /// redacted placeholders. "" when one is left that only the user can fill in
    /// (an address).
    function unredactCommand(text): string {
        let s = String(text ?? "");
        const userName = root.user || String(Quickshell.env("USER") ?? "");
        const host = hostnameFile.text().trim();
        if (userName.length > 0)
            s = s.split("<user>").join(userName);
        if (host.length > 0)
            s = s.split("<host>").join(host);
        return /<(ip|mac|user|host)>/.test(s) ? "" : s;
    }

    /// Replaces what identifies this machine or this person in text that may leave it.
    function redactText(text): string {
        let s = String(text ?? "");
        const home = String(Quickshell.env("HOME") ?? "");
        const userName = root.user || String(Quickshell.env("USER") ?? "");
        const host = hostnameFile.text().trim();
        if (home.length > 1)
            s = s.split(home).join("~");
        if (userName.length > 1)
            s = s.replace(new RegExp(`\\b${userName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "g"), "<user>");
        if (host.length > 1)
            s = s.replace(new RegExp(host.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g"), "<host>");
        s = s.replace(/\b(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b/g, "<mac>");
        s = s.replace(/\b(?:\d{1,3}\.){3}\d{1,3}\b/g, "<ip>");
        s = s.replace(/\b(?:[0-9a-fA-F]{1,4}:){3,7}[0-9a-fA-F]{1,4}\b/g, "<ip>");
        return s;
    }

    FileView {
        id: hostnameFile
        path: "/proc/sys/kernel/hostname"
        printErrors: false
    }

    // ── The system report ───────────────────────────────────────────────
    FileView {
        id: osReleaseFile
        path: "/etc/os-release"
        printErrors: false
    }
    FileView {
        id: forkCommitFile
        // Written by setup: the commit of ii this config was installed from.
        path: FileUtils.trimFileProtocol(Quickshell.shellPath(".active-commit"))
        printErrors: false
    }

    /// Everything System Health knows, as Markdown ready for a bug report: the
    /// system, every open finding, crashes with their top frames, what got fixed,
    /// vitals and hardware. Always redacted, whatever the assistant setting.
    function buildReport(): string {
        const now = Date.now();
        const L = [];
        const os = (osReleaseFile.text().match(/^PRETTY_NAME="?([^"\n]*)"?/m) ?? [])[1] ?? "";
        L.push(`# System Health report, ${Qt.formatDateTime(new Date(now), "yyyy-MM-dd hh:mm")}`);
        L.push("");
        L.push("## System");
        L.push(`- OS: ${os || "unknown"}`);
        L.push(`- Kernel: ${root.system?.kernel?.running ?? "unknown"}`);
        L.push(`- ii: ${forkCommitFile.text().trim().slice(0, 12) || "unknown"}`);
        const qs = Array.from(root.finding("rebuild")?.data?.packages ?? []).find(p => p.reason === "quickshell");
        L.push(`- Quickshell: ${qs ? `built for Qt ${qs.built}, Qt ${qs.installed} installed (needs a rebuild)` : "matches the installed Qt"}`);
        L.push(`- Helper: ${root.running ? "running" : "stopped"}${root.synced ? "" : ", not synced yet"}`);
        L.push("");
        const open = root.findings.filter(f => !root.isSnoozed(f));
        L.push(`## Open findings (${open.length})`);
        if (open.length === 0)
            L.push("None.");
        for (const f of open) {
            const detail = HealthText.detail(f, now);
            L.push(`- **${f.sev}** ${HealthText.title(f)}${detail ? ` — ${detail}` : ""} (for ${HealthText.age(f.since, now) || "now"})`);
        }
        const snoozed = root.snoozedFindings;
        if (snoozed.length > 0) {
            L.push("");
            L.push(`Snoozed: ${snoozed.map(f => HealthText.title(f)).join("; ")}`);
        }
        const crashes = root.crashGroups.filter(g => !g.muted).slice(0, 8);
        if (crashes.length > 0) {
            L.push("");
            L.push("## Crashes, last 7 days");
            for (const g of crashes) {
                L.push(`- ${g.name} ×${g.count}: ${HealthText.signalName(g.signal, g.signalName)}${g.package ? `, ${g.package} ${g.version ?? ""}` : ""}${g.afterUpdate ? `, first after updating ${g.afterUpdate.name}` : ""}`);
                for (const fr of Array.from(g.trace ?? []).slice(0, 3))
                    L.push(`  - \`${fr.fn ?? "?"}\` (${fr.module ?? "?"})`);
            }
        }
        const fixed = root.resolved.slice(-10).reverse();
        if (fixed.length > 0) {
            L.push("");
            L.push("## Fixed recently");
            for (const r of fixed)
                L.push(`- ${HealthText.title(r)}: ${HealthText.age(r.resolvedAt, now)} ago, ${r.by === "self" ? "on its own" : `after ${HealthText.verbLabel(r.by)}`}`);
        }
        L.push("");
        L.push("## Vitals");
        const v = root.vitals;
        const rootFs = Array.from(v?.fs ?? []).find(f => f.mount === "/");
        if (v?.psi?.memory)
            L.push(`- Memory pressure: ${Number(v.psi.memory.some60 ?? 0).toFixed(2)} % (60 s)`);
        if (v?.memory)
            L.push(`- Memory available: ${HealthText.bytes(v.memory.available)} of ${HealthText.bytes(v.memory.total)}`);
        if (rootFs)
            L.push(`- Root disk: ${Math.round(rootFs.usedPct)} % used, ${HealthText.bytes(rootFs.avail)} free`);
        if (v?.cpuTempC)
            L.push(`- CPU: ${Math.round(v.cpuTempC)} °C, throttled ${v.throttle?.total ?? 0} times since boot`);
        if (v?.shellRss)
            L.push(`- Shell memory: ${HealthText.bytes(v.shellRss)}`);
        const boot = root.boots[root.boots.length - 1];
        if (boot)
            L.push(`- Last boot: ${HealthText.seconds(boot.total)} (slowest: ${Array.from(boot.top ?? []).slice(0, 3).map(u => `${u.unit} ${HealthText.seconds(u.ms)}`).join(", ")})`);
        for (const b of Array.from(root.hardware?.batteries ?? []))
            L.push(`- Battery ${b.name}: ${b.healthPct ?? "?"} % of design, ${b.cycles ?? "?"} cycles`);
        for (const g of Array.from(root.hardware?.gpus ?? []))
            L.push(`- GPU: ${g.model || g.vendor} (${g.driver ?? "?"})`);
        L.push("");
        L.push("_User, host and home names, IP and MAC addresses are redacted. No crash dump is included._");
        return root.redactText(L.join("\n"));
    }

    /// Copies the report and saves it to the Downloads folder; `callback(path)`.
    function copyReport(callback): void {
        const text = root.buildReport();
        Quickshell.clipboardText = text;
        const dir = Directories.downloads ? FileUtils.trimFileProtocol(Directories.downloads) : `${Quickshell.env("HOME")}/Downloads`;
        const path = `${dir}/system-health-${Qt.formatDateTime(new Date(), "yyyy-MM-dd-hhmm")}.md`;
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$2")" && printf "%s\\n" "$1" > "$2"', "ii-health-report", text, path]);
        if (callback)
            callback(path);
    }

    function crashGroup(exe): var {
        return root.crashGroups.find(g => g.exe === exe) ?? null;
    }

    /// A Markdown bug report for the newest crash of `exe`, copied to the clipboard.
    /// Built from the journal's stack trace, never from the dump itself.
    function copyCrashReport(exe, callback): void {
        const g = root.crashGroup(exe);
        root.query("crashInfo", { exe: exe }, (ok, data) => {
            const lines = [];
            lines.push(`## ${g?.name ?? exe} crashed (${HealthText.signalName(g?.signal, g?.signalName)})`);
            lines.push("");
            lines.push(`- Program: \`${exe}\``);
            if (g?.package)
                lines.push(`- Package: ${g.package} ${g.version ?? ""}`);
            lines.push(`- Crashes in 7 days: ${g?.count ?? 1}`);
            if (g?.afterUpdate)
                lines.push(`- First crash after updating ${g.afterUpdate.name} ${g.afterUpdate.from ?? ""} → ${g.afterUpdate.to ?? ""}`);
            lines.push(`- Kernel: ${root.system?.kernel?.running ?? ""}`);
            lines.push("");
            lines.push("```");
            const message = ok ? String(data?.message ?? "") : (g?.trace ?? []).map((fr, i) => `#${i} ${fr.fn} (${fr.module})`).join("\n");
            lines.push(message.trim());
            lines.push("```");
            const text = lines.join("\n");
            Quickshell.clipboardText = root.redact ? root.redactText(text) : text;
            if (callback)
                callback(true);
        });
    }

    // ── Crash-dump access ───────────────────────────────────────────────
    property bool accessBusy: false
    property string accessError: ""

    function refreshDumpAccess(): void {
        accessStatus.running = false;
        accessStatus.running = true;
    }

    /// Grants or revokes this account's read access to system crash dumps. pkexec asks
    /// for the password; the result is read back from the ACL, not assumed.
    function setDumpAccess(grant): void {
        if (root.accessBusy)
            return;
        root.accessBusy = true;
        root.accessError = "";
        accessChange.command = ["pkexec", root.accessScript, grant ? "grant" : "revoke", root.user || String(Quickshell.env("USER") ?? "")];
        accessChange.running = true;
    }

    Process {
        id: accessStatus
        command: [root.accessScript, "status", root.user || String(Quickshell.env("USER") ?? "")]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = this.text.trim();
                if (s === "granted" || s === "denied")
                    root.dumpAccess = s;
            }
        }
    }

    Process {
        id: accessChange
        stderr: StdioCollector {
            id: accessChangeErr
        }
        onExited: (code, status) => {
            root.accessBusy = false;
            // 126/127: the password prompt was dismissed or pkexec is missing.
            if (code !== 0)
                root.accessError = code === 126 || code === 127 ? "cancelled" : (accessChangeErr.text.trim() || `exit ${code}`);
            root.refreshDumpAccess();
        }
    }

    // ── The pacman hook (scripts/quickshell-guard/install-hook.sh) ──────
    /// installed | outdated | missing | unsupported, "" while unknown.
    property string qtHookStatus: ""
    property bool qtHookBusy: false
    /// "" | "cancelled" | what install-hook.sh said.
    property string qtHookError: ""

    /// The Overview recommends the hook once the helper runs, the way the setup script
    /// does after its own build — whichever way System Health was installed. Asked
    /// before the dump access: it only reads and warns, so it is the one to say yes to.
    readonly property bool offerQtHook: root.running
        && (root.qtHookStatus === "missing" || root.qtHookStatus === "outdated")
        && !(Persistent.states?.healthApp?.qtHookAsked ?? false)

    function answerQtHookOffer(install): void {
        if (Persistent.states?.healthApp)
            Persistent.states.healthApp.qtHookAsked = true;
        if (install)
            root.setQtHook(true);
    }

    function checkQtHook(): void {
        qtHookCheck.running = false;
        qtHookCheck.running = true;
    }

    /// Installs or removes the hook; pkexec asks for the password, and the status is
    /// read back afterwards, not assumed.
    function setQtHook(install): void {
        if (root.qtHookBusy)
            return;
        root.qtHookBusy = true;
        root.qtHookError = "";
        qtHookChange.command = ["pkexec", `${root.guardDir}/install-hook.sh`, install ? "install" : "remove"];
        qtHookChange.running = true;
    }

    Process {
        id: qtHookCheck
        command: ["bash", `${root.guardDir}/install-hook.sh`, "status"]
        stdout: StdioCollector {
            onStreamFinished: root.qtHookStatus = this.text.trim()
        }
    }

    Process {
        id: qtHookChange
        stderr: StdioCollector {
            id: qtHookChangeErr
        }
        onExited: (code, status) => {
            root.qtHookBusy = false;
            // 126/127: the password prompt was dismissed or pkexec is missing.
            if (code !== 0)
                root.qtHookError = code === 126 || code === 127 ? "cancelled" : (qtHookChangeErr.text.trim() || `exit ${code}`);
            root.checkQtHook();
        }
    }

    // ── Cleanup ─────────────────────────────────────────────────────────
    property string cleaning: ""
    signal cleanupFinished(string what, bool ok)

    /// Frees space: "journal" (archives older than 4 weeks), "pacmanCache" (keep 2
    /// versions), "trash". The privileged ones go through pkexec.
    function cleanup(what): void {
        if (root.cleaning.length > 0)
            return;
        let cmd = null;
        if (what === "journal")
            cmd = ["pkexec", "journalctl", "--vacuum-time=4weeks"];
        else if (what === "pacmanCache")
            cmd = ["pkexec", "paccache", "-rk2"];
        else if (what === "trash")
            cmd = ["gio", "trash", "--empty"];
        if (!cmd)
            return;
        root.cleaning = what;
        cleanupProc.what = what;
        cleanupProc.command = cmd;
        cleanupProc.running = true;
    }

    Process {
        id: cleanupProc
        property string what: ""
        onExited: (code, status) => {
            root.cleaning = "";
            root.cleanupFinished(cleanupProc.what, code === 0);
            root.rescan();
        }
    }

    /// Opens a terminal running `args`, waiting for Enter at the end so the output stays.
    function runInTerminal(args): void {
        const terminal = Config.options?.apps?.terminal || "kitty -1";
        const cmd = terminal.split(" ").filter(part => part.length > 0);
        cmd.push("-e", "bash", "-c", '"$@"; printf "\\n[Press Enter to close] "; read -r', "ii-health", ...args);
        Quickshell.execDetached(cmd);
    }

    /// A terminal on a command that keeps its own window open (asks, then waits).
    function openTerminal(args): void {
        const terminal = Config.options?.apps?.terminal || "kitty -1";
        const cmd = terminal.split(" ").filter(part => part.length > 0);
        cmd.push("-e", ...args);
        Quickshell.execDetached(cmd);
    }

    // ── Process ─────────────────────────────────────────────────────────
    function checkBinary(): void {
        probe.running = false;
        probe.running = true;
    }

    function restart(): void {
        root._restarting = true;
        Qt.callLater(() => root._restarting = false);
    }

    Component.onCompleted: {
        if (root.enabled)
            root.checkBinary();
        root.checkQtHook();
    }
    onEnabledChanged: {
        if (root.enabled)
            root.checkBinary();
    }

    Process {
        id: probe
        command: ["sh", "-c", `[ -x "${root.binaryPath}" ] && echo 1 || echo 0`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.binaryPresent = this.text.trim() === "1";
                root.probed = true;
                root.refreshDumpAccess();
            }
        }
    }

    readonly property var srcOpts: root.opts?.sources ?? null
    readonly property var launchArgs: {
        const names = ["units", "userUnits", "appLaunches", "crashes", "journal", "drives", "filesystems", "firmware", "packages", "pressure", "thermals", "timesync",
            "rebuild", "shell", "boot", "hardware"];
        const on = names.filter(n => root.srcOpts?.[n] ?? true);
        // Off unless asked for: following the shell's log keeps a 50 MB `qs log` running.
        if (root.srcOpts?.shellLog === true)
            on.push("shellLog");
        const noise = root.opts?.noise;
        const th = root.opts?.thresholds;
        return [
            "--state-dir", root.stateDir,
            "--sources", on.join(","),
            "--known-after", String(noise?.knownAfterBoots ?? 3),
            "--of-last", String(noise?.ofLastBoots ?? 5),
            "--quiet-days", String(noise?.quietDaysForNew ?? 14),
            "--disk-warn", String(th?.diskWarnPercent ?? 90),
            "--disk-crit", String(th?.diskCritPercent ?? 97),
            "--psi-mem", String(th?.psiMemPercent ?? 10),
            "--restart-loop", String(th?.restartLoop ?? 5),
            "--history-days", String(root.opts?.historyDays ?? 30),
            "--shell-mem-mb", String(th?.shellMemoryMb ?? 1200),
            "--battery-wear", String(th?.batteryWearPercent ?? 80)
        ];
    }
    readonly property string launchKey: root.launchArgs.join("|")
    onLaunchKeyChanged: {
        if (helper.running)
            root.restart();
    }

    /// Crashes restart it with a growing pause, so a helper that dies on start cannot spin.
    property int _failures: 0
    Timer {
        id: backoff
        onTriggered: root._restarting = false
    }

    Process {
        id: helper
        running: root.enabled && root.probed && root.binaryPresent && !root._restarting
        stdinEnabled: true
        command: [root.binaryPath, ...root.launchArgs]

        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("[Health]", data)
        }

        onRunningChanged: {
            if (helper.running)
                root._callbacks = ({});
        }

        onExited: (code, status) => {
            const wasRunning = root.running;
            root.running = false;
            root.synced = false;
            for (const req in root._callbacks) {
                try {
                    root._callbacks[req](false, null, "exited");
                } catch (e) {}
            }
            root._callbacks = ({});
            if (root._restarting || !root.enabled)
                return;
            if (code !== 0) {
                console.warn(`[Health] helper exited with code ${code}`);
                root._failures = wasRunning ? 1 : root._failures + 1;
                root._restarting = true;
                backoff.interval = Math.min(300000, 2000 * Math.pow(2, Math.min(7, root._failures)));
                backoff.restart();
            }
        }
    }
}
