pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common

/**
 * Auto-Compact mode for the workspace compactor: watches Hyprland events and runs the
 * `workspace_compactor` binary (with --auto) whenever a window close/move leaves a gap in the
 * focused monitor's workspace numbering. The manual keybind is untouched.
 *
 * A gap on the *current* workspace (the user just emptied the workspace they are standing on)
 * is handled per Config.options.bar.workspaces.autoCompactCurrentGap. The binary spots it from
 * Hyprland's own state, since HyprlandData still lags the event that armed the debounce:
 *   - "onswitch": deferred until they switch away (default)
 *   - "immediate": compacted right away like any other gap
 *   - "never": left for the manual keybind; gaps elsewhere still auto-compact
 */
Singleton {
    id: root

    readonly property var opts: Config.options.bar.workspaces
    readonly property bool enabled: Config.ready && (root.opts.autoCompact ?? false)
    readonly property string binaryPath: `${Directories.scriptPath}/hyprland/workspace_compactor`
    readonly property string currentGapMode: root.opts.autoCompactCurrentGap ?? "onswitch"
    // Must match CURRENT_GAP_EXIT in workspace_compactor_src/src/main.rs: the run left a gap on
    // the current workspace alone.
    readonly property int currentGapExit: 3

    // Lock.qml parks every monitor on a temporary workspace with an id far above this while the
    // screen is locked (and sweeps anything it finds up there back down on unlock).
    readonly property int lockWorkspaceMin: 10000

    // A gap on the current workspace is waiting for the user to switch away.
    property bool pending: false
    property bool warnedMissing: false

    onEnabledChanged: {
        if (!enabled) {
            root.pending = false;
            debounce.stop();
        }
    }

    // Running the binary is cheap and idempotent: it re-derives everything from Hyprland itself
    // and exits early when the block is already gapless.
    function fire() {
        if (!root.enabled) return;
        // The lock screen owns the workspace layout from lock until its unlock restore batch
        // has landed: compacting then would be measured against the temporary lock workspace.
        // A pending gap survives this and is re-evaluated on the next event.
        if (GlobalStates.screenLocked || GlobalStates.workspaceRestoreInProgress) return;
        if ((HyprlandData.activeWorkspace?.id ?? 0) >= root.lockWorkspaceMin) return;
        if (compactProc.running) {
            debounce.restart();
            return;
        }
        root.pending = false;
        compactProc.running = true;
    }

    Timer {
        id: debounce
        interval: Math.max(100, root.opts.autoCompactDelay ?? 600)
        repeat: false
        onTriggered: root.fire()
    }

    Connections {
        target: Hyprland
        enabled: root.enabled

        function onRawEvent(event) {
            switch (event.name) {
                // Events that can leave a gap behind.
                case "closewindow":
                case "movewindow":
                case "movewindowv2":
                case "destroyworkspace":
                    debounce.restart();
                    break;

                // A deferred gap compacts once the user switches away from it.
                case "workspacev2":
                    if (root.pending) debounce.restart();
                    break;
            }
        }
    }

    Process {
        id: compactProc
        command: ["bash", "-c", `exec '${root.binaryPath}' --auto --current-gap='${root.currentGapMode}'`]
        onExited: exitCode => {
            if (exitCode === root.currentGapExit) {
                root.pending = (root.currentGapMode === "onswitch");
                return;
            }
            if (exitCode !== 126 && exitCode !== 127) return;
            if (root.warnedMissing) return;
            root.warnedMissing = true;
            console.warn(`[WorkspaceCompactor] ${root.binaryPath} is missing or not executable — `
                + "build it once (Settings › Workspaces › Workspace Compactor)");
        }
    }
}
