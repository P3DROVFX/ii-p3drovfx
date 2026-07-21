pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * KDE Connect bridge for the Sidebar Policies "Phone" tab.
 *
 * Spawns `scripts/kdeconnect/monitor.py` which listens to the
 * `org.kde.kdeconnect` DBus daemon and emits JSON events on stdout.
 * Each event updates the reactive list of devices, notifications,
 * battery / cellular signal state, etc.
 *
 * One-shot actions (find phone, ping, share URL, send clipboard,
 * sftp mount, dismiss notification) are dispatched via `qdbus-qt6`.
 *
 * The activeDeviceId is persisted in `Persistent.states.sidebar.
 * policies.phone.activeDeviceId`; if it is empty or points to a
 * device that disappeared, the first reachable paired device is
 * selected automatically.
 */
Singleton {
    id: root

    property bool available: false
    property bool ready: false
    readonly property bool hasDevices: devices.length > 0

    property string activeDeviceId: ""
    onActiveDeviceIdChanged: {
        if (root.activeDeviceId && root.notifications.length === 0) {
            const cached = root._getCachedNotifications(root.activeDeviceId)
            if (cached.length > 0) root.notifications = cached
        }
    }

    property var devices: []
    readonly property var activeDevice: root._findDevice(root.activeDeviceId)

    /** Recent paired devices (excluding the active one) in MRU order.
     *  Backed by Persistent.states.sidebar.policies.phone.recentDeviceIds. */
    readonly property var recentDevices: root._computeRecentDevices()
    function _computeRecentDevices() {
        const phoneObj = Persistent.states.sidebar.policies.phone
        const ids = phoneObj ? (phoneObj.recentDeviceIds || []) : []
        const out = []
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i]
            if (id === root.activeDeviceId) continue
            const d = root._findDevice(id)
            if (d && d.paired) out.push(d)
        }
        return out.slice(0, 4)
    }
    readonly property bool activeReachable: root.activeDevice
        ? (root.activeDevice.reachable === true)
        : false
    onActiveReachableChanged: SoundService.playEvent("devices", root.activeReachable ? "device-added" : "device-removed")
    readonly property bool activeHasNotifications: root.activeDeviceId !== ""
        && root._devicePlugins(root.activeDeviceId).indexOf("kdeconnect_notifications") >= 0
    readonly property bool scrcpyAvailable: root._scrcpyAvailable
    property bool scrcpyRunning: false

    /** True immediately when launchScrcpy() is called, stays true until the
     *  pgrep poller confirms the process is actually running (or until the
     *  fallback timer fires ~10s later if the process never appeared).
     *  Lets the UI give instant feedback while scrcpy is still starting up
     *  (the scrcpyStatusTimer only runs every 1.5s, which causes an
     *  8-second perceptual delay otherwise). */
    property bool scrcpyLaunching: false

    /** Milliseconds since scrcpy was first detected running by the
     *  pgrep poller. Updates every 1 second while running. Zero when
     *  not running. */
    property int scrcpyElapsedMs: 0

    /** Error message set when scrcpy launch fails (e.g. ADB not reachable).
     *  Cleared when scrcpy is actually running. The PhoneFooter reads this
     *  to show a hint on the card. */
    property string scrcpyLaunchError: ""

    /** True if `adb` is reachable on the active device (either wireless ADB
     *  via Config.options.phone.scrcpy.useWireless + configured IP, or via
     *  a USB-attached device). Cached for 30s — used to enable ADB-only
     *  quick actions (screenshot, power key, volume, am start). */
    property bool adbReachable: false

    property var notifications: []
    readonly property int notificationCount: notifications.length
    onNotificationsChanged: {
        if (root.ready) cacheSaveTimer.restart()
    }

    /** Pending incoming pair requests from the KDE Connect daemon.
     *  Each entry is `{id, name}`. Managed by the monitor.py events and
     *  cleaned up once the device reports itself paired or disappears. */
    property var pendingPairRequests: []

    // Remote notification persistence cache. Stored as a JSON object keyed
    // by device ID in Persistent.states.sidebar.policies.phone.
    // Kept in memory so the Phone tab is not empty after a shell reload
    // while the monitor is still handshaking.
    property var _notificationsCache: ({})

    // Ticks every 30s to force the friendly time string ("2m", "1h") in
    // RemoteNotificationGroup to re-evaluate. Without this, the binding
    // `getFriendlyNotifTimeString(time)` only re-evaluates when `time`
    // changes — but since the DBus doesn't expose a real timestamp, we
    // store Date.now() at fetch time and the display would freeze on
    // "Now" forever.
    property real _timeTick: 0
    Timer {
        interval: 30000
        repeat: true
        running: root.ready && root._enabled
        onTriggered: root._timeTick = Date.now()
    }

    readonly property var groupsByAppName: {
        const groups = {}
        notifications.forEach(n => {
            const key = n.appName || n.summary || Translation.tr("Unknown")
            if (!groups[key]) {
                groups[key] = {
                    appName: key,
                    appIcon: n.iconPath || "",
                    notifications: [],
                    time: 0
                }
            }
            groups[key].notifications.push(n)
            if (n.time > groups[key].time)
                groups[key].time = n.time
        })
        // Sort notifications within each group by time descending so the
        // newest notification is always first when the group renders its
        // preview (slice(0, 2)). Without this, the order depends on the
        // DBus iteration order, which may not match arrival time.
        for (const key in groups) {
            groups[key].notifications.sort((a, b) => (b.time || 0) - (a.time || 0))
        }
        return groups
    }
    readonly property list<string> appNameList: {
        return Object.keys(groupsByAppName).sort((a, b) => {
            return groupsByAppName[b].time - groupsByAppName[a].time
        })
    }

    signal devicePairingRequested(string devId, string name)
    signal deviceShareReceived(string devId, string url)
    signal actionFeedback(string message, bool ok)
    // Emitted when the active device transitions from reachable→offline
    // while a phone feature (webcam/mic/scrcpy) is running — shell UI
    // surfaces an inline warning inside the active card.
    signal activeDeviceLostDuringUse(string devId)
    // Emitted when the active device battery crosses below 20%.
    // Connected once in Phone.qml to fire a desktop notification.
    signal activeDeviceBatteryLow(string devId, int charge)
    // Emitted when the active device battery recovers (≥25% or plugged in).
    signal activeDeviceBatteryRecovered(string devId, int charge)
    // Emitted when critical dependencies are missing (kdeconnect-cli, pactl,
    // dbus python module, etc). Phone.qml shows a toast warning the user.
    signal criticalDepMissing(string depName, string message)

    property int _previousBattery: -1
    property bool _lowBatteryNotified: false

    readonly property string _scriptPath: FileUtils.trimFileProtocol(Directories.scriptPath + "/kdeconnect/monitor.py")
    readonly property string _fetchNotifsScriptPath: FileUtils.trimFileProtocol(Directories.scriptPath + "/kdeconnect/fetch_notifications.py")

    IpcHandler {
        target: "kdeconnect"

        function status(): string {
            const dev = KdeConnectService.activeDevice
            return JSON.stringify({
                available: KdeConnectService.available,
                ready: KdeConnectService.ready,
                persistentReady: Persistent.ready,
                persistedActiveDeviceId: (Persistent.states.sidebar
                                            && Persistent.states.sidebar.policies
                                            && Persistent.states.sidebar.policies.phone)
                                        ? Persistent.states.sidebar.policies.phone.activeDeviceId
                                        : "(null-phone)",
                scrcpyAvailable: KdeConnectService.scrcpyAvailable,
                devicesCount: KdeConnectService.devices.length,
                activeDeviceId: KdeConnectService.activeDeviceId,
                activeReachable: KdeConnectService.activeReachable,
                activeName: dev ? dev.name : "(none)",
                activeBattery: dev ? dev.charge : -1,
                notificationsCount: KdeConnectService.notificationCount,
                monitorRunning: monitorProc.running,
            })
        }

        function ping(devId: string): void {
            KdeConnectService.sendPing(devId || KdeConnectService.activeDeviceId, "ping via ipc")
        }
    }

    Component.onCompleted: {
        // Respect the Phone tab toggle. If the user has disabled the Phone
        // tab in SidebarsConfig, we don't start the DBus monitor or any
        // polling process — keeps memory/CPU at zero for users who don't
        // use phone integration.
        if (!root._enabled) return
        detectDistroProc.running = true
        checkAvailabilityProc.running = true
        checkScrcpyProc.running = true
        checkAdbProc.running = true
        checkPythonDbusProc.running = true
    }

    // Reflects Config.options.policies.phone. When false, the service stays
    // dormant: no DBus monitor, no pgrep polling, no ADB probing. Bindings
    // from the UI still resolve without forcing instantiation side effects.
    readonly property bool _enabled: Config.options.policies.phone !== 0

    // Stop all background activity when the Phone tab is toggled off at runtime.
    // Restart when toggled back on. This lets users enable/disable Phone
    // integration without reloading the shell.
    on_EnabledChanged: {
        if (root._enabled) {
            // Re-enabled: spin the background workers back up.
            detectDistroProc.running = true
            checkAvailabilityProc.running = true
            checkScrcpyProc.running = true
            checkAdbProc.running = true
            checkPythonDbusProc.running = true
        } else {
            // Disabled: stop everything that consumes CPU/IPC.
            monitorProc.running = false
            checkScrcpyRunningProc.running = false
            checkScrcpyProc.running = false
            adbProbeProc.running = false
            adbProber.running = false
            scrcpyStatusTimer.running = false
            scrcpyLaunchFallbackTimer.running = false
            scrcpyElapsedTicker.running = false
            // Reset user-facing state so UI doesn't show stale data.
            root.scrcpyRunning = false
            root.scrcpyLaunching = false
            root.devices = []
            root.notifications = []
            root.pendingPairRequests = []
        }
    }

    Process {
        id: checkAvailabilityProc
        running: false
        command: ["bash", "-c", "command -v kdeconnect-cli >/dev/null"]
        onExited: (code, status) => {
            root.available = (code === 0)
            if (root.available) {
                root.startMonitor()
            } else {
                // KDE Connect is the backbone of the entire Phone tab.
                // If it's missing, warn the user immediately.
                root.criticalDepMissing("kdeconnect-cli",
                    Translation.tr("KDE Connect is not installed — phone integration requires it"))
            }
        }
    }

    Process {
        id: checkScrcpyProc
        running: false
        command: ["bash", "-c", "command -v scrcpy >/dev/null"]
        onExited: (code, status) => {
            root._scrcpyAvailable = (code === 0)
        }
    }
    property bool _scrcpyAvailable: false

    // ─── Granular dependency flags (for the install guide UI) ───
    property bool adbPresent: false
    property bool pythonDbusPresent: false
    property string detectedDistro: "unknown"

    /** Array of missing dependency descriptors for the scrcpy card install
     *  guide popup. Each entry: { key, name, description, present, installCommands } */
    readonly property var scrcpyMissingDeps: {
        const deps = []
        if (!root._scrcpyAvailable)
            deps.push({
                key: "scrcpy",
                name: Translation.tr("scrcpy"),
                description: Translation.tr("Mirrors your phone screen in a floating SDL window. The main binary for screen mirroring."),
                present: false,
                installCommands: ({
                    arch: "sudo pacman -S scrcpy",
                    fedora: "sudo dnf install scrcpy",
                    debian: "sudo apt install scrcpy",
                })
            })
        if (!root.adbPresent)
            deps.push({
                key: "android-tools",
                name: Translation.tr("android-tools (adb)"),
                description: Translation.tr("Required for USB connection, quick actions (screenshot, power button) and opening apps from notifications."),
                present: false,
                installCommands: ({
                    arch: "sudo pacman -S android-tools",
                    fedora: "sudo dnf install android-tools",
                    debian: "sudo apt install android-tools-adb",
                })
            })
        if (!root.pythonDbusPresent)
            deps.push({
                key: "python-dbus",
                name: Translation.tr("python-dbus"),
                description: Translation.tr("Python D-Bus bindings — required for the KDE Connect monitor to read notifications, battery, and connectivity."),
                present: false,
                installCommands: ({
                    arch: "sudo pacman -S python-dbus",
                    fedora: "sudo dnf install python3-dbus",
                    debian: "sudo apt install python3-dbus",
                })
            })
        return deps
    }

    // ─── Distro detection (runs once on startup) ──────────
    Process {
        id: detectDistroProc
        running: false
        command: ["bash", "-c",
            "if [ -f /etc/arch-release ]; then echo arch; " +
            "elif [ -f /etc/fedora-release ]; then echo fedora; " +
            "elif [ -f /etc/debian_version ]; then echo debian; " +
            "else echo unknown; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = String(this.text).trim()
                if (d.length > 0) root.detectedDistro = d
            }
        }
    }

    // ─── ADB presence check ────────────────────────────────
    Process {
        id: checkAdbProc
        running: false
        command: ["bash", "-c", "command -v adb >/dev/null 2>&1"]
        onExited: (code, status) => {
            root.adbPresent = (code === 0)
        }
    }

    // ─── Python dbus presence check ───────────────────────────
    Process {
        id: checkPythonDbusProc
        running: false
        command: ["bash", "-c", "python3 -c 'import dbus' 2>/dev/null && echo 'ok'"]
        stdout: SplitParser {
            onRead: line => {
                root.pythonDbusPresent = (String(line).trim() === "ok")
            }
        }
        onExited: (code, status) => {
            if (code !== 0)
                root.pythonDbusPresent = false
        }
    }

    Process {
        id: cleanupProc
        running: false
        command: ["pkill", "-f", "kdeconnect/monitor.py"]
        onExited: (code, status) => {
            monitorProc.command = ["python3", root._scriptPath]
            monitorProc.running = true
        }
    }

    function startMonitor() {
        if (monitorProc.running) return
        cleanupProc.running = true
    }

    Process {
        id: monitorProc
        running: false

        stdout: SplitParser {
            onRead: line => {
                if (!line || line.length === 0) return
                let ev
                try {
                    ev = JSON.parse(line)
                } catch (e) {
                    console.warn("[KdeConnect] Bad JSON:", e.message,
                        "len:", line.length,
                        "first:", line.substring(0, 60),
                        "last:", line.substring(Math.max(0, line.length - 60)))
                    return
                }
                try {
                    root._handleEvent(ev)
                } catch (e) {
                    console.warn("[KdeConnect] Handler error for event",
                                 JSON.stringify(ev.event),
                                 "msg:", e.message,
                                 "stack:", (e.stack || "").split("\n")[1] || "(no stack)")
                }
            }
        }

        stderr: SplitParser {
            onRead: line => {
                // Carry on. Most stderr noise is from D-Bus introspect
                // failures for inaccessible plugin paths on offline devices.
                if (String(line).indexOf("Introspect error") < 0
                    && String(line).indexOf("UnknownObject") < 0)
                    console.warn("[KdeConnect] monitor stderr:", line)
            }
        }

        onExited: (code, status) => {
            root.ready = false
            if (code === 0) {
                // Likely fatal (no daemon). Try to restart after backoff.
                restartTimer.restart()
            } else {
                restartTimer.restart()
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 4000
        repeat: false
        onTriggered: {
            if (root.available && Persistent.ready) root.startMonitor()
        }
    }

    function _handleEvent(ev) {
        switch (ev.event) {
        case "ready":
            root.ready = true
            break
        case "fatal":
            root.ready = false
            console.warn("[KdeConnect] monitor fatal:", ev.error, ev.message ?? "", ev.detail ?? "")
            if (ev.error === "missing_deps") {
                const msg = ev.message || Translation.tr("Missing Python dependency")
                const detail = ev.detail || ""
                const label = detail.length > 0 ? msg + "\n" + detail : msg
                root.criticalDepMissing("python-deps", label)
            }
            break
        case "device_added_signal":
            // Marker before `device_added`. Swallow.
            break
        case "device_added":
            root._mergeDevice(ev)
            root._sanitiseActiveDevice()
            break
        case "device_removed":
            root._removeDevice(ev.id)
            root._sanitiseActiveDevice()
            break
        case "device_props":
            root._applyDeviceProps(ev.id, ev.changed ?? {})
            break
        case "device_visibility":
            root._patchDevice(ev.id, {"reachable": ev.reachable})
            root._sanitiseActiveDevice()
            break
        case "battery":
            root._patchDevice(ev.id, {"charge": ev.charge, "charging": ev.charging})
            // Also emit low / recovered signals directly — _patchDevice
            // takes the merged dict path but may not see charge changes
            // coming via the inline "battery" event in some scenarios
            // (e.g., first event after shell boot, when _previousBattery
            // is still -1 and the merge path's comparison is skipped).
            if (ev.id === root.activeDeviceId) {
                const charge = ev.charge ?? -1
                const charging = !!ev.charging
                if (charge >= 0 && charge < 20 && !charging
                    && !root._lowBatteryNotified
                    && root._previousBattery >= 20) {
                    root.activeDeviceBatteryLow(ev.id, charge)
                    root._lowBatteryNotified = true
                } else if ((charge >= 25 || charging)
                           && root._lowBatteryNotified) {
                    root.activeDeviceBatteryRecovered(ev.id, charge)
                    root._lowBatteryNotified = false
                }
                root._previousBattery = charge
            }
            break
        case "connectivity":
            root._patchDevice(ev.id, {"signalType": ev.type, "signalStrength": ev.strength})
            break
        case "sync_notifications":
            if (ev.id === root.activeDeviceId) {
                root.notifications = root._normaliseNotifications(ev.notifications ?? [])
            }
            break
        case "notif_cleared":
            if (ev.id === root.activeDeviceId) root.notifications = []
            break
        case "notif_posted":
        case "notif_updated":
        case "notif_removed":
            // sync_notifications event always follows; nothing more to do.
            break
        case "share_received":
            root.deviceShareReceived(ev.id, ev.url)
            break
        case "pairing_request":
            root._addPairingRequest(ev.id, ev.name ?? "")
            break
        case "debug":
            // Best-effort: keep log only when env var set
            if (typeof Qt !== "undefined" && Qt.application)
                console.log("[KdeConnect] debug",
                    ev.what ?? "", ev.error ?? "", ev.raw ?? "")
            break
        }
    }

    function _mergeDevice(ev) {
        const devices = root.devices.slice()
        const idx = devices.findIndex(d => d.id === ev.id)
        const normalized = {
            id: ev.id,
            name: ev.name ?? "",
            type: ev.type ?? "phone",
            icon: ev.icon ?? "phone",
            reachable: !!ev.reachable,
            paired: !!ev.paired,
            charge: ev.charge ?? -1,
            charging: !!ev.charging,
            signalType: ev.signalType ?? "",
            signalStrength: ev.signalStrength ?? 0,
            supportedPlugins: ev.supported_plugins ?? [],
            loadedPlugins: ev.loaded_plugins ?? [],
        }
        if (idx < 0) devices.push(normalized)
        else devices[idx] = Object.assign({}, devices[idx], normalized)
        root.devices = devices
        if (normalized.paired) root._removePairingRequest(ev.id)
    }

    function _patchDevice(id, patch) {
        const devices = root.devices.slice()
        const idx = devices.findIndex(d => d.id === id)
        if (idx < 0) return
        const prev = devices[idx]
        const merged = Object.assign({}, devices[idx], patch)

        // Phase 6 — detect "device lost during use".
        // If we just transitioned reachable=true → false AND this is the
        // active device AND a phone feature is currently running, emit
        // signal so the UI can show an inline warning instead of looking
        // like a silent state change.
        if (id === root.activeDeviceId
            && prev.reachable === true
            && merged.reachable === false) {
            const anyFeatureRunning = PhoneCameraService.running
                || PhoneMicService.running
                || root.scrcpyRunning
            if (anyFeatureRunning) {
                root.activeDeviceLostDuringUse(id)
            }
        }

        // Phase 7.4 — low battery notification (cross 20% threshold).
        if (id === root.activeDeviceId && merged.charge !== undefined) {
            const newCharge = merged.charge
            if (newCharge >= 0 && newCharge < 20
                && !merged.charging
                && !root._lowBatteryNotified
                && root._previousBattery >= 20) {
                root.activeDeviceBatteryLow(id, newCharge)
                root._lowBatteryNotified = true
            } else if ((newCharge >= 25 || merged.charging)
                       && root._lowBatteryNotified) {
                root.activeDeviceBatteryRecovered(id, newCharge)
                root._lowBatteryNotified = false
            }
            root._previousBattery = newCharge
        }

        devices[idx] = merged
        root.devices = devices
        if (patch.paired === true) root._removePairingRequest(id)
    }

    function _addPairingRequest(id, name) {
        if (!id) return
        const list = root.pendingPairRequests.slice()
        if (!list.find(p => p.id === id)) {
            list.push({ id: id, name: name })
            root.pendingPairRequests = list
            root.devicePairingRequested(id, name)
        }
    }

    function _removePairingRequest(id) {
        if (!id) return
        const list = root.pendingPairRequests.filter(p => p.id !== id)
        if (list.length !== root.pendingPairRequests.length)
            root.pendingPairRequests = list
    }

    function _applyDeviceProps(id, changed) {
        if (!changed) return
        const patch = {}
        if ("name" in changed) patch.name = String(changed.name)
        if ("type" in changed) patch.type = String(changed.type)
        if ("iconName" in changed) patch.icon = String(changed.iconName)
        if ("isReachable" in changed) patch.reachable = !!changed.isReachable
        if ("isPaired" in changed) patch.paired = !!changed.isPaired
        if ("pairState" in changed) {
            // pairState: 0 = unpaired, 1 = paired, 2 = requested
            const ps = changed.pairState
            if (patch.paired === undefined) {
                patch.paired = (ps === 1)
            }
        }
        if ("loadedPlugins" in changed) patch.loadedPlugins = changed.loadedPlugins.slice(0)
        if ("supportedPlugins" in changed) patch.supportedPlugins = changed.supportedPlugins.slice(0)
        root._patchDevice(id, patch)
    }

    function _removeDevice(id) {
        root.devices = root.devices.filter(d => d.id !== id)
        root._removePairingRequest(id)
    }

    function _feedback(message, ok) {
        KdeConnectService.dispatchActionFeedback(message, ok)
    }

    function dispatchActionFeedback(message, ok) {
        root.actionFeedback(message, ok)
    }

    function _findDevice(id) {
        if (!id) return null
        return root.devices.find(d => d.id === id) || null
    }

    function _devicePlugins(id) {
        const d = root._findDevice(id)
        return d ? (d.supportedPlugins || []) : []
    }

    function _sanitiseActiveDevice() {
        const current = root._findDevice(root.activeDeviceId)
        if (current && current.reachable && current.paired) return
        const fallback = root.devices.find(d => d.reachable && d.paired)
            || root.devices.find(d => d.paired)
            || null
        const nextId = fallback ? fallback.id : ""
        if (nextId !== root.activeDeviceId) {
            root.activeDeviceId = nextId
            root._persistActiveDeviceId(nextId)
            requestNotificationsRefresh()
        }
    }

    function selectDevice(id) {
        if (!id || id === root.activeDeviceId) return
        root.activeDeviceId = id
        root._persistActiveDeviceId(id)
        requestNotificationsRefresh()
    }

    function _persistActiveDeviceId(id) {
        if (!Persistent.ready) return
        try {
            const phoneObj = Persistent.states.sidebar.policies.phone
            if (phoneObj && phoneObj.activeDeviceId !== undefined) {
                phoneObj.activeDeviceId = id
            }
            if (id && phoneObj && phoneObj.recentDeviceIds !== undefined) {
                const list = phoneObj.recentDeviceIds || []
                const idx = list.indexOf(id)
                if (idx !== -1) list.splice(idx, 1)
                list.unshift(id)
                if (list.length > 5) list.length = 5
                phoneObj.recentDeviceIds = list
            }
        } catch (e) {
            console.warn("[KdeConnect] Could not persist activeDeviceId:",
                         e.message)
        }
    }

    function _normaliseNotifications(list) {
        // Build a lookup of existing notification timestamps AND content by
        // publicId so we can:
        //   1. PRESERVE timestamps across syncs (so "Now" → "1m" works)
        //   2. UPDATE the timestamp when the notification content changes
        //      (e.g. WhatsApp group receives a new message — the publicId
        //      stays the same but the ticker/body changes, and the group
        //      should move to the top of the notification list)
        const existing = {}
        for (let i = 0; i < root.notifications.length; i++) {
            const n = root.notifications[i]
            if (n.publicId) {
                existing[n.publicId] = {
                    time: n.time,
                    ticker: n.ticker || "",
                    body: n.body || "",
                }
            }
        }
        return list.map(n => {
            const ticker = n.ticker ?? ""
            const appName = n.appName ?? ""
            const title = n.summary ?? n.title ?? ""
            const body = n.body ?? n.text ?? ""
            const publicId = n.publicId ?? n.key ?? ""

            let time
            const prev = existing[publicId]
            if (prev) {
                // Notification already existed — check if content changed.
                const contentChanged = (ticker !== prev.ticker)
                    || (body !== prev.body)
                if (contentChanged) {
                    // Content changed (new message in a conversation, etc.)
                    // Update timestamp so the group moves to the top.
                    time = Date.now()
                } else {
                    // No content change — preserve existing timestamp.
                    time = prev.time
                }
            } else if (typeof n.time === "number") {
                time = n.time
            } else if (n.time) {
                time = parseInt(n.time, 10)
            } else {
                // New notification — use current time.
                time = Date.now()
            }
            return {
                publicId: publicId,
                appName: appName,
                summary: title || appName,
                body: body || ticker,
                ticker: ticker,
                time: time,
                dismissable: n.dismissable !== undefined
                    ? Boolean(n.dismissable)
                    : (n.isCancel !== false),
                iconPath: n.iconPath ?? "",
                actions: (n.actions ?? []).map(a => ({
                    key: a.key ?? "",
                    label: a.label ?? a.text ?? "",
                })),
                replyId: n.replyId ?? "",
                replyPlaceholder: n.replyPlaceholder ?? Translation.tr("Reply"),
                package: n.package ?? "",
            }
        })
    }

    function requestNotificationsRefresh() {
        if (!root.activeDeviceId) {
            root.notifications = []
            return
        }
        // Invoke the Python one-shot fetcher instead of `qdbus-qt6`.
        // The qdbus-qt6 wrapping (`[Variant(QString): "..."]`) made every
        // notification line fail JSON.parse, so the manual refresh button
        // at the bottom of the Phone tab silently returned [] even when
        // the device actually had active notifications. The fetcher uses
        // the same DBus path as monitor.py and emits a single JSON array
        // line that StdioCollector parses cleanly.
        refresher.command = ["python3", root._fetchNotifsScriptPath,
                             root.activeDeviceId]
        refresher.running = true
    }

    Process {
        id: refresher
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text
                if (!text || text.trim().length === 0) return
                try {
                    const parsed = JSON.parse(text.trim())
                    if (!Array.isArray(parsed)) {
                        console.warn("[KdeConnect] fetch_notifications: unexpected non-array response")
                        return
                    }
                    // Always overwrite — even with [] — so the UI matches
                    // the device's actual state after a manual refresh.
                    root.notifications = root._normaliseNotifications(parsed)
                } catch (e) {
                    console.warn("[KdeConnect] Failed to parse notifications:", e)
                }
            }
        }
        onExited: (code, status) => {
            // no-op
        }
    }

    function discardAllNotifications() {
        const list = root.notifications.slice()
        for (const notif of list) {
            if (notif.dismissable !== false && notif.publicId) {
                // Use dismiss() on the per-notification leaf interface so the
                // notification is actually removed on the phone — see
                // discardNotification() for the full rationale. The previous
                // sendAction(devId, publicId, "cancel") was a no-op because
                // "cancel" isn't a registered action button on Android
                // notifications, so dismissing all from the sidebar left all
                // notifications still active in the phone's notification shade.
                const leafPath = "/modules/kdeconnect/devices/" + root.activeDeviceId +
                                 "/notifications/" + notif.publicId
                Quickshell.execDetached([
                    "bash", "-c",
                    "QDBUS=$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus); " +
                    "$QDBUS org.kde.kdeconnect " + leafPath +
                    " org.kde.kdeconnect.device.notifications.notification.dismiss" +
                    " >/dev/null 2>&1 || true"
                ])
            }
        }
        root.notifications = []
    }

    function discardNotification(publicId) {
        if (!publicId) return
        // Calls `dismiss()` on the per-notification leaf interface at
        // `/modules/kdeconnect/devices/<dev>/notifications/<publicId>`.
        // This is the *correct* way to dismiss a notification on the phone:
        // the dismiss() method sends an `isCancel=true` network packet to the
        // Android device, which calls NotificationManager.cancel(id) for the
        // matching notification.
        //
        // The previous implementation used
        //   sendAction(devId, publicId, "cancel")
        // which calls `org.kde.kdeconnect.device.notifications.sendAction(key, action)`
        // — but that method invokes a named ACTION button on the notification
        // (e.g. "Reply", "Mark as read") and treats "cancel" as just another
        // action_key. Since Android notifications don't expose a "cancel"
        // action button, the dismiss never reached the phone: the sidebar
        // removed the card from its local list, but the phone's notification
        // shade kept showing it. Using dismiss() actually cancels it on the
        // phone.
        const devId = root.activeDeviceId
        const leafPath = "/modules/kdeconnect/devices/" + devId +
                         "/notifications/" + publicId
        Quickshell.execDetached([
            "bash", "-c",
            "QDBUS=$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus); " +
            "$QDBUS org.kde.kdeconnect " + leafPath +
            " org.kde.kdeconnect.device.notifications.notification.dismiss" +
            " >/dev/null 2>&1 || true"
        ])
        const idx = root.notifications.findIndex(n => n.publicId === publicId)
        if (idx >= 0) {
            const next = root.notifications.slice()
            next.splice(idx, 1)
            root.notifications = next
        }
    }

    function sendAction(devId, key, action) {
        if (!devId || !key) return
        const identity = root._shellQuote(key)
        const actionArg = root._shellQuote(action ?? "")
        root._call(devId, "notifications",
                   "org.kde.kdeconnect.device.notifications.sendAction",
                   [identity, actionArg])
    }

    function replyNotification(publicId, message) {
        if (!publicId || !message) return
        const devId = root.activeDeviceId
        const notif = root.notifications.find(n => n.publicId === publicId)
        if (!notif || !notif.replyId) return
        const replyId = root._shellQuote(notif.replyId)
        const msg = root._shellQuote(message)
        root._call(devId, "notifications",
                   "org.kde.kdeconnect.device.notifications.sendReply",
                   [replyId, msg])
        // KDE Connect emits `notificationUpdated` on the Android side after a
        // reply, but the daemon's IPC timing is racy — the monitor.py sync
        // sometimes fires before the phone has updated the body, so the QML
        // would keep showing the stale text. Force a delayed re-fetch so the
        // updated body (e.g. "You: hi") replaces the old one reliably.
        replyRefreshTimer.publicId = publicId
        replyRefreshTimer.restart()
        root.actionFeedback(Translation.tr("Reply sent"), true)
    }

    Timer {
        id: replyRefreshTimer
        interval: 800
        repeat: false
        property string publicId: ""
        onTriggered: root.requestNotificationsRefresh()
    }

    function findMyPhone(devId) {
        root._call(devId, "findmyphone",
                   "org.kde.kdeconnect.device.findmyphone.ring", [])
    }

    function sendPing(devId, message) {
        const args = message ? [root._shellQuote(message)] : []
        root._call(devId, "ping",
                   "org.kde.kdeconnect.device.ping.sendPing", args)
    }

    function shareUrl(devId, url) {
        if (!url) return
        root._call(devId, "share",
                   "org.kde.kdeconnect.device.share.shareUrl",
                   [root._shellQuote(url)])
    }

    function shareText(devId, text) {
        if (!text) return
        root._call(devId, "share",
                   "org.kde.kdeconnect.device.share.shareText",
                   [root._shellQuote(text)])
    }

    function sendClipboard(devId) {
        if (!devId) return
        root._call(devId, "clipboard",
                   "org.kde.kdeconnect.device.clipboard.sendClipboard", [])
    }

    /** Accepts an incoming pair request for a device (daemon method
     *  acceptPairing on the device object path). */
    function acceptPairing(devId) {
        if (!devId) return
        Quickshell.execDetached([
            "bash", "-c",
            "QDBUS=$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus); " +
            "$QDBUS org.kde.kdeconnect /modules/kdeconnect/devices/" +
            devId + " org.kde.kdeconnect.device.acceptPairing " +
            ">/dev/null 2>&1 || true"
        ])
        root._removePairingRequest(devId)
        root.actionFeedback(Translation.tr("Pairing accepted"), true)
    }

    /** Cancels/declines an incoming pair request (daemon method
     *  cancelPairing on the device object path). */
    function declinePairing(devId) {
        if (!devId) return
        Quickshell.execDetached([
            "bash", "-c",
            "QDBUS=$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus); " +
            "$QDBUS org.kde.kdeconnect /modules/kdeconnect/devices/" +
            devId + " org.kde.kdeconnect.device.cancelPairing " +
            ">/dev/null 2>&1 || true"
        ])
        root._removePairingRequest(devId)
        root.actionFeedback(Translation.tr("Pairing declined"), false)
    }

    /** Restarts the KDE Connect DBus monitor process. This triggers a fresh
     *  device enumeration and notification sync without reloading the shell. */
    function refreshDevices() {
        monitorProc.running = false
        root.ready = false
        Qt.callLater(() => root.startMonitor())
        root.actionFeedback(Translation.tr("Refreshing devices…"), true)
    }

    function mountSftp(devId) {
        if (!devId) return
        root._call(devId, "sftp",
                   "org.kde.kdeconnect.device.sftp.mount", [])
    }

    function unmountSftp(devId) {
        if (!devId) return
        root._call(devId, "sftp",
                   "org.kde.kdeconnect.device.sftp.unmount", [])
    }

    function browseFiles(devId) {
        if (!devId) return
        mountSftp(devId)
        sftpOpenTimer.devId = devId
        sftpOpenTimer.restart()
    }

    // ─── ADB reachability + intent dispatch (Phase 4 features) ────

    /**
     * Checks whether ADB is reachable on the active device. Updates
     * `adbReachable` asynchronously. Called once on shell boot and
     * re-checked periodically (every 30s) for sticky state. The cache
     * avoids spawning `adb get-state` for every quick action.
     */
    Timer {
        id: adbProber
        interval: 30000
        repeat: true
        running: root.ready && root._enabled
        onTriggered: root._probeAdb()
    }

    Process {
        id: adbProbeProc
        running: false
        command: ["bash", "-c",
            "if command -v adb >/dev/null 2>&1; then " +
            "  IP=" + root._shellQuote((Config.options.phone && Config.options.phone.scrcpy)
                                      ? (Config.options.phone.scrcpy.wirelessIp || "")
                                      : "") + "; " +
            "  if [ -n \"$IP\" ]; then " +
            "    adb connect \"$IP\" 2>/dev/null; " +
            "  fi; " +
            "  STATE=$(adb get-state 2>/dev/null); " +
            "  [ \"$STATE\" = \"device\" ] && exit 0 || exit 1; " +
            "else exit 1; fi"]
        onExited: (code, status) => {
            const now = (code === 0)
            if (now !== root.adbReachable) {
                root.adbReachable = now
                if (root.stateChanged) root.stateChanged()
            }
        }
    }

    function _probeAdb() {
        adbProbeProc.running = false
        adbProbeProc.running = true
    }

    /**
     * Opens the Android app that originated a remote notification on the
     * phone. Launches scrcpy to mirror the phone screen AND uses ADB to
     * open the specific app, so the user sees the app opening in the
     * scrcpy window.
     *
     * The KDE Connect DBus does NOT expose the original Android Intent —
     * only the notification text, appName, and internalId. However, the
     * internalId contains the package name (format: "0|<package>|..."),
     * which we extracted in the Python scripts into the `package` field.
     *
     * Launch strategy:
     *   1. Always launch scrcpy to mirror the phone screen (so the user
     *      sees the app opening). scrcpy works even when the phone is
     *      locked — it mirrors the lock screen and the user can unlock
     *      by tapping on the scrcpy window.
     *   2. If we have a package name, run `adb shell monkey -p <pkg>` to
     *      open the app on the phone. Delayed by 1s to give scrcpy time
     *      to start mirroring first.
     *   3. If no package name, scrcpy is still launched — the user can
     *      open the app manually by tapping on the mirrored screen.
     */
    function openNotificationIntent(publicId) {
        const notif = root.notifications.find(n => n.publicId === publicId)
        if (!notif) return

        const pkg = notif.package || ""
        const appName = notif.appName || notif.summary || Translation.tr("the app")

        // Step 1: Always launch scrcpy so the user can see the phone screen.
        root.launchScrcpy(root.activeDeviceId)

        // Step 2: If we have a package, open the app via ADB.
        if (!pkg) {
            root.actionFeedback(
                Translation.tr("Opening scrcpy - tap the app on the mirrored screen"),
                true)
            return
        }

        const scrcpyConf = Config.options.phone ? Config.options.phone.scrcpy : null
        const useWireless = scrcpyConf ? scrcpyConf.useWireless : false
        const wirelessIp = scrcpyConf ? (scrcpyConf.wirelessIp || "") : ""
        const wirelessPort = scrcpyConf ? (scrcpyConf.wirelessPort || "5555") : "5555"

        // Build shell command — delay monkey by 1s so scrcpy starts first.
        let cmd = ""
        if (useWireless && wirelessIp.length > 0) {
            cmd += "adb connect " + root._shellQuote(wirelessIp + ":" + wirelessPort) + " >/dev/null 2>&1; "
        }
        cmd += "sleep 1; "
        cmd += "adb shell monkey -p " + root._shellQuote(pkg) +
               " -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1"
        cmd += " && notify-send -i smartphone 'ii' " +
               root._shellQuote(Translation.tr("Opened %1 on phone").arg(appName)) +
               " || notify-send -i smartphone 'ii' " +
               root._shellQuote(Translation.tr("Could not open %1 - ADB unreachable").arg(appName))

        Quickshell.execDetached(["bash", "-c", cmd])
        root.actionFeedback(
            Translation.tr("Opening scrcpy + %1...").arg(appName),
            true)
    }

    // - ADB quick actions (Phase 5) -

    /** Screenshots the phone screen via `adb exec-out screencap`. Saves
     *  to ~/Pictures/PhoneScreenshots/<timestamp>.png. Returns void —
     *  completion is async via notify-send. */
    function adbScreenshot() {
        const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19)
        Quickshell.execDetached(["bash", "-c",
            "DIR=\"$HOME/Pictures/PhoneScreenshots\"; " +
            "mkdir -p \"$DIR\"; " +
            "FILE=\"$DIR/screen-${ts}.png\"; " +
            "if command -v adb >/dev/null 2>&1 && " +
            "   adb get-state 2>/dev/null | grep -q device; then " +
            "  adb exec-out screencap -p > \"$FILE\" 2>/dev/null; " +
            "  if [ -s \"$FILE\" ]; then " +
            "    notify-send -i smartphone 'ii' 'Saved phone screenshot to ' \"$FILE\"; " +
            "  else " +
            "    rm -f \"$FILE\"; " +
            "    notify-send -i smartphone 'ii' 'Phone screenshot failed'; " +
            "  fi; " +
            "else " +
            "  notify-send -i smartphone 'ii' 'ADB was not reachable'; " +
            "fi"
        ])
        root.actionFeedback(Translation.tr("Screenshotting phone…"), true)
    }

    /** Enables TCP/IP mode on a USB-connected device so it can later be
     *  reached wirelessly on port 5555. Requires `adb` and a USB connection.
     *  Completion is reported via notify-send. */
    function enableWirelessAdb() {
        Quickshell.execDetached(["bash", "-c",
            "if command -v adb >/dev/null 2>&1 && " +
            "   adb get-state 2>/dev/null | grep -q device; then " +
            "  if adb tcpip 5555 >/dev/null 2>&1; then " +
            "    notify-send -i smartphone 'ii' " +
            "      '" + Translation.tr("Wireless ADB enabled on port 5555") + "'; " +
            "  else " +
            "    notify-send -i smartphone 'ii' " +
            "      '" + Translation.tr("Could not enable wireless ADB") + "'; " +
            "  fi; " +
            "else " +
            "  notify-send -i smartphone 'ii' " +
            "    '" + Translation.tr("ADB not connected via USB") + "'; " +
            "fi"
        ])
        root.actionFeedback(Translation.tr("Enabling wireless ADB…"), true)
    }

    /** Toggles phone screen power. Uses `adb shell input keyevent 26`
     *  (KEYCODE_POWER). Best-effort; silently ignored if ADB isn't ready. */
    function adbTogglePower() {
        Quickshell.execDetached(["bash", "-c",
            "adb shell input keyevent 26 >/dev/null 2>&1 || " +
            "notify-send -i smartphone 'ii' 'Could not toggle power on phone'"])
        root.actionFeedback(Translation.tr("Toggled phone power"), true)
    }

    /** Adjusts phone media volume via ADB. direction: +1 = up, -1 = down. */
    function adbChangeVolume(direction) {
        const key = direction > 0 ? "24" : "25"  // KEYCODE_VOLUME_UP / _DOWN
        Quickshell.execDetached(["bash", "-c",
            "adb shell input keyevent " + key + " >/dev/null 2>&1 || true"])
    }

    /** Mutes/unmutes phone ringer via ADB. */
    function adbToggleMute() {
        Quickshell.execDetached(["bash", "-c",
            "adb shell input keyevent 91 >/dev/null 2>&1 || true"])
    }

    /** Presses the Home button via ADB. */
    function adbHome() {
        Quickshell.execDetached(["bash", "-c",
            "adb shell input keyevent 3 >/dev/null 2>&1 || true"])
    }

    /** Presses the Back button via ADB. */
    function adbBack() {
        Quickshell.execDetached(["bash", "-c",
            "adb shell input keyevent 4 >/dev/null 2>&1 || true"])
    }

    /** Presses the Recents button via ADB. */
    function adbRecents() {
        Quickshell.execDetached(["bash", "-c",
            "adb shell input keyevent 187 >/dev/null 2>&1 || true"])
    }

    Timer {
        id: sftpOpenTimer
        property string devId: ""
        interval: 600
        repeat: false
        onTriggered: {
            if (!devId) return
            Quickshell.execDetached([
                "bash", "-c",
                "QDBUS=$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus); "
                + "MOUNT=$($QDBUS org.kde.kdeconnect /modules/kdeconnect/devices/"
                + devId + "/sftp org.kde.kdeconnect.device.sftp.mountPoint 2>/dev/null); "
                + "if [ -z \"$MOUNT\" ]; then MOUNT=$($QDBUS org.kde.kdeconnect /modules/kdeconnect/devices/"
                + devId + "/sftp org.freedesktop.DBus.Properties.Get "
                + "org.kde.kdeconnect.device.sftp mountPoint 2>/dev/null "
                + " | sed 's/^.*: \"\\(.*\\)\"/\\1/'); fi; "
                + "if [ -n \"$MOUNT\" ]; then "
                + "  TARGET=\"$MOUNT\"; "
                + "  if [ -d \"$MOUNT/storage/emulated/0\" ]; then TARGET=\"$MOUNT/storage/emulated/0\"; fi; "
                // gio open respects the system's default file manager via
                // GVFS mimetype associations — unlike xdg-open which can
                // route to the browser if inode/directory is misassociated.
                + "  if command -v gio >/dev/null 2>&1; then "
                + "    gio open \"$TARGET\" >/dev/null 2>&1 & exit 0; "
                + "  fi; "
                // Fall back to xdg-open if gio is unavailable.
                + "  xdg-open \"$TARGET\" >/dev/null 2>&1 & "
                + "fi"
            ])
        }
    }

    function sendFile(devId) {
        if (!devId) return
        filePicker.command = [
            "bash", "-c",
            "if command -v kdialog >/dev/null 2>&1; then "
            + "kdialog --getopenfilename \"$HOME\" --multiple 2>/dev/null | tr '\\n' '|'; "
            + "elif command -v zenity >/dev/null 2>&1; then "
            + "zenity --file-selection --multiple --separator '|' 2>/dev/null; "
            + "fi"
        ]
        filePicker.running = true
    }

    Process {
        id: filePicker
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim()
                if (!txt) return
                const paths = txt.split("|").map(s => s.trim()).filter(s => s.length > 0)
                for (const p of paths) {
                    root.shareUrl(root.activeDeviceId, "file://" + p)
                }
            }
        }
    }

    function _call(devId, plugin, fullMethod, args) {
        if (!devId) return
        const path = "/modules/kdeconnect/devices/" + devId + "/" + plugin
        const argString = (args || []).join(" ")
        Quickshell.execDetached([
            "bash", "-c",
            "QDBUS=$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus); " +
            "$QDBUS org.kde.kdeconnect " + path + " " + fullMethod
                + (argString.length > 0 ? " " + argString : "")
                + " >/dev/null 2>&1 || true"
        ])
    }

    property string _wirelessPromptDevId: ""

    function promptWirelessConnect(devId) {
        root._wirelessPromptDevId = devId || ""
        wirelessPromptProc.command = [
            "bash", "-c",
            "PREV_IP=$(jq -r '.phone.scrcpy.wirelessIp' " + root._shellQuote(Directories.shellConfigPath) + " 2>/dev/null || echo ''); "
            + "PREV_PORT=$(jq -r '.phone.scrcpy.wirelessPort' " + root._shellQuote(Directories.shellConfigPath) + " 2>/dev/null || echo '5555'); "
            + "if [ -z \"$PREV_PORT\" ] || [ \"$PREV_PORT\" = \"null\" ]; then PREV_PORT='5555'; fi; "
            + "if [ -z \"$PREV_IP\" ] || [ \"$PREV_IP\" = \"null\" ]; then PREV_VAL='192.168.1.50:5555'; else PREV_VAL=\"${PREV_IP}:${PREV_PORT}\"; fi; "
            + "if command -v kdialog >/dev/null 2>&1; then "
            + "  kdialog --inputbox \"Enter Device IP and Port:\" \"$PREV_VAL\" 2>/dev/null; "
            + "elif command -v zenity >/dev/null 2>&1; then "
            + "  zenity --entry --title=\"scrcpy Wireless\" --text=\"Enter Device IP and Port (IP:PORT):\" --entry-text=\"$PREV_VAL\" 2>/dev/null; "
            + "fi"
        ]
        wirelessPromptProc.running = true
    }

    Process {
        id: wirelessPromptProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim()
                if (!txt || txt === "") return
                
                let ip = txt
                let port = "5555"
                const colonIdx = txt.indexOf(":")
                if (colonIdx >= 0) {
                    ip = txt.substring(0, colonIdx).trim()
                    port = txt.substring(colonIdx + 1).trim()
                }
                
                if (ip !== "") {
                    if (Config.options.phone && Config.options.phone.scrcpy) {
                        Config.options.phone.scrcpy.wirelessIp = ip
                        Config.options.phone.scrcpy.wirelessPort = port
                        Config.options.phone.scrcpy.useWireless = true
                    }
                    root.launchScrcpy(root._wirelessPromptDevId, "wireless")
                }
            }
        }
    }

    function _shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function launchScrcpy(devId, mode, deepLink) {
        if (!devId) return

        // Pre-flight check: ADB must be reachable (USB debugging or wireless).
        // Without it, scrcpy has no device to connect to and the error is
        // just "unknown" — unhelpful. Early return with a descriptive message.
        if (!root.adbReachable) {
            const wirelessIp = Config.options.phone && Config.options.phone.scrcpy
                ? (Config.options.phone.scrcpy.wirelessIp || "").trim()
                : ""
            if (!wirelessIp || mode === "usb") {
                root.scrcpyLaunchError = Translation.tr("Phone not connected via ADB.\n\n"
                    + "To mirror your screen you need ADB access:\n"
                    + "  • USB: plug your phone AND enable USB debugging\n"
                    + "    (Settings → Developer options → USB debugging)\n"
                    + "  • Wireless: enable Wireless debugging in\n"
                    + "    Developer options, pair via ADB, then set\n"
                    + "    the IP in Phone → scrcpy settings.\n\n"
                    + "Scrcpy launches once ADB detects your phone.")
                root.actionFeedback(Translation.tr("scrcpy needs ADB — connect via USB or configure wireless"), false)
                return
            }
        }

        root.scrcpyLaunchError = ""
        // Instant UI feedback: turn on the launching flag before the
        // scrcpyStatusTimer has had a chance to poll pgrep. The flag is
        // cleared by checkScrcpyRunningProc.onExited once the process
        // is confirmed, or by scrcpyLaunchFallbackTimer after 10s.
        root.scrcpyLaunching = true
        scrcpyLaunchFallbackTimer.restart()
        const dev = root._findDevice(devId)
        const name = dev ? dev.name : ""
        const nick = "ii scrcpy - " + (name || devId)

        let scrcpyArgs = [
            "scrcpy",
            "--window-title=" + root._shellQuote(nick)
        ]

        // If a deep link is provided (from a notification intent), pass it as
        // --start-app=<package> when possible. scrcpy 3.0+ supports the
        // `--start-app=<package>` shorthand. For older versions we fall back
        // to adb am start BEFORE launching scrcpy (in the bash command).
        if (deepLink) {
            if (deepLink.package) {
                scrcpyArgs.push("--start-app=" + root._shellQuote(deepLink.package))
            } else if (deepLink.action) {
                // Will be dispatched via adb before scrcpy launches.
            }
        }

        let stayAwake = true
        let turnScreenOff = true
        let noPowerOn = true
        let noAudio = false
        let showTouches = false
        let fullscreen = false
        let alwaysOnTop = false
        let maxFps = 60
        let bitRate = "8M"
        let maxSize = 0
        let videoBuffer = 80
        let useWireless = false
        let wirelessIp = ""
        let wirelessPort = "5555"
        let showTerminal = false

        if (Config.options.phone && Config.options.phone.scrcpy) {
            const scrcpyConf = Config.options.phone.scrcpy
            stayAwake = scrcpyConf.stayAwake
            turnScreenOff = scrcpyConf.turnScreenOff
            noPowerOn = scrcpyConf.noPowerOn
            noAudio = scrcpyConf.noAudio
            showTouches = scrcpyConf.showTouches
            fullscreen = scrcpyConf.fullscreen
            alwaysOnTop = scrcpyConf.alwaysOnTop
            maxFps = scrcpyConf.maxFps
            bitRate = scrcpyConf.bitRate
            maxSize = scrcpyConf.maxSize
            videoBuffer = scrcpyConf.videoBuffer
            showTerminal = scrcpyConf.showTerminal

            if (mode === "wireless") {
                useWireless = true
                wirelessIp = scrcpyConf.wirelessIp
                wirelessPort = scrcpyConf.wirelessPort
            } else if (mode === "usb") {
                useWireless = false
            } else {
                useWireless = scrcpyConf.useWireless
                wirelessIp = scrcpyConf.wirelessIp
                wirelessPort = scrcpyConf.wirelessPort
            }
        }

        if (stayAwake) scrcpyArgs.push("--stay-awake")
        if (turnScreenOff) scrcpyArgs.push("--turn-screen-off")
        if (noPowerOn) scrcpyArgs.push("--no-power-on")
        if (noAudio) scrcpyArgs.push("--no-audio")
        if (showTouches) scrcpyArgs.push("--show-touches")
        if (fullscreen) scrcpyArgs.push("--fullscreen")
        if (alwaysOnTop) scrcpyArgs.push("--always-on-top")

        if (maxFps > 0) scrcpyArgs.push("--max-fps=" + maxFps)
        if (bitRate && bitRate !== "") scrcpyArgs.push("--video-bit-rate=" + bitRate)
        if (maxSize > 0) scrcpyArgs.push("--max-size=" + maxSize)
        if (videoBuffer > 0) scrcpyArgs.push("--video-buffer=" + videoBuffer)

        let wirelessHost = ""
        if (useWireless && wirelessIp && wirelessIp.trim() !== "") {
            const ip = wirelessIp.trim()
            const port = (wirelessPort && wirelessPort.trim() !== "") ? wirelessPort.trim() : "5555"
            if (ip.indexOf(":") < 0) {
                wirelessHost = ip + ":" + port
            } else {
                wirelessHost = ip
            }
        }

        let baseCmd = ""
        if (useWireless && wirelessHost !== "") {
            const quotedHost = root._shellQuote(wirelessHost)
            baseCmd = "adb connect " + quotedHost + " && "
            scrcpyArgs.push("--serial=" + quotedHost)
        }

        // Deep-link pre-launch: if we got an `am start` intent from a
        // notification action, dispatch it BEFORE scrcpy so the target
        // activity is in the foreground when the mirror window opens.
        let deepLinkCmd = ""
        if (deepLink && deepLink.action) {
            const actionArg = root._shellQuote(deepLink.action)
            const dataArg = deepLink.data ? " -d " + root._shellQuote(deepLink.data) : ""
            deepLinkCmd = "adb shell am start -a " + actionArg + dataArg + " >/dev/null 2>&1; "
        }

        const terminal = Config.options.apps.terminal || "kitty -1"
        const fullScrcpyCmd = deepLinkCmd + baseCmd + scrcpyArgs.join(" ")

        if (showTerminal) {
            const shellCmd = fullScrcpyCmd + " || { echo ''; echo 'scrcpy exited with error.'; echo 'Press Enter to close...'; read -r; }"
            Quickshell.execDetached([
                "bash", "-c",
                terminal + " -e sh -c " + root._shellQuote(shellCmd) + " &"
            ])
        } else {
            // Capture stderr so the notify-send shows the REAL error instead
            // of a generic "Failed to start" message. The previous generic
            // message made it impossible to diagnose why scrcpy was failing
            // (e.g., "device not found", "unknown option", ADB auth issues).
            // Enhanced: also check adb devices when stderr is empty, so the
            // user gets a human-readable hint instead of "unknown error".
            const shellCmd = "ERRFILE=$(mktemp); (" + fullScrcpyCmd + ") 2>\"$ERRFILE\" || { ERR=$(head -5 \"$ERRFILE\"); if [ -z \"$ERR\" ]; then ADB_DEVICES=$(adb devices 2>/dev/null | grep -v 'List of devices' | grep -v '^$' | wc -l); if [ \"$ADB_DEVICES\" = \"0\" ]; then HINT='No device detected via ADB.\nConnect via USB (USB debugging) or configure\nwireless debugging in Phone → scrcpy settings.'; else HINT='scrcpy exited but ADB is connected.\nCheck that the phone screen is unlocked and\nthe ADB authorization is accepted.'; fi; notify-send 'scrcpy Mirror' \"$HINT\" -i smartphone; else notify-send 'scrcpy Mirror' \"scrcpy failed:\n${ERR}\" -i smartphone; fi; }; rm -f \"$ERRFILE\""
            Quickshell.execDetached([
                "bash", "-c",
                shellCmd + " &"
            ])
        }
    }

    Connections {
        target: Persistent
        ignoreUnknownSignals: true
        function onReadyChanged() {
            if (Persistent.ready) {
                root._initNotificationsCache()
                if (Persistent.states.sidebar.policies.phone
                        && Persistent.states.sidebar.policies.phone.activeDeviceId) {
                    root.activeDeviceId =
                        Persistent.states.sidebar.policies.phone.activeDeviceId
                }
                root._sanitiseActiveDevice()
                // Restore the last seen notifications for the active device
                // while the DBus monitor is still handshaking.
                const cached = root._getCachedNotifications(root.activeDeviceId)
                if (cached.length > 0 && root.notifications.length === 0) {
                    root.notifications = cached
                }
            }
        }
    }

    Timer {
        id: cacheSaveTimer
        interval: 2000
        repeat: false
        onTriggered: root._saveNotificationsCache()
    }

    function _initNotificationsCache() {
        try {
            const raw = Persistent.states.sidebar.policies.phone
                            ? Persistent.states.sidebar.policies.phone.cachedNotificationsJson
                            : ""
            root._notificationsCache = raw ? JSON.parse(raw) : {}
        } catch (e) {
            root._notificationsCache = {}
        }
    }

    function _saveNotificationsCache() {
        if (!root.activeDeviceId) return
        const slim = root.notifications.map(n => ({
            publicId: n.publicId,
            appName: n.appName,
            summary: n.summary,
            body: n.body,
            ticker: n.ticker,
            time: n.time,
            package: n.package,
            replyId: n.replyId,
            replyPlaceholder: n.replyPlaceholder,
            dismissable: n.dismissable,
            iconPath: n.iconPath,
            actions: (n.actions || []).map(a => ({ key: a.key, label: a.label }))
        }))
        root._notificationsCache[root.activeDeviceId] = {
            timestamp: Date.now(),
            notifications: slim
        }
        if (Persistent.states.sidebar.policies.phone) {
            Persistent.states.sidebar.policies.phone.cachedNotificationsJson =
                JSON.stringify(root._notificationsCache)
        }
    }

    function _getCachedNotifications(devId) {
        if (!devId) return []
        const entry = root._notificationsCache[devId]
        return entry && Array.isArray(entry.notifications)
            ? root._normaliseNotifications(entry.notifications)
            : []
    }

    function killScrcpy() {
        // Only kill scrcpy MIRROR processes (ones with --window-title).
        // The PhoneMicService also uses scrcpy with --audio-source=mic and
        // --no-window; killing it here would silently stop the phone
        // microphone while the mic card still shows "running".
        //
        // Uses `for pid in $(pgrep ...)` instead of `pgrep | while read`
        // for the same reason as checkScrcpyRunningProc — the pipe form
        // runs in a subshell (though `kill $pid` works in a subshell,
        // we keep the pattern consistent).
        Quickshell.execDetached(["bash", "-c",
            "for pid in $(pgrep -x scrcpy 2>/dev/null); do " +
            "  if tr '\\0' ' ' < /proc/$pid/cmdline 2>/dev/null | grep -q -- '--window-title'; then " +
            "    kill $pid 2>/dev/null; " +
            "  fi; " +
            "done"])
        root.scrcpyRunning = false
        root.scrcpyLaunching = false
        root.scrcpyLaunchError = ""
        scrcpyLaunchFallbackTimer.stop()
    }

    /**
     * Raises the existing scrcpy SDL window on top of the Z stack without
     * relaunching the process. Falls back to launching scrcpy if the window
     * vanished (e.g., user closed it manually between poll and click).
     *
     * Uses `wmctrl` if available; otherwise falls back to
     * `hyprctl dispatch focuswindow` regex.
     */
    function focusScrcpyWindow() {
        Quickshell.execDetached(["bash", "-c",
            "if command -v wmctrl >/dev/null 2>&1; then " +
            "  wmctrl -a 'ii scrcpy' 2>/dev/null; " +
            "elif command -v hyprctl >/dev/null 2>&1; then " +
            "  hyprctl dispatch focuswindow '^(scrcpy)$' 2>/dev/null; " +
            "fi"
        ])
    }

    Timer {
        id: scrcpyStatusTimer
        interval: 10000
        running: root.ready && root._enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            checkScrcpyRunningProc.running = false
            checkScrcpyRunningProc.running = true
        }
    }

    // 1s tick for the scrcpy elapsed counter.
    Timer {
        id: scrcpyElapsedTicker
        interval: 1000
        repeat: true
        running: root.scrcpyRunning
        onTriggered: root.scrcpyElapsedMs += 1000
    }

    // Safety net: if 10s pass and the pgrep poller never detected scrcpy
    // running, drop the launching flag so the UI doesn't stay stuck in the
    // "active" state forever (happens if scrcpy failed to start, e.g.,
    // missing binary or ADB auth rejected).
    Timer {
        id: scrcpyLaunchFallbackTimer
        interval: 10000
        repeat: false
        onTriggered: root.scrcpyLaunching = false
    }

    Process {
        id: checkScrcpyRunningProc
        running: false
        // Detect scrcpy MIRROR processes only (have --window-title).
        // Skip scrcpy mic processes (have --no-window --audio-source=mic),
        // which are managed by PhoneMicService and must NOT set
        // scrcpyRunning=true (otherwise the mirror card shows as "active"
        // when the user only started the microphone).
        //
        // CRITICAL: use `for pid in $(pgrep ...)` instead of
        // `pgrep ... | while read pid`. The pipe form runs the while loop
        // in a SUBSHELL — `exit 0` inside it only exits the subshell, and
        // the main bash process always falls through to `exit 1`. This was
        // the root cause of scrcpy never being detected as running: the
        // check ALWAYS returned exit code 1, so `scrcpyRunning` never
        // became true and the card stayed stuck in "connecting" until the
        // 10s fallback timer cleared `scrcpyLaunching`.
        command: ["bash", "-c",
            "for pid in $(pgrep -x scrcpy 2>/dev/null); do " +
            "  if tr '\\0' ' ' < /proc/$pid/cmdline 2>/dev/null | grep -q -- '--window-title'; then " +
            "    exit 0; " +
            "  fi; " +
            "done; " +
            "exit 1"]
        onExited: (code, status) => {
            const now = (code === 0)
            if (now) {
                // scrcpy found — transition to "running". Clear the
                // launching flag and stop the fallback timer.
                if (!root.scrcpyRunning)
                    root.scrcpyElapsedMs = 0
                root.scrcpyRunning = true
                root.scrcpyLaunching = false
                root.scrcpyLaunchError = ""
                scrcpyLaunchFallbackTimer.stop()
            } else {
                // scrcpy NOT found. This could mean:
                //   a) scrcpy never started (failed, not installed, ADB auth
                //      rejected) — the scrcpyLaunchFallbackTimer (10s) will
                //      eventually clear scrcpyLaunching.
                //   b) scrcpy is still starting up (bash -c "..." & takes
                //      ~200-500ms before scrcpy appears in pgrep).
                //
                // Previously, this branch unconditionally cleared
                // scrcpyLaunching=false and STOPPED the fallback timer.
                // That caused a race: if the first pgrep fired within 1.5s
                // of launch (before scrcpy had appeared), the card would
                // immediately go from "connecting" back to "ready" — even
                // though scrcpy was about to start. The user saw the card
                // "lose its connection" while the scrcpy window was fine.
                //
                // Fix: do NOT clear scrcpyLaunching here. Only update
                // scrcpyRunning. The scrcpyLaunchFallbackTimer will clear
                // scrcpyLaunching after 10s if no pgrep ever succeeds.
                if (root.scrcpyRunning)
                    root.scrcpyElapsedMs = 0
                root.scrcpyRunning = false
            }
        }
    }
}

