pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.modules.common

/**
 * The single answer to "is the island on, and what does it own?".
 *
 * That question used to be spelled out at every call site - nine of them, in the panel,
 * the panel family, GlobalStates, ShellModePolicy, the OSD and the top layer - and the
 * copies drifted: some forgot `centerInBar`, others forgot the per-activity toggle. A
 * surface that renders twice, or not at all, is the usual result.
 *
 * It also owns the quiet window, which is what keeps a boot, a hot reload or an unlock
 * from being mistaken for user activity.
 */
Singleton {
    id: root

    // Config may carry either the new `dynamicIsland` block or the legacy
    // `bar.floatingNotch` keys, so the engine does not depend on when the migration
    // lands. Both are read through these accessors and nowhere else.
    readonly property var legacy: Config.ready ? Config.options.bar.floatingNotch : null

    // The v23 migration already writes `Config.options.dynamicIsland`, but the legacy
    // notch surface and the current settings page still read and write
    // `bar.floatingNotch`. Reading the new block before they are ported would make every
    // toggle in Settings do nothing, so the switch is one flag, flipped when the
    // surfaces move over (phase 3+) and the old block is deleted with them.
    readonly property bool useModernSchema: false
    readonly property var modern: (root.useModernSchema && Config.ready) ? Config.options.dynamicIsland : null

    // Hug and the Dynamic Island bar style are the only ones that leave the island a
    // centre to sit in; see ShellModePolicy for why Float and Rect are refused. A config
    // edited by hand into that combination disables the island rather than rendering it
    // over the bar's widgets.
    readonly property bool barStyleSupportsCenterInBar: ShellModePolicy.centerInBarStyleSupported

    readonly property bool enabled: {
        if (!Config.ready)
            return false;
        if (root.modern)
            return root.modern.enable === true;
        if (root.legacy.enable === true)
            return true;
        return root.legacy.centerInBar === true && root.barStyleSupportsCenterInBar;
    }

    // "notch" is the legacy surface attached to the top edge; "pills" is the floating
    // cluster. Existing users keep the notch until they choose otherwise.
    readonly property string style: {
        if (!root.enabled)
            return "none";
        if (root.modern && root.modern.style)
            return root.modern.style;
        return "notch";
    }

    readonly property bool isNotch: root.style === "notch"
    readonly property bool isPills: root.style === "pills"

    // The notch can be drawn inside the bar's centre instead of floating below the edge.
    readonly property bool centerInBar: {
        if (!root.isNotch || !root.barStyleSupportsCenterInBar)
            return false;
        if (root.modern)
            return root.modern.notch && root.modern.notch.centerInBar === true;
        return root.legacy.centerInBar === true;
    }

    function widgetEnabled(id) {
        if (!root.enabled)
            return false;
        if (root.modern) {
            const widgets = root.modern.widgets;
            const entry = widgets ? widgets[id] : null;
            return !entry || entry.enable !== false;
        }
        // The legacy schema stores the inverse, one flat key per activity.
        const key = "disable" + id.charAt(0).toUpperCase() + id.slice(1);
        return root.legacy[key] !== true;
    }

    // Ownership. Each of these suppresses a standalone popup elsewhere in the shell, so
    // they must be read from here rather than re-derived.
    readonly property bool ownsNotifications: root.enabled && root.widgetEnabled("notification")
    readonly property bool ownsOsd: root.enabled && root.widgetEnabled("osd")
    readonly property bool ownsModeFlash: root.enabled
    readonly property bool ownsBluetoothPopup: root.enabled && root.widgetEnabled("bluetooth")
    readonly property bool ownsKeyboardPopup: root.enabled && root.widgetEnabled("keyboard")
    readonly property bool ownsLocalSendPopup: root.enabled && root.widgetEnabled("localSend")
    readonly property bool ownsSearch: root.enabled && !root.centerInBar && !GlobalStates.searchCenterMode

    // ── The quiet window ────────────────────────────────────────────────────────
    // A boot, a hot reload and an unlock all restore state in bulk: workspaces come back
    // from the lock's saved set, bluetooth devices reconnect, wifi re-associates, and the
    // Wayland selection is re-advertised (which makes cliphist store the same text again
    // under a new id). None of that is a user action. Sources that infer an event from
    // state must stay silent here; sources with a real cause - a hook, a genuinely new
    // clipboard entry - are unaffected.
    readonly property int quietWindowMs: (root.modern && root.modern.behavior && root.modern.behavior.quietWindowMs) ? root.modern.behavior.quietWindowMs : 1200
    property bool quietWindowActive: true

    function beginQuietWindow() {
        root.quietWindowActive = true;
        quietWindowTimer.interval = root.quietWindowMs;
        quietWindowTimer.restart();
    }

    property Timer quietWindowTimer: Timer {
        id: quietWindowTimer
        interval: root.quietWindowMs
        running: true
        repeat: false
        onTriggered: root.quietWindowActive = false
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked)
                root.beginQuietWindow();
        }
    }
}
