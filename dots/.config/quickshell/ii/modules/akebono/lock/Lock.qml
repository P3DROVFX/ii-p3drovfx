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

    lockSurface: LockSurface {
        context: root.context
    }

    Binding {
        target: GlobalStates
        property: "desktopLockClockHidden"
        value: GlobalStates.screenLocked
    }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            property string targetMonitorName: modelData.name
            property int lastWorkspaceId
            onShouldPushChanged: {
                if (shouldPush) {
                    lastWorkspaceId = HyprlandData.monitors.find(m => m.name == targetMonitorName)?.activeWorkspace?.id ?? 1;
                    Quickshell.execDetached(["bash", "-c", `hyprctl eval "hl.animation({ leaf = 'workspaces', enabled = true, speed = 7, bezier = 'menu_decel', style = 'slidevert' })"; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - lastWorkspaceId}})'`]);
                } else {
                    Quickshell.execDetached(["bash", "-c", `hyprctl dispatch 'hl.dsp.focus({workspace=${lastWorkspaceId}})'; hyprctl reload`]);
                }
            }
        }
    }
}
