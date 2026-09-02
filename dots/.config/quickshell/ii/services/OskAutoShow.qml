pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

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

    // Keyboard bounds in 0..1 screen coordinates, published by OnScreenKeyboard.qml.
    // Normalized so it can be compared against helper coordinates without knowing
    // which output the touchscreen is mapped to.
    property rect keyboardBounds: Qt.rect(0, 0, 1, 1)
    property bool keyboardPinned: false

    // Whether the keyboard currently on screen is one *we* raised. A manually opened
    // or pinned keyboard is never closed behind the user's back.
    property bool autoShown: false

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
        if (kind === "touch") return root.opts?.allowTouch ?? true;
        return root.opts?.allowPen ?? true;
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
        const parts = line.trim().split(" ");
        if (parts.length === 0) return;

        switch (parts[0]) {
        case "activate":
            root.onActivate();
            break;
        case "deactivate":
            root.textInputActive = false;
            root.scheduleHide();
            break;
        case "touch":
        case "pen":
            root.onPointerPress(parts[0], parseFloat(parts[1]), parseFloat(parts[2]));
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

    Process {
        id: helper
        running: root.enabled && !GlobalStates.screenLocked
        command: [root.binaryPath]

        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }

        onRunningChanged: {
            if (helper.running) return;
            root.hideNow();
            root.lastPointerMs = -Infinity;
            root.pendingActivateMs = -Infinity;
            root.textInputActive = false;
        }
    }
}
