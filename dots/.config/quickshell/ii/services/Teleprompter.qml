pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The teleprompter: a user script scrolling through the Dynamic Island.
 *
 * One owner of the session (text, phase, scroll offset) and one reader of the
 * configuration (`dynamicIsland.widgets.teleprompter`, clamped here and nowhere
 * else). Both faces of the island activity — the contracted strip and the card
 * the hover grows — bind their text to `scrollY` from here, so the script keeps
 * its position across the morph instead of each face owning an animation.
 *
 * The engine is deliberately splittable: `advance(dtMs)` and `stepCountdown()`
 * are the whole of the motion, called by the two Timers below and directly by
 * the offscreen tests. The Timer measures wall-clock deltas rather than trusting
 * its interval, so a stalled compositor slows the scroll by the time that
 * actually passed instead of desyncing it.
 *
 * Two build facts shape the imports. One: in this quickshell build a file that
 * carries an IpcHandler only resolves the type when `Quickshell.Io` is also
 * imported — every other IpcHandler user in the tree (Cliphist, AlarmService,
 * SongRec, NotchIsland) imports it, and without it the whole services module
 * failed to compile. Two: this file does not import the island's core module;
 * `TeleprompterSource` pushes `IslandPolicy.enabled` into `islandEnabled` with
 * a Binding instead, so the service stays independent of any surface.
 *
 * Entry points (all just call `start()`):
 *   - Settings → Features → Teleprompter (script field, or the saved one)
 *   - the island's "Copied!" banner (`startFromClipboard()`)
 *   - the clipboard panel's action row and its per-entry drag handle
 *   - a text drop on the island (NotchIsland's DropArea)
 *   - IPC: `qs -c ii ipc call teleprompter start "text"`
 */
Singleton {
    id: root

    // ── Configuration, read once ─────────────────────────────────────────────
    readonly property var cfg: Config.ready ? Config.options.dynamicIsland.widgets.teleprompter : null
    readonly property bool featureEnabled: root.cfg ? root.cfg.enable !== false : false
    /**
     * Whether an island surface exists to draw the session. Pushed in by
     * `TeleprompterSource` (a Binding over `IslandPolicy.enabled`) — the service
     * itself must not import the island's core module; see the header.
     */
    property bool islandEnabled: false
    /** Set while a drag hovers the island's drop area; it holds the surface out. */
    property bool dragHovering: false
    /** The island exists and the feature is on: the entry points gate on this. */
    readonly property bool available: root.featureEnabled && root.islandEnabled

    readonly property int lines: Math.min(4, Math.max(1, root.cfg?.lines ?? 2))
    readonly property int expandedLines: Math.max(root.lines, Math.min(8, root.cfg?.expandedLines ?? 5))
    readonly property int fontSize: Math.min(48, Math.max(12, root.cfg?.fontSize ?? 22))
    /** Fixed line height, so the island's height is arithmetic the faces share. */
    readonly property real lineHeightPx: Math.round(root.fontSize * 1.35)
    /** The contracted box: exactly the configured lines, edge to edge — the
     * clip has no vertical margin, so a resting script fills the body and a
     * scrolling one is cut by the body's own edges, teleprompter-style. */
    readonly property int compactBoxHeight: Math.round(root.lines * root.lineHeightPx)
    readonly property int boxWidth: Math.min(1200, Math.max(280, root.cfg?.width ?? 520))
    /**
     * The hover card is always wider than the strip it grows from — wider, in
     * fact, than any width the strip can visually take: the hold-to-reveal
     * swell scales the body by 1.2 while it waits, and a card narrower than
     * the swell would read as the island shrinking when it opens.
     */
    readonly property int expandedBoxWidth: Math.min(1200, Math.round(root.boxWidth * 1.2) + 64)
    // Editing the saved script mid-session rewrites what is being read; the
    // faces re-measure on the next layout report and clamp the scroll.
    onSavedTextChanged: {
        if (root.running)
            root.text = root.savedText;
    }
    /** Reading speed, px/s. The range stays in the low, readable register: a
     * teleprompter is read, not skimmed. */
    readonly property real speedMin: 10
    readonly property real speedMax: 80
    readonly property real speed: Math.min(root.speedMax, Math.max(root.speedMin, root.cfg?.speed ?? 45))
    readonly property bool bold: root.cfg ? root.cfg.bold !== false : true
    readonly property bool mirror: root.cfg ? root.cfg.mirror === true : false
    readonly property bool loop: root.cfg ? root.cfg.loop === true : false
    readonly property bool showProgress: root.cfg ? root.cfg.showProgress !== false : true
    readonly property bool holdVisible: root.cfg ? root.cfg.holdVisible !== false : true
    readonly property int countdownSeconds: Math.min(10, Math.max(0, root.cfg?.countdownSeconds ?? 3))
    /** How long the finished script holds the island before giving it back. 0 keeps it until stopped by hand. */
    readonly property int finishHoldSeconds: Math.min(30, Math.max(0, root.cfg?.finishHoldSeconds ?? 4))
    readonly property string savedText: root.cfg?.text ?? ""
    /** The reading face: the shell's reading family, falling back to the main one. */
    readonly property string promptFontFamily: {
        const reading = Appearance.font.family.reading;
        return (reading !== undefined && reading !== "") ? reading : Appearance.font.family.main;
    }

    // ── Session state ────────────────────────────────────────────────────────
    property bool running: false
    property bool paused: false
    /** "idle" | "ready" | "countdown" | "scrolling" | "finished" */
    property string phase: "idle"
    property int countdownLeft: 0
    /** The script of the live session; `savedText` is only its default. */
    property string text: ""
    property real scrollY: 0

    /**
     * Reported by the faces whenever the script lays out: the full height of the
     * wrapped text, and the viewport showing it. The scroll extent — all there is
     * to travel — is the difference, so neither face carries geometry the other
     * has to agree with.
     */
    property real contentHeight: 0
    property real viewportHeight: 0
    readonly property real scrollExtent: Math.max(0, root.contentHeight - root.viewportHeight)
    readonly property real progress: root.scrollExtent > 0
        ? Math.min(1, Math.max(0, root.scrollY / root.scrollExtent))
        : (root.running && root.phase !== "countdown" && root.phase !== "ready" ? 1 : 0)
    readonly property real remainingSeconds: root.speed > 0 ? Math.max(0, (root.scrollExtent - root.scrollY) / root.speed) : 0
    readonly property real totalSeconds: root.speed > 0 ? root.scrollExtent / root.speed : 0

    /**
     * Begin a session. `withText` omitted (or null) reads the saved script.
     * Returns false when nothing can be shown: no island, feature off, empty text.
     */
    function start(withText) {
        const script = (withText === undefined || withText === null) ? root.savedText : String(withText);
        if (!root.available || script.trim().length === 0)
            return false;
        root.text = script;
        root.scrollY = 0;
        root.contentHeight = 0;
        root.viewportHeight = 0;
        root.paused = false;
        root.running = true;
        root.countdownLeft = root.countdownSeconds;
        root.phase = "ready";
        root._lastTick = 0;
        return true;
    }

    /** The clipboard's current text, the way the "Copied!" banner offers it. */
    function startFromClipboard() {
        return root.start(Quickshell.clipboardText ?? "");
    }

    /** Ready → countdown → scrolling: the reader's own gesture starts it. */
    function beginReading() {
        if (!root.running || root.phase !== "ready")
            return;
        root.countdownLeft = root.countdownSeconds;
        root.phase = root.countdownSeconds > 0 ? "countdown"
            : (root.scrollExtent <= 0 ? "finished" : "scrolling");
        root._lastTick = 0;
    }

    function stop() {
        root.running = false;
        root.paused = false;
        root.phase = "idle";
        root.scrollY = 0;
        root.text = "";
    }

    function pause() {
        if (root.running && (root.phase === "scrolling" || root.phase === "countdown"))
            root.paused = true;
    }

    function resume() {
        if (!root.running)
            return;
        if (root.phase === "ready") {
            root.beginReading();
            return;
        }
        root.paused = false;
        root._lastTick = 0;
    }

    /** Play/pause as one button: ready begins, finished restarts. */
    function togglePause() {
        if (!root.running)
            return;
        if (root.phase === "ready") {
            root.beginReading();
            return;
        }
        if (root.phase === "finished") {
            root.restart();
            return;
        }
        root.paused = !root.paused;
        root._lastTick = 0;
    }

    function restart() {
        if (!root.running)
            return;
        root.scrollY = 0;
        root.paused = false;
        root.countdownLeft = root.countdownSeconds;
        root.phase = root.countdownSeconds > 0 ? "countdown"
            : (root.scrollExtent <= 0 ? "finished" : "scrolling");
        root._lastTick = 0;
    }

    /** Manual travel (the wheel over the island), in pixels; sign = direction. */
    function nudge(deltaPx) {
        if (!root.running || root.phase === "countdown" || root.scrollExtent <= 0)
            return;
        root.scrollY = Math.min(root.scrollExtent, Math.max(0, root.scrollY + deltaPx));
        // Scrolling back up from the end reopens the session where it left off.
        if (root.phase === "finished" && root.scrollY < root.scrollExtent)
            root.phase = "scrolling";
    }

    /** The hover card's −/+ adjust the persisted speed, not just this session. */
    function adjustSpeed(delta) {
        if (!root.cfg)
            return;
        const next = Math.round(Math.min(root.speedMax, Math.max(root.speedMin, root.speed + delta)));
        if (next !== root.cfg.speed)
            root.cfg.speed = next;
    }

    function reportLayout(contentHeight, viewportHeight) {
        root.contentHeight = contentHeight;
        root.viewportHeight = viewportHeight;
        root.scrollY = Math.min(root.scrollY, root.scrollExtent);
        // A script that fits the face whole has nothing to travel: it is read the
        // moment it arrives.
        if (root.running && root.phase === "scrolling" && root.scrollExtent <= 0)
            root.phase = "finished";
    }

    // ── Engine ───────────────────────────────────────────────────────────────
    property real _lastTick: 0

    /** Move the script by one measured slice of time. Called by the tick Timer and by tests. */
    function advance(dtMs) {
        if (root.phase !== "scrolling" || root.paused || dtMs <= 0 || root.scrollExtent <= 0)
            return;
        root.scrollY += root.speed * dtMs / 1000;
        if (root.scrollY >= root.scrollExtent) {
            if (root.loop) {
                root.scrollY = 0;
            } else {
                root.scrollY = root.scrollExtent;
                root.phase = "finished";
            }
        }
    }

    Timer {
        id: ticker
        interval: 16
        repeat: true
        // The island's window is a fullscreen layer surface: a tick repaints all
        // of it, so the engine exists only while a session is actually scrolling.
        running: root.running && root.phase === "scrolling" && !root.paused
        onTriggered: {
            const now = Date.now();
            // The first tick after (re)starting has no delta; a resumed session
            // must not jump by the time it spent paused. Cap the slice so a
            // suspended compositor does not fast-forward the script either.
            const dt = root._lastTick > 0 ? Math.min(250, now - root._lastTick) : 0;
            root._lastTick = now;
            root.advance(dt);
        }
    }

    /** One step of the 3..2..1. Called by the countdown Timer and by tests. */
    function stepCountdown() {
        if (root.phase !== "countdown")
            return;
        root.countdownLeft -= 1;
        if (root.countdownLeft <= 0) {
            root.countdownLeft = 0;
            root._lastTick = 0;
            // A script that fits the face whole was already measured while the
            // countdown owned it: there is nothing to scroll into, so it is read
            // the moment the number clears — never a session parked on zero.
            root.phase = root.scrollExtent <= 0 ? "finished" : "scrolling";
        }
    }

    Timer {
        id: countdownTicker
        interval: 1000
        repeat: true
        running: root.running && root.phase === "countdown" && !root.paused
        onTriggered: root.stepCountdown()
    }

    /**
     * A finished script gives the island back: the reader is done, and an island
     * parked on a dead session never "goes back to normal". `finishHoldSeconds`
     * 0 keeps it up until stopped by hand.
     */
    property Timer _finishGrace: Timer {
        interval: Math.max(1, root.finishHoldSeconds) * 1000
        running: root.running && root.phase === "finished" && root.finishHoldSeconds > 0
        onTriggered: root.stop()
    }

    IpcHandler {
        target: "teleprompter"

        function start(text: string): bool {
            return root.start(text);
        }
        function startSaved(): bool {
            return root.start();
        }
        function stop(): void {
            root.stop();
        }
        function pause(): void {
            root.pause();
        }
        function resume(): void {
            root.resume();
        }
        function togglePause(): void {
            root.togglePause();
        }
        function restart(): void {
            root.restart();
        }
        /** A JSON snapshot of the session and the resolved layout, for scripts and tests. */
        function status(): string {
            return JSON.stringify({
                "available": root.available,
                "running": root.running,
                "paused": root.paused,
                "phase": root.phase,
                "countdownLeft": root.countdownLeft,
                "scrollY": Math.round(root.scrollY),
                "scrollExtent": Math.round(root.scrollExtent),
                "progress": root.progress,
                "lines": root.lines,
                "expandedLines": root.expandedLines,
                "fontSize": root.fontSize,
                "lineHeight": root.lineHeightPx,
                "speed": root.speed,
                "width": root.boxWidth,
                "compactHeight": root.compactBoxHeight,
                "mirror": root.mirror,
                "loop": root.loop,
                "textLength": root.text.length
            });
        }
    }
}
