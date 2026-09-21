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

    // The mirror the Phone sidebar draws inside itself. Same session manager,
    // same auto-resume, but its window is never meant to be looked at
    // directly — see PhoneMirrorService for what happens to it.
    readonly property string embedSessionId: "embed"
    property bool embedRunning: false
    property bool embedLaunching: false
    property string embedError: ""

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

    // Process.write() is thrown away while the child is still being spawned,
    // and `running` is already true by then — only processId/started tell the
    // two apart. So the very first command after the manager has idled out
    // used to vanish, which is precisely what a dock click is: the app list
    // gets away with it only because refreshApps() starts the manager seconds
    // before it sends anything.
    property var _pendingCommands: []

    function _send(payload): void {
        if (!root._managerAllowed) return
        root.ensureManagerRunning()
        const line = JSON.stringify(payload) + "\n"
        if (!sessionManagerProc.processId) {
            root._pendingCommands = root._pendingCommands.concat([line])
            return
        }
        sessionManagerProc.write(line)
    }

    Timer {
        id: managerIdleTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (root.sessionCount === 0 && !root.mirrorLaunching && !root.embedLaunching && !root.appsLoading)
                root._managerWanted = false
        }
    }

    onSessionCountChanged: managerIdleTimer.restart()
    onAppsLoadingChanged: managerIdleTimer.restart()
    onMirrorLaunchingChanged: managerIdleTimer.restart()
    onEmbedLaunchingChanged: managerIdleTimer.restart()

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

    /** Options that hold for any scrcpy session, mirror or single app. App
     *  windows used to build their command from the App Mode block alone, so
     *  "Turn screen off", "Stay awake" and every quality setting silently
     *  applied to the mirror only. */
    function _commonScrcpyArgs() {
        const opts = Config.options?.phone?.scrcpy
        if (!opts) return []

        const args = []
        if (opts.stayAwake) args.push("--stay-awake")
        if (opts.turnScreenOff) args.push("--turn-screen-off")
        if (opts.noPowerOn) args.push("--no-power-on")
        if (opts.noAudio) args.push("--no-audio")
        if (opts.showTouches) args.push("--show-touches")
        if (opts.fullscreen) args.push("--fullscreen")
        if (opts.alwaysOnTop) args.push("--always-on-top")
        if (opts.maxFps > 0) args.push("--max-fps=" + opts.maxFps)
        if (opts.bitRate) args.push("--video-bit-rate=" + opts.bitRate)
        if (opts.maxSize > 0) args.push("--max-size=" + opts.maxSize)
        // scrcpy 3.0 renamed --display-buffer to --video-buffer; the old
        // spelling makes scrcpy exit on a usage error instead of starting.
        if (opts.videoBuffer > 0) args.push("--video-buffer=" + opts.videoBuffer)
        // Locking must not flash the phone awake on the way out. Without this
        // scrcpy restores the screen power it had turned off, and only then
        // does the sleep land — so the panel lights up for a moment first.
        if (root._sessionEndMode() === "lock") args.push("--power-off-on-close")
        return args
    }

    function _launchMirror(targetArgs): void {
        const extraArgs = root._commonScrcpyArgs()

        const opts = Config.options?.phone?.scrcpy
        if (opts) {
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
                if (root._sessionEndMode() === "continue") {
                    extraArgs.push("--no-vd-destroy-content")
                }
            }
        }

        root._rememberSession("mirror", "mirror", extraArgs)
        root._send(root._launchPayload("mirror", "mirror", targetArgs, extraArgs))
    }

    function stopMirror(): void {
        root._markIntentionalStop("mirror")
        root._send({
            "cmd": "stop",
            "id": "mirror"
        })
    }

    function restartMirror(): void {
        root.stopMirror()
        root.mirrorLaunching = true
        restartMirrorTimer.restart()
    }

    Timer {
        id: restartMirrorTimer
        interval: 600
        repeat: false
        onTriggered: {
            root.mirrorLaunching = false
            root.launchMirror()
        }
    }

    function focusMirror(): void {
        root._send({
            "cmd": "focus",
            "id": "mirror"
        })
    }

    /** Starts the session the sidebar embeds. `streamSize` caps the encoded
     *  height to what the panel actually shows. */
    function launchEmbed(streamSize: int): void {
        if (root.embedRunning || root.embedLaunching) return
        root.embedLaunching = true
        root.embedError = ""
        KdeConnectService.withAdbTarget(args => root._launchEmbed(args, streamSize))
    }

    function _launchEmbed(targetArgs, streamSize): void {
        const extraArgs = root._embedScrcpyArgs(streamSize)
        root._rememberSession(root.embedSessionId, "embed", extraArgs)
        root._send({
            "cmd": "launch",
            "id": root.embedSessionId,
            "type": "embed",
            "target_args": targetArgs,
            "extra_args": extraArgs,
            // Never "lock": leaving the page must not put the phone to sleep.
            "end_action": "",
            "auto_unlock": Config.options?.phone?.scrcpy?.appMode?.autoUnlock ?? true
        })
    }

    /** Says the shell still wants the embedded session. The manager drops it
     *  when this stops arriving — see its keepalive watchdog for why a session
     *  with no window of its own needs one. */
    function keepEmbedAlive(): void {
        if (!root.embedRunning) return
        root._send({
            "cmd": "keepalive",
            "id": root.embedSessionId
        })
    }

    function stopEmbed(): void {
        root._markIntentionalStop(root.embedSessionId)
        root.embedLaunching = false
        root._send({
            "cmd": "stop",
            "id": root.embedSessionId
        })
    }

    /** The embedded window is positioned, sized and covered by the panel, so
     *  everything that would move or raise it is left out on purpose:
     *  --fullscreen, --always-on-top, the configured --max-size, and the
     *  --power-off-on-close that a "lock" session end would add. */
    function _embedScrcpyArgs(streamSize) {
        const args = ["--window-borderless"]
        if (streamSize > 0) args.push("--max-size=" + streamSize)

        const opts = Config.options?.phone?.scrcpy
        if (opts) {
            if (opts.stayAwake) args.push("--stay-awake")
            if (opts.turnScreenOff) args.push("--turn-screen-off")
            if (opts.noPowerOn) args.push("--no-power-on")
            if (opts.noAudio) args.push("--no-audio")
            if (opts.showTouches) args.push("--show-touches")
            if (opts.maxFps > 0) args.push("--max-fps=" + opts.maxFps)
            if (opts.bitRate) args.push("--video-bit-rate=" + opts.bitRate)
            if (opts.videoBuffer > 0) args.push("--video-buffer=" + opts.videoBuffer)
        }
        return args
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

    /** What the phone should be left doing once a session ends. */
    function _sessionEndMode(): string {
        const mode = Config.options?.phone?.scrcpy?.appMode?.onSessionEnd
        return (mode === "continue" || mode === "lock") ? mode : "home"
    }

    function _launchApp(packageName: string, targetArgs): void {
        const sessionId = "app:" + packageName
        const appOpts = Config.options?.phone?.scrcpy?.appMode || {}
        const useFlex = appOpts.flexDisplay ?? false
        const w = appOpts.displayWidth || 1280
        const h = appOpts.displayHeight || 960
        const density = appOpts.density || 160

        // A '+' force-stops the app before starting it. On a virtual display
        // that is mandatory: Android resumes an app that is already running in
        // its existing task, i.e. back on the phone's own screen, leaving the
        // new display showing nothing but Samsung DeX's launcher.
        const extraArgs = root._commonScrcpyArgs().concat([
            "--start-app=" + (useFlex ? "+" : "") + packageName
        ])

        if (useFlex) {
            extraArgs.push("--new-display=" + w + "x" + h + "/" + density)
            extraArgs.push("--flex-display")
            if (appOpts.keepActive) {
                extraArgs.push("--keep-active")
            }
            if (appOpts.systemDecorations === false) {
                extraArgs.push("--no-vd-system-decorations")
            }
            // Without this the virtual display takes the app down with it.
            if (root._sessionEndMode() === "continue") {
                extraArgs.push("--no-vd-destroy-content")
            }
        }

        root._rememberSession(sessionId, "app", extraArgs)
        root._send(root._launchPayload(sessionId, "app", targetArgs, extraArgs))

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
        root._markIntentionalStop("app:" + packageName)
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
        root.stopApp(packageName)
        // The relaunch has to wait for the stop to actually land: starting it
        // on the next tick would re-arm auto-resume before the deliberate
        // exit arrives, and that exit would then be treated as a crash.
        restartAppTimer.pkg = packageName
        restartAppTimer.restart()
    }

    Timer {
        id: restartAppTimer
        property string pkg: ""
        interval: 600
        repeat: false
        onTriggered: if (restartAppTimer.pkg) root.launchApp(restartAppTimer.pkg)
    }

    function stopAllApps(): void {
        const live = root.sessions || []
        for (let i = 0; i < live.length; i++) {
            if (live[i].type === "app") root._markIntentionalStop(live[i].id)
        }
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

    // ─── Session auto-resume ──────────────────────────────────
    // adbd restarts whenever the phone is unlocked: every ADB connection
    // drops for a few seconds and takes any live scrcpy with it, and a
    // virtual display destroys its content on the way out. Relaunching the
    // same session once the phone answers again is the only way a mirror or
    // a DeX window survives an unlock.

    // id -> {type, args} for every session that could be resumed.
    property var _sessionArgs: ({})
    // ids whose exit was asked for, so a deliberate stop is never undone.
    property var _intentionalStops: ({})
    // id -> {count, first}: a phone that refuses to come back must not be
    // retried forever.
    property var _resumeAttempts: ({})
    property var _resumeQueue: []

    readonly property int _maxResumeAttempts: 5

    function _launchPayload(sessionId, typeStr, targetArgs, extraArgs) {
        return {
            "cmd": "launch",
            "id": sessionId,
            "type": typeStr,
            "target_args": targetArgs,
            "extra_args": extraArgs,
            // "continue" is already carried by --no-vd-destroy-content; only
            // "lock" needs the manager to act after the window is gone.
            "end_action": root._sessionEndMode() === "lock" ? "lock" : "",
            "auto_unlock": Config.options?.phone?.scrcpy?.appMode?.autoUnlock ?? true
        }
    }

    function _rememberSession(sessionId, typeStr, extraArgs): void {
        root._sessionArgs[sessionId] = { "type": typeStr, "args": extraArgs }
        delete root._intentionalStops[sessionId]
    }

    function _markIntentionalStop(sessionId): void {
        root._intentionalStops[sessionId] = true
        root._resumeQueue = root._resumeQueue.filter(id => id !== sessionId)
    }

    function _forgetSession(sessionId): void {
        delete root._sessionArgs[sessionId]
        delete root._intentionalStops[sessionId]
        delete root._resumeAttempts[sessionId]
    }

    /** Queues `sessionId` for a relaunch if its exit looks like a dropped
     *  connection rather than something the user asked for. Returns whether
     *  the window is coming back. */
    function _maybeResume(sessionId, code): bool {
        if (root._intentionalStops[sessionId]) {
            root._forgetSession(sessionId)
            return false
        }
        // scrcpy keeps an exit code of its own for a lost connection (2).
        // Anything else is either the window being closed or a launch that
        // failed outright — a bad option, an app that is not there — and
        // that would fail the same way on every retry while the real error
        // stayed hidden behind "connection lost".
        if (code !== 2) {
            root._forgetSession(sessionId)
            return false
        }
        if (!(Config.options?.phone?.scrcpy?.autoResume ?? true)) return false
        if (!root._sessionArgs[sessionId]) return false

        const now = Date.now()
        let attempt = root._resumeAttempts[sessionId]
        if (!attempt || now - attempt.first > 120000) attempt = { "count": 0, "first": now }
        if (attempt.count >= root._maxResumeAttempts) {
            root._forgetSession(sessionId)
            KdeConnectService.dispatchActionFeedback(
                Translation.tr("Phone connection lost — could not reopen the window"), false)
            return false
        }
        attempt.count += 1
        root._resumeAttempts[sessionId] = attempt

        if (root._resumeQueue.indexOf(sessionId) < 0)
            root._resumeQueue = root._resumeQueue.concat([sessionId])
        return true
    }

    Timer {
        // Short: the session manager does the actual waiting now, holding the
        // relaunch until the phone answers, so retrying here is cheap.
        id: resumeTimer
        interval: 1000
        repeat: true
        running: root._resumeQueue.length > 0
        onTriggered: {
            const queued = root._resumeQueue.slice()
            root._resumeQueue = []
            for (let i = 0; i < queued.length; i++) root._resumeSession(queued[i])
        }
    }

    function _resumeSession(sessionId): void {
        const rec = root._sessionArgs[sessionId]
        if (!rec) return
        if (sessionId === "mirror") root.mirrorLaunching = true
        else if (sessionId === root.embedSessionId) root.embedLaunching = true
        // withAdbTarget re-resolves the target first: the port the session
        // died on is exactly the one that just changed.
        KdeConnectService.withAdbTarget(args => {
            if (!root._sessionArgs[sessionId]) return
            root._send(root._launchPayload(sessionId, rec.type, args, rec.args))
        })
    }

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

        onStarted: {
            const queued = root._pendingCommands
            root._pendingCommands = []
            for (let i = 0; i < queued.length; i++) sessionManagerProc.write(queued[i])
        }

        // Every session was this process' child, and nothing will report on
        // them again. Left as they were, a manager that died with a window
        // open kept the session count above zero forever: the idle timer
        // never let go of it, so it was never started again either.
        onExited: {
            root.sessions = []
            root.mirrorRunning = false
            root.mirrorLaunching = false
            root.embedRunning = false
            root.embedLaunching = false
            root.appsLoading = false
            const queued = root._pendingCommands.length > 0
            root._managerWanted = false
            // Commands that arrived while it was going down belong to the
            // next one; onStarted delivers them.
            if (queued) Qt.callLater(root.ensureManagerRunning)
        }

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
                        } else if (sid === root.embedSessionId) {
                            root.embedRunning = true
                            root.embedLaunching = false
                            root.embedError = ""
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

                    } else if (ev === "waiting") {
                        // The manager holds a launch back while the phone is
                        // unreachable or still locked; say so instead of
                        // leaving a dead-looking button.
                        if (msg.id === "mirror") root.mirrorLaunching = true
                        else if (msg.id === root.embedSessionId) root.embedLaunching = true
                        // Android draws the PIN pad on a FLAG_SECURE surface,
                        // so that window can only ever show black there. Input
                        // still reaches the phone, so the PIN can be typed
                        // blind — but only if the user is told to.
                        const waitText = msg.reason !== "locked"
                            ? Translation.tr("Waiting for the phone to reconnect…")
                            : !msg.unlockWindow
                                ? Translation.tr("Waiting for the phone to be unlocked…")
                                : msg.secure
                                    ? Translation.tr("Type your PIN in the window that opened — Android blanks the PIN screen, so it stays black")
                                    : Translation.tr("Unlock your phone in the window that just opened")
                        KdeConnectService.dispatchActionFeedback(waitText, true)

                    } else if (ev === "exited") {
                        const sid = msg.id
                        const asked = !!root._intentionalStops[sid]
                        const resuming = root._maybeResume(sid, msg.code)
                        // A drop that is about to be reopened is not worth a
                        // toast — the window comes back on its own — and
                        // neither is a stop the user asked for.
                        const failed = msg.error && msg.code !== 0 && !resuming && !asked
                        if (sid === "mirror") {
                            root.mirrorRunning = false
                            root.mirrorLaunching = resuming
                            if (failed) {
                                root.mirrorLaunchError = msg.error
                                KdeConnectService.dispatchActionFeedback(Translation.tr("scrcpy mirror stopped: %1").arg(msg.error), false)
                            }
                        } else if (sid === root.embedSessionId) {
                            root.embedRunning = false
                            root.embedLaunching = resuming
                            // The page shows this in place of the picture, so
                            // it does not also need a toast over the sidebar.
                            if (failed) root.embedError = msg.error
                        } else if (failed) {
                            // App windows used to die without a word.
                            KdeConnectService.dispatchActionFeedback(Translation.tr("%1 stopped: %2").arg(sid.substring(4).split(".").pop()).arg(msg.error), false)
                        }
                        let curSessions = (root.sessions || []).filter(s => s.id !== sid)
                        root.sessions = curSessions

                    } else if (ev === "error") {
                        if (msg.id === "mirror") {
                            root.mirrorLaunching = false
                            root.mirrorLaunchError = msg.message || "scrcpy error"
                        } else if (msg.id === root.embedSessionId) {
                            root.embedLaunching = false
                            root.embedError = msg.message || "scrcpy error"
                            return
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
