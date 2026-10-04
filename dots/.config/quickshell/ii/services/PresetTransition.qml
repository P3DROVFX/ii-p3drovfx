pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

/**
 * PresetTransition — the single clock for applying a preset.
 *
 * Applying a preset rewrites config.json and colors.json together. Reacting to
 * that is heavy and mostly unavoidable: sections of the config change, panels
 * are destroyed and built (the bar becomes the vertical bar, the sidebars the
 * top layer, the island takes over the popups), and every new layer window
 * blocks the GUI thread for 40–100 ms until its first frame is up. Anything
 * animating through that work stutters, so the transition separates the two:
 *
 *   1. colors  — the bar and the dock slide off their edges
 *                (`presetWorkDeferred` keeps the config and a cached palette
 *                out until they are gone), then everything holds still
 *                (`presetHoldMotion`) while the config lands, the new panels
 *                are built and the new palette snaps in. Nothing on screen is
 *                moving, so the stalls read as a pause, not as lag.
 *   2. widgets — once all of that is done, garbage is collected and the GUI
 *                thread has gone quiet, the wallpaper transition plays and the
 *                background widgets leave, arrive and cascade into their new
 *                places (WidgetStateManager staggers them).
 *   3. bar     — the bar and the dock slide back in wearing the new style.
 *
 * The palette snaps instead of crossfading: a crossfade re-evaluates every
 * coloured binding in every window once per palette role per frame, 20–30 ms
 * a frame, which no amount of scheduling hides.
 *
 * The phase drives the flags on GlobalStates — `presetBarHidden` (the bar and
 * the dock leave), `presetRecoloring` (a palette arriving after the hold
 * crossfades rather than snaps), `presetHoldMotion` and `presetWorkDeferred`. They live on GlobalStates rather than
 * here because the bar, the widgets and the theme loader already react to that
 * singleton reliably; consumers bind to those, not to this.
 */
