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
 * The System Health app: its lifecycle and its ways in.
 *
 * Only this Scope lives with the shell — the keybinds and an IPC target. The window is
 * the same RetainedLoader the clock, Usage and Modes use: built asynchronously when the
 * app opens, kept hidden for 30 s after it closes, then destroyed. The helper keeps
 * watching in HealthService whether the window exists or not.
 */
Scope {
    id: root

    // The window's component: compiled on the first open (synchronously, so the
    // build below starts at once) and held for later opens. The build itself
    // stays asynchronous.
    property Component windowComponent: null
    readonly property bool windowRequested: GlobalStates.healthAppOpen
    onWindowRequestedChanged: root.ensureWindowComponent()
    Component.onCompleted: root.ensureWindowComponent()
    function ensureWindowComponent(): void {
        if (!root.windowRequested || root.windowComponent !== null)
            return;
        const component = Qt.createComponent("HealthAppWindow.qml");
        // A window that fails to compile is reported and not kept, so the
        // next open tries again instead of silently never opening.
        if (component.status === Component.Error) {
            console.warn("[HealthApp] HealthAppWindow.qml failed to load:", component.errorString());
            Qt.callLater(() => root.requestClose());
            return;
        }
        root.windowComponent = component;
    }

    readonly property var tabIds: ["overview", "services", "crashes", "journal", "storage", "system"]

    function requestOpen(tab = ""): void {
        GlobalStates.openHealthApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.healthAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.healthAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        id: windowLoader
        requested: GlobalStates.healthAppOpen
        retainFor: 30000
        // The window compiles on its first open, not with the shell: an inline
        // `sourceComponent: HealthAppWindow {}` compiled its whole tree at start.
        sourceComponent: root.windowComponent
    }

    Connections {
        target: windowLoader.item
        function onCloseRequested(): void {
            root.requestClose();
        }
    }

    GlobalShortcut {
        name: "healthToggle"
        description: "Toggles the System Health app"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "healthOpen"
        description: "Opens the System Health app"
        onPressed: root.requestOpen()
    }

    IpcHandler {
        target: "health"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        /// overview | services | crashes | journal | storage | system
        function openTab(tab: string): void {
            root.requestOpen(String(tab ?? ""));
        }

        /// Re-runs every check now.
        function rescan(): void {
            HealthService.rescan();
        }

        /// How many problems need attention, for scripts and status bars.
        function attention(): int {
            return HealthService.attentionCount;
        }
    }
}
