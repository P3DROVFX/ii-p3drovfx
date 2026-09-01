pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    // Capabilities
    property bool available: false
    property string version: ""
    property int versionMajor: 0
    property int versionMinor: 0
    readonly property bool appModeSupported: available && versionMajor >= 4

    // Mirror Session
    property bool mirrorRunning: false
    property bool mirrorLaunching: false
    property int mirrorElapsedMs: 0
    property string mirrorLaunchError: ""

    // Apps Catalog
    property var apps: []
    property bool appsLoading: false
    property string appsError: ""
    property string appsSearchQuery: ""
    property var filteredApps: []

    // Active Sessions (Model: list of {id, type, package, title, pid, startedAt})
    property var sessions: []
    readonly property int sessionCount: sessions ? sessions.length : 0

    // Elapsed timer for active sessions
    Timer {
        id: mirrorElapsedTimer
        interval: 1000
        repeat: true
        running: root.mirrorRunning
        onTriggered: root.mirrorElapsedMs += 1000
    }

    Connections {
        target: KdeConnectService
        ignoreUnknownSignals: true
        function onActiveDeviceIdChanged() {
            root.refreshCapabilities()
            root.refreshApps()
        }
        function onAdbReachableChanged() {
            if (KdeConnectService.adbReachable) {
                root.refreshApps()
            }
        }
    }

    Component.onCompleted: {
        root.refreshCapabilities()
    }

    // The session manager only acts on commands written to its stdin: between them it sits in a
    // blocking read doing nothing. So it is started when there is a command to send and shut down
    // once it has been idle with no live session — never while one is running, since it owns those
    // scrcpy child processes and reports their exit.
    property bool _managerWanted: false
    readonly property bool _managerAllowed: (Config.options?.phone?.kdeconnectEnabled ?? true) && KdeConnectService.available

    function ensureManagerRunning(): void {
        if (!root._managerAllowed) return
        root._managerWanted = true
        managerIdleTimer.restart()
    }

    function _send(payload): void {
        if (!root._managerAllowed) return
        root.ensureManagerRunning()
        sessionManagerProc.write(JSON.stringify(payload) + "\n")
    }

    Timer {
        id: managerIdleTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (root.sessionCount === 0 && !root.mirrorLaunching && !root.appsLoading)
                root._managerWanted = false
        }
    }

    onSessionCountChanged: managerIdleTimer.restart()
    onAppsLoadingChanged: managerIdleTimer.restart()
    onMirrorLaunchingChanged: managerIdleTimer.restart()

    function refreshCapabilities(): void {
        scrcpyVersionProc.running = false
        scrcpyVersionProc.running = true
    }

    function refreshApps(): void {
        if (!appModeSupported) return
        root.appsLoading = true
        root.appsError = ""
        root.ensureManagerRunning()
        // Resolve the ADB target on demand: the phone's wireless-debugging
        // port can change between two polls of the 30s prober, and a stale
        // one silently lists zero apps.
        KdeConnectService.withAdbTarget(args => root._refreshApps(args))
    }

    function _refreshApps(targetArgs): void {
        const deviceId = KdeConnectService.activeDeviceId || "default"

        root._send({
            "cmd": "list_apps",
            "target_args": targetArgs,
            "deviceId": deviceId
        })
    }

    function setSearchQuery(query: string): void {
        root.appsSearchQuery = query
        root._updateFilteredApps()
    }

    function launchMirror(): void {
        if (root.mirrorRunning) {
            root.focusMirror()
            return
        }
        root.mirrorLaunching = true
        root.mirrorLaunchError = ""
        KdeConnectService.withAdbTarget(args => root._launchMirror(args))
    }

    function _launchMirror(targetArgs): void {
        const extraArgs = []

        const opts = Config.options?.phone?.scrcpy
        if (opts) {
            if (opts.stayAwake) extraArgs.push("--stay-awake")
            if (opts.turnScreenOff) extraArgs.push("--turn-screen-off")
            if (opts.noPowerOn) extraArgs.push("--no-power-on")
            if (opts.noAudio) extraArgs.push("--no-audio")
            if (opts.showTouches) extraArgs.push("--show-touches")
            if (opts.fullscreen) extraArgs.push("--fullscreen")
            if (opts.alwaysOnTop) extraArgs.push("--always-on-top")
            if (opts.maxFps > 0) extraArgs.push("--max-fps=" + opts.maxFps)
            if (opts.bitRate) extraArgs.push("--video-bit-rate=" + opts.bitRate)
            if (opts.maxSize > 0) extraArgs.push("--max-size=" + opts.maxSize)
            if (opts.videoBuffer > 0) extraArgs.push("--display-buffer=" + opts.videoBuffer)

            const appOpts = opts.appMode || {}
            if (appOpts.flexDisplay) {
                const w = appOpts.displayWidth || 1280
                const h = appOpts.displayHeight || 960
                const density = appOpts.density || 160
                extraArgs.push("--new-display=" + w + "x" + h + "/" + density)
                extraArgs.push("--flex-display")
                if (appOpts.keepActive) {
                    extraArgs.push("--keep-active")
                }
            }
        }

        root._send({
            "cmd": "launch",
            "id": "mirror",
            "type": "mirror",
            "target_args": targetArgs,
            "extra_args": extraArgs
        })
    }

    function stopMirror(): void {
        root._send({
            "cmd": "stop",
            "id": "mirror"
        })
    }

    function focusMirror(): void {
        root._send({
            "cmd": "focus",
            "id": "mirror"
        })
    }

    function launchApp(packageName: string): void {
        if (!packageName) return
        if (!appModeSupported) {
            KdeConnectService.dispatchActionFeedback(Translation.tr("scrcpy 4.0+ is required for App Mode"), false)
            return
        }

        if (root.isAppRunning(packageName)) {
            root.focusApp(packageName)
            return
        }

        KdeConnectService.withAdbTarget(args => root._launchApp(packageName, args))
    }

    function _launchApp(packageName: string, targetArgs): void {
        const sessionId = "app:" + packageName
        const appOpts = Config.options?.phone?.scrcpy?.appMode || {}
        const useFlex = appOpts.flexDisplay ?? false
        const w = appOpts.displayWidth || 1280
        const h = appOpts.displayHeight || 960
        const density = appOpts.density || 160

        const extraArgs = [
            "--start-app=" + packageName
        ]

        if (useFlex) {
            extraArgs.push("--new-display=" + w + "x" + h + "/" + density)
            extraArgs.push("--flex-display")
            if (appOpts.keepActive) {
                extraArgs.push("--keep-active")
            }
            if (appOpts.systemDecorations === false) {
                extraArgs.push("--no-vd-system-decorations")
            }
        }

        root._send({
            "cmd": "launch",
            "id": sessionId,
            "type": "app",
            "target_args": targetArgs,
            "extra_args": extraArgs
        })

        // Record in recents
        let recents = (Persistent.states?.phone?.scrcpy?.recentPackages || []).slice()
        const idx = recents.indexOf(packageName)
        if (idx >= 0) recents.splice(idx, 1)
        recents.unshift(packageName)
        if (recents.length > 20) recents = recents.slice(0, 20)
        Persistent.states.phone.scrcpy.recentPackages = recents

        KdeConnectService.dispatchActionFeedback(Translation.tr("Launching %1…").arg(packageName.split(".").pop()), true)
    }

    function stopApp(packageName: string): void {
        if (!packageName) return
        root._send({
            "cmd": "stop",
            "id": "app:" + packageName
        })
    }

    function focusApp(packageName: string): void {
        if (!packageName) return
        root._send({
            "cmd": "focus",
            "id": "app:" + packageName
        })
    }

    function restartApp(packageName: string): void {
        stopApp(packageName)
        Qt.callLater(() => root.launchApp(packageName))
    }

    function stopAllApps(): void {
        root._send({
            "cmd": "stop_all"
        })
    }

    function isAppRunning(packageName: string): bool {
        if (!packageName || !sessions) return false
        const id = "app:" + packageName
        for (let i = 0; i < sessions.length; i++) {
            if (sessions[i].id === id) return true
        }
        return false
    }

    function toggleAppFavorite(packageName: string): void {
        if (!packageName) return
        let favs = (Config.options?.phone?.scrcpy?.appMode?.favoritePackages || []).slice()
        const idx = favs.indexOf(packageName)
        if (idx >= 0) {
            favs.splice(idx, 1)
        } else {
            favs.push(packageName)
        }
        Config.options.phone.scrcpy.appMode.favoritePackages = favs
        root._updateFilteredApps()
    }

    function isAppFavorite(packageName: string): bool {
        if (!packageName) return false
        const favs = Config.options?.phone?.scrcpy?.appMode?.favoritePackages || []
        return favs.indexOf(packageName) >= 0
    }

    function _updateFilteredApps(): void {
        if (!apps) {
            filteredApps = []
            return
        }
        const q = appsSearchQuery.trim().toLowerCase()
        if (!q) {
            filteredApps = apps
            return
        }
        filteredApps = apps.filter(a => {
            if (!a) return false
            if (a.name && a.name.toLowerCase().includes(q)) return true
            if (a.package && a.package.toLowerCase().includes(q)) return true
            return false
        })
    }

    onAppsChanged: root._updateFilteredApps()

    // ─── scrcpy --version probe ──────────────────────────────
    Process {
        id: scrcpyVersionProc
        command: ["scrcpy", "--version"]
        running: false

        stdout: SplitParser {
            onRead: line => {
                const match = line.match(/^scrcpy\s+v?(\d+)\.(\d+)(?:\.(\d+))?/)
                if (match) {
                    root.available = true
                    root.versionMajor = parseInt(match[1])
                    root.versionMinor = parseInt(match[2])
                    root.version = match[1] + "." + match[2] + (match[3] ? "." + match[3] : "")
                }
            }
        }
    }

    // ─── Session Manager Process ──────────────────────────────
    Process {
        id: sessionManagerProc
        stdinEnabled: true
        command: ProcUtils.pdeath([
            "python3",
            Quickshell.shellPath("scripts/phone/scrcpy_session_manager.py")
        ])
        running: root._managerWanted && root._managerAllowed

        stdout: SplitParser {
            onRead: data => {
                try {
                    const msg = JSON.parse(data)
                    const ev = msg.event

                    if (ev === "apps_list") {
                        root.apps = msg.apps || []
                        root.appsLoading = false
                        root.appsError = ""
                    } else if (ev === "apps_error") {
                        root.appsLoading = false
                        root.appsError = msg.message || "Failed to list apps"
                    } else if (ev === "started") {
                        const sid = msg.id
                        if (sid === "mirror") {
                            root.mirrorRunning = true
                            root.mirrorLaunching = false
                            root.mirrorElapsedMs = 0
                        }
                        let curSessions = (root.sessions || []).slice()
                        const existingIdx = curSessions.findIndex(s => s.id === sid)
                        const sessionObj = {
                            id: sid,
                            type: msg.type || (sid === "mirror" ? "mirror" : "app"),
                            package: sid.startsWith("app:") ? sid.substring(4) : "",
                            title: msg.title || "",
                            pid: msg.pid || 0,
                            startedAt: Date.now()
                        }
                        if (existingIdx >= 0) {
                            curSessions[existingIdx] = sessionObj
                        } else {
                            curSessions.push(sessionObj)
                        }
                        root.sessions = curSessions

                    } else if (ev === "exited") {
                        const sid = msg.id
                        if (sid === "mirror") {
                            root.mirrorRunning = false
                            root.mirrorLaunching = false
                            if (msg.error && msg.code !== 0) {
                                root.mirrorLaunchError = msg.error
                                KdeConnectService.dispatchActionFeedback(Translation.tr("scrcpy mirror stopped: %1").arg(msg.error), false)
                            }
                        }
                        let curSessions = (root.sessions || []).filter(s => s.id !== sid)
                        root.sessions = curSessions

                    } else if (ev === "error") {
                        if (msg.id === "mirror") {
                            root.mirrorLaunching = false
                            root.mirrorLaunchError = msg.message || "scrcpy error"
                        }
                        KdeConnectService.dispatchActionFeedback(msg.message || "scrcpy session error", false)
                    }
                } catch (e) {
                    console.warn("[PhoneScrcpyService] JSON error:", e, "Data:", data)
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length > 0) {
                    console.warn("[PhoneScrcpyService stderr]", data)
                }
            }
        }
    }
}