Singleton {
    id: root

    // "idle" | "colors" | "widgets" | "bar" | "done"
    property string phase: "idle"
    readonly property bool active: root.phase !== "idle" && root.phase !== "done"

    // Publish the phase as the flags the rest of the shell watches. Computed
    // from `phase` directly (not from a derived property) because a derived
    // property read inside this handler can still hold its pre-change value.
    onPhaseChanged: {
        GlobalStates.presetBarHidden = (root.phase === "colors" || root.phase === "widgets");
        GlobalStates.presetRecoloring = root.active;
        GlobalStates.presetHoldMotion = root.phase === "colors";
        if (root.phase !== "colors")
            GlobalStates.presetWorkDeferred = false;
    }

    signal started
    signal finished

    // Timings scale with the user's animation multiplier. Under reduced motion
    // there is no staging at all — everything just applies instantly, which is
    // what that setting asks for.
    readonly property real mult: Appearance.animMultiplier
    readonly property bool reduced: Appearance.reducedMotion

    // The bar has to be fully off its edge before anything heavy may land:
    // its slide (shellEdgeSlide) plus a frame of margin.
    readonly property int barOutMs: Appearance.animation.shellEdgeSlide.enterDuration + 34
    // The widget cascade (WidgetStateManager staggers at 60ms x index).
    readonly property int widgetsHold: Math.round(460 * root.mult)
    // The bar's slide back in (shellEdgeSlide.enterDuration is ~420ms).
    readonly property int barInHold: Math.round(460 * root.mult)
    // How long the hold waits for the new palette before moving without it;
    // a late palette still crossfades when it lands.
    readonly property int paletteWaitMs: 1500
    // A config that matches what is loaded produces no staged apply at all.
    readonly property int configWaitMs: 500
    // Never hold longer than this after the apply finished.
    readonly property int holdCapMs: 3500
    // Backstop: if applyFinished never arrives, do not leave the bar hidden.
    readonly property int safetyTimeout: 8000

    property double _beganAt: 0
    property double _appliedAt: 0
    property int _serialAtBegin: 0
    property int _paletteSerialAtBegin: 0
    property double _lastSettleTick: 0
    property int _quietTicks: 0
    property bool _collected: false

    // Called from PresetStore.applyPreset at click time — the earliest, most
    // reliable trigger. Re-entrant: clicking another preset mid-transition
    // keeps the bar out and the motion held, and waits for the newer apply.
    function begin() {
        if (root.reduced)
            return; // reduced motion: no staging, everything applies at once
        stageTimer.stop();
        settle.stop();
        safety.restart();
        root._beganAt = Date.now();
        root._appliedAt = 0;
        root._serialAtBegin = Config.externalApplySerial;
        root._paletteSerialAtBegin = MaterialThemeLoader.paletteSerial;
        root.phase = "colors";
        GlobalStates.presetWorkDeferred = true;
        barOutTimer.restart();
        root.started();
    }

    function _advance(next, hold) {
        root.phase = next;
        if (hold > 0) {
            stageTimer.interval = hold;
            stageTimer.restart();
        }
    }

    // presets.sh holds its full theming pass until this file exists.
    function _markSettled() {
        Quickshell.execDetached(["touch", `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/ii-preset-settled`]);
    }

    function _finish() {
        stageTimer.stop();
        settle.stop();
        safety.stop();
        if (root.phase === "idle")
            return;
        root.phase = "done";
        root.finished();
        root._markSettled();
        idleTimer.restart(); // drop back to idle on the next tick
    }

    // Whether the heavy part of the apply is over: the config has landed in
    // full, every panel it asks for exists, and the palette is in.
    function _workDone(now) {
        const sinceApply = now - root._appliedAt;
        if (now - root._beganAt < root.barOutMs)
            return false;
        if (Config.applyingExternal || !PanelSchedule.idle)
            return false;
        if (Config.externalApplySerial === root._serialAtBegin && sinceApply < root.configWaitMs)
            return false;
        return MaterialThemeLoader.paletteSerial !== root._paletteSerialAtBegin || sinceApply >= root.paletteWaitMs;
    }

    // Polls the hold. Its own tick gap doubles as a stall detector: deferred
    // work (deletions, first frames of new windows) still running shows up as
    // a late tick, and the hold waits for two on-time ticks in a row.
    Timer {
        id: settle
        interval: 50
        repeat: true
        onTriggered: {
            const now = Date.now();
            const onTime = now - root._lastSettleTick < settle.interval + 30;
            root._lastSettleTick = now;
            if (now - root._appliedAt >= root.holdCapMs) {
                root._advance("widgets", root.widgetsHold);
                settle.stop();
                return;
            }
            root._quietTicks = (onTime && root._workDone(now)) ? root._quietTicks + 1 : 0;
            if (root._quietTicks >= 2 && !root._collected) {
                // The hold leaves a lot of garbage behind (the old panels, the
                // staged config). Collect it now, while nothing moves, instead of
                // letting the collector run through the cascade; the late tick
                // this causes restarts the quiet count.
                root._collected = true;
                root._quietTicks = 0;
                gc();
                return;
            }
            if (root._quietTicks >= 2) {
                settle.stop();
                root._advance("widgets", root.widgetsHold);
            }
        }
    }

    // The staged countdown, reached once the hold has released.
    Timer {
        id: stageTimer
        repeat: false
        onTriggered: {
            if (root.phase === "widgets")
                root._advance("bar", root.barInHold);
            else if (root.phase === "bar")
                root._finish();
        }
    }

    // Let the deferred config in once the bar is off its edge.
    Timer {
        id: barOutTimer
        interval: root.barOutMs
        repeat: false
        onTriggered: GlobalStates.presetWorkDeferred = false
    }

    Timer {
        id: idleTimer
        interval: 32
        repeat: false
        onTriggered: if (root.phase === "done") root.phase = "idle"
    }

    Timer {
        id: safety
        interval: root.safetyTimeout
        repeat: false
        onTriggered: root._finish()
    }


    // The apply script has written config.json; start waiting for its work.
    Connections {
        target: PresetStore
        function onApplyFinished(name, ok) {
            if (!root.active) {
                // Reduced motion: nothing is animating, theme right away.
                root._markSettled();
                return;
            }
            if (!ok) {
                // A failed apply changed nothing; bring the bar straight back.
                root._finish();
                return;
            }
            if (root.phase !== "colors")
                return;
            root._appliedAt = Date.now();
            root._lastSettleTick = root._appliedAt;
            root._quietTicks = 0;
            root._collected = false;
            settle.restart();
        }
    }
}
