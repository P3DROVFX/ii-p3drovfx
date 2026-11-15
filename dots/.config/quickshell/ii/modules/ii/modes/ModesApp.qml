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

    // The window's component: compiled on the first open (synchronously, so the
    // build below starts at once) and held for later opens. The build itself
    // stays asynchronous.
    property Component windowComponent: null
    readonly property bool windowRequested: GlobalStates.modesOpen
    onWindowRequestedChanged: root.ensureWindowComponent()
    Component.onCompleted: root.ensureWindowComponent()
    function ensureWindowComponent(): void {
        if (!root.windowRequested || root.windowComponent !== null)
            return;
        const component = Qt.createComponent("ModesAppWindow.qml");
        // A window that fails to compile is reported and not kept, so the
        // next open tries again instead of silently never opening.
        if (component.status === Component.Error) {
            console.warn("[ModesApp] ModesAppWindow.qml failed to load:", component.errorString());
            Qt.callLater(() => root.requestClose());
            return;
        }
        root.windowComponent = component;
    }

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
        id: windowLoader
        requested: GlobalStates.modesOpen
        retainFor: 30000
        // The window compiles on its first open, not with the shell: an inline
        // `sourceComponent: ModesAppWindow {}` compiled its whole tree at start.
        sourceComponent: root.windowComponent
    }

    Connections {
        target: windowLoader.item
        function onCloseRequested(): void {
            root.requestClose();
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
