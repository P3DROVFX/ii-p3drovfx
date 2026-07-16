pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// WidgetExtensionManager — manages third-party desktop widget extensions.
// Handles install / uninstall / update / local-path installs.
// Persistence lives in widget_extensions.json (separate from config.json to
// avoid the property-var-inside-JsonObject segfault bug).
//
// widgetId convention: "ext:<directoryName>"  (e.g. "ext:my-cool-widget")
Singleton {
    id: root

    // ── Public state ─────────────────────────────────────────────────────────

    // installedWidgets: { extId: { name, version, author, repoUrl, installedPath,
    //                              isLocal, enabled, installedAt, widgetJson } }
    property var installedWidgets: ({})

    // widgetConfigs: { extId: { key: value, ... } }
    property var widgetConfigs: ({})

    property bool ready: false
    property bool loading: false
    property string lastError: ""

    // Community discover results: list of { name, fullName, description, stars,
    //   author, avatarUrl, repoUrl, cloneUrl, updatedAt }
    property var communityWidgets: []
    property bool discoverLoading: false
    property string discoverError: ""

    // Emitted when any installed/config/enable state changes — consumers re-read.
    signal extensionsChanged
    signal discoverFinished

    // ── Internal state ───────────────────────────────────────────────────────

    property real _initTimestamp: Date.now()
    property int _gracePeriod: 2000
    property int _retryInterval: 1500

    // ── File persistence (widget_extensions.json) ────────────────────────────

    FileView {
        id: extFileView
        path: Directories.widgetExtensionsPath
        watchChanges: true
        atomicWrites: true
        adapter: JsonAdapter {
            id: extAdapter
            property var data: ({
                    "installedWidgets": {},
                    "widgetConfigs": {}
                })
        }

        onLoaded: {
            let d = extAdapter.data || {};
            root.installedWidgets = d.installedWidgets || {};
            root.widgetConfigs = d.widgetConfigs || {};
            root.ready = true;
            root.extensionsChanged();
        }

        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                return;
            if (Date.now() - root._initTimestamp > root._gracePeriod) {
                extFileView.writeAdapter();
                root.ready = true;
            } else {
                retryTimer.restart();
            }
        }
    }

    Timer {
        id: retryTimer
        interval: root._retryInterval
        repeat: false
        onTriggered: extFileView.reload()
    }

    Timer {
        id: writeTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (!root.ready) {
                writeTimer.restart();
                return;
            }
            extAdapter.data = {
                "installedWidgets": root.installedWidgets,
                "widgetConfigs": root.widgetConfigs
            };
            extFileView.writeAdapter();
        }
    }

    function _save() {
        writeTimer.restart();
    }

    // ── Init ─────────────────────────────────────────────────────────────────

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", Directories.userWidgetsPath]);
        extFileView.reload();
    }

    // ── Public API ───────────────────────────────────────────────────────────

    // Install from a GitHub URL or a local absolute path.
    // localPath=true skips git clone and reads the directory in-place.
    function installWidget(urlOrPath) {
        if (!urlOrPath || urlOrPath.trim() === "")
            return;
        root.loading = true;
        root.lastError = "";
        installProc.urlOrPath = urlOrPath.trim();
        installProc.running = false;
        installProc.running = true;
    }

    function uninstallWidget(extId) {
        let entry = root.installedWidgets[extId];
        if (!entry)
            return;

        if (!entry.isLocal) {
            uninstallProc.targetPath = entry.installedPath;
            uninstallProc.extId = extId;
            uninstallProc.running = false;
            uninstallProc.running = true;
        } else {
            _finalizeUninstall(extId);
        }
    }

    function _finalizeUninstall(extId) {
        let clone = Object.assign({}, root.installedWidgets);
        delete clone[extId];
        root.installedWidgets = clone;

        let cfgClone = Object.assign({}, root.widgetConfigs);
        delete cfgClone[extId];
        root.widgetConfigs = cfgClone;

        _save();
        root.extensionsChanged();
    }

    function toggleWidget(extId, enabled) {
        let entry = root.installedWidgets[extId];
        if (!entry)
            return;
        let clone = Object.assign({}, root.installedWidgets);
        clone[extId] = Object.assign({}, entry, {
            "enabled": enabled
        });
        root.installedWidgets = clone;
        _save();
        root.extensionsChanged();
    }

    function updateWidget(extId) {
        let entry = root.installedWidgets[extId];
        if (!entry || entry.isLocal)
            return;
        root.loading = true;
        // Step 1: backup, then git pull
        backupProc.extId = extId;
        backupProc.sourcePath = entry.installedPath;
        backupProc.running = false;
        backupProc.running = true;
    }

    function reloadLocalWidget(extId) {
        let entry = root.installedWidgets[extId];
        if (!entry || !entry.isLocal)
            return;
        _readWidgetJson(extId, entry.installedPath);
    }

    function getWidgetConfig(extId, key, defaultValue) {
        let cfg = root.widgetConfigs[extId];
        if (!cfg)
            return defaultValue;
        return cfg[key] !== undefined ? cfg[key] : defaultValue;
    }

    function setWidgetConfig(extId, key, value) {
        let clone = Object.assign({}, root.widgetConfigs);
        clone[extId] = Object.assign({}, clone[extId] || {});
        clone[extId][key] = value;
        root.widgetConfigs = clone;
        _save();
    }

    // Returns list of enabled installedWidgets entries ready for WidgetsRegistry.
    function getRegistryEntries() {
        let result = [];
        let keys = Object.keys(root.installedWidgets);
        for (let i = 0; i < keys.length; i++) {
            let extId = keys[i];
            let entry = root.installedWidgets[extId];
            if (!entry.enabled)
                continue;
            let wj = entry.widgetJson || {};
            let qmlFile = root._getComponent(wj);
            let qmlPath = entry.installedPath + "/" + qmlFile;
            result.push({
                "widgetId": "ext:" + extId,
                "name": entry.name || extId,
                "category": wj.category || "Utility",
                "qmlPath": "file://" + qmlPath,
                "icon": wj.icon || "extension",
                "description": entry.description || wj.description || "",
                "isExtension": true,
                "extId": extId
            });
        }
        return result;
    }

    // Returns true if extId is installed (for Background placeholder logic).
    function isWidgetInstalled(extId) {
        return root.installedWidgets[extId] !== undefined;
    }

    // Fetch community widgets from GitHub by topic ii-desktop-widget.
    function discoverWidgets() {
        if (root.discoverLoading)
            return;
        root.discoverLoading = true;
        root.discoverError = "";
        discoverProc.running = false;
        discoverProc.running = true;
    }

    // Load a widget QML component dynamically.
    // Returns null if entry not found; caller must check component.status.
    function loadWidgetComponent(extId) {
        let entry = root.installedWidgets[extId];
        if (!entry)
            return null;
        let wj = entry.widgetJson || {};
        let qmlFile = root._getComponent(wj);
        let fullPath = entry.installedPath + "/" + qmlFile;
        // Plain file:// URL — no query string (Qt rejects them for local files)
        let url = "file://" + fullPath;
        let comp = Qt.createComponent(url);
        if (comp.status === Component.Error) {
            console.error("[WidgetExtensionManager] component error for", extId, comp.errorString());
            return null;
        }
        return comp;
    }

    // ── Internal helpers ─────────────────────────────────────────────────────

    // Resolve component QML file from widget.json — handles both flat and nested schema.
    // Flat:   { "component": "Widget.qml" }
    // Nested: { "widget": { "component": "Widget.qml" } }
    function _getComponent(wj) {
        if (wj.component)
            return wj.component;
        if (wj.widget && wj.widget.component)
            return wj.widget.component;
        return "main.qml";
    }

    function _isLocalPath(s) {
        return s.startsWith("/") || s.startsWith("~/") || s.startsWith("file://");
    }

    function _extIdFromPath(p) {
        // last path segment, stripped of trailing slash
        let clean = p.replace(/\/+$/, "");
        let parts = clean.split("/");
        return parts[parts.length - 1];
    }

    function _extIdFromUrl(url) {
        // https://github.com/user/repo → repo   (strip .git)
        let s = url.replace(/\.git$/, "");
        let parts = s.split("/");
        return parts[parts.length - 1];
    }

    function _applyConfigDefaults(extId, widgetJson) {
        let defaults = widgetJson.configDefaults || {};
        let keys = Object.keys(defaults);
        if (keys.length === 0)
            return;
        let clone = Object.assign({}, root.widgetConfigs);
        let existing = clone[extId] || {};
        for (let k of keys) {
            if (existing[k] === undefined)
                existing[k] = defaults[k];
        }
        clone[extId] = existing;
        root.widgetConfigs = clone;
    }

    function _registerInstalled(extId, installedPath, repoUrl, isLocal, widgetJson) {
        let clone = Object.assign({}, root.installedWidgets);
        clone[extId] = {
            "name": widgetJson.name || extId,
            "description": widgetJson.description || "",
            "version": widgetJson.version || "",
            "author": widgetJson.author || "",
            "repoUrl": repoUrl,
            "installedPath": installedPath,
            "isLocal": isLocal,
            "enabled": true,
            "installedAt": new Date().toISOString(),
            "widgetJson": widgetJson
        };
        root.installedWidgets = clone;
        _applyConfigDefaults(extId, widgetJson);
        _save();
        root.loading = false;
        root.extensionsChanged();
    }

    function _readWidgetJson(extId, installedPath, repoUrl, isLocal) {
        widgetJsonReader.extId = extId;
        widgetJsonReader.installedPath = installedPath;
        widgetJsonReader.repoUrl = repoUrl || "";
        widgetJsonReader.isLocal = isLocal || false;
        widgetJsonReader.path = installedPath + "/widget.json";
        widgetJsonReader.reload();
    }

    // ── Processes ─────────────────────────────────────────────────────────────

    // Install process — runs widget_extensions.py install
    Process {
        id: installProc
        property string urlOrPath: ""

        command: ["python3", Directories.scriptPath + "/widget_extensions.py", "install", urlOrPath, Directories.userWidgetsPath]

        stdout: SplitParser {
            onRead: data => {
                let s = data.trim();
                if (!s)
                    return;
                try {
                    let result = JSON.parse(s);
                    if (result.status === "ok") {
                        root._readWidgetJson(result.extId, result.installedPath, installProc.urlOrPath, result.isLocal);
                    } else {
                        root.lastError = result.error || "Install failed";
                        root.loading = false;
                    }
                } catch (e) {
                    console.error("[WidgetExtensionManager] install parse error:", e, s);
                    root.loading = false;
                }
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.trim())
                    console.warn("[WidgetExtensionManager] install:", data);
            }
        }
    }

    // Uninstall process — rm -rf the cloned directory
    Process {
        id: uninstallProc
        property string targetPath: ""
        property string extId: ""

        command: ["rm", "-rf", targetPath]

        onRunningChanged: {
            if (!running && targetPath !== "") {
                root._finalizeUninstall(extId);
                targetPath = "";
                extId = "";
            }
        }
    }

    // Backup process — runs before every git update (non-fatal on failure)
    Process {
        id: backupProc
        property string extId: ""
        property string sourcePath: ""

        command: ["python3", Directories.scriptPath + "/widget_extensions.py", "backup", extId, sourcePath, Directories.widgetBackupsPath]

        stdout: SplitParser {
            onRead: data => {
                let s = data.trim();
                if (!s)
                    return;
                try {
                    let r = JSON.parse(s);
                    if (r.status !== "ok") {
                        console.warn("[WidgetExtensionManager] backup warning:", r.error);
                    }
                } catch (e) {}
            }
        }

        onRunningChanged: {
            if (!running && extId !== "") {
                // Backup done (or skipped) — proceed with git pull
                let entry = root.installedWidgets[extId];
                if (entry) {
                    updateProc.extId = extId;
                    updateProc.targetPath = entry.installedPath;
                    updateProc.running = false;
                    updateProc.running = true;
                } else {
                    root.loading = false;
                }
                extId = "";
                sourcePath = "";
            }
        }
    }

    // Update process — git pull --ff-only (triggered by backupProc)
    Process {
        id: updateProc
        property string extId: ""
        property string targetPath: ""

        command: ["git", "-C", targetPath, "pull", "--ff-only"]

        onRunningChanged: {
            if (!running && extId !== "") {
                // Re-read widget.json after pull
                let entry = root.installedWidgets[extId];
                if (entry) {
                    root._readWidgetJson(extId, entry.installedPath, entry.repoUrl, false);
                }
                root.loading = false;
                extId = "";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.trim())
                    console.warn("[WidgetExtensionManager] update:", data);
            }
        }
    }

    // Read widget.json after install or reload
    FileView {
        id: widgetJsonReader
        property string extId: ""
        property string installedPath: ""
        property string repoUrl: ""
        property bool   isLocal: false

        watchChanges: false
        atomicWrites: false

        onLoaded: {
            try {
                let wj = JSON.parse(widgetJsonReader.text() || "{}");
                root._registerInstalled(extId, installedPath, repoUrl, isLocal, wj);
            } catch (e) {
                console.error("[WidgetExtensionManager] Failed to parse widget.json for", extId, e);
                root.lastError = "Failed to parse widget.json: " + e.message;
                root.loading = false;
            }
        }

        onLoadFailed: error => {
            console.error("[WidgetExtensionManager] widget.json missing for", extId, error);
            root.lastError = "widget.json not found in " + installedPath;
            root.loading = false;
        }
    }

    // Discover process — runs widget_extensions.py discover
    Process {
        id: discoverProc

        command: ["python3", Directories.scriptPath + "/widget_extensions.py", "discover", "30"]

        stdout: SplitParser {
            onRead: data => {
                let s = data.trim();
                if (!s)
                    return;
                try {
                    let result = JSON.parse(s);
                    if (result.status === "ok") {
                        root.communityWidgets = result.results || [];
                    } else {
                        root.discoverError = result.error || "Discover failed";
                    }
                } catch (e) {
                    root.discoverError = "Parse error: " + e.message;
                }
                root.discoverLoading = false;
                root.discoverFinished();
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.trim())
                    console.warn("[WidgetExtensionManager] discover:", data);
            }
        }
        onRunningChanged: {
            if (!running && root.discoverLoading) {
                // Process ended without stdout (e.g. crash)
                root.discoverLoading = false;
                if (root.discoverError === "")
                    root.discoverError = "Discover process exited unexpectedly";
                root.discoverFinished();
            }
        }
    }

    IpcHandler {
        target: "widgetExtensionManager"
        function install(urlOrPath: string): void {
            root.installWidget(urlOrPath);
        }
        function uninstall(extId: string): void {
            root.uninstallWidget(extId);
        }
        function toggle(extId: string, enabled: bool): void {
            root.toggleWidget(extId, enabled);
        }
        function reload(extId: string): void {
            root.reloadLocalWidget(extId);
        }
    }
}
