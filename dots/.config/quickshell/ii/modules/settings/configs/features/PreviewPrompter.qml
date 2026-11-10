pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * A stand-in teleprompter session for the Settings preview.
 *
 * The faces take a `prompter` and ask it for everything — layout, scroll,
 * phase — so the preview needs no special casing in them: this object answers
 * the same contract as the service, with the layout half delegated to the real
 * service (the preview shows the user's lines, size and speed as they change)
 * and a quiet demo session of its own for the motion. The demo always loops:
 * it has no end to reach, and it only ticks while the preview is on screen.
 *
 * A real session takes the stage over it — the preview binds
 * `Teleprompter.running ? Teleprompter : demo`.
 */
QtObject {
    id: demo

    // ── Layout: the real service's answers ──────────────────────────────────
    readonly property bool featureEnabled: true
    readonly property bool available: true
    readonly property int lines: Teleprompter.lines
    readonly property int expandedLines: Teleprompter.expandedLines
    readonly property int fontSize: Teleprompter.fontSize
    readonly property real lineHeightPx: Teleprompter.lineHeightPx
    readonly property int boxWidth: Teleprompter.boxWidth
    readonly property int compactBoxHeight: Teleprompter.compactBoxHeight
    readonly property real speed: Teleprompter.speed
    readonly property bool bold: Teleprompter.bold
    readonly property bool mirror: Teleprompter.mirror
    readonly property bool loop: Teleprompter.loop
    readonly property bool showProgress: Teleprompter.showProgress
    readonly property bool holdVisible: Teleprompter.holdVisible
    readonly property int countdownSeconds: 0
    readonly property string promptFontFamily: Teleprompter.promptFontFamily

    // ── The demo session ────────────────────────────────────────────────────
    property bool running: true
    property bool paused: false
    property string phase: "scrolling"
    property int countdownLeft: 0
    property string text: Translation.tr("This is how your script reads on the island. The preview runs its own quiet demo session, so a change to the lines, the size or the speed shows here first — and a real session, once started, takes this stage over.")
    property real scrollY: 0
    property real contentHeight: 0
    property real viewportHeight: 0
    readonly property real scrollExtent: Math.max(0, demo.contentHeight - demo.viewportHeight)
    readonly property real progress: demo.scrollExtent > 0 ? Math.min(1, demo.scrollY / demo.scrollExtent) : 1
    readonly property real remainingSeconds: demo.speed > 0 ? Math.max(0, (demo.scrollExtent - demo.scrollY) / demo.speed) : 0
    readonly property real totalSeconds: demo.speed > 0 ? demo.scrollExtent / demo.speed : 0

    /** Bound by the preview: a demo that is not on screen does not tick. */
    property bool visible: false

    property real _last: 0

    function advance(dtMs) {
        if (demo.phase !== "scrolling" || demo.paused || dtMs <= 0 || demo.scrollExtent <= 0)
            return;
        demo.scrollY += demo.speed * dtMs / 1000;
        if (demo.scrollY >= demo.scrollExtent)
            demo.scrollY = 0;
    }

    // A property, not a child: QtObject has no default property (the
    // TransientSource `_ttl` pattern).
    property Timer _tick: Timer {
        interval: 16
        repeat: true
        running: demo.visible && demo.running && demo.phase === "scrolling" && !demo.paused
        onTriggered: {
            const now = Date.now();
            const dt = demo._last > 0 ? Math.min(250, now - demo._last) : 0;
            demo._last = now;
            demo.advance(dt);
        }
    }

    function pause() {
        demo.paused = true;
    }
    function resume() {
        demo.paused = false;
        demo._last = 0;
    }
    function togglePause() {
        demo.paused = !demo.paused;
        demo._last = 0;
    }
    function restart() {
        demo.scrollY = 0;
        demo.paused = false;
    }
    function stop() {
        demo.restart();
    }
    function nudge(deltaPx) {
        if (demo.scrollExtent <= 0)
            return;
        demo.scrollY = Math.min(demo.scrollExtent, Math.max(0, demo.scrollY + deltaPx));
    }
    function adjustSpeed(delta) {
        Teleprompter.adjustSpeed(delta);
    }
    function reportLayout(contentHeight, viewportHeight) {
        demo.contentHeight = contentHeight;
        demo.viewportHeight = viewportHeight;
        demo.scrollY = Math.min(demo.scrollY, demo.scrollExtent);
    }
}
