pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * PresetStore — the shell's side of the community preset store.
 *
 * Every call goes through `scripts/preset_store.py`, which answers with one
 * JSON line and never raises, so nothing here has to parse git or gh output.
 *
 * Two rules shape this file:
 *
 *  - One job at a time. Two git operations on the same clone at once corrupt
 *    it, and a preset install rewrites the same folder an apply reads from, so
 *    everything queues behind a single process rather than racing.
 *  - The presets folder is the only store of record. An installed preset is a
 *    normal preset on disk; what lives here is which repository it came from
 *    and whether an update is waiting.
 */
Singleton {
    id: root

    // ── Public state ─────────────────────────────────────────────────────────

    // Rows from `preset_store.py links`: { name, repo, repoUrl, version,
    // configVersion, owned, installedAt, updatedAt, present, installed }
    property var installed: []
    readonly property var published: root.installed.filter(entry => entry.owned)

    // Rows from `check-updates`: { name, repo, commits, installedVersion,
    // availableVersion, compatibility, changelog, owned }
    property var updates: []
    property var updateProblems: []
    readonly property int updateCount: root.updates.length

    // Rows from `discover`: { repo, name, description, author, avatarUrl,
    // stars, repoUrl, updatedAt, defaultBranch, installedAs }
    property var discoverResults: []
    property bool discovering: false
    property string discoverError: ""

    // From `auth status`. `authenticated` is what gates publishing.
    property var auth: ({
            hasGh: false,
            authenticated: false,
            login: "",
            scopes: [],
            missingScopes: [],
            hint: ""
        })

    // The preset the running config came from, written by presets.sh on apply.
    // Empty after a revert, or when the settings were never a preset.
    property string activePreset: ""

    property bool ready: false
    property bool busy: false
    property string busyAction: ""
    property string busyName: ""
    property string lastError: ""

    // ── Signals ──────────────────────────────────────────────────────────────

    signal installedRefreshed
    signal presetFilesChanged           // the presets folder was rewritten
    signal discoverFinished
    signal manifestReady(string repo, var result)
    signal installFinished(string name, bool ok, string error)
    signal updatesChecked(int count)
    signal pullFinished(string name, bool ok, bool changed, string error)
    signal diffReady(string name, var result)
    signal publishFinished(string name, bool ok, string repoUrl, string error)
    signal pushFinished(string name, bool ok, bool changed, string error)
    signal removeFinished(string name, bool ok, string error)
    signal applyFinished(string name, bool ok)
    signal revertFinished(bool ok)
    signal authRefreshed
    signal loginCodeReady(string userCode, string verificationUri, int expiresIn)
    signal loginFinished(bool ok, string login, string error)
    // The device flow needs an OAuth app this build may not carry. Rather than
    // failing silently, the command that does work is handed back.
    signal loginUnavailable(string command, string reason)

    // ── Paths ────────────────────────────────────────────────────────────────

    readonly property string storeScript: `${Directories.scriptPath}/preset_store.py`
    readonly property string presetsScript: `${Directories.scriptPath}/presets.sh`
    readonly property string presetsFolder: FileUtils.trimFileProtocol(
        `${Directories.config}/illogical-impulse/presets`)

    // ── Public API ───────────────────────────────────────────────────────────

    function refresh() {
        root._run("links", "", ["links"]);
    }

    // Called by every page that shows the store, so the first one pays for the
    // read and startup pays for nothing.
    function ensureLoaded() {
        if (root.ready || root._pending("links", ""))
            return;
        root.refresh();
    }

    function refreshAuth() {
        root._run("auth", "", ["auth", "status"]);
    }

    function discover(query, limit) {
        if (root._pending("discover", ""))
            return;
        root.discovering = true;
        root.discoverError = "";
        let args = ["discover", "--limit", String(limit && limit > 0 ? limit : 30)];
        if (query && query.trim().length > 0)
            args = args.concat(["--query", query.trim()]);
        root._run("discover", "", args);
    }

    function fetchManifest(repo) {
        if (!repo)
            return;
        root._run("fetch-manifest", repo, ["fetch-manifest", repo]);
    }

    function install(repo, name, force) {
        if (!repo || root._pending("install", repo))
            return;
        let args = ["install", repo];
        if (name && name.length > 0)
            args = args.concat(["--name", name]);
        if (force)
            args.push("--force");
        root._run("install", repo, args);
    }

    // Checking every preset means a fetch each, so a page that opens twice in a
    // minute reuses the answer unless the refresh was asked for.
    function checkUpdates(force) {
        if (root._pending("check-updates", ""))
            return;
        if (!force && root._lastUpdateCheck > 0 && Date.now() - root._lastUpdateCheck < root._updateInterval)
            return;
        root._run("check-updates", "", ["check-updates"]);
    }

    function pull(name, force) {
        if (!name || root._pending("pull", name))
            return;
        let args = ["pull", name];
        if (force)
            args.push("--force");
        root._run("pull", name, args);
    }

    // incoming: what an update would change. Otherwise: what publishing would.
    function diff(name, incoming) {
        if (!name)
            return;
        let args = ["diff", name];
        if (incoming)
            args.push("--incoming");
        root._run("diff", name, args);
    }

    // screenshots is a list of file paths. Passing none at all leaves the
    // pictures a preset already ships alone, which is what an update that only
    // changed settings wants.
    function publish(name, repoName, description, notes, isPrivate, screenshots) {
        if (!name || root._pending("publish", name))
            return;
        let args = ["publish", name];
        if (repoName && repoName.length > 0)
            args = args.concat(["--repo", repoName]);
        if (description && description.length > 0)
            args = args.concat(["--description", description]);
        if (notes && notes.length > 0)
            args = args.concat(["--notes", notes]);
        if (isPrivate)
            args.push("--private");
        args = args.concat(root._screenshotArgs(screenshots));
        root._run("publish", name, args);
    }

    // bump is "major" | "minor" | "patch"; an explicit version wins over it.
    function pushUpdate(name, bump, notes, version, screenshots) {
        if (!name || root._pending("push-update", name))
            return;
        let args = ["push-update", name];
        if (version && version.length > 0)
            args = args.concat(["--version", version]);
        else if (bump && bump.length > 0)
            args = args.concat(["--bump", bump]);
        if (notes && notes.length > 0)
            args = args.concat(["--notes", notes]);
        args = args.concat(root._screenshotArgs(screenshots));
        root._run("push-update", name, args);
    }

    function _screenshotArgs(screenshots) {
        if (!screenshots)
            return [];
        let args = [];
        for (let i = 0; i < screenshots.length; i++) {
            if (screenshots[i] && String(screenshots[i]).length > 0)
                args = args.concat(["--screenshot", String(screenshots[i])]);
        }
        // The flag carrying no value is how "ship none" is spelled, and it is
        // the only way to tell it apart from not touching them at all.
        return args.length > 0 ? args : ["--screenshot"];
    }

    // Forgets where a preset came from but keeps the preset itself.
    function unlink(name) {
        if (!name || root._pending("unlink", name))
            return;
        root._run("unlink", name, ["unlink", name]);
    }

    function uninstall(name) {
        if (!name || root._pending("uninstall", name))
            return;
        root._run("uninstall", name, ["uninstall", name]);
    }

    // Apply and revert queue with the rest on purpose: applying a preset reads
    // the same files an install or a pull rewrites.
    function applyPreset(name) {
        if (!name || root._pending("apply", name))
            return;
        root._enqueue({
            action: "apply",
            name: name,
            json: false,
            guardsConfig: true,
            command: [root.presetsScript, "load", name]
        });
    }

    function revert() {
        if (root._pending("revert", ""))
            return;
        root._enqueue({
            action: "revert",
            name: "",
            json: false,
            guardsConfig: true,
            command: [root.presetsScript, "revert"]
        });
    }

    function login() {
        if (root.loggingIn)
            return;
        root.loggingIn = true;
        root._loginReported = false;
        loginProc.running = false;
        loginProc.running = true;
    }

    function cancelLogin() {
        if (!root.loggingIn)
            return;
        root._loginReported = true;
        root.loggingIn = false;
        loginProc.running = false;
    }

    property bool loggingIn: false

    // ── Lookups for the UI ───────────────────────────────────────────────────

    function linkFor(name) {
        for (let i = 0; i < root.installed.length; i++) {
            if (root.installed[i].name === name)
                return root.installed[i];
        }
        return null;
    }

    function updateFor(name) {
        for (let i = 0; i < root.updates.length; i++) {
            if (root.updates[i].name === name)
                return root.updates[i];
        }
        return null;
    }

    function isFromStore(name) {
        return root.linkFor(name) !== null;
    }

    function isOwned(name) {
        let link = root.linkFor(name);
        return link !== null && link.owned === true;
    }

    // True while anything is queued or running for this preset, so a card can
    // grey its own buttons without freezing the rest of the list.
    function busyFor(name) {
        if (root.busy && root.busyName === name)
            return true;
        for (let i = 0; i < root._queue.length; i++) {
            if (root._queue[i].name === name)
                return true;
        }
        return false;
    }

    // ── Job queue ────────────────────────────────────────────────────────────

    property var _queue: []
    property var _current: null
    property real _lastUpdateCheck: 0
    readonly property int _updateInterval: 30 * 60 * 1000
    // A backstop only. Every command already carries its own timeout; this is
    // for the case where the process never reports at all, which would
    // otherwise wedge the queue for the rest of the session.
    readonly property int _watchdogInterval: 300000

    function _run(action, name, args) {
        root._enqueue({
            action: action,
            name: name,
            json: true,
            command: ["python3", root.storeScript].concat(args)
        });
    }

    function _enqueue(job) {
        root._queue = root._queue.concat([job]);
        root._pump();
    }

    function _pending(action, name) {
        if (root._current && root._current.action === action && root._current.name === name)
            return true;
        for (let i = 0; i < root._queue.length; i++) {
            if (root._queue[i].action === action && root._queue[i].name === name)
                return true;
        }
        return false;
    }

    function _pump() {
        if (root._current || root._queue.length === 0)
            return;
        let job = root._queue[0];
        root._queue = root._queue.slice(1);
        root._current = job;
        root.busy = true;
        root.busyAction = job.action;
        root.busyName = job.name;

        runner.sawExit = false;
        runner.sawOutput = false;
        runner.collected = "";
        runner.errorText = "";
        runner.exitCode = -1;
        runner.command = job.command;
        if (!job.guardsConfig) {
            root._startRunner();
            return;
        }
        // The script about to run reads config.json and writes it back. A
        // write the shell still owes that file has to be on disk before it is
        // read, and nothing more may be written until the result has landed.
        root._holdConfigWrites();
        configFlush.restart();
    }

    function _startRunner() {
        runner.running = false;
        runner.running = true;
        watchdog.restart();
    }

    // Python prints exactly one JSON line, but a stray warning from the
    // interpreter would come first, so the last line that parses wins.
    function _parse(text) {
        let lines = String(text).split("\n");
        for (let i = lines.length - 1; i >= 0; i--) {
            let line = lines[i].trim();
            if (line.length === 0)
                continue;
            try {
                return JSON.parse(line);
            } catch (e) {}
        }
        return null;
    }

    function _finish(payload) {
        let job = root._current;
        root._current = null;
        root.busy = false;
        root.busyAction = "";
        root.busyName = "";
        watchdog.stop();
        configFlush.stop();
        if (job && job.guardsConfig)
            root._releaseConfigWrites();
        if (job)
            root._dispatch(job, payload);
        root._pump();
    }

    function _dispatch(job, payload) {
        let result = payload || {
            ok: false,
            error: Translation.tr("The preset store did not answer.")
        };
        let ok = result.ok === true;
        let error = ok ? "" : (result.error || Translation.tr("Something went wrong."));
        if (!ok && job.action !== "discover")
            root.lastError = error;

        if (job.action === "links") {
            root.installed = ok ? (result.links || []) : [];
            root.ready = true;
            root.installedRefreshed();
            return;
        }
        if (job.action === "auth") {
            if (ok)
                root.auth = result;
            root.authRefreshed();
            return;
        }
        if (job.action === "discover") {
            root.discovering = false;
            root.discoverResults = ok ? (result.results || []) : [];
            root.discoverError = error;
            root.discoverFinished();
            return;
        }
        if (job.action === "fetch-manifest") {
            root.manifestReady(job.name, result);
            return;
        }
        if (job.action === "install") {
            if (ok) {
                root.presetFilesChanged();
                root.refresh();
            }
            // The store lists repositories, so the name a preset landed under
            // is only known once it is installed.
            root.installFinished(ok ? (result.name || "") : job.name, ok, error);
            return;
        }
        if (job.action === "check-updates") {
            if (ok) {
                root.updates = result.updates || [];
                root.updateProblems = result.problems || [];
                root._lastUpdateCheck = Date.now();
            }
            root.updatesChecked(ok ? root.updates.length : 0);
            return;
        }
        if (job.action === "pull") {
            if (ok) {
                root._dropUpdate(job.name);
                root.presetFilesChanged();
                root.refresh();
            }
            root.pullFinished(job.name, ok, ok && result.changed === true, error);
            return;
        }
        if (job.action === "diff") {
            root.diffReady(job.name, result);
            return;
        }
        if (job.action === "publish") {
            if (ok)
                root.refresh();
            root.publishFinished(job.name, ok, ok ? (result.repoUrl || "") : "", error);
            return;
        }
        if (job.action === "push-update") {
            if (ok)
                root.refresh();
            root.pushFinished(job.name, ok, ok && result.changed === true, error);
            return;
        }
        if (job.action === "unlink" || job.action === "uninstall") {
            if (ok) {
                root._dropUpdate(job.name);
                if (job.action === "uninstall")
                    root.presetFilesChanged();
                root.refresh();
            }
            root.removeFinished(job.name, ok, error);
            return;
        }
        if (job.action === "apply") {
            // presets.sh writes the marker itself; re-reading it is what makes
            // activePreset true rather than assumed.
            activeFile.reload();
            root.applyFinished(job.name, ok);
            return;
        }
        if (job.action === "revert") {
            activeFile.reload();
            root.revertFinished(ok);
            return;
        }
    }

    function _dropUpdate(name) {
        root.updates = root.updates.filter(entry => entry.name !== name);
    }

    // ── Holding the config still ─────────────────────────────────────────────
    //
    // Config.qml writes config.json on a short debounce of its own. Applying a
    // preset rewrites that same file from a script, so without this a setting
    // touched moments earlier would be written back over the preset the
    // instant it landed.

    readonly property int _configFlushDelay: 150
    readonly property int _configResumeDelay: 600

    function _holdConfigWrites() {
        configResume.stop();
        Config.saveOptionsNow();
        Config.blockWrites = true;
        // The file about to appear was written against whichever schema the
        // preset was exported from, and the shell only migrates a file it
        // reads once per session. Re-arming that pass is what makes "migrate
        // up" true for a preset applied hours after startup, rather than only
        // at the next restart.
        Config.configRepaired = false;
    }

    function _releaseConfigWrites() {
        configResume.restart();
    }

    Timer {
        id: configFlush
        interval: root._configFlushDelay
        repeat: false
        onTriggered: root._startRunner()
    }

    Timer {
        id: configResume
        interval: root._configResumeDelay
        repeat: false
        onTriggered: {
            // A config the shell is refusing to write for its own reasons — a
            // broken file it is preserving — stays blocked. This lifts only
            // the hold that was put on here.
            if (!Config.configMalformed)
                Config.blockWrites = false;
        }
    }

    // ── The one worker ───────────────────────────────────────────────────────

    Process {
        id: runner
        property bool sawExit: false
        property bool sawOutput: false
        property string collected: ""
        property string errorText: ""
        property int exitCode: -1

        // Exit and end-of-output are two separate events and neither is
        // reliably last, so the job is only finished once both have landed.
        function settle() {
            if (!runner.sawExit || !runner.sawOutput)
                return;
            let payload = root._parse(runner.collected);
            if (!payload && runner.exitCode !== 0) {
                let stderrLine = runner.errorText.trim().split("\n").pop();
                if (stderrLine.length === 0)
                    stderrLine = Translation.tr("The preset store did not answer.");
                payload = {
                    ok: false,
                    error: stderrLine
                };
            }
            if (!payload && root._current && root._current.json !== true)
                payload = {
                    ok: runner.exitCode === 0
                };
            root._finish(payload);
        }

        stdout: StdioCollector {
            onStreamFinished: {
                runner.collected = text;
                runner.sawOutput = true;
                runner.settle();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: runner.errorText = text
        }

        onExited: (code, status) => {
            runner.exitCode = code;
            runner.sawExit = true;
            runner.settle();
        }
    }

    Timer {
        id: watchdog
        interval: root._watchdogInterval
        repeat: false
        onTriggered: {
            if (!root._current)
                return;
            runner.running = false;
            root._finish({
                ok: false,
                error: Translation.tr("This took too long and was stopped.")
            });
        }
    }

    // ── Signing in ───────────────────────────────────────────────────────────
    //
    // Its own process: the device flow streams a line as soon as the code is
    // ready and then waits minutes for it to be entered, which is exactly what
    // the queue must not be blocked on.

    property bool _loginReported: false

    Process {
        id: loginProc
        command: ["python3", root.storeScript, "auth", "login"]

        stdout: SplitParser {
            // One read can carry several lines glued together, so every chunk
            // is split again rather than parsed whole.
            onRead: data => {
                let lines = String(data).split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line.length === 0)
                        continue;
                    try {
                        root._loginEvent(JSON.parse(line));
                    } catch (e) {}
                }
            }
        }

        onExited: {
            root.loggingIn = false;
            if (root._loginReported)
                return;
            root._loginReported = true;
            root.loginFinished(false, "", Translation.tr("Signing in ended without an answer."));
        }
    }

    function _loginEvent(event) {
        if (event.event === "code") {
            root.loginCodeReady(event.userCode || "", event.verificationUri || "", event.expiresIn || 900);
            return;
        }
        if (event.event === "unavailable") {
            root._loginReported = true;
            root.loginUnavailable(event.command || "gh auth login --scopes repo", event.error || "");
            return;
        }
        if (event.event === "done") {
            root._loginReported = true;
            root.refreshAuth();
            root.loginFinished(true, event.login || "", "");
            return;
        }
        if (event.event === "error") {
            root._loginReported = true;
            root.loginFinished(false, "", event.error || Translation.tr("Signing in failed."));
        }
    }

    // ── Which preset is in use ───────────────────────────────────────────────

    FileView {
        id: activeFile
        path: `${root.presetsFolder}/.active`
        watchChanges: true
        onLoaded: root.activePreset = text().trim()
        // No marker means no preset is in use, which is the normal state on a
        // fresh install and after a revert.
        onLoadFailed: root.activePreset = ""
        onFileChanged: activeFile.reload()
    }

    Component.onCompleted: activeFile.reload()

    IpcHandler {
        target: "presetStore"

        function refresh(): void {
            root.refresh();
        }
        function updates(): string {
            root.checkUpdates(true);
            return "checking";
        }
        function apply(name: string): void {
            root.applyPreset(name);
        }
        function revert(): void {
            root.revert();
        }
        function active(): string {
            return root.activePreset;
        }
    }
}
