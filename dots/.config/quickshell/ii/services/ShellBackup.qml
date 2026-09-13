pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * ShellBackup — one zip holding everything the shell knows about a user.
 *
 * Two folders carry every choice made here: `~/.config/illogical-impulse`
 * (settings, presets, profile pictures, extensions) and
 * `~/.local/state/quickshell` (todo, notes, clipboard pins, usage, keybinds).
 * Neither comes back from a reinstall, so losing them is losing the desktop
 * rather than the shell. `scripts/backup/shell_backup.py` packs and unpacks
 * them; everything here is state and sequencing around that one script.
 *
 * Three rules shape this file:
 *
 *  - One job at a time. A restore rewrites the same files a backup reads, and
 *    both touch config.json, so a second call while one runs is refused rather
 *    than raced.
 *  - A restore holds config.json still. Config.qml writes that file on its own
 *    debounce; without the hold, a setting touched moments earlier would be
 *    written back over the restored one the instant it landed. Same guard the
 *    preset store uses, for the same reason.
 *  - Google Drive is not re-implemented here. "Keep a copy in Drive" means the
 *    backup folder joins the set the existing rclone sync already carries, on
 *    its own schedule.
 */
Singleton {
    id: root

    readonly property var options: Persistent.states.shellBackup
    readonly property string script: `${Directories.scriptPath}/backup/shell_backup.py`

    readonly property bool enabled: root.options?.enabled ?? false
    readonly property string folder: String(root.options?.folder ?? "")
    readonly property bool autoDrive: root.options?.autoDrive ?? false
    readonly property int keepCount: root.options?.keepCount ?? 5
    readonly property int intervalDays: root.options?.intervalDays ?? 7
    readonly property string lastBackupTime: String(root.options?.lastBackupTime ?? "")
    readonly property string lastBackupPath: String(root.options?.lastBackupPath ?? "")
    readonly property real lastBackupSizeBytes: Number(root.options?.lastBackupSizeBytes ?? 0)
    // The feature is only actually armed once it knows where to put things.
    readonly property bool configured: root.enabled && root.folder !== ""

    property bool busy: false
    property string busyAction: ""
    property string lastError: ""
    // Rows from `list`: { path, name, sizeBytes, mtime, valid, createdAt,
    // fileCount, host }
    property var backups: []

    signal createFinished(bool ok, string path, string error)
    signal restoreFinished(bool ok, string error)
    signal inspectFinished(bool ok, var manifest, string error)
    signal listRefreshed

    // ── Public API ───────────────────────────────────────────────────────────

    function refresh() {
        if (root.folder === "" || root.busy)
            return;
        root._run("list", ["list", "--dest", root.folder]);
    }

    function createBackup() {
        if (root.folder === "" || root.busy)
            return;
        root._run("create", ["create", "--dest", root.folder,
            "--keep", String(Math.max(0, root.keepCount))]);
    }

    // `archive` is any zip on disk - one this made, or one carried in from
    // another machine. The script refuses anything without our manifest.
    function inspectArchive(archive) {
        if (!archive || root.busy)
            return;
        root._run("inspect", ["inspect", "--archive", String(archive)]);
    }

    function restoreArchive(archive) {
        if (!archive || root.busy)
            return;
        root._holdConfigWrites();
        // The safety copy lands in the backup folder when there is one. A
        // restore run from the Welcome on a fresh machine has nowhere to put
        // one and nothing worth keeping, and says so by passing no folder.
        let args = ["restore", "--archive", String(archive)];
        if (root.folder !== "")
            args = args.concat(["--safety-dest", root.folder]);
        root._run("restore", args);
    }

    function humanSize(bytes) {
        const value = Number(bytes || 0);
        if (value <= 0)
            return "";
        const units = ["B", "KB", "MB", "GB"];
        let index = 0;
        let scaled = value;
        while (scaled >= 1024 && index < units.length - 1) {
            scaled /= 1024;
            index++;
        }
        return `${scaled < 10 && index > 0 ? scaled.toFixed(1) : Math.round(scaled)} ${units[index]}`;
    }

    // ── Google Drive, without a second uploader ──────────────────────────────
    // The Drive sync already walks a list of folders on a schedule. Turning
    // this on adds the backup folder to that list; turning it off takes it
    // back out, and never touches a folder the user put there themselves.
    function syncDriveFolder() {
        const drive = Persistent.states.googleDrive;
        if (!drive)
            return;
        const current = Array.from(drive.backupFolders ?? []);
        const wanted = root.folder;
        const has = wanted !== "" && current.indexOf(wanted) !== -1;
        if (root.autoDrive && root.enabled && wanted !== "" && !has) {
            drive.backupFolders = current.concat([wanted]);
            return;
        }
        if ((!root.autoDrive || !root.enabled) && has)
            drive.backupFolders = current.filter(entry => entry !== wanted);
    }

    onAutoDriveChanged: root.syncDriveFolder()
    onEnabledChanged: root.syncDriveFolder()
    onFolderChanged: {
        root.backups = [];
        root.syncDriveFolder();
        root.refresh();
    }

    // ── The automatic one ────────────────────────────────────────────────────
    // Not a clock: the shell is not always running, and a backup that only
    // happens if the machine is awake at 3am is a backup that never happens.
    // It asks once, a little after startup, whether the last one is older than
    // the interval - which is also true after a week of the machine being off.
    readonly property real _dayMs: 24 * 60 * 60 * 1000

    function _dueForBackup() {
        if (!root.configured)
            return false;
        if (root.lastBackupTime === "")
            return true;
        const last = Date.parse(root.lastBackupTime);
        if (isNaN(last))
            return true;
        return Date.now() - last >= Math.max(1, root.intervalDays) * root._dayMs;
    }

    Timer {
        id: startupCheck
        interval: 45000
        repeat: false
        running: Persistent.ready && root.configured
        onTriggered: {
            if (root._dueForBackup())
                root.createBackup();
        }
    }

    // ── Holding config.json still across a restore ───────────────────────────

    property bool _holding: false

    function _holdConfigWrites() {
        configResume.stop();
        root._holding = true;
        Config.saveOptionsNow();
        Config.blockWrites = true;
        Persistent.blockWrites = true;
        // The file about to appear was written against whichever schema the
        // backup was taken from, so the one-shot migration pass is re-armed.
        Config.configRepaired = false;
    }

    Timer {
        id: configResume
        // Long enough for both file watchers to notice the new bytes and
        // reload before anything is allowed to write over them again.
        interval: 1200
        repeat: false
        onTriggered: {
            root._holding = false;
            Persistent.blockWrites = false;
            if (!Config.configMalformed)
                Config.blockWrites = false;
        }
    }

    // ── The one worker ───────────────────────────────────────────────────────

    function _run(action, args) {
        root.busy = true;
        root.busyAction = action;
        root.lastError = "";
        runner.action = action;
        runner.collected = "";
        runner.errorText = "";
        runner.running = false;
        runner.command = ["python3", root.script].concat(args);
        runner.running = true;
    }

    function _parse(text) {
        const trimmed = String(text ?? "").trim();
        if (trimmed === "")
            return null;
        // The script prints one JSON line, but a stray warning from Python
        // could precede it, so the LAST parsable line wins.
        const lines = trimmed.split("\n");
        for (let i = lines.length - 1; i >= 0; i--) {
            try {
                return JSON.parse(lines[i]);
            } catch (e) {
                continue;
            }
        }
        return null;
    }

    Process {
        id: runner
        property string action: ""
        property string collected: ""
        property string errorText: ""

        stdout: StdioCollector {
            onStreamFinished: runner.collected = text
        }
        stderr: StdioCollector {
            onStreamFinished: runner.errorText = text
        }

        onExited: exitCode => {
            const action = runner.action;
            let payload = root._parse(runner.collected);
            if (!payload) {
                const stderrLine = runner.errorText.trim().split("\n").pop();
                payload = {
                    "ok": false,
                    "error": stderrLine.length > 0 ? stderrLine
                        : Translation.tr("The backup script did not answer.")
                };
            }
            root.busy = false;
            root.busyAction = "";
            const ok = payload.ok === true;
            const error = ok ? "" : String(payload.error ?? "");
            if (!ok && action !== "list")
                root.lastError = error;

            if (action === "list") {
                root.backups = ok ? (payload.backups ?? []) : [];
                root.listRefreshed();
                return;
            }
            if (action === "create") {
                if (ok) {
                    root.options.lastBackupTime = String(payload.createdAt ?? "");
                    root.options.lastBackupPath = String(payload.path ?? "");
                    root.options.lastBackupSizeBytes = Number(payload.sizeBytes ?? 0);
                }
                root.createFinished(ok, ok ? String(payload.path ?? "") : "", error);
                root.refresh();
                return;
            }
            if (action === "inspect") {
                root.inspectFinished(ok, ok ? payload.manifest : null, error);
                return;
            }
            if (action === "restore") {
                // Release even on failure: the hold exists for the window in
                // which the files change, and that window is over either way.
                configResume.restart();
                root.restoreFinished(ok, error);
                return;
            }
        }
    }
}
