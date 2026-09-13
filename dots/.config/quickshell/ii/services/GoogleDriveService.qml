pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Google Drive backup service.
 *
 * The UI only changes explicit Config.options.googleDrive values. All rclone
 * work is delegated to scripts/gdrive so the shell remains responsive and the
 * command-line surface can be tested independently.
 */
Singleton {
    id: root

    readonly property var options: Persistent.ready ? Persistent.states.googleDrive : Config.options.googleDrive
    readonly property string scriptRoot: Quickshell.shellPath("scripts/gdrive")
    readonly property string notificationIconPath: Quickshell.shellPath("assets/icons/google_drive.png")
    readonly property string defaultDriveBasePath: root._safePathPart(SystemInfo.username, "user")
        + "_" + root._safePathPart(SystemInfo.distroId, "linux") + "_backups"
    readonly property string effectiveDriveBasePath: {
        const configuredPath = String(options.driveBasePath || "").trim();
        return configuredPath === "" || configuredPath === "ii-backup"
            ? root.defaultDriveBasePath
            : configuredPath;
    }

    property bool rcloneInstalled: false
    property bool configured: false
    property bool syncing: false
    property bool setupRunning: false
    property bool setupPendingCheck: false
    property bool checking: false
    property bool meteredConnection: false
    property bool networkWasConnected: false
    property bool bootHandled: false
    property bool bootSyncPending: false
    property bool cancelRequested: false
    property real progress: 0.0
    property string currentFile: ""
    property string currentFolder: ""
    property string statsLine: ""
    property int syncElapsedSeconds: 0
    property real syncStartedAtMs: 0
    property int currentFolderFiles: 0
    property int currentFolderTotalFiles: 0
    property real currentFolderBytes: 0.0
    property real currentFolderTotalBytes: 0.0
    property int filesTransferred: 0
    property int filesTotal: 0
    property real bytesTransferred: 0.0
    property real bytesTotal: 0.0
    property string errorMessage: ""
    property string warningMessage: ""
    property bool finalizing: false
    property real driveUsedMb: 0.0
    property real driveQuotaMb: 0.0
    property real driveBackupUsageMb: 0.0
    property list<var> syncHistory: []

    readonly property bool networkConnected: Network.ethernet || Network.wifiStatus === "connected"
    readonly property string statusText: root.syncing
        ? Translation.tr("Syncing")
        : root.errorMessage !== ""
            ? root.errorMessage
            : root.configured
                ? Translation.tr("Connected")
                : Translation.tr("Setup required")

    function _safePathPart(value: string, fallback: string): string {
        const cleaned = String(value || "").trim().toLowerCase()
            .replace(/[^a-z0-9._-]+/g, "_")
            .replace(/^[_\-.]+|[_\-.]+$/g, "");
        return cleaned && cleaned !== "unknown" ? cleaned : fallback;
    }

    function intervalFor(value: string): int {
        const intervals = ({
            "1h": 3600000,
            "4h": 14400000,
            "1d": 86400000,
            "2d": 172800000,
            "3d": 259200000
        });
        return intervals[value] || intervals["3d"];
    }

    function normalizedInterval(value: string): string {
        const migrations = ({
            "24h": "1d",
            "48h": "2d",
            "72h": "3d"
        });
        const candidate = migrations[value] || value;
        return ["1h", "4h", "1d", "2d", "3d"].indexOf(candidate) >= 0
            ? candidate
            : "3d";
    }

    function parseEnv(text: string): var {
        const values = ({ "GOOGLE_CLIENT_ID": "", "GOOGLE_CLIENT_SECRET": "", "GMAIL_CLIENT_ID": "", "GMAIL_CLIENT_SECRET": "" });
        for (const rawLine of String(text || "").split(/\r?\n/)) {
            const line = rawLine.trim();
            if (!line || line.startsWith("#"))
                continue;
            const separator = line.indexOf("=");
            if (separator < 0)
                continue;
            const key = line.substring(0, separator).trim();
            if (values[key] !== undefined)
                values[key] = line.substring(separator + 1).trim();
        }
        return {
            "clientId": values.GOOGLE_CLIENT_ID || values.GMAIL_CLIENT_ID || "",
            "clientSecret": values.GOOGLE_CLIENT_SECRET || values.GMAIL_CLIENT_SECRET || ""
        };
    }

    function checkRclone(): void {
        if (checkProcess.running)
            return;
        root.checking = true;
        checkProcess.running = true;
    }

    function initializeAfterConfig(): void {
        if (!Config.ready || !Persistent.ready || root.bootHandled)
            return;
        const storedHistory = options.syncHistory || [];
        root.syncHistory = storedHistory.slice().filter(entry => entry && entry.time);
        root.driveUsedMb = Math.max(0, Number(options.totalDriveUsageMb || 0));
        root.driveQuotaMb = Math.max(0, Number(options.driveQuotaMb || 0));
        root.driveBackupUsageMb = Math.max(0, Number(options.driveBackupUsageMb || 0));
        const normalizedSyncInterval = root.normalizedInterval(String(options.syncInterval || ""));
        if (options.syncInterval !== normalizedSyncInterval)
            options.syncInterval = normalizedSyncInterval;
        root.bootHandled = true;
        root.bootSyncPending = options.enabled && options.syncOnBoot && root.shouldRunBootSync();
        root.checkRclone();
        root.networkWasConnected = root.networkConnected;
        root.checkMetered();
    }

    function shouldRunBootSync(): bool {
        const lastSyncAt = Date.parse(String(options.lastSyncTime || ""));
        if (options.lastSyncStatus === "running") {
            if (!isFinite(lastSyncAt))
                return true;
            return Date.now() - lastSyncAt > 30 * 60 * 1000;
        }
        if (!isFinite(lastSyncAt))
            return true;
        return Date.now() - lastSyncAt >= root.intervalFor(String(options.syncInterval || ""));
    }

    // Timer instances can be recreated by a shell hot-reload. Guard the
    // automatic path with the persisted completion time so a restart cannot
    // turn a multi-day schedule into an immediate second upload.
    function shouldRunScheduledSync(): bool {
        if (!Config.ready || !Persistent.ready || !options.enabled || !root.configured || root.syncing)
            return false;
        const lastSyncAt = Date.parse(String(options.lastSyncTime || ""));
        if (!isFinite(lastSyncAt))
            return true;
        return Date.now() - lastSyncAt >= root.intervalFor(String(options.syncInterval || ""));
    }

    function startScheduledSync(): void {
        if (root.shouldRunScheduledSync())
            root.startSync();
    }

    function rcloneMissingMessage(): string {
        return Translation.tr("rclone is required for Google Drive authorization. Install rclone, then try again.");
    }

    function _beginSetup(): void {
        root.setupRunning = true;
        root.errorMessage = "";
        envProcess.running = true;
    }

    function setupRclone(): void {
        if (root.setupRunning || root.setupPendingCheck)
            return;
        root.errorMessage = "";
        if (checkProcess.running) {
            root.setupPendingCheck = true;
            return;
        }
        if (!root.rcloneInstalled) {
            root.setupPendingCheck = true;
            root.checkRclone();
            return;
        }
        root._beginSetup();
    }

    function _startSetup(envText: string): void {
        const env = root.parseEnv(envText);
        if (!env.clientId || !env.clientSecret) {
            root.setupRunning = false;
            root.errorMessage = Translation.tr("Google OAuth credentials were not found in .env (GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET)");
            return;
        }
        setupProcess.command = [
            "python3",
            root.scriptRoot + "/setup_rclone.py",
            env.clientId,
            env.clientSecret
        ];
        setupProcess.running = true;
    }

    function _setSyncConfig(status: string, time: string, fileCount: int, sizeMb: real): void {
        if (Persistent.ready) {
            const drive = Persistent.states.googleDrive;
            drive.lastSyncStatus = status;
            drive.lastSyncTime = time;
            drive.lastSyncFileCount = fileCount;
            drive.lastSyncSizeMb = sizeMb;
        }
        if (Config.ready) {
            const drive = Config.options.googleDrive;
            drive.lastSyncStatus = status;
            drive.lastSyncTime = time;
            drive.lastSyncFileCount = fileCount;
            drive.lastSyncSizeMb = sizeMb;
        }
    }

    function _notify(title: string, body: string, icon: string): void {
        const notify = title === Translation.tr("Google Drive backup complete")
            ? options.notifyOnComplete
            : options.notifyOnError;
        if (notify)
            Quickshell.execDetached(["notify-send", "-a", "Google Drive Backup", "-i", icon, title, body]);
    }

    function _unitBytes(value: string, unit: string): real {
        const amount = Number(String(value || "0").replace(",", "."));
        const multipliers = ({
            "B": 1,
            "KiB": 1024,
            "MiB": 1024 * 1024,
            "GiB": 1024 * 1024 * 1024,
            "TiB": 1024 * 1024 * 1024 * 1024
        });
        return amount * (multipliers[unit] || 1);
    }

    function _handleStatsLine(line: string): void {
        const stats = String(line || "").replace(/\s+/g, " ").trim();
        if (!stats)
            return;
        root.statsLine = stats;

        const percentages = stats.match(/[0-9]{1,3}%/g);
        if (percentages && percentages.length > 0) {
            const percent = Number(percentages[percentages.length - 1].replace("%", ""));
            root.progress = Math.max(0, Math.min(1, percent / 100));
        }

        const transfer = stats.match(/([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)\s*\/\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)/);
        if (transfer) {
            root.currentFolderBytes = root._unitBytes(transfer[1], transfer[2]);
            root.currentFolderTotalBytes = root._unitBytes(transfer[3], transfer[4]);
            root.bytesTransferred = Math.max(root.bytesTransferred, root.currentFolderBytes);
            root.bytesTotal = Math.max(root.bytesTotal, root.currentFolderTotalBytes);
        }

        const files = stats.match(/\(xfr#([0-9]+)\/([0-9]+)\)/);
        if (files) {
            root.currentFolderFiles = Number(files[1]) || 0;
            root.currentFolderTotalFiles = Number(files[2]) || 0;
            root.filesTransferred = Math.max(root.filesTransferred, root.currentFolderFiles);
            root.filesTotal = Math.max(root.filesTotal, root.currentFolderTotalFiles);
        }
    }

    function startSync(): void {
        if (root.syncing || !Config.ready || !Persistent.ready)
            return;
        if (!root.rcloneInstalled) {
            root.errorMessage = Translation.tr("rclone is not installed");
            return;
        }
        if (!root.configured) {
            root.errorMessage = Translation.tr("Authorize Google Drive before syncing");
            return;
        }
        if (!root.networkConnected) {
            root.errorMessage = Translation.tr("No network connection");
            return;
        }
        if (root.meteredConnection && options.pauseOnMeteredConnection) {
            root.errorMessage = Translation.tr("Sync paused on a metered connection");
            return;
        }
        const folders = options.backupFolders || [];
        if (folders.length === 0) {
            root.errorMessage = Translation.tr("Add a backup folder first");
            return;
        }

        const previousSyncTime = String(options.lastSyncTime || "").trim();
        const command = [
            "bash", root.scriptRoot + "/sync.sh",
            "--base-path", root.effectiveDriveBasePath,
            "--bandwidth-kbps", String(Math.max(0, options.bandwidthLimitKbps || 0)),
            "--keep-versions", String(Math.max(0, options.keepVersions || 0)),
            "--delete-orphans", options.deleteRemoteOrphans ? "true" : "false"
        ];
        if (options.onlyModifiedSinceLastSync && previousSyncTime !== "") {
            command.push("--max-age", previousSyncTime);
        }
        for (const folder of folders)
            command.push("--folder", String(folder));

        syncProcess.environment = ({
            "GDRIVE_EXCLUDE_PATTERNS": (options.excludePatterns || []).join("\n")
        });
        syncProcess.command = command;
        root.cancelRequested = false;
        root.syncing = true;
        root.progress = 0.0;
        root.currentFile = "";
        root.currentFolder = "";
        root.statsLine = "";
        root.syncElapsedSeconds = 0;
        root.syncStartedAtMs = Date.now();
        root.currentFolderFiles = 0;
        root.currentFolderTotalFiles = 0;
        root.currentFolderBytes = 0.0;
        root.currentFolderTotalBytes = 0.0;
        root.filesTransferred = 0;
        root.filesTotal = 0;
        root.bytesTransferred = 0.0;
        root.bytesTotal = 0.0;
        root.errorMessage = "";
        root.warningMessage = "";
        root.finalizing = false;
        root._setSyncConfig("running", new Date().toISOString(), 0, 0.0);
        syncProcess.running = true;
    }

    function cancelSync(): void {
        if (!root.syncing)
            return;
        root.cancelRequested = true;
        syncProcess.running = false;
        root.syncing = false;
        root.progress = 0.0;
        root.currentFile = "";
        root.currentFolder = "";
        root.statsLine = "";
        root.syncElapsedSeconds = 0;
        root.syncStartedAtMs = 0;
        root.currentFolderFiles = 0;
        root.currentFolderTotalFiles = 0;
        root.currentFolderBytes = 0.0;
        root.currentFolderTotalBytes = 0.0;
        root.finalizing = false;
        root.errorMessage = Translation.tr("Sync cancelled");
    }

    function handleSyncLine(line: string): void {
        let event;
        try {
            event = JSON.parse(String(line || ""));
        } catch (error) {
            return;
        }
        if (event.type === "start") {
            root.currentFolder = event.folder || "";
            root.currentFile = "";
            root.finalizing = false;
            root.currentFolderFiles = 0;
            root.currentFolderTotalFiles = 0;
            root.currentFolderBytes = 0.0;
            root.currentFolderTotalBytes = 0.0;
        }
        if (event.type === "file")
            root.currentFile = event.file || "";
        if (event.filesTransferred !== undefined)
            root.filesTransferred = event.type === "complete"
                ? Math.max(0, Number(event.filesTransferred) || 0)
                : Math.max(root.filesTransferred, Number(event.filesTransferred) || 0);
        if (event.filesTotal !== undefined)
            root.filesTotal = Math.max(root.filesTotal, Number(event.filesTotal) || 0);
        if (event.bytesTransferred !== undefined)
            root.bytesTransferred = Math.max(root.bytesTransferred, Number(event.bytesTransferred) || 0);
        if (event.bytesTotal !== undefined)
            root.bytesTotal = Math.max(root.bytesTotal, Number(event.bytesTotal) || 0);
        if (event.type === "stats")
            root._handleStatsLine(event.error || event.file || "");
        if (event.type === "maintenance") {
            root.finalizing = true;
            root.currentFile = "";
            root.statsLine = event.error || Translation.tr("Finalizing backup…");
        }
        if (event.type === "warning") {
            root.warningMessage = event.error || Translation.tr("The backup completed with warnings");
            root.statsLine = root.warningMessage;
        }
        if (event.type === "done") {
            root.currentFile = "";
            root.currentFolderFiles = Math.max(0, Number(event.filesTransferred) || root.currentFolderFiles);
            root.currentFolderTotalFiles = Math.max(0, Number(event.filesTotal) || root.currentFolderTotalFiles);
            root.currentFolderBytes = Math.max(0, Number(event.bytesTransferred) || root.currentFolderBytes);
            root.currentFolderTotalBytes = Math.max(root.currentFolderBytes, root.currentFolderTotalBytes);
            if (event.status === "error")
                root.errorMessage = event.error || Translation.tr("Google Drive sync failed");
        }
        if (event.type === "complete" && event.status === "error")
            root.errorMessage = event.error || Translation.tr("Google Drive sync failed");
        if (event.type === "complete")
            root.finalizing = false;
    }

    function _finishSync(exitCode: int): void {
        const wasCancelled = root.cancelRequested;
        const elapsedMilliseconds = root.syncStartedAtMs > 0
            ? Date.now() - root.syncStartedAtMs
            : root.syncElapsedSeconds * 1000;
        const durationSeconds = Math.max(1, Math.round(elapsedMilliseconds / 1000));
        root.syncing = false;
        root.cancelRequested = false;
        root.currentFolder = "";
        root.currentFile = "";
        root.statsLine = "";
        root.finalizing = false;
        root.currentFolderFiles = 0;
        root.currentFolderTotalFiles = 0;
        root.currentFolderBytes = 0.0;
        root.currentFolderTotalBytes = 0.0;
        root.syncStartedAtMs = 0;
        if (wasCancelled)
            return;

        const now = new Date().toISOString();
        const success = exitCode === 0 && root.errorMessage === "";
        const status = success ? "success" : "error";
        const sizeMb = root.bytesTransferred / (1024 * 1024);
        const averageBytesPerSecond = durationSeconds > 0
            ? root.bytesTransferred / durationSeconds
            : 0;
        root.progress = success ? 1.0 : root.progress;
        root._setSyncConfig(status, now, root.filesTransferred, sizeMb);
        const history = root.syncHistory.slice();
        history.push({
            "time": now,
            "fileCount": root.filesTransferred,
            "sizeMb": sizeMb,
            "transferCount": 1,
            "durationSeconds": durationSeconds,
            "averageBytesPerSecond": averageBytesPerSecond,
            "status": status
        });
        // Keep a year of events so day/week/month views remain useful while
        // preventing the settings JSON from growing without bound.
        while (history.length > 366)
            history.shift();
        root.syncHistory = history;
        if (Persistent.ready)
            Persistent.states.googleDrive.syncHistory = history;
        if (Config.ready)
            options.syncHistory = history;
        if (success) {
            root.errorMessage = "";
            root._notify(
                Translation.tr("Google Drive backup complete"),
                Translation.tr("%1 files backed up.").arg(String(root.filesTransferred)),
                root.notificationIconPath
            );
            root.fetchDriveInfo();
        } else {
            if (root.errorMessage === "")
                root.errorMessage = Translation.tr("Google Drive sync failed");
            root._notify(Translation.tr("Google Drive backup failed"), root.errorMessage, root.notificationIconPath);
        }
    }

    function fetchDriveInfo(): void {
        if (!root.configured || driveInfoProcess.running)
            return;
        driveInfoProcess.command = [
            "python3",
            root.scriptRoot + "/drive_info.py",
            root.effectiveDriveBasePath
        ];
        driveInfoProcess.running = true;
    }

    function _handleDriveInfo(text: string): void {
        try {
            const info = JSON.parse(String(text || ""));
            const usedMb = Number(info.used || 0) / (1024 * 1024);
            const quotaMb = Number(info.total || 0) / (1024 * 1024);
            const backupMb = Number(info.backupSize || 0) / (1024 * 1024);
            const hasError = String(info.error || "") !== "";
            if (!hasError || quotaMb > 0) {
                root.driveUsedMb = usedMb;
                root.driveQuotaMb = quotaMb;
            }
            if (!hasError || backupMb > 0)
                root.driveBackupUsageMb = backupMb;
            if (Persistent.ready) {
                if (!hasError || quotaMb > 0) {
                    Persistent.states.googleDrive.totalDriveUsageMb = usedMb;
                    Persistent.states.googleDrive.driveQuotaMb = quotaMb;
                }
                if (!hasError || backupMb > 0)
                    Persistent.states.googleDrive.driveBackupUsageMb = backupMb;
            }
            if (Config.ready) {
                if (!hasError || quotaMb > 0) {
                    Config.options.googleDrive.totalDriveUsageMb = usedMb;
                    Config.options.googleDrive.driveQuotaMb = quotaMb;
                }
                if (!hasError || backupMb > 0)
                    Config.options.googleDrive.driveBackupUsageMb = backupMb;
            }
        } catch (error) {
            // A missing rclone remote is already represented by configured=false.
        }
    }

    function checkMetered(): void {
        if (meteredProcess.running)
            return;
        meteredProcess.running = true;
    }

    function handleNetworkStateChanged(): void {
        const connected = root.networkConnected;
        if (connected && !root.networkWasConnected) {
            root.checkMetered();
            if (Config.ready && options.enabled && options.syncOnNetworkChange)
                networkSyncTimer.restart();
        }
        root.networkWasConnected = connected;
    }

    Timer {
        id: syncTimer
        interval: root.intervalFor(options.syncInterval)
        repeat: true
        running: Config.ready && Persistent.ready && options.enabled && root.configured
        onTriggered: root.startScheduledSync()
    }

    Timer {
        id: syncElapsedTimer
        interval: 1000
        repeat: true
        running: root.syncing
        onTriggered: root.syncElapsedSeconds += 1
    }

    Timer {
        id: networkSyncTimer
        interval: 3000
        repeat: false
        onTriggered: root.startSync()
    }

    Process {
        id: checkProcess
        command: ["bash", root.scriptRoot + "/check_rclone.sh"]
        stdout: StdioCollector { id: checkOutput }
        onRunningChanged: {
            if (!running)
                return;
            root.checking = true;
        }
        onExited: {
            root.checking = false;
            try {
                const result = JSON.parse(checkOutput.text || "{}");
                root.rcloneInstalled = result.installed === true;
                root.configured = result.configured === true;
                if (root.configured)
                    root.fetchDriveInfo();
                if (!root.rcloneInstalled)
                    root.errorMessage = Translation.tr("rclone is not installed");
            } catch (error) {
                root.rcloneInstalled = false;
                root.configured = false;
            }
            if (root.setupPendingCheck) {
                root.setupPendingCheck = false;
                if (root.rcloneInstalled)
                    root._beginSetup();
                else
                    root.errorMessage = root.rcloneMissingMessage();
            }
            if (root.bootSyncPending) {
                root.bootSyncPending = false;
                Qt.callLater(() => root.startSync());
            }
        }
    }

    Process {
        id: envProcess
        command: ["cat", Quickshell.shellPath(".env")]
        stdout: StdioCollector {
            onStreamFinished: root._startSetup(text)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !setupProcess.running && root.setupRunning)
                root._startSetup("");
        }
    }

    Process {
        id: setupProcess
        stdout: StdioCollector { id: setupOutput }
        onRunningChanged: {
            if (running)
                return;
            root.setupRunning = false;
            const output = (setupOutput.text || "").trim();
            if (output === "OK") {
                root.errorMessage = "";
                root.checkRclone();
            } else {
                root.errorMessage = output.startsWith("ERROR: ")
                    ? output.substring(7)
                    : output || Translation.tr("Google Drive setup failed");
            }
        }
    }

    Process {
        id: syncProcess
        stdout: SplitParser {
            onRead: data => root.handleSyncLine(data)
        }
        stderr: StdioCollector { id: syncErrorOutput }
        onExited: (exitCode, exitStatus) => {
            const errorText = (syncErrorOutput.text || "").trim();
            if (errorText && root.errorMessage === "")
                root.errorMessage = errorText;
            root._finishSync(exitCode);
        }
    }

    Process {
        id: driveInfoProcess
        stdout: StdioCollector {
            onStreamFinished: root._handleDriveInfo(text)
        }
    }

    Process {
        id: meteredProcess
        command: ["bash", "-c", "nmcli -t -f GENERAL.METERED dev show 2>/dev/null | grep -q 'yes'"]
        onExited: (exitCode, exitStatus) => {
            root.meteredConnection = exitCode === 0;
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready && Config.ready)
                root.initializeAfterConfig();
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Persistent.ready && Config.ready)
                root.initializeAfterConfig();
        }
    }

    Connections {
        target: options
        function onSyncIntervalChanged() {
            syncTimer.restart();
        }
        function onEnabledChanged() {
            if (options.enabled && root.configured && !root.syncing) {
                root.startScheduledSync();
            }
        }
    }

    Connections {
        target: Network
        function onWifiStatusChanged() { root.handleNetworkStateChanged(); }
        function onEthernetChanged() { root.handleNetworkStateChanged(); }
    }

    IpcHandler {
        target: "googleDriveBackup"

        function sync(): void {
            root.startSync();
        }

        function cancel(): void {
            root.cancelSync();
        }

        function setBandwidthLimit(kbps: int): void {
            options.bandwidthLimitKbps = Math.max(0, kbps);
        }

        function status(): string {
            return JSON.stringify({
                "configured": root.configured,
                "syncing": root.syncing,
                "interval": options.syncInterval,
                "intervalMilliseconds": root.intervalFor(options.syncInterval),
                "bandwidthLimitKbps": options.bandwidthLimitKbps,
                "progress": root.progress,
                "folder": root.currentFolder,
                "filesTransferred": root.filesTransferred,
                "filesTotal": root.filesTotal,
                "bytesTransferred": root.bytesTransferred,
                "bytesTotal": root.bytesTotal,
                "finalizing": root.finalizing,
                "error": root.errorMessage
            });
        }
    }

    Component.onCompleted: {
        root.checkRclone();
        root.networkWasConnected = root.networkConnected;
        root.checkMetered();
        root.initializeAfterConfig();
    }
}
