pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland

LockScreen {
    id: root

    // Monitor name -> workspace id to restore on unlock (set when locking)
    property var savedWorkspaces: ({})
    property var savedPinnedAddresses: []
    property string unlockFocusedMonitor: ""

    Timer {
        id: restoreTimer
        interval: 450 // Delayed until zoom-in is fully finished (450ms)
        repeat: false
        onTriggered: {
            if (GlobalStates.screenLocked)
                return;

            var batch = "keyword animation workspaces,0";
            var hasCmds = false;
            for (var j = 0; j < Quickshell.screens.length; ++j) {
                var monName = Quickshell.screens[j].name;
                var wsId = root.savedWorkspaces[monName];
                if (wsId !== undefined) {
                    var mData = HyprlandData.monitors.find(m => m.name === monName);
                    if (mData && mData.activeWorkspace && mData.activeWorkspace.id > 1000000) {
                        batch += ` ; dispatch hl.dsp.focus {monitor="${monName}"} ; dispatch hl.dsp.focus {workspace=${wsId}}`;
                        hasCmds = true;
                    }
                }
            }
            if (root.savedPinnedAddresses && root.savedPinnedAddresses.length > 0) {
                for (var r = 0; r < root.savedPinnedAddresses.length; ++r) {
                    var addr = root.savedPinnedAddresses[r];
                    if (addr) {
                        batch += ` ; dispatch hl.dsp.window.pin {window="address:${addr}"}`;
                        hasCmds = true;
                    }
                }
                root.savedPinnedAddresses = [];
            }
            if (root.unlockFocusedMonitor !== "") {
                batch += ` ; dispatch hl.dsp.focus {monitor="${root.unlockFocusedMonitor}"}`;
                hasCmds = true;
            }
            batch += " ; keyword animation workspaces,1";
            if (hasCmds) {
                Quickshell.execDetached(["hyprctl", "--batch", batch]);
            }

            // Keep workspace labels hidden until Hyprland has applied the
            // restore batch. The reveal is then driven by the label's own
            // opacity Behavior instead of exposing the temporary lock ID.
            workspaceNumbersRevealTimer.restart();
        }
    }

    Timer {
        id: workspaceNumbersRevealTimer
        interval: Appearance.animation.elementMoveSlow.duration
        repeat: false
        onTriggered: GlobalStates.workspaceRestoreInProgress = false
    }

    lockSurface: LockSurface {
        context: root.context
    }

    // Single batch for lock and unlock so we don't race multiple hyprctl calls
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                restoreTimer.stop();
                workspaceNumbersRevealTimer.stop();
                GlobalStates.workspaceRestoreInProgress = false;
                // Lock: save workspace per monitor and move all to temp workspace in one batch
                var activeMon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
                var next = {};
                var batch = "keyword animation workspaces,0";
                var hasCmds = false;
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i] ? Quickshell.screens[i].name : null;
                    if (!mon)
                        continue;
                    var mData = HyprlandData.monitors.find(m => m.name === mon);
                    if (mData?.activeWorkspace == undefined) {
                        continue; // Skip this monitor rather than aborting all others
                    }
                    if (mData.specialWorkspace && mData.specialWorkspace.name !== "" && mData.specialWorkspace.id !== 0) {
                        var specName = mData.specialWorkspace.name || "";
                        var cleanSpecName = specName.startsWith("special:") ? specName.substring(8) : specName;
                        if (!cleanSpecName)
                            cleanSpecName = "special";
                        batch += ` ; dispatch hl.dsp.focus {monitor="${mon}"} ; dispatch hl.dsp.workspace.toggle_special('${cleanSpecName}')`;
                        hasCmds = true;
                    }
                    var ws = (mData?.activeWorkspace?.id ?? 1);
                    // If already on a lock workspace (> 1000000), preserve existing saved workspace if present
                    if (ws <= 1000000 || !root.savedWorkspaces[mon]) {
                        next[mon] = ws;
                    } else {
                        next[mon] = root.savedWorkspaces[mon];
                    }

                    var lockWs = ws > 1000000 ? ws : (2147483647 - Math.abs(ws));
                    batch += ` ; dispatch hl.dsp.focus {monitor="${mon}"} ; dispatch hl.dsp.focus {workspace=${lockWs}}`;
                    hasCmds = true;
                }
                // Unpin any pinned windows so they hide when switching to lock workspace
                var pinnedAddrs = [];
                if (HyprlandData.windowList) {
                    for (var p = 0; p < HyprlandData.windowList.length; ++p) {
                        var pWin = HyprlandData.windowList[p];
                        if (pWin && pWin.pinned && pWin.address) {
                            pinnedAddrs.push(pWin.address);
                            batch += ` ; dispatch hl.dsp.window.pin {window="address:${pWin.address}"}`;
                            hasCmds = true;
                        }
                    }
                }
                root.savedPinnedAddresses = pinnedAddrs;

                if (activeMon !== "") {
                    batch += ` ; dispatch hl.dsp.focus {monitor="${activeMon}"}`;
                }
                batch += " ; keyword animation workspaces,1";
                root.savedWorkspaces = next;
                if (hasCmds) {
                    Quickshell.execDetached(["hyprctl", "--batch", batch]);
                }
            } else {
                root.unlockFocusedMonitor = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
                GlobalStates.workspaceRestoreInProgress = true;
                restoreTimer.start();
            }
        }
    }

    // Evict any new window opened while screen is locked out of the temporary lock workspace
    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            if (!GlobalStates.screenLocked) return;
            if (!HyprlandData.windowListLoaded || !HyprlandData.windowList) return;

            var batch = "";
            var hasCmds = false;
            for (var i = 0; i < HyprlandData.windowList.length; ++i) {
                var win = HyprlandData.windowList[i];
                if (win && win.workspace && win.workspace.id > 10000 && win.address) {
                    var targetWs = 1;
                    if (HyprlandData.monitors && win.monitor !== undefined && HyprlandData.monitors[win.monitor]) {
                        var monName = HyprlandData.monitors[win.monitor].name;
                        if (monName && root.savedWorkspaces[monName] && root.savedWorkspaces[monName] <= 10000) {
                            targetWs = root.savedWorkspaces[monName];
                        }
                    }
                    batch += ` ; dispatch movetoworkspacesilent ${targetWs},address:${win.address} ; dispatch hl.dsp.window.move({ workspace = ${targetWs}, follow = false, window = "address:${win.address}" })`;
                    hasCmds = true;
                }
            }
            if (hasCmds) {
                Quickshell.execDetached(["hyprctl", "--batch", batch.substring(3)]);
            }
        }
    }

    // Push everything down (visual only; workspace switch is in Connections above)
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            // Guard against null modelData during screen reconfiguration on lock
            property string targetMonitorName: modelData ? modelData.name : ""
            property int verticalMovementDistance: modelData ? modelData.height : 0
            property int horizontalSqueeze: modelData ? modelData.width * 0.2 : 0
        }
    }
}
