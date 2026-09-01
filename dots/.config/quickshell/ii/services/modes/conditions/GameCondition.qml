import QtQuick
import qs.services
import ".."

/**
 * A game is running (`when: running`) or focused (`when: focused`), as
 * judged by GameDetector. Holding the detector while this condition exists
 * is what turns GPU polling on for the fullscreen+GPU heuristic.
 */
ModeCondition {
    id: root
    readonly property bool wantFocused: root.params?.when === "focused"
    satisfied: root.wantFocused ? GameDetector.gameFocused : GameDetector.gameRunning
    reason: GameDetector.reason

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
    Component.onCompleted: root.syncHold()
    Component.onDestruction: {
        if (root.holding)
            GameDetector.release();
    }
}
