pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.core

// Bar entry point — one BarWindow per monitor.
// Window/autohide/exclusiveZone logic lives in bar/core/BarWindow.qml.
Scope {
    id: bar

    Variants {
        id: barVariant

        readonly property var variantModel: GlobalStates.allowedScreens
        model: variantModel
        LazyLoader {
            id: barLoader
            required property ShellScreen modelData
            property int monitorIndex: barVariant.variantModel.indexOf(modelData)

            active: GlobalStates.barOpen && !GlobalStates.screenLocked && !GlobalStates.connectModeActive
            component: BarWindow {
                screen:       barLoader.modelData
                monitorIndex: barLoader.monitorIndex
            }
        }
    }

    // ── IPC / Global shortcuts ────────────────────────────────────────────────
    IpcHandler {
        target: "bar"
        function toggle(): void { GlobalStates.barOpen = !GlobalStates.barOpen; }
        function close():  void { GlobalStates.barOpen = false; }
        function open():   void { GlobalStates.barOpen = true; }
    }

    GlobalShortcut {
        name: "barToggle"; description: "Toggles bar on press"
        onPressed: GlobalStates.barOpen = !GlobalStates.barOpen
    }
    GlobalShortcut {
        name: "barOpen"; description: "Opens bar on press"
        onPressed: GlobalStates.barOpen = true
    }
    GlobalShortcut {
        name: "barClose"; description: "Closes bar on press"
        onPressed: GlobalStates.barOpen = false
    }
}
