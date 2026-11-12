import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Keeps Hyprland from warping the pointer to a window's centre while a card is
 * dragged in the overview. The drop dispatches move/swap, which focus the
 * window and would otherwise teleport the cursor out from under the user.
 */
Item {
    id: root

    property bool suspended: false

    // Hyprland applies the drop dispatches asynchronously, so warps stay off a moment longer.
    property int releaseDelay: 600

    property bool engaged: false

    onSuspendedChanged: {
        if (root.suspended) {
            releaseTimer.stop();
            if (!root.engaged)
                readProc.running = true;
        } else {
            releaseTimer.restart();
        }
    }

    Component.onDestruction: root.release()

    function release() {
        if (!root.engaged)
            return;
        root.engaged = false;
        root.apply(false);
    }

    function apply(noWarps: bool) {
        Quickshell.execDetached(["hyprctl", "eval", `hl.config({ cursor = { no_warps = ${noWarps} } })`]);
    }

    Timer {
        id: releaseTimer
        interval: root.releaseDelay
        onTriggered: root.release()
    }

    // Only take over when the user's own setting leaves warps on.
    Process {
        id: readProc
        command: ["hyprctl", "-j", "getoption", "cursor:no_warps"]
        stdout: StdioCollector {
            onStreamFinished: {
                let alreadyOff = false;
                try {
                    alreadyOff = JSON.parse(text).bool === true;
                } catch (e) {
                    console.log(`[OverviewWarpGuard] Could not read cursor:no_warps: ${e}`);
                    return;
                }
                if (alreadyOff || !root.suspended)
                    return;
                root.engaged = true;
                root.apply(true);
            }
        }
    }
}
