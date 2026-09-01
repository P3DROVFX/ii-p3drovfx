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

            // Keep an already-open bar mapped while the lock surface is entering.
            // Destroying the PanelWindow here makes Wayland recompute the layer
            // geometry in the same frame as the lock animation, which produces a
            // visible slide when wrapped frame is enabled.
            // Edit Mode holds the bar mapped and revealed: its viewport reserves the bar's edge
            // whatever the bar is doing, and stage 6 edits the bar in place.
            active: (GlobalStates.barOpen || GlobalStates.editMode) && !GlobalStates.connectModeActive && !GlobalStates.isMediaModeActiveForScreen(barLoader.modelData ? barLoader.modelData.name : "")
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
