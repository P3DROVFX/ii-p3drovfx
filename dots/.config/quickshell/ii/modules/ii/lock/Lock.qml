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

    Timer {
        id: restoreTimer
        interval: 450 // Delayed until zoom-in is fully finished (450ms)
        repeat: false
        onTriggered: {
            var batch = "keyword animation workspaces,0"
            var hasCmds = false
            for (var j = 0; j < Quickshell.screens.length; ++j) {
                var monName = Quickshell.screens[j].name
                var wsId = root.savedWorkspaces[monName]
                if (wsId !== undefined) {
                    var mData = HyprlandData.monitors.find(m => m.name === monName)
                    if (mData && mData.activeWorkspace && mData.activeWorkspace.id > 1000000) {
                        batch += ` ; dispatch hl.dsp.focus {monitor="${monName}"} ; dispatch hl.dsp.focus {workspace=${wsId}}`
                        hasCmds = true
                    }
                }
            }
            batch += " ; keyword animation workspaces,1"
            if (hasCmds) {
                GlobalStates.workspaceRestoreInProgress = false;
                Quickshell.execDetached(["hyprctl", "--batch", batch])
            } else {
                GlobalStates.workspaceRestoreInProgress = false;
            }
        }
    }

    lockSurface: LockSurface {
        context: root.context
    }

    // Single batch for lock and unlock so we don't race multiple hyprctl calls
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                GlobalStates.workspaceRestoreInProgress = false;
                // Lock: save workspace per monitor and move all to temp workspace in one batch
                var next = {}
                var batch = "keyword animation workspaces,0"
                var hasCmds = false
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i] ? Quickshell.screens[i].name : null
                    if (!mon) continue;
                    var mData = HyprlandData.monitors.find(m => m.name === mon)
                    if (mData?.activeWorkspace == undefined) {
                        continue; // Skip this monitor rather than aborting all others
                    }
                    var ws = (mData?.activeWorkspace?.id ?? 1)
                    next[mon] = ws
                    var hasWindows = HyprlandData.windowList.some(function(w) { return w.workspace.id === ws; })
                    if (hasWindows) {
                        batch += ` ; dispatch hl.dsp.focus {monitor="${mon}"} ; dispatch hl.dsp.focus {workspace=${2147483647 - ws}}`
                        hasCmds = true
                    }
                }
                batch += " ; keyword animation workspaces,1"
                root.savedWorkspaces = next
                if (hasCmds) {
                    Quickshell.execDetached(["hyprctl", "--batch", batch])
                }
            } else {
                GlobalStates.workspaceRestoreInProgress = true;
                restoreTimer.start()
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