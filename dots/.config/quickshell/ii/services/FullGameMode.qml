pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.models.hyprland
import "modes/ModeSchema.js" as ModeSchema

/**
 * Full game mode: the whole shell is swapped for gameMode.qml, a second entry point that
 * runs only the game overlay, the polkit agent and a hyprlock fallback for locking.
 *
 * Unloading panels inside the running shell only gives back ~200 MB: singletons live as
 * long as the engine, their daemons keep running, and the JS heap and allocator keep what
 * they took. A fresh process with just the overlay has no helper daemons and roughly a
 * third of the full shell's memory, so entering and leaving is a process swap done by
 * scripts/gameMode/swap.sh, which outlives the shell that started it.
 *
 * Entering also turns on the regular game mode's Hyprland overrides and stops external
 * wallpaper processes. Undoing both happens when the full shell boots and finds the
 * session marker (recover()), so leaving through the overlay and a plain shell restart
 * end up the same way.
 */
Singleton {
    id: root

    /// Set by gameMode.qml: this process is the game mode shell.
    property bool running: false
    /// True from the moment a swap is requested; the process is about to be killed.
    property bool switching: false

    readonly property string swapScript: Quickshell.shellPath("scripts/gameMode/swap.sh")
    readonly property string sessionMarker: `${Quickshell.env("XDG_RUNTIME_DIR")}/ii-game-mode/active`

    property HyprlandConfigOption animationsOption: HyprlandConfigOption {
        key: "animations:enabled"
    }
    readonly property bool hyprlandGameModeOn: root.animationsOption.value === 0 || root.animationsOption.value === false

    property var pendingSwap: []
    property bool recovering: false

    function enter() {
        if (root.running || root.switching)
            return;
        root.switching = true;
        const restore = !root.hyprlandGameModeOn;
        if (restore)
            HyprlandConfig.setMany(ModeSchema.GAME_MODE_OPTIONS, { addLines: [ModeSchema.GAME_MODE_RULE] });
        root.swapWhenWritten(["enter", restore ? "1" : "0"]);
    }

    function exit() {
        if (!root.running || root.switching)
            return;
        root.switching = true;
        root.swapWhenWritten(["exit"]);
    }

    /// Called by the full shell on boot: undoes a game mode session it replaced.
    function recover() {
        if (!root.running)
            root.recovering = true;
    }

    function swapWhenWritten(args) {
        root.pendingSwap = args;
        swapTimer.waited = 0;
        swapTimer.restart();
    }

    // The swap kills this process, so the Hyprland override write has to land first.
    Timer {
        id: swapTimer
        interval: 50
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (HyprlandConfig.busy && waited < 3000)
                return;
            stop();
            Quickshell.execDetached(["setsid", "-f", "bash", root.swapScript].concat(root.pendingSwap));
        }
    }

    FileView {
        id: sessionFile
        // Bound to `recovering` so the game mode shell never reads its own session.
        path: root.recovering ? root.sessionMarker : ""
        printErrors: false
        onLoaded: {
            if (sessionFile.text().trim() === "1")
                HyprlandConfig.resetMany(Object.keys(ModeSchema.GAME_MODE_OPTIONS), {
                    removeMatching: [ModeSchema.GAME_MODE_RULE_MARKER]
                });
            Quickshell.execDetached(["bash", root.swapScript, "recover"]);
        }
    }
}
