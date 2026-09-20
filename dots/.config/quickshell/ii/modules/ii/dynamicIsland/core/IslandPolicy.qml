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

    /**
     * The outer shell: "notch" (attached to the edge) or "island" (a floating pill).
     * Only the shell changes; the faces inside are the same.
     */
    readonly property string shape: {
        const value = (root.modern && root.modern.appearance && root.modern.appearance.shape)
            ? root.modern.appearance.shape
            : ((root.legacy && root.legacy.shape) ? root.legacy.shape : "notch");
        return value === "island" ? "island" : "notch";
    }

    /** Hover time before the expanded face opens; the contracted one shows at once. */
    readonly property int hoverExpandDelayMs: {
        if (root.modern && root.modern.behavior && root.modern.behavior.hoverExpandDelayMs !== undefined)
            return root.modern.behavior.hoverExpandDelayMs;
        return (root.legacy && root.legacy.hoverExpandDelayMs !== undefined) ? root.legacy.hoverExpandDelayMs : 600;
    }

    /**
     * Hold to reveal: the dashboard waits for the pointer to rest this long.
     *
     * Read from the new block directly rather than through `modern`/`legacy`, because it
     * has no legacy key to fall back to - the surfaces still on the old schema must see
     * the same value the toggle writes.
     */
    readonly property bool holdToReveal: Config.ready
        && (Config.options.dynamicIsland?.behavior?.holdToReveal === true)
    /** How long that hold is, in milliseconds. */
    readonly property int holdToRevealMs: {
        const value = Config.ready ? Config.options.dynamicIsland?.behavior?.holdToRevealMs : undefined;
        if (typeof value !== "number" || !isFinite(value))
            return 700;
        return Math.max(150, Math.min(3000, Math.round(value)));
    }

    /**
     * Click, not hover, opens an expanded face. Read here so the bubbles answer the
     * same setting the island does instead of re-deriving it from Config.
     */
    readonly property bool clickToExpand: {
        if (root.modern && root.modern.notch && root.modern.notch.clickToExpand !== undefined)
            return root.modern.notch.clickToExpand === true;
        return (root.legacy && root.legacy.clickToExpand === true) ?? false;
    }

    /**
     * How long a pointer rests on a surface before its expanded face opens.
     *
     * One answer for the island and for the bubbles. Hold to reveal *is* that question,
     * so when it is on its own length wins; the bubbles used to keep the plain hover
     * delay, which meant a hold set shorter than the delay opened the island first and
     * left the bubble sitting there. Click to expand is not a hover affordance, so it
     * falls back to the delay.
     */
    readonly property int revealDwellMs: (root.holdToReveal && !root.clickToExpand)
        ? root.holdToRevealMs : root.hoverExpandDelayMs

    /** Whether media and workspace changes may move out into the auxiliary bubble. */
    readonly property bool auxiliaryBubble: {
        if (root.modern && root.modern.behavior && root.modern.behavior.auxiliaryBubble !== undefined)
            return root.modern.behavior.auxiliaryBubble === true;
        return (root.legacy && root.legacy.auxiliaryBubble === true) ?? false;
    }

    /**
     * The activities a bubble may take, in the order they are seated when several
     * arrive together. Each gets its own slot; the first two take the island's right
     * and left, the rest chain outwards from them.
     */
    readonly property var bubbleActivities: ["media", "workspaces", "ai", "recording", "timer", "dictation", "mode"]

    /**
     * The activities that go straight out into a bubble instead of taking the island
     * first: all of them. Showing the island's face for a settle window and only then
     * moving it out made the island flash a widget the bubble was about to take.
     */
    readonly property var bubbleDirectActivities: root.bubbleActivities

    // Legacy key suffix per activity, where it differs from the id.
    readonly property var legacySuffixes: ({ "ai": "AiStatus", "clock": "Home" })

    function widgetEnabled(id) {
        if (!root.enabled)
            return false;
        if (root.modern) {
            const widgets = root.modern.widgets;
            const entry = widgets ? widgets[id] : null;
            return !entry || entry.enable !== false;
        }
        // The legacy schema stores the inverse, one flat key per activity. The
        // suffix comes from `legacySuffixes` like the heights always did: "ai" is
        // stored as `disableAiStatus`, and reading `disableAi` made the Settings
        // toggle for the AI notch write a key nothing ever read.
        const suffix = root.legacySuffixes[id] ?? (id.charAt(0).toUpperCase() + id.slice(1));
        return root.legacy["disable" + suffix] !== true;
    }

    // Ownership. Each of these suppresses a standalone popup elsewhere in the shell, so
    // they must be read from here rather than re-derived.
    readonly property bool ownsNotifications: root.enabled && root.widgetEnabled("notification")
    readonly property bool ownsOsd: root.enabled && root.widgetEnabled("osd")
    readonly property bool ownsModeFlash: root.enabled
    readonly property bool ownsBluetoothPopup: root.enabled && root.widgetEnabled("bluetooth")
    readonly property bool ownsKeyboardPopup: root.enabled && root.widgetEnabled("keyboard")
    readonly property bool ownsLocalSendPopup: root.enabled && root.widgetEnabled("localSend")
    /** Whether the drag panel offers a KDE Connect column beside LocalSend. */
    readonly property bool kdeConnectColumnEnabled: {
        if (root.modern) {
            const widgets = root.modern.widgets;
            const entry = widgets ? widgets.localSend : null;
            return !entry || entry.kdeConnectColumn !== false;
        }
        return root.legacy && root.legacy.disableKdeConnectInLocalSend !== true;
    }

    /**
     * The island is the search surface whenever it is enabled - in either shell mode and
     * in bar-centre mode too. It used to stand aside for bar-centre, so the same keybind
     * opened two different launchers depending on a setting unrelated to search.
     */
    readonly property bool ownsSearch: root.enabled
        && GlobalStates.classicOverviewOpen
        && !GlobalStates.searchCenterMode

    // Published so the other surfaces can suppress themselves without each re-deriving
    // the answer; see GlobalStates.islandOwnsSearch.
    property Binding _searchOwnership: Binding {
        target: GlobalStates
        property: "islandOwnsSearch"
        value: root.ownsSearch
        restoreMode: Binding.RestoreBindingOrValue
    }

    /**
     * The island draws the wallpaper picker, as one row inside itself, rather than the
     * full-screen selector opening over everything.
     *
     * Opt-out rather than opt-in: with the island on, a picker that takes the whole
     * screen to change one setting is the thing the island exists to replace. Turning
     * this off gives back the standalone selector, unchanged.
     */
    readonly property bool ownsWallpaper: root.enabled
        && (root.legacy ? root.legacy.integratedWallpaperBrowser !== false : true)

    /**
     * The island lays the workspace overview out itself: a small fixed grid below the
     * search field, opening with the island rather than playing the desktop overview's
     * entrance. The desktop overview's own settings are left alone - and disabled in
     * the settings page while this is on, since nothing would read them.
     */
    readonly property bool ownsOverview: root.enabled
        && (root.legacy ? root.legacy.integratedOverview !== false : true)

    property Binding _overviewOwnership: Binding {
        target: GlobalStates
        property: "islandOwnsOverview"
        value: root.ownsOverview
        restoreMode: Binding.RestoreBindingOrValue
    }

    /**
     * The island draws the session menu instead of the full-screen session screen.
     * Every entry point already sets `GlobalStates.sessionOpen`, so this is only about
     * which surface answers it.
     */
    readonly property bool ownsSession: root.enabled
        && (root.legacy ? root.legacy.integratedSessionMenu !== false : true)

    property Binding _sessionOwnership: Binding {
        target: GlobalStates
        property: "islandOwnsSession"
        value: root.ownsSession
        restoreMode: Binding.RestoreBindingOrValue
    }

    /** The island shows a picked colour and an incoming transfer, not a floating popup. */
    readonly property bool ownsColorPicker: root.enabled
        && (root.legacy ? root.legacy.integratedPopups !== false : true)
    readonly property bool ownsLocalSendRequest: root.enabled && root.widgetEnabled("localSend")
        && (root.legacy ? root.legacy.integratedPopups !== false : true)

    /** The island shows a connected device as the popup's own card. */
    readonly property bool ownsBluetoothCard: root.enabled && root.widgetEnabled("bluetooth")
        && (root.legacy ? root.legacy.integratedPopups !== false : true)

    property Binding _bluetoothCardOwnership: Binding {
        target: GlobalStates
        property: "islandOwnsBluetoothCard"
        value: root.ownsBluetoothCard
        restoreMode: Binding.RestoreBindingOrValue
    }

    /**
     * The island's dashboard is where the quick settings live while it is on, so a
     * surface wanting one of their pages must not open the right sidebar for it.
     */
    property Binding _dashboardOwnership: Binding {
        target: GlobalStates
        property: "islandOwnsDashboard"
        value: root.enabled
        restoreMode: Binding.RestoreBindingOrValue
    }

    property Binding _colorPickerOwnership: Binding {
        target: GlobalStates
        property: "islandOwnsColorPicker"
        value: root.ownsColorPicker
        restoreMode: Binding.RestoreBindingOrValue
    }
    property Binding _localSendRequestOwnership: Binding {
        target: GlobalStates
        property: "islandOwnsLocalSendRequest"
        value: root.ownsLocalSendRequest
        restoreMode: Binding.RestoreBindingOrValue
    }

    property Binding _wallpaperOwnership: Binding {
        target: GlobalStates
        property: "islandOwnsWallpaper"
        value: root.ownsWallpaper
        restoreMode: Binding.RestoreBindingOrValue
    }

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
