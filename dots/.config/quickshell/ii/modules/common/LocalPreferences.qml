pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LocalPreferences — the durable copy of the settings that belong to this
 * machine, not to a theme.
 *
 * Everything listed in `protectedPatterns` below is what `presets_helper.py`
 * refuses to put into a preset (the blacklists and LOCAL_ONLY_PATHS). Until
 * now those values lived only inside config.json, so deleting config.json —
 * the recovery step every settings problem eventually points at — deleted
 * them with it: the cheatsheet setup, the launcher preferences, the dock
 * pins, the accounts' machine state.
 *
 * This singleton mirrors them, continuously, into
 * `~/.config/illogical-impulse/local-preferences.json` — a plain JSON map of
 * `{ "<dotted.config.path>": <value> }`, holding only values that differ
 * from the QML defaults, so the file stays small and a default is never
 * pinned. config.json keeps working exactly as before (single adapter,
 * single source at runtime); this file is what brings those settings back:
 *
 * - `reconcile()` runs whenever config.json finished loading (boot, external
 *   rewrite, preset apply) and whenever the missing-file grace seeded
 *   defaults. For each saved path, if the live value still equals the QML
 *   default, the saved value is pushed back into the adapter — which is
 *   exactly the state after config.json was deleted, and a no-op otherwise.
 * - `syncFromConfig()` runs after every normal config.json write and pulls
 *   the current protected values back into this file (write only on change;
 *   equality check against `lastSerialized`, no re-parse).
 * - `overlayOntoDefaults()` lets `Config.resetConfigToDefaults()` build its
 *   payload with the protected values kept, so the reset button cannot
 *   silently defeat this protection either.
 *
 * To truly clear a protected setting: change it back to its default in the
 * settings UI (the next sync prunes it from this file), or delete this file
 * while config.json holds the desired state (the next sync rewrites it from
 * there).
 *
 * Cost: one subtree walk on config-save ticks (debounced by Config.qml's own
 * write timer), one small stringify per tick, and a file write only when the
 * protected subset actually changed. Nothing runs on a timer or per frame.
 */
