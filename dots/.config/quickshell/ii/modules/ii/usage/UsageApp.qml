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
 * App usage in the shell: the keybinds, the IPC target, and the app window.
 *
 * Per-app screen time, battery and daily limits used to be an overlay on the layer
 * shell; they are now the clock app's sibling, built from its parts. The window is the
 * clock's RetainedLoader: built when the app opens, kept hidden 30 s after it closes so
 * a quick reopen is instant, then destroyed with its tree and the day files AppStats
 * parsed for it.
 */
Scope {
    id: root

    // The window's component: compiled on the first open (synchronously, so the
    // build below starts at once) and held for later opens. The build itself
    // stays asynchronous.
    property Component windowComponent: null
    readonly property bool windowRequested: GlobalStates.usageOpen
    onWindowRequestedChanged: root.ensureWindowComponent()
    Component.onCompleted: root.ensureWindowComponent()
    function ensureWindowComponent(): void {
        if (!root.windowRequested || root.windowComponent !== null)
            return;
        const component = Qt.createComponent("UsageAppWindow.qml");
        // A window that fails to compile is reported and not kept, so the
        // next open tries again instead of silently never opening.
        if (component.status === Component.Error) {
            console.warn("[UsageApp] UsageAppWindow.qml failed to load:", component.errorString());
            Qt.callLater(() => root.requestClose());
            return;
        }
        root.windowComponent = component;
    }

    readonly property var tabIds: ["apps", "battery", "limits"]

    function requestOpen(tab = ""): void {
        // The singleton probes once at startup. Retry only while the sampler is absent,
        // so opening the app does not launch a process on every toggle.
        if (!AppStats.probed || !AppStats.binaryPresent)
            AppStats.checkInstall();
        GlobalStates.openUsageApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.usageOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.usageOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        id: windowLoader
        requested: GlobalStates.usageOpen
        retainFor: 30000
        onActiveChanged: {
            if (!active)
                AppStats.releaseCache();
        }
        // The window compiles on its first open, not with the shell: an inline
        // `sourceComponent: UsageAppWindow {}` compiled its whole tree at start.
        sourceComponent: root.windowComponent
    }

    Connections {
        target: windowLoader.item
        function onCloseRequested(): void {
            root.requestClose();
        }
    }

    GlobalShortcut {
        name: "usageToggle"
        description: "Toggles the App usage app"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "usageOpen"
        description: "Opens the App usage app"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "usageClose"
        description: "Closes the App usage app"
        onPressed: root.requestClose()
    }

    IpcHandler {
        target: "usage"

        function toggle(): void {
            root.requestToggle();
        }

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function limits(): void {
            root.requestOpen("limits");
        }

        /// apps | battery | limits
        function openTab(tab: string): void {
            root.requestOpen(String(tab ?? ""));
        }
    }
}
