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
 * Applying a preset used to fire everything at once: config.json is rewritten,
 * ~967 properties re-deserialize, 48+ bar files, the widgets and the background
 * all re-evaluate their bindings in the same one or two frames, the palette
 * snaps, and switchwall's heavy colour work competes for the CPU on top. The
 * result is a visible freeze and a flash.
 *
 * This singleton turns that burst into a short, staged sequence so only one
 * thing moves at a time:
 *
 *   1. colors  — the palette (colors.json) crossfades and the wallpaper
 *                animates. The bar has already slid off its edge, so the heavy
 *                config reload lands while it is off-screen.
 *   2. widgets — the background widgets cascade into their new positions
 *                (WidgetStateManager already staggers them).
 *   3. bar     — the bar slides back in wearing the new style.
 *
 * The phase drives two flags on GlobalStates — `presetBarHidden` (the bar
 * slides off its edge) and `presetRecoloring` (the theme loader crossfades
 * rather than snaps). They live on GlobalStates rather than here because the
 * bar and the theme loader already react to that singleton reliably; consumers
 * bind to those, not to this. The countdown is anchored on the click (`begin`)
 * and on PresetStore.applyFinished, so a slow apply never brings the bar back
 * before the new config has actually landed.
 */
Singleton {
    id: root

    // "idle" | "colors" | "widgets" | "bar" | "done"
    property string phase: "idle"
    readonly property bool active: root.phase !== "idle" && root.phase !== "done"

    // Publish the phase as the two flags the rest of the shell watches. Computed
    // from `phase` directly (not from a derived property) because a derived
    // property read inside this handler can still hold its pre-change value.
    onPhaseChanged: {
        GlobalStates.presetBarHidden = (root.phase === "colors" || root.phase === "widgets");
        GlobalStates.presetRecoloring = root.active;
    }

    signal started
    signal finished

    // Timings scale with the user's animation multiplier. Under reduced motion
    // there is no staging at all — everything just applies instantly, which is
    // what that setting asks for.
    readonly property real mult: Appearance.animMultiplier
    readonly property bool reduced: Appearance.reducedMotion

    // The bar clears its edge, then the reload + relayout happen hidden.
    readonly property int reloadGateMs: Math.round(400 * root.mult)
    // The widget cascade (WidgetStateManager staggers at 60ms x index).
    readonly property int widgetsHold: Math.round(460 * root.mult)
    // The bar's slide back in (shellEdgeSlide.enterDuration is ~420ms).
    readonly property int barInHold: Math.round(460 * root.mult)
    // Backstop: if applyFinished never arrives, do not leave the bar hidden.
    readonly property int safetyTimeout: 6000

    // Called from PresetStore.applyPreset at click time — the earliest, most
    // reliable trigger. Re-entrant: clicking another preset mid-transition
    // pivots smoothly (the bar stays out, the palette loader pivots its own
    // crossfade) rather than snapping back.
    function begin() {
        if (root.reduced)
            return; // reduced motion: no staging, everything applies at once
        stageTimer.stop();
        reloadGate.stop();
        safety.restart();
        root.phase = "colors";
        root.started();
    }

    function _advance(next, hold) {
        root.phase = next;
        if (hold > 0) {
            stageTimer.interval = hold;
            stageTimer.restart();
        }
    }

    function _finish() {
        stageTimer.stop();
        reloadGate.stop();
        safety.stop();
        if (root.phase === "idle")
            return;
        root.phase = "done";
        root.finished();
        idleTimer.restart(); // drop back to idle on the next tick
    }

    // The staged countdown, reached once the apply has landed.
    Timer {
        id: stageTimer
        repeat: false
        onTriggered: {
            if (root.phase === "colors")
                root._advance("widgets", root.widgetsHold);
            else if (root.phase === "widgets")
                root._advance("bar", root.barInHold);
            else if (root.phase === "bar")
                root._finish();
        }
    }

    // Keep the bar out for the reload + relayout, then start the widget stage.
    Timer {
        id: reloadGate
        interval: root.reloadGateMs
        repeat: false
        onTriggered: if (root.phase === "colors") root._advance("widgets", root.widgetsHold)
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

    // Anchor the countdown on the real end of the apply script: config.json has
    // been written by now and the reload is milliseconds away.
    Connections {
        target: PresetStore
        function onApplyFinished(name, ok) {
            if (!root.active)
                return;
            if (!ok) {
                // A failed apply changed nothing; bring the bar straight back.
                root._finish();
                return;
            }
            reloadGate.restart();
        }
    }
}