Singleton {
    id: root

    readonly property string filePath: Directories.localPreferencesPath
    property bool ready: false

    // { "<concrete dotted path>": plain-JSON value } — the loaded file.
    property var saved: ({})
    // Canonical text of the last content handed to the disk, so unchanged
    // content never triggers a write.
    property string lastSerialized: ""

    /**
     * Mirrors scripts/presets_helper.py — keep the two in sync:
     *   ROOT_PRESET_BLACKLIST_KEYS (minus "ai", see note in the file header),
     *   PERSONAL_PATHS, MONITOR_BINDING_PATHS, LOCAL_FOLDER_PATHS,
     *   LOCAL_PREFERENCE_PATHS, DOCK_BLACKLIST_KEYS, and the search whitelist
     *   in remove_secrets_and_userdata() ("search.*" minus searchAppearanceKeys).
     * "*" matches any dict key at that position.
     */
    readonly property var protectedPatterns: [
        // Whole sections a preset never carries.
        "ai",
        "cheatsheet",
        "googleDrive",
        "todo",
        "language",
        "policies",
        "workSafety",
        // Monitor bindings.
        "bar.onlyShowOnSingleMonitor",
        "bar.singleMonitorName",
        "bar.screenList",
        "bar.floatingNotch.onlyShowOnSingleMonitor",
        "bar.floatingNotch.singleMonitorName",
        "background.widgets.showOnlyOnSingleMonitor",
        "background.widgets.targetMonitor",
        "interactions.touchGestures.targetMonitor",
        "notifications.monitor.enable",
        "notifications.monitor.name",
        // Identity and paired hardware.
        "userProfile.customName",
        "userProfile.customBio",
        "userProfile.customGreeting",
        "userProfile.imagePath",
        "sidebar.dashboardHeader.profileImagePath",
        "background.widgets.*.imagePath",
        "background.thumbnailPath",
        "bluetoothDeviceImages",
        "soundcore.macAddress",
        "phone.contacts.favoriteIds",
        "phone.microphone.wifiIp",
        "phone.scrcpy.wirelessIp",
        "phone.webcam.wifiIp",
        "sidebar.booru.zerochan.username",
        "interactions.touchGestures.deviceId",
        "tailscale.exitNode",
        "tailscale.advertiseRoutes",
        "vpn.defaultProfile",
        "vpn.defaultLocation",
        "vpn.recentProvider",
        "bar.weather.city",
        "bar.weather.enableGPS",
        "update.lastAutoCheck",
        // Folders that only exist on this disk.
        "screenRecord.savePath",
        "screenSnip.savePath",
        "localsend.downloadPath",
        "mediaDownloader.downloadPath",
        "wallpapers.paths",
        "wallpaperSelector.customDefaultPath",
        "wallpaperSelector.directories",
        // Choices a theme has no business overriding.
        "appearance.iconTheme",
        "appearance.icons.enableThemed",
        "search.*",
        // Dock: pinned content and per-widget toggles.
        "dock.pinnedApps",
        "dock.pinnedFiles",
        "dock.appGroups",
        "dock.order",
        "dock.ignoredAppRegexes",
        "dock.livePreviewAppId",
        "dock.enableMediaWidget",
        "dock.enableWeatherWidget",
        "dock.enableSportsWidget",
        "dock.enableLivePreviewWidget",
        "dock.livePreviewSlots",
        "dock.livePreviewPaintCursor",
        "dock.livePreviewCaptureMode",
        "dock.livePreviewFollowActiveWindow",
        "dock.showPhoneButton",
        "dock.showTrashButton",
        "dock.showOverviewButton",
        "dock.showPinButton",
    ]

    // SEARCH_APPEARANCE_KEYS in presets_helper.py: the only search keys a
    // preset may carry, so every *other* search key is protected.
    readonly property var searchAppearanceKeys: [
        "positionStyle",
        "centerVerticalRatio",
        "bestMatch",
        "baseWidth",
        "baseHeight",
        "connectStyle",
        "appearance",
    ]

    function isArrayLike(value) {
        return typeof value === "object" && value !== null && typeof value.length === "number";
    }

    // A live adapter node (JsonObject / QtObject wrapper) answers to
    // objectName; a plain JSON value never has one.
    function isAdapterNode(value) {
        return value !== null && typeof value === "object" && value.objectName !== undefined;
    }

    function childKeys(node) {
        let keys = [];
        for (const key in node) {
            if (key === "objectName")
                continue;
            keys.push(key);
        }
        return keys;
    }

    // Expand a pattern with optional "*" segments into concrete key lists.
    function expandPattern(node, pattern, out) {
        if (node === null || node === undefined || typeof node !== "object")
            return;
        const keys = pattern.split(".");
        function step(current, depth, trail) {
            if (current === null || current === undefined || typeof current !== "object")
                return;
            if (depth === keys.length) {
                out.push(trail);
                return;
            }
            if (keys[depth] === "*") {
                for (const key of childKeys(current)) {
                    // Presets export strips every search key outside the
                    // appearance whitelist; mirror that exclusion.
                    if (keys[0] === "search" && depth === 1 && root.searchAppearanceKeys.includes(key))
                        continue;
                    step(current[key], depth + 1, trail.concat(key));
                }
                return;
            }
            step(current[keys[depth]], depth + 1, trail.concat(keys[depth]));
        }
        step(node, 0, []);
    }

    function getIn(node, keys) {
        for (const key of keys) {
            if (node === null || node === undefined || typeof node !== "object")
                return undefined;
            node = node[key];
        }
        return node;
    }

    function sameAsDefault(snapshot, defaultValue) {
        // Both sides are plain JSON here (adapter nodes were run through
        // Config.snapshotDefaults, defaults are already plain), so text
        // equality is a cheap deep-equal — key order is deterministic on
        // both sides because both trees were walked the same way.
        try {
            return JSON.stringify(snapshot) === JSON.stringify(defaultValue);
        } catch (e) {
            return false;
        }
    }

    // Apply a plain-JSON value into the live adapter under `keys`, recursing
    // through declared JsonObject groups (assigning a whole plain object
    // onto a QObject property would not stick).
    function applyInto(node, keys, value) {
        if (node === null || node === undefined || typeof node !== "object")
            return;
        const head = keys[0];
        if (keys.length === 1) {
            const child = node[head];
            if (value !== null && typeof value === "object" && !Array.isArray(value) && !root.isArrayLike(value)
                    && root.isAdapterNode(child)) {
                for (const key in value)
                    root.applyInto(child, [key], value[key]);
                return;
            }
            node[head] = Array.isArray(value) || root.isArrayLike(value) ? Array.from(value) : value;
            return;
        }
        root.applyInto(node[head], keys.slice(1), value);
    }

    // config.json -> local-preferences.json. Values equal to the QML
    // defaults are pruned, so the file only ever pins what the user set.
    function syncFromConfig() {
        if (!root.ready || !Config.ready || Config.defaultOptions === null || Config.configMalformed)
            return;
        let payload = {};
        for (const pattern of root.protectedPatterns) {
            let paths = [];
            root.expandPattern(Config.options, pattern, paths);
            for (const keys of paths) {
                const value = root.getIn(Config.options, keys);
                if (value === undefined)
                    continue;
                const snapshot = typeof value === "object" ? Config.snapshotDefaults(value) : value;
                const defaultValue = root.getIn(Config.defaultOptions, keys);
                if (defaultValue !== undefined && root.sameAsDefault(snapshot, defaultValue))
                    continue;
                payload[keys.join(".")] = snapshot;
            }
        }
        let serialized;
        try {
            serialized = JSON.stringify(payload);
        } catch (e) {
            return;
        }
        if (serialized === root.lastSerialized)
            return;
        root.saved = payload;
        root.lastSerialized = serialized;
        localPreferencesFileView.setText(JSON.stringify(payload, null, 2) + "\n");
    }

    // local-preferences.json -> config.json, but only where the live value
    // is still a pristine default: that is what a deleted (or freshly
    // seeded) config.json looks like, and the no-op for any file that still
    // carries real settings.
    function restoreIntoConfig() {
        if (!root.ready || !Config.ready || Config.defaultOptions === null)
            return;
        let restored = 0;
        for (const dotted in root.saved) {
            const keys = dotted.split(".");
            const value = root.getIn(Config.options, keys);
            if (value === undefined)
                continue;
            const snapshot = typeof value === "object" ? Config.snapshotDefaults(value) : value;
            const defaultValue = root.getIn(Config.defaultOptions, keys);
            if (defaultValue === undefined || !root.sameAsDefault(snapshot, defaultValue))
                continue;
            root.applyInto(Config.options, keys, root.saved[dotted]);
            restored++;
        }
        if (restored > 0)
            console.log(`[LocalPreferences] Restored ${restored} protected setting(s) after config.json lost them`);
    }

    // The full dance on a config.json load: take the protected values back
    // before handing the (possibly defaulted) state to the mirror, so a
    // deletion can never pull its own defaults into local-preferences.json.
    function reconcile() {
        root.restoreIntoConfig();
        root.syncFromConfig();
    }

    // For Config.resetConfigToDefaults(): the reset payload is plain JSON
    // built from the defaults snapshot, so the overlay is a plain walk — no
    // adapter involved.
    function overlayOntoDefaults(defaultsPayload) {
        const copy = JSON.parse(JSON.stringify(defaultsPayload));
        if (!root.ready)
            return copy;
        for (const dotted in root.saved)
            root.applyInto(copy, dotted.split("."), root.saved[dotted]);
        return copy;
    }

    function loadSaved() {
        let payload = {};
        try {
            const text = localPreferencesFileView.text();
            const parsed = JSON.parse(text);
            if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed))
                payload = parsed;
        } catch (e) {
            // An empty, missing or half-written file is the first-run state;
            // the next syncFromConfig() rewrites it from the live config,
            // which is authoritative at runtime.
            payload = {};
        }
        root.saved = payload;
        root.lastSerialized = JSON.stringify(payload);
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && root.ready)
                Qt.callLater(root.reconcile);
        }
    }

    FileView {
        id: localPreferencesFileView
        path: root.filePath
        // Written only by this singleton; no external editor or script owns
        // it, so there is nothing to watch, and skipping the watcher is one
        // less inotify registration on a file nobody else touches.
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.loadSaved();
            root.ready = true;
            if (Config.ready)
                Qt.callLater(root.reconcile);
        }
        onLoadFailed: error => {
            // Missing is normal until the first sync; a corrupt/absent file
            // must not block the mirror from rebuilding it from config.json.
            root.loadSaved();
            root.ready = true;
            if (Config.ready)
                Qt.callLater(root.reconcile);
        }
    }
}
