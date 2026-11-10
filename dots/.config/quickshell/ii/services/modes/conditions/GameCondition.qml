import QtQuick
import qs.services
import ".."
import "../ModeSchema.js" as ModeSchema

/**
 * A game is running (`when: running`) or focused (`when: focused`), as
 * judged by GameDetector. Holding the detector while this condition exists
 * is what turns GPU polling on for the fullscreen+GPU heuristic.
 *
 * Reads the detector's undelayed verdict and keeps counting `offSec` after
 * it drops (ModeSchema.gameOffSec), so each mode picks its own delay.
 */
ModeCondition {
    id: root
    readonly property bool wantFocused: root.params?.when === "focused"
    readonly property bool raw: root.wantFocused ? GameDetector.rawFocused : GameDetector.rawRunning
    readonly property int offMs: ModeSchema.gameOffSec(root.params) * 1000
    property bool lingering: false
    satisfied: root.raw || root.lingering

    property Timer offTimer: Timer {
        interval: Math.max(1, root.offMs)
        repeat: false
        onTriggered: root.lingering = false
    }

    function sync() {
        if (root.raw) {
            root.offTimer.stop();
            root.lingering = true;
            root.reason = GameDetector.primaryMatch?.reason ?? root.reason;
        } else if (root.offMs > 0 && root.lingering) {
            root.offTimer.restart();
        } else {
            root.offTimer.stop();
            root.lingering = false;
        }
    }
    onRawChanged: root.sync()
    onOffMsChanged: root.sync()

    property Connections detectorWatch: Connections {
        target: GameDetector
        function onPrimaryMatchChanged() {
            if (root.raw && GameDetector.primaryMatch)
                root.reason = GameDetector.primaryMatch.reason;
        }
    }

    // Hold the detector only while this can actually start something.
    property bool holding: false
    function syncHold() {
        if (root.armed === root.holding)
            return;
        root.holding = root.armed;
        if (root.holding)
            GameDetector.acquire();
        else
            GameDetector.release();
    }
    onArmedChanged: root.syncHold()
    Component.onCompleted: {
        root.syncHold();
        root.sync();
    }
    Component.onDestruction: {
        if (root.holding)
            GameDetector.release();
    }
}
