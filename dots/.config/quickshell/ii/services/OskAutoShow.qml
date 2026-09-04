pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import "OskAutoShowProtocol.js" as OskProtocol

/**
 * Raises the on-screen keyboard when a text field is focused by finger or pen.
 *
 * Wayland reports *that* a text field was focused but not which device did it, so the
 * osk_autoshow helper reports both, and this singleton correlates them: an `activate`
 * only counts when a touch or pen press landed shortly before it. Mouse and keyboard
 * focus are ignored on purpose.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.osk?.autoShow ?? null
    /// Whether the user wants auto-show. Separate from `enabled`, which also needs the helper
    /// to exist — Settings shows the build instructions off the difference between the two.
    readonly property bool wanted: root.opts?.enable ?? true
    readonly property bool enabled: root.wanted && root.binaryExists

    /// The helper ships as source. Without this check, a fresh install spawns a process for a
    /// path that is not there on every config reload, and the only sign is a log line.
    property bool binaryExists: false
    readonly property string binaryPath: `${Directories.scriptPath}/osk/osk_autoshow`
    readonly property string sourcePath: `${Directories.scriptPath}/osk/osk_autoshow_src`

    Process {
        id: binaryCheck
        command: ["test", "-f", root.binaryPath]
        onExited: code => root.binaryExists = (code === 0)
    }

    function checkBinary() {
        if (Directories.scriptPath.length === 0)
            return;
        binaryCheck.running = false;
        Qt.callLater(() => binaryCheck.running = true);
    }

    Component.onCompleted: root.checkBinary()

    // ── Building the helper ─────────────────────────────────────────────────
    /**
     * Compiling the helper from inside the shell.
     *
     * This used to be a command in a box for the user to paste into a terminal, which is
     * the one thing a device with no keyboard cannot do — and the auto-show switch is
     * *the* feature that stands between such a device and a text field. So the build is a
     * button, and the binary check re-runs when it finishes: the helper process is bound
     * to `enabled`, so the keyboard starts raising itself the moment the build lands,
     * with no restart.
     *
     * The command is deliberately the same one the box printed, so a user who prefers the
     * terminal and a user who taps the button get identical results.
     */
    property bool building: false
    /// "" while nothing has been attempted this session, else "ok" or "failed".
    property string buildResult: ""
    /// Whatever cargo said when it failed. Empty on success — nobody reads a build log
    /// that worked, and keeping it around only invites showing it.
    property string buildOutput: ""
    /// No toolchain, no button: pointing someone at a build they cannot run is worse than
    /// telling them what is missing.
    property bool cargoAvailable: false

    Process {
        id: cargoCheck
        command: ["sh", "-c", "command -v cargo"]
        onExited: code => root.cargoAvailable = (code === 0)
        Component.onCompleted: running = true
    }

    Process {
        id: buildProcess
        // `sh -c` rather than an argv list because this is three steps — configure, build,
        // install — and the install has to be conditional on the build.
        //
        // Installed through a rename rather than a copy. By the time anyone rebuilds, the
        // previous helper is usually running, and writing over a running executable is
        // ETXTBSY — `cp` fails, the build reports failure, and the successful compile is
        // thrown away. A rename swaps the directory entry instead and leaves the running
        // process on the old inode until it exits, which it does the moment `enabled`
        // cycles below.
        command: ["sh", "-c",
            `cd '${root.sourcePath}' && cargo build --release`
            + ` && cp target/release/osk_autoshow '${root.binaryPath}.new'`
            + ` && mv -f '${root.binaryPath}.new' '${root.binaryPath}'`]

        stdout: StdioCollector { id: buildOut }
        stderr: StdioCollector { id: buildErr }

        onExited: code => {
            root.building = false;
            root.buildResult = code === 0 ? "ok" : "failed";
            root.buildOutput = code === 0 ? "" : (buildErr.text || buildOut.text || "").trim();
            if (code !== 0)
                console.warn(`[OskAutoShow] helper build failed (${code}): ${root.buildOutput}`);
            // What makes the button worth having: the helper is started off `enabled`,
            // which is `wanted && binaryExists`, so re-checking is the whole handover.
            root.checkBinary();
            // A rebuild leaves the old process running on the old inode. Cycling the
            // restart guard drops it and spawns the binary that was just installed.
            if (code === 0)
                root.restartHelper();
        }
    }

    function buildHelper() {
        if (root.building || Directories.scriptPath.length === 0)
            return;
        root.building = true;
        root.buildResult = "";
        root.buildOutput = "";
        buildProcess.running = false;
        Qt.callLater(() => buildProcess.running = true);
    }

    // Keyboard bounds in 0..1 screen coordinates, published by OnScreenKeyboard.qml.
    // Normalized so it can be compared against helper coordinates without knowing
    // which output the touchscreen is mapped to.
    property rect keyboardBounds: Qt.rect(0, 0, 1, 1)
    property bool keyboardPinned: false

    // Whether the keyboard currently on screen is one *we* raised. A manually opened
    // or pinned keyboard is never closed behind the user's back.
    property bool autoShown: false

    // ── What the helper can see ─────────────────────────────────────────────
    /**
     * The daemon's own inventory of pointing devices, reported once at startup.
     *
     * This exists because the failure was silent. A helper that can open no touchscreen
     * still binds the input method, still emits `activate`, and still never raises the
     * keyboard — identically to a helper that was never built, a switch that was never
     * turned on, and a machine with no touchscreen. Four different problems, one
     * symptom, and nothing anywhere distinguishing them.
     */
    property bool deviceReportReceived: false
    property int touchDeviceCount: 0
    property int penDeviceCount: 0
    property int mouseDeviceCount: 0
    /// At least one device that can actually fire the trigger, honouring the switches.
    readonly property bool anyTriggerDevice: OskProtocol.anyTriggerDevice({
        touch: root.touchDeviceCount,
        pen: root.penDeviceCount,
        mouse: root.mouseDeviceCount
    }, root.opts)
    /// /dev/input refused at least one device. Fixed by group membership, not by us.
    property bool permissionDenied: false

    property real lastPointerMs: -Infinity
    // An activate that arrived without a preceding touch. Kept briefly in case the
    // helper's touch line lands just after it.
    property real pendingActivateMs: -Infinity
    // Whether a text field is currently focused at the protocol level. Unlike
    // GlobalStates.oskOpen, this doesn't flip when we hide the keyboard for a touch
    // outside its bounds — the field stays focused, and no new `activate` line will
    // ever arrive to tell us that. Without this, a second tap in the same field would
    // be silently dropped instead of raising the keyboard back up.
    property bool textInputActive: false

    function show() {
        hideTimer.stop();
        // Already up by the user's own doing — don't take ownership of it.
        if (GlobalStates.oskOpen) return;
        root.autoShown = true;
        GlobalStates.oskOpen = true;
    }

    function scheduleHide() {
        if (!root.autoShown || root.keyboardPinned) return;
        hideTimer.restart();
    }

    function hideNow() {
        hideTimer.stop();
        if (!root.autoShown || root.keyboardPinned) return;
        root.autoShown = false;
        GlobalStates.oskOpen = false;
    }

    function pointerAllowed(kind) {
        return OskProtocol.pointerAllowed(kind, root.opts);
    }

    function outsideKeyboard(x, y) {
        const b = root.keyboardBounds;
        return x < b.x || x > b.x + b.width || y < b.y || y > b.y + b.height;
    }

    function onPointerPress(kind, x, y) {
        if (!root.pointerAllowed(kind)) return;
        const now = Date.now();
        root.lastPointerMs = now;

        // The helper's touch line normally precedes activate, but the two arrive on
        // different threads — honour a very recent activate that missed its window.
        // Also re-show for a field that's still focused: it won't send another
        // activate just because we hid the keyboard out from under it.
        if (!GlobalStates.oskOpen && (root.textInputActive || now - root.pendingActivateMs <= 300)) {
            root.pendingActivateMs = -Infinity;
            root.show();
            return;
        }

        if (!GlobalStates.oskOpen || !(root.opts?.hideOnTouchOutside ?? true)) return;
        // A still-focused field's own area counts as "outside keyboard bounds" too —
        // e.g. tapping it again to move the cursor. Let `deactivate` drive hiding
        // instead of guessing from touch position while the field is still active.
        if (root.textInputActive) return;
        // A relative pointer reports no position, so there is no "outside" to be on the
        // wrong side of. Hiding on every click would close the keyboard the first time
        // someone used the mouse for anything at all.
        if (kind === "mouse") return;
        if (root.outsideKeyboard(x, y)) root.scheduleHide();
    }

    function onActivate() {
        root.textInputActive = true;

        // Tapping straight from one text field into another emits deactivate then
        // activate; cancelling the pending hide keeps the keyboard from flickering.
        hideTimer.stop();

        if (Date.now() - root.lastPointerMs <= (root.opts?.touchWindowMs ?? 1200)) {
            root.show();
            return;
        }
        root.pendingActivateMs = Date.now();
    }

    function handleLine(line) {
        const event = OskProtocol.parseLine(line);

        switch (event.kind) {
        case "activate":
            root.onActivate();
            break;
        case "deactivate":
            root.textInputActive = false;
            root.scheduleHide();
            break;
        case "pointer":
            root.onPointerPress(event.pointer, event.x, event.y);
            break;
        // How many pointing devices the helper could actually open. Reported once at
        // startup so "nothing happens" can say which of its causes it is: a machine with
        // no touchscreen, or /dev/input we are not allowed to read.
        case "devices":
            root.touchDeviceCount = event.touch;
            root.penDeviceCount = event.pen;
            root.mouseDeviceCount = event.mouse;
            root.deviceReportReceived = true;
            if (!root.anyTriggerDevice) {
                console.warn("[OskAutoShow] no touchscreen or pen found;"
                    + " nothing can raise the keyboard until one appears"
                    + " (or the mouse trigger is switched on)");
            }
            break;
        case "denied":
            root.permissionDenied = true;
            console.warn("[OskAutoShow] /dev/input is not readable; add this user to the input group");
            break;
        case "key":
            if (root.opts?.hideOnPhysicalKey ?? true) root.hideNow();
            break;
        case "unavailable":
            console.warn("[OskAutoShow] another input method holds the seat; auto-show disabled");
            break;
        }
    }

    // Grace period so field-to-field taps and app-driven focus churn don't flicker
    // the keyboard away and straight back.
    Timer {
        id: hideTimer
        interval: 150
        onTriggered: root.hideNow()
    }

    // A keyboard the user dismissed by hand is no longer ours to manage.
    Connections {
        target: GlobalStates

        function onOskOpenChanged() {
            if (!GlobalStates.oskOpen) root.autoShown = false;
        }
    }

    /// Held false for one tick to make the helper Process stop and start again.
    property bool _restarting: false

    function restartHelper() {
        root._restarting = true;
        Qt.callLater(() => root._restarting = false);
    }

    Process {
        id: helper
        running: root.enabled && !GlobalStates.screenLocked && !root._restarting
        command: [root.binaryPath]

        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }

        onRunningChanged: {
            if (helper.running) {
                // A fresh process reports its own inventory; the previous one's is stale.
                root.deviceReportReceived = false;
                root.permissionDenied = false;
                return;
            }
            root.hideNow();
            root.lastPointerMs = -Infinity;
            root.pendingActivateMs = -Infinity;
            root.textInputActive = false;
        }
    }
}
