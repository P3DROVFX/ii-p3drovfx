pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * ii Vitals: its lifecycle and its ways in (Super+H, the `vitals` IPC target, search).
 *
 * Only this Scope lives with the shell. The window is the same RetainedLoader the clock,
 * Usage and System Health use: built asynchronously when the app opens, kept hidden for
 * 30 s after it closes, then destroyed. Nothing here touches VitalsService, so a closed
 * app costs nothing.
 */
Scope {
    id: root

    // The window's component: compiled on the first open (synchronously, so the
    // build below starts at once) and held for later opens. The build itself
    // stays asynchronous.
    property Component windowComponent: null
    readonly property bool windowRequested: GlobalStates.vitalsAppOpen
    onWindowRequestedChanged: root.ensureWindowComponent()
    Component.onCompleted: root.ensureWindowComponent()
    function ensureWindowComponent(): void {
        if (!root.windowRequested || root.windowComponent !== null)
            return;
        const component = Qt.createComponent("VitalsAppWindow.qml");
        // A window that fails to compile is reported and not kept, so the
        // next open tries again instead of silently never opening.
        if (component.status === Component.Error) {
            console.warn("[VitalsApp] VitalsAppWindow.qml failed to load:", component.errorString());
            Qt.callLater(() => root.requestClose());
            return;
        }
        root.windowComponent = component;
    }

    function requestOpen(page = ""): void {
        GlobalStates.openVitalsApp(page);
    }

    function requestClose(): void {
        GlobalStates.vitalsAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.vitalsAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        id: windowLoader
        requested: GlobalStates.vitalsAppOpen
        retainFor: 30000
        sourceComponent: root.windowComponent
    }

    Connections {
        target: windowLoader.item
        function onCloseRequested(): void {
            root.requestClose();
        }
    }

    GlobalShortcut {
        name: "vitalsToggle"
        description: "Toggles the ii Vitals app"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "vitalsOpen"
        description: "Opens the ii Vitals app"
        onPressed: root.requestOpen()
    }

    IpcHandler {
        target: "vitals"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        /// today | activity | sleep | heart | workouts | body | more | settings
        function openPage(page: string): void {
            root.requestOpen(String(page ?? ""));
        }
    }
}
