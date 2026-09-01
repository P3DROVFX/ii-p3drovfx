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
 * is handled per Config.options.bar.workspaces.autoCompactCurrentGap:
 *   - "onswitch": deferred until they switch away (default)
 *   - "immediate": compacted right away like any other gap
 *   - "never": left for the manual keybind; gaps elsewhere still auto-compact
 */
Singleton {
    id: root

    readonly property var opts: Config.options.bar.workspaces
    readonly property bool enabled: Config.ready && (root.opts.autoCompact ?? false)
    readonly property string binaryPath: `${Directories.scriptPath}/hyprland/workspace_compactor`

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

    // The current workspace itself is a gap when it is a regular workspace, holds no windows,
    // and occupied workspaces exist above it on the same monitor — compacting now would move
    // windows around (or onto) the workspace the user is looking at.
    function currentWorkspaceIsGap() {
        const active = HyprlandData.activeWorkspace;
        if (!active || active.id <= 0 || active.name !== String(active.id)) return false;
        if ((active.windows ?? 0) > 0) return false;
        return HyprlandData.workspaces.some(ws => ws.monitorID === active.monitorID
            && ws.id > active.id && ws.name === String(ws.id) && (ws.windows ?? 0) > 0);
    }

    // Evaluated after the debounce, so HyprlandData has had time to refresh from the event
    // that armed the timer. Actually running the binary is cheap and idempotent: it re-derives
    // everything from Hyprland itself and exits early when the block is already gapless.
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
        if (root.currentWorkspaceIsGap()) {
            const mode = root.opts.autoCompactCurrentGap ?? "onswitch";
            if (mode !== "immediate") {
                root.pending = (mode === "onswitch");
                return;
            }
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
        command: ["bash", "-c", `exec '${root.binaryPath}' --auto`]
        onExited: exitCode => {
            if (exitCode !== 126 && exitCode !== 127) return;
            if (root.warnedMissing) return;
            root.warnedMissing = true;
            console.warn(`[WorkspaceCompactor] ${root.binaryPath} is missing or not executable — `
                + "build it once (Settings › Workspaces › Workspace Compactor)");
        }
    }
}
