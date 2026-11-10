pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Modes & Routines in the shell: the keybinds and the app window.
 *
 * The manager used to be an overlay on the layer shell; it is now the clock app's
 * sibling, built from its parts. The window is the clock's RetainedLoader: built when
 * the app opens, kept hidden 30 s after it closes so a quick reopen is instant, then
 * destroyed with its editors. The IPC target `modes` lives in the engine and drives
 * GlobalStates.modesOpen, like everything else that opens this app.
 */
Scope {
    id: root

    function requestClose(): void {
        GlobalStates.modesOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.modesOpen)
            root.requestClose();
        else
            GlobalStates.openModesApp("");
    }

    RetainedLoader {
        requested: GlobalStates.modesOpen
        retainFor: 30000
        sourceComponent: ModesAppWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "modesToggle"
        description: "Toggles the Modes & Routines app"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "modesOpen"
        description: "Opens the Modes & Routines app"
        onPressed: GlobalStates.openModesApp("")
    }

    GlobalShortcut {
        name: "modesClose"
        description: "Closes the Modes & Routines app"
        onPressed: root.requestClose()
    }
}
