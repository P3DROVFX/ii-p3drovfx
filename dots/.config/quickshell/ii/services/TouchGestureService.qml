pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common

Singleton {
    id: root

    readonly property var opts:
        (Config.options && Config.options.interactions && Config.options.interactions.touchGestures)
            ? Config.options.interactions.touchGestures
            : null

    readonly property bool enabled:
        Config.ready && Boolean(root.opts && root.opts.enable)

    property string helperStatus: "stopped"
    property string helperError: ""
    property var devices: []

    // Gesture Recognizer States
    readonly property int stateIdle: 0
    readonly property int stateTracking: 1
    readonly property int stateQualified: 2
    readonly property int stateCooldown: 3

    property int gestureState: root.stateIdle

    // ── Multi-finger swipes ─────────────────────────────────────────────────
    // The touchpad's three-finger gestures, for a device that has no touchpad. The
    // single-contact recogniser above owns the edges and cancels itself the moment a second
    // finger lands, so the two never compete for the same touch.
    readonly property var multiOpts: (root.opts && root.opts.multiFinger) ? root.opts.multiFinger : null
    readonly property bool multiEnabled: root.enabled && Boolean(root.multiOpts && root.multiOpts.enable)
    readonly property int multiFingerCount: (root.multiOpts && root.multiOpts.fingers) ? root.multiOpts.fingers : 3
    readonly property real multiCommitDistance: (root.multiOpts && root.multiOpts.distance) ? root.multiOpts.distance : 90

    /// contactId -> { x, y }. Every allowed contact, whatever the recogniser is doing.
    property var multiPoints: ({})
    property bool multiArmed: false
    /// One action per hand-down. Without this a long swipe fires on every frame past the
    /// threshold, and a workspace change becomes ten.
    property bool multiFired: false
    property real multiStartX: 0
    property real multiStartY: 0
    property string multiScreenName: ""

    signal multiFingerSwipe(string direction, string actionId, string screenName)

    // Active Gesture Data
    property string activeDeviceId: ""
    property int activeContactId: -1
    property string activeOrigin: ""
    property string activeActionId: ""
    property string activeScreenName: ""

    /**
     * Whether `gestureStarted` has been emitted without a matching end.
     *
     * `gestureCancelled` used to be emitted only from the tracking and qualified states,
     * so every other route to `resetGestureState()` — the touch-up safety net, the
     * binary being deleted, a device disappearing — announced a gesture that listeners
     * then never heard the end of. The feedback overlay is the one that noticed: its pill
     * stayed on screen until the shell restarted.
     *
     * Every announced gesture now gets exactly one end signal, whichever way it ends.
     */
    property bool gestureAnnounced: false

    property real startX: 0
    property real startY: 0
    property real currentX: 0
    property real currentY: 0

    property real startTime: 0
    property real currentTime: 0

    property real primaryTravel: 0
    property real offAxisTravel: 0
    property real progress: 0

    property var velocitySamples: []
    property int activeContactCount: 0
    property bool waitForAllContactsUp: false

    // Signals for feedback overlay
    signal gestureStarted(string screenName, string origin, string actionId, real x, real y)
    signal gestureProgressChanged(string screenName, string origin, string actionId, real progress, real primaryTravel)
    signal gestureCancelled(string screenName, string origin, string actionId)
    signal gestureCommitted(string screenName, string origin, string actionId)

    // Calibration / Visual Overlay preview state
    property bool calibrating: false
    property string calibrationMode: ""
    property real calibrationValue: 0

    function startCalibration(mode, val) {
        calibrating = true;
        calibrationMode = mode;
        calibrationValue = val;
    }

    function updateCalibration(val) {
        calibrationValue = val;
    }

    function stopCalibration() {
        calibrating = false;
        calibrationMode = "";
        calibrationValue = 0;
    }

    Component.onCompleted: {
        root.checkBinary();
        console.log("[TouchGestures] Service initialized. enabled:", root.enabled);
    }

    // Fullscreen / Context detection
    function isFullscreenOnScreen(screenName) {
        try {
            var focusedName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
            if (focusedName === screenName) {
                if (ToplevelManager.activeToplevel?.wayland?.fullscreen) {
                    return true;
                }
                var mon = Hyprland.monitorFor(screenByName(screenName));
                if (mon && mon.activeWorkspace && HyprlandData && HyprlandData.windowList) {
                    var wsId = mon.activeWorkspace.id;
                    var fsWin = HyprlandData.windowList.find(w => w.workspace?.id === wsId && (w.fullscreen || (w.fullscreenMode !== undefined && w.fullscreenMode > 0)));
                    if (fsWin) return true;
                }
            }
        } catch (e) {}
        return false;
    }

    readonly property bool gesturesBlocked:
        GlobalStates.screenLocked
        || GlobalStates.regionSelectorOpen
        || GlobalStates.screenshotOverlayOpen
        || (root.opts && root.opts.disableInMediaMode && GlobalStates.isMediaModeActiveForScreen(activeScreenName))
        || (root.opts && root.opts.disableInFullscreen && isFullscreenOnScreen(activeScreenName))

    onGesturesBlockedChanged: {
        if (gesturesBlocked && gestureState !== root.stateIdle) {
            cancelActiveGesture("blocked");
        }
    }

    Timer {
        id: cooldownTimer
        interval: (root.opts && root.opts.cooldownMs) ? root.opts.cooldownMs : 250
        repeat: false
        onTriggered: root.resetGestureState()
    }

    // Safety net: a touch_up that never arrives (or arrives for a contact we are not
    // tracking) would otherwise pin the recognizer in "tracking" forever, leaving the
    // feedback indicator on screen and rejecting every later gesture.
    Timer {
        id: watchdogTimer
        interval: 4000
        repeat: false
        running: root.gestureState === root.stateTracking
        onTriggered: {
            console.warn("[TouchGestures] Watchdog: no touch up after", interval, "ms — forcing reset");
            root.cancelActiveGesture("watchdog-timeout");
            root.forgetContacts();
        }
    }

    // Contact bookkeeping lives outside the gesture state machine, so it needs an
    // explicit reset whenever the event stream is no longer trustworthy.
    function forgetContacts() {
        activeContactCount = 0;
        waitForAllContactsUp = false;
    }

    property bool binaryExists: false

    Process {
        id: checkBinaryProcess
        command: ["test", "-f", Directories.scriptPath + "/touchGestures/touch_gestures"]
        onExited: (code) => {
            root.binaryExists = (code === 0);
            if (root._checkPending) {
                root._checkPending = false;
                Qt.callLater(root.checkBinary);
            }
        }
    }

    /// A check asked for while one was already running.
    property bool _checkPending: false

    /// Never cancels a check in flight: killing a running `test` makes it exit non-zero,
    /// so a second caller arriving mid-check produced "missing" for a binary that was
    /// there. See the same note in OskAutoShow.
    function checkBinary() {
        if (Directories.scriptPath.length === 0)
            return;
        if (checkBinaryProcess.running) {
            root._checkPending = true;
            return;
        }
        checkBinaryProcess.running = true;
    }

    // Same reason as OskAutoShow's: the check gives up while the path is still empty, so
    // it has to run again when the path arrives rather than only at completion.
    readonly property string _scriptPath: Directories.scriptPath
    on_ScriptPathChanged: root.checkBinary()

    Process {
        id: deleteBinaryProcess
        command: ["rm", "-f", Directories.scriptPath + "/touchGestures/touch_gestures"]
        onExited: (code) => {
            root.binaryExists = false;
            root.cancelActiveGesture("binary-deleted");
            root.forgetContacts();
            root.devices = [];
            root.helperStatus = "stopped";
            console.log("[TouchGestures] Binary deleted.");
        }
    }

    function deleteBinary() {
        deleteBinaryProcess.running = false;
        Qt.callLater(() => {
            deleteBinaryProcess.running = true;
        });
    }

    // ── Building the helper ─────────────────────────────────────────────────
    /**
     * The daemon ships as source, and until this existed the page offered a command to
     * paste into a terminal.
     *
     * On a tablet that is circular: touch gestures are how you navigate a shell with no
     * keyboard, and the instruction for turning them on needed a keyboard. The keyboard's
     * own helper got a build button first; this is the same machinery, and the two are
     * the pair a fresh install has to get past.
     */
    readonly property RustHelperBuild helperBuild: RustHelperBuild {
        label: "TouchGestures"
        sourceDir: Directories.scriptPath + "/touchGestures/touch_gestures_src"
        binaryPath: Directories.scriptPath + "/touchGestures/touch_gestures"
        crateName: "touch_gestures"

        // `helperProcess` is bound to `enabled`, which the check below feeds, so
        // re-checking is the whole handover — the daemon starts without a restart.
        onFinished: ok => root.checkBinary()
    }

    readonly property bool building: root.helperBuild.building
    readonly property string buildResult: root.helperBuild.buildResult
    readonly property string buildOutput: root.helperBuild.buildOutput
    readonly property bool cargoAvailable: root.helperBuild.cargoAvailable
    /// Cargo's own narration, for a build that has to be watched rather than waited out.
    readonly property string buildProgress: root.helperBuild.progressText
    readonly property int buildUnits: root.helperBuild.unitsCompiled
    readonly property int buildSeconds: root.helperBuild.elapsedSeconds
    readonly property real buildProgressValue: root.helperBuild.progress

    function buildHelper() {
        root.helperBuild.build();
    }

    Process {
        id: helperProcess

        running: root.enabled && !GlobalStates.screenLocked && Directories.scriptPath.length > 0

        command: [
            Directories.scriptPath + "/touchGestures/touch_gestures"
        ]

        onStarted: {
            root.binaryExists = true;
            console.log("[TouchGestures] Process started:", command[0]);
        }

        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }

        stderr: SplitParser {
            onRead: line => console.warn("[TouchGestures-stderr]", line)
        }

        onExited: (code, status) => {
            console.log("[TouchGestures] Process exited. code:", code, "status:", status);
            root.cancelActiveGesture("helper-stopped");
            root.forgetContacts();
            root.devices = [];
            if (root.helperStatus !== "error") {
                root.helperStatus = "stopped";
            }
            root.checkBinary();
        }
    }

    function handleLine(line) {
        var event;
        try {
            event = JSON.parse(line);
        } catch (error) {
            console.warn("[TouchGestures] Invalid helper event:", line);
            return;
        }

        switch (event.type) {
        case "ready":
            helperStatus = "ready";
            helperError = "";
            console.log("[TouchGestures] Helper daemon ready");
            break;

        case "device_added":
            addDevice(event);
            break;

        case "device_removed":
            removeDevice(event.deviceId);
            break;

        case "touch_down":
            onTouchDown(event);
            break;

        case "touch_move":
            onTouchMove(event);
            break;

        case "touch_up":
            onTouchUp(event);
            break;

        case "touch_cancel":
            onTouchCancel(event);
            break;

        case "status":
            if (event.code === "no_touchscreen") {
                helperStatus = "no_touchscreen";
                console.log("[TouchGestures] Helper reported: no touchscreen");
            } else if (event.code === "permission_denied") {
                helperStatus = "permission_denied";
                console.warn("[TouchGestures] Permission denied opening /dev/input devices. Add user to 'input' group: sudo usermod -aG input $USER");
            }
            break;

        case "error":
            helperStatus = "error";
            helperError = event.code ? event.code : "unknown";
            console.warn("[TouchGestures] Helper error:", helperError);
            break;
        }
    }

    function addDevice(event) {
        var list = devices.slice();
        var existingIdx = -1;
        for (var i = 0; i < list.length; ++i) {
            if (list[i].deviceId === event.deviceId) {
                existingIdx = i;
                break;
            }
        }
        var entry = {
            deviceId: event.deviceId,
            name: event.name,
            path: event.path,
            kind: event.kind ? event.kind : "touch",
            isDesktopMapped: Boolean(event.isDesktopMapped)
        };
        if (existingIdx >= 0) {
            list[existingIdx] = entry;
        } else {
            list.push(entry);
        }
        devices = list;
        helperStatus = "ready";
        console.log("[TouchGestures] Device registered:", event.name, "(" + event.path + ") isDesktopMapped:", entry.isDesktopMapped);
    }

    function removeDevice(deviceId) {
        var list = [];
        for (var i = 0; i < devices.length; ++i) {
            if (devices[i].deviceId !== deviceId) {
                list.push(devices[i]);
            }
        }
        devices = list;
        if (devices.length === 0) {
            helperStatus = "no_touchscreen";
        }
        if (deviceId === activeDeviceId) {
            cancelActiveGesture("device-removed");
            forgetContacts();
        }
        console.log("[TouchGestures] Device removed:", deviceId);
    }

    function deviceKind(deviceId) {
        for (var i = 0; i < devices.length; ++i) {
            if (devices[i].deviceId === deviceId)
                return devices[i].kind ? devices[i].kind : "touch";
        }
        return "touch";
    }

    function deviceAllowed(deviceId) {
        // An explicitly picked device always wins, stylus included.
        if (root.opts && root.opts.deviceId && root.opts.deviceId !== "auto")
            return root.opts.deviceId === deviceId;

        // A pen is a pointer as well, so it drags and resizes windows while it swipes.
        // Keep it out of the recognizer unless the user asked for it.
        if (deviceKind(deviceId) === "pen")
            return Boolean(root.opts && root.opts.includeStylus);

        return true;
    }

    function screenByName(name) {
        for (var i = 0; i < Quickshell.screens.length; ++i) {
            if (Quickshell.screens[i].name === name) {
                return Quickshell.screens[i];
            }
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    function resolveScreenName() {
        if (root.opts && root.opts.targetMonitor && root.opts.targetMonitor !== "auto") {
            for (var i = 0; i < Quickshell.screens.length; ++i) {
                if (Quickshell.screens[i].name === root.opts.targetMonitor)
                    return root.opts.targetMonitor;
            }
        }

        if (Quickshell.screens.length === 1)
            return Quickshell.screens[0].name;

        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            return Hyprland.focusedMonitor.name;

        if (Quickshell.primaryScreen && Quickshell.primaryScreen.name)
            return Quickshell.primaryScreen.name;

        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    function effectiveTransform(screenName) {
        if (root.opts && root.opts.transform && root.opts.transform !== "auto") {
            var val = parseInt(root.opts.transform, 10);
            return isNaN(val) ? 0 : val;
        }
        if (HyprlandData && HyprlandData.monitors) {
            for (var i = 0; i < HyprlandData.monitors.length; ++i) {
                var m = HyprlandData.monitors[i];
                if (m.name === screenName) {
                    switch (m.transform) {
                    case 1: return 90;
                    case 2: return 180;
                    case 3: return 270;
                    default: return 0;
                    }
                }
            }
        }
        return 0;
    }

    function transformPoint(x, y, screenName) {
        var rot = effectiveTransform(screenName);
        switch (rot) {
        case 90:
            return Qt.point(1 - y, x);
        case 180:
            return Qt.point(1 - x, 1 - y);
        case 270:
            return Qt.point(y, 1 - x);
        default:
            return Qt.point(x, y);
        }
    }

    function isDeviceDesktopMapped(deviceId) {
        for (var i = 0; i < devices.length; ++i) {
            if (devices[i].deviceId === deviceId)
                return Boolean(devices[i].isDesktopMapped);
        }
        return false;
    }

    function getDesktopBounds() {
        var monitors = (HyprlandData && HyprlandData.monitors && HyprlandData.monitors.length > 0)
            ? HyprlandData.monitors
            : Quickshell.screens;

        if (!monitors || monitors.length === 0) {
            return { minX: 0, minY: 0, maxX: 1920, maxY: 1080, width: 1920, height: 1080 };
        }

        var minX = monitors[0].x;
        var minY = monitors[0].y;
        var maxX = monitors[0].x + monitors[0].width;
        var maxY = monitors[0].y + monitors[0].height;

        for (var i = 1; i < monitors.length; ++i) {
            var m = monitors[i];
            minX = Math.min(minX, m.x);
            minY = Math.min(minY, m.y);
            maxX = Math.max(maxX, m.x + m.width);
            maxY = Math.max(maxY, m.y + m.height);
        }

        return {
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            width: Math.max(1, maxX - minX),
            height: Math.max(1, maxY - minY)
        };
    }

    function resolveScreenAndCoords(deviceId, normX, normY) {
        var isDesktop = isDeviceDesktopMapped(deviceId);
        var explicitTarget = (root.opts && root.opts.targetMonitor && root.opts.targetMonitor !== "auto")
            ? root.opts.targetMonitor
            : "";

        var monitors = (HyprlandData && HyprlandData.monitors && HyprlandData.monitors.length > 0)
            ? HyprlandData.monitors
            : Quickshell.screens;

        if (!isDesktop || monitors.length <= 1) {
            var fallbackScreenName = explicitTarget ? explicitTarget : resolveScreenName();
            var fallbackScreen = screenByName(fallbackScreenName);
            if (!fallbackScreen) return null;
            var singlePt = transformPoint(normX, normY, fallbackScreenName);
            return {
                screenName: fallbackScreenName,
                screen: fallbackScreen,
                px: singlePt.x * fallbackScreen.width,
                py: singlePt.y * fallbackScreen.height
            };
        }

        // Multi-monitor desktop mapped space (e.g. OpenTabletDriver, virtual absolute digitizers)
        var bounds = getDesktopBounds();
        var globalX = bounds.minX + normX * bounds.width;
        var globalY = bounds.minY + normY * bounds.height;

        var targetMon = null;
        if (explicitTarget) {
            for (var i = 0; i < monitors.length; ++i) {
                if (monitors[i].name === explicitTarget) {
                    targetMon = monitors[i];
                    break;
                }
            }
        }

        if (!targetMon) {
            // Find which monitor contains (globalX, globalY)
            for (var j = 0; j < monitors.length; ++j) {
                var monCandidate = monitors[j];
                if (globalX >= monCandidate.x && globalX <= (monCandidate.x + monCandidate.width)
                    && globalY >= monCandidate.y && globalY <= (monCandidate.y + monCandidate.height)) {
                    targetMon = monCandidate;
                    break;
                }
            }
        }

        if (!targetMon) {
            // Fallback: closest monitor by center distance
            var bestDist = Infinity;
            for (var k = 0; k < monitors.length; ++k) {
                var mon = monitors[k];
                var monCenterX = mon.x + mon.width / 2;
                var monCenterY = mon.y + mon.height / 2;
                var dist = Math.hypot(globalX - monCenterX, globalY - monCenterY);
                if (dist < bestDist) {
                    bestDist = dist;
                    targetMon = mon;
                }
            }
        }

        if (!targetMon) return null;

        var chosenScreen = screenByName(targetMon.name);
        if (!chosenScreen) return null;

        var localX = Math.max(0, Math.min(chosenScreen.width, globalX - targetMon.x));
        var localY = Math.max(0, Math.min(chosenScreen.height, globalY - targetMon.y));

        var normLocalX = localX / chosenScreen.width;
        var normLocalY = localY / chosenScreen.height;
        var transformedPt = transformPoint(normLocalX, normLocalY, targetMon.name);

        return {
            screenName: targetMon.name,
            screen: chosenScreen,
            px: transformedPt.x * chosenScreen.width,
            py: transformedPt.y * chosenScreen.height
        };
    }

    function classifyOrigin(px, py, width, height) {
        var edge = (root.opts && root.opts.edgeWidth) ? root.opts.edgeWidth : 24;
        var corner = (root.opts && root.opts.cornerSize) ? root.opts.cornerSize : 72;

        if (px <= corner && py <= corner)
            return "topLeftCorner";

        if (px >= width - corner && py <= corner)
            return "topRightCorner";

        if (px <= corner && py >= height - corner)
            return "bottomLeftCorner";

        if (px >= width - corner && py >= height - corner)
            return "bottomRightCorner";

        if (px <= edge)
            return "leftEdge";

        if (px >= width - edge)
            return "rightEdge";

        if (py <= edge)
            return "topEdge";

        if (py >= height - edge)
            return "bottomEdge";

        // Anything else is the body of the screen. Unlike an edge this has no binding and
        // no fixed axis: it exists only so a family can claim a free 2D drag there — the
        // home screen swiping between workspaces. onTouchDown drops it unless a handler
        // has claimed it, so nothing changes for a family that has not.
        return "surface";
    }

    function actionForOrigin(origin) {
        // An edge a family drags never commits to a discrete action, so its binding does
        // not apply. Let the family name the drag instead, for the feedback overlay.
        const dragged = TouchGestureDragRegistry.actionId(origin);
        if (dragged)
            return dragged;

        var bindings = root.opts ? root.opts.bindings : null;
        if (!bindings) return "none";

        const bound = root.boundActionForOrigin(bindings, origin);
        // A binding pointing at a surface this family does not load would recognise the
        // swipe, commit it, and do nothing — which reads as a broken touchscreen rather
        // than a wrong setting. Treat it as unbound instead.
        if (!TouchGestureActionRegistry.availableForFamily(
                TouchGestureActionRegistry.actionById(bound), PanelFamily.current))
            return "none";
        return bound;
    }

    function boundActionForOrigin(bindings, origin) {

        switch (origin) {
        case "leftEdge": return bindings.leftEdge ? bindings.leftEdge : "none";
        case "rightEdge": return bindings.rightEdge ? bindings.rightEdge : "none";
        case "topEdge": return bindings.topEdge ? bindings.topEdge : "none";
        case "bottomEdge": return bindings.bottomEdge ? bindings.bottomEdge : "none";
        case "topLeftCorner": return bindings.topLeftCorner ? bindings.topLeftCorner : "none";
        case "topRightCorner": return bindings.topRightCorner ? bindings.topRightCorner : "none";
        case "bottomLeftCorner": return bindings.bottomLeftCorner ? bindings.bottomLeftCorner : "none";
        case "bottomRightCorner": return bindings.bottomRightCorner ? bindings.bottomRightCorner : "none";
        default: return "none";
        }
    }

    function calculateTravel(px, py) {
        var dx = px - startX;
        var dy = py - startY;
        var invSqrt2 = 0.7071067811865475;

        switch (activeOrigin) {
        case "surface":
            // No axis to lock to, so report the distance travelled along whichever axis is
            // longer and leave offAxis at zero. That keeps the direction-tolerance and
            // reverse-direction guards below inert for surface drags, where "backwards" is
            // a direction the handler may well want, rather than a cancelled gesture.
            return { primary: Math.max(Math.abs(dx), Math.abs(dy)), offAxis: 0 };
        case "leftEdge":
            return { primary: dx, offAxis: Math.abs(dy) };
        case "rightEdge":
            return { primary: -dx, offAxis: Math.abs(dy) };
        case "topEdge":
            return { primary: dy, offAxis: Math.abs(dx) };
        case "bottomEdge":
            return { primary: -dy, offAxis: Math.abs(dx) };
        case "topLeftCorner":
            return {
                primary: (dx + dy) * invSqrt2,
                offAxis: Math.abs(dx - dy) * invSqrt2
            };
        case "topRightCorner":
            return {
                primary: (-dx + dy) * invSqrt2,
                offAxis: Math.abs(dx + dy) * invSqrt2
            };
        case "bottomLeftCorner":
            return {
                primary: (dx - dy) * invSqrt2,
                offAxis: Math.abs(dx + dy) * invSqrt2
            };
        case "bottomRightCorner":
            return {
                primary: (-dx - dy) * invSqrt2,
                offAxis: Math.abs(dx - dy) * invSqrt2
            };
        default:
            return { primary: -dy, offAxis: Math.abs(dx) };
        }
    }

    function currentVelocity() {
        if (velocitySamples.length < 2)
            return 0;

        var first = velocitySamples[0];
        var last = velocitySamples[velocitySamples.length - 1];
        var dt = (last.time - first.time) / 1000;

        if (dt <= 0)
            return 0;

        return (last.distance - first.distance) / dt;
    }

    function multiActionFor(direction) {
        if (!root.multiOpts)
            return "none";
        if (direction === "left")
            return root.multiOpts.swipeLeft ?? "none";
        if (direction === "right")
            return root.multiOpts.swipeRight ?? "none";
        if (direction === "up")
            return root.multiOpts.swipeUp ?? "none";
        return root.multiOpts.swipeDown ?? "none";
    }

    function multiCentroid() {
        var sx = 0, sy = 0, n = 0;
        for (var key in root.multiPoints) {
            sx += root.multiPoints[key].x;
            sy += root.multiPoints[key].y;
            n++;
        }
        return n === 0 ? null : { x: sx / n, y: sy / n, count: n };
    }

    function multiReset() {
        root.multiPoints = ({});
        root.multiArmed = false;
        root.multiFired = false;
        root.multiScreenName = "";
    }

    function multiTrack(contactId, px, py, screenName) {
        root.multiPoints[contactId] = { x: px, y: py };
        if (screenName)
            root.multiScreenName = screenName;
    }

    function multiEvaluate() {
        if (!root.multiEnabled || root.multiFired)
            return;

        var centroid = root.multiCentroid();
        if (!centroid)
            return;

        // Exactly the configured number of fingers. A fourth landing mid-swipe is a
        // different gesture, not more of this one.
        if (centroid.count !== root.multiFingerCount) {
            if (root.multiArmed && centroid.count > root.multiFingerCount)
                root.multiFired = true;
            root.multiArmed = false;
            return;
        }

        if (!root.multiArmed) {
            root.multiArmed = true;
            root.multiStartX = centroid.x;
            root.multiStartY = centroid.y;
            return;
        }

        var dx = centroid.x - root.multiStartX;
        var dy = centroid.y - root.multiStartY;
        if (Math.max(Math.abs(dx), Math.abs(dy)) < root.multiCommitDistance)
            return;

        var direction = Math.abs(dx) > Math.abs(dy)
            ? (dx < 0 ? "left" : "right")
            : (dy < 0 ? "up" : "down");
        root.multiFired = true;
        root.multiCommit(direction);
    }

    function multiCommit(direction) {
        var actionId = root.multiActionFor(direction);
        if (!actionId || actionId === "none")
            return;
        if (gesturesBlocked) {
            console.log("[TouchGestures] Multi-finger swipe blocked by active modal/lockscreen");
            return;
        }

        // A binding pointing at a surface this family does not load would be recognised,
        // commit, and do nothing — which reads as the touchscreen being broken.
        var action = TouchGestureActionRegistry.actionById(actionId);
        if (!TouchGestureActionRegistry.availableForFamily(action, PanelFamily.current)) {
            console.log("[TouchGestures] Multi-finger", direction, "->", actionId,
                        "is not available on the", PanelFamily.current, "family");
            return;
        }

        var screenName = root.multiScreenName ? root.multiScreenName : root.resolveScreenName();
        console.log("[TouchGestures]", root.multiFingerCount + "-finger", direction,
                    "-> action:", actionId, "on screen:", screenName);
        root.multiFingerSwipe(direction, actionId, screenName);
        TouchGestureActionRegistry.trigger(actionId, screenName);
    }

    function onTouchDown(event) {
        // Filtered devices must not reach the contact counter either, or their unpaired
        // ups and downs would drift it away from the real number of fingers down.
        if (!deviceAllowed(event.deviceId))
            return;

        activeContactCount++;

        var multiResolved = root.multiEnabled ? resolveScreenAndCoords(event.deviceId, event.x, event.y) : null;
        if (multiResolved) {
            root.multiTrack(event.contactId, multiResolved.px, multiResolved.py, multiResolved.screenName);
            root.multiEvaluate();
        }

        if (activeContactCount > 1) {
            waitForAllContactsUp = true;
            if (gestureState !== root.stateIdle) {
                cancelActiveGesture("multitouch");
            }
            return;
        }

        if (!enabled || gestureState !== root.stateIdle || waitForAllContactsUp)
            return;

        var resolved = resolveScreenAndCoords(event.deviceId, event.x, event.y);
        if (!resolved)
            return;

        var screenName = resolved.screenName;
        var screen = resolved.screen;
        var px = resolved.px;
        var py = resolved.py;

        var origin = classifyOrigin(px, py, screen.width, screen.height);
        if (origin === "") {
            return;
        }

        // The body of the screen is not a gesture zone by default. Without this every touch
        // anywhere would arm the recogniser, and the shell would be tracking drags inside
        // application windows for nothing.
        if (origin === "surface" && !TouchGestureDragRegistry.claims(origin))
            return;

        var actionId = actionForOrigin(origin);
        if (!actionId || actionId === "none")
            return;

        if (gesturesBlocked) {
            console.log("[TouchGestures] Gestures blocked by active modal/lockscreen");
            return;
        }

        activeDeviceId = event.deviceId;
        activeContactId = event.contactId;
        activeOrigin = origin;
        activeActionId = actionId;
        activeScreenName = screenName;

        startX = px;
        startY = py;
        currentX = px;
        currentY = py;

        startTime = event.time;
        currentTime = event.time;

        primaryTravel = 0;
        offAxisTravel = 0;
        progress = 0;
        velocitySamples = [{ distance: 0, time: event.time }];

        gestureState = root.stateTracking;

        console.log("[TouchGestures] Gesture START on", screenName, ":", origin, "action:", actionId, "startX:", px.toFixed(0), "startY:", py.toFixed(0));
        gestureStarted(screenName, origin, actionId, px, py);
        root.gestureAnnounced = true;

        TouchGestureDragRegistry.begin(origin, screenName);
    }

    function onTouchMove(event) {
        // Before the single-contact filter: the hand's other fingers are not the active
        // contact and their movement is the whole gesture.
        if (root.multiEnabled && root.multiPoints[event.contactId] !== undefined) {
            var multiResolved = resolveScreenAndCoords(event.deviceId, event.x, event.y);
            if (multiResolved) {
                root.multiTrack(event.contactId, multiResolved.px, multiResolved.py, multiResolved.screenName);
                root.multiEvaluate();
            }
        }

        if (event.deviceId !== activeDeviceId || event.contactId !== activeContactId)
            return;

        if (gestureState !== root.stateTracking)
            return;

        var resolved = resolveScreenAndCoords(event.deviceId, event.x, event.y);
        if (!resolved)
            return;

        var px = resolved.px;
        var py = resolved.py;

        currentX = px;
        currentY = py;
        currentTime = event.time;

        var travel = calculateTravel(px, py);
        primaryTravel = travel.primary;
        offAxisTravel = travel.offAxis;

        if (primaryTravel < -8) {
            cancelActiveGesture("reverse-direction");
            return;
        }

        // Direction lock check after 16px
        if (primaryTravel > 16) {
            var angle = Math.atan2(travel.offAxis, Math.max(travel.primary, 0.001)) * 180 / Math.PI;
            var tol = (root.opts && root.opts.directionTolerance) ? root.opts.directionTolerance : 35;
            if (angle > tol) {
                cancelActiveGesture("direction-tolerance-exceeded");
                return;
            }
        }

        velocitySamples.push({ distance: primaryTravel, time: event.time });
        while (velocitySamples.length > 1 && event.time - velocitySamples[0].time > 80) {
            velocitySamples.shift();
        }

        var commitDist = (root.opts && root.opts.commitDistance) ? root.opts.commitDistance : 110;
        progress = Math.max(0, Math.min(1, primaryTravel / commitDist));

        gestureProgressChanged(activeScreenName, activeOrigin, activeActionId, progress, primaryTravel);

        // dx/dy as well as the scalar travel: an edge handler only needs how far along its
        // one axis the finger has gone, but a surface handler has to know which way.
        TouchGestureDragRegistry.update(activeOrigin, activeScreenName, primaryTravel,
                                        currentVelocity(), px - startX, py - startY);
    }

    function onTouchUp(event) {
        if (!deviceAllowed(event.deviceId))
            return;

        activeContactCount = Math.max(0, activeContactCount - 1);
        delete root.multiPoints[event.contactId];
        if (Object.keys(root.multiPoints).length === 0)
            root.multiReset();
        else
            root.multiArmed = false;
        if (activeContactCount === 0) {
            waitForAllContactsUp = false;
        }

        if (event.deviceId !== activeDeviceId || event.contactId !== activeContactId)
            return;

        if (gestureState !== root.stateTracking)
            return;

        var commitDist = (root.opts && root.opts.commitDistance) ? root.opts.commitDistance : 110;
        var minDist = (root.opts && root.opts.minDistance) ? root.opts.minDistance : 44;
        var velThreshold = (root.opts && root.opts.velocityThreshold) ? root.opts.velocityThreshold : 650;

        var vel = currentVelocity();

        // A family dragging this edge owns the release: it settles its own surface from
        // the velocity, and no discrete action fires.
        if (TouchGestureDragRegistry.release(activeOrigin, vel)) {
            enterCooldown();
            return;
        }

        var distanceCommit = primaryTravel >= commitDist;
        var flickCommit = primaryTravel >= minDist && vel >= velThreshold;

        if (distanceCommit || flickCommit) {
            commitGesture();
        } else {
            cancelActiveGesture("released-before-threshold (travel: " + primaryTravel.toFixed(0) + "px / needed: " + commitDist + "px)");
        }
    }

    function onTouchCancel(event) {
        if (!deviceAllowed(event.deviceId))
            return;

        activeContactCount = Math.max(0, activeContactCount - 1);
        delete root.multiPoints[event.contactId];
        if (Object.keys(root.multiPoints).length === 0)
            root.multiReset();
        else
            root.multiArmed = false;
        if (activeContactCount === 0) {
            waitForAllContactsUp = false;
        }

        if (event.deviceId === activeDeviceId && event.contactId === activeContactId) {
            cancelActiveGesture("cancelled");
        }
    }

    function commitGesture() {
        if (gestureState === root.stateIdle)
            return;

        var actionId = activeActionId;
        var screenName = activeScreenName;
        var origin = activeOrigin;

        console.log("[TouchGestures] Gesture COMMITTED:", origin, "-> action:", actionId, "on screen:", screenName);
        gestureCommitted(screenName, origin, actionId);
        root.gestureAnnounced = false;
        TouchGestureActionRegistry.trigger(actionId, screenName);

        enterCooldown();
    }

    function cancelActiveGesture(reason) {
        // The drag registry only knows about gestures that reached tracking, so its
        // cancel keeps the old guard. The *signal* does not: anyone told a gesture began
        // has to be told it ended, from whatever state it ends in.
        if (gestureState === root.stateTracking || gestureState === root.stateQualified)
            TouchGestureDragRegistry.cancel(activeOrigin);
        if (root.gestureAnnounced)
            console.log("[TouchGestures] Gesture CANCELLED:", reason);
        resetGestureState();
    }

    function enterCooldown() {
        gestureState = root.stateCooldown;
        cooldownTimer.restart();
    }

    function resetGestureState() {
        // Emitted before the fields are cleared, so listeners get the gesture's own
        // identity rather than empty strings. This is the single place every route out
        // of a gesture passes through, which is why the end signal lives here.
        if (root.gestureAnnounced) {
            root.gestureAnnounced = false;
            gestureCancelled(activeScreenName, activeOrigin, activeActionId);
        }
        gestureState = root.stateIdle;
        activeDeviceId = "";
        activeContactId = -1;
        activeOrigin = "";
        activeActionId = "";
        activeScreenName = "";
        startX = 0;
        startY = 0;
        currentX = 0;
        currentY = 0;
        primaryTravel = 0;
        offAxisTravel = 0;
        progress = 0;
        velocitySamples = [];
    }

    IpcHandler {
        target: "touchGestures"

        function trigger(actionId: string, screenName: string): void {
            var targetScreen = screenName ? screenName : resolveScreenName();
            TouchGestureActionRegistry.trigger(actionId, targetScreen);
        }

        function triggerAction(actionId: string): void {
            TouchGestureActionRegistry.trigger(actionId, resolveScreenName());
        }

        function triggerOrigin(origin: string): void {
            var targetScreen = resolveScreenName();
            var actionId = actionForOrigin(origin);
            if (actionId && actionId !== "none") {
                TouchGestureActionRegistry.trigger(actionId, targetScreen);
            }
        }

        function toggle(): void {
            if (root.opts) {
                root.opts.enable = !root.opts.enable;
            }
        }
    }
}
