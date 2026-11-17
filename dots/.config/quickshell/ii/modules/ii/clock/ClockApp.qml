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
 * The clock app: its lifecycle and its ways in.
 *
 * Only this Scope lives with the shell — a keybind and an IPC target. The window is the
 * same RetainedLoader Usage and Modes use: built asynchronously when the clock opens, so
 * the keybind never waits on the tree, and kept hidden for 30 s after it closes, so a
 * quick reopen is instant. When that window expires the tree is destroyed and collected:
 * a closed clock holds no tree, no timers and no cache. Alarms, timers and the pomodoro
 * keep running in their services, exactly as they do for the bar and the sidebar.
 */
Scope {
    id: root

    // The window's component: compiled on the first open (synchronously, so the
    // build below starts at once) and held for later opens. The build itself
    // stays asynchronous.
    property Component windowComponent: null
    readonly property bool windowRequested: GlobalStates.clockAppOpen
    onWindowRequestedChanged: root.ensureWindowComponent()
    Component.onCompleted: root.ensureWindowComponent()
    function ensureWindowComponent(): void {
        if (!root.windowRequested || root.windowComponent !== null)
            return;
        const component = Qt.createComponent("ClockAppWindow.qml");
        // A window that fails to compile is reported and not kept, so the
        // next open tries again instead of silently never opening.
        if (component.status === Component.Error) {
            console.warn("[ClockApp] ClockAppWindow.qml failed to load:", component.errorString());
            Qt.callLater(() => root.requestClose());
            return;
        }
        root.windowComponent = component;
    }

    readonly property var tabIds: ["alarms", "worldClock", "timer", "stopwatch", "pomodoro", "bedtime", "reminders"]

    function requestOpen(tab = ""): void {
        GlobalStates.openClockApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.clockAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.clockAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        id: windowLoader
        requested: GlobalStates.clockAppOpen
        // The last clock stays warm for a quick reopen, then goes entirely.
        retainFor: 30000
        // The window compiles on its first open, not with the shell: an inline
        // `sourceComponent: ClockAppWindow {}` compiled its whole tree at start.
        sourceComponent: root.windowComponent
    }

    Connections {
        target: windowLoader.item
        function onCloseRequested(): void {
            root.requestClose();
        }
    }

    GlobalShortcut {
        name: "clockToggle"
        description: "Toggles the clock app"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "clockOpen"
        description: "Opens the clock app"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "clockClose"
        description: "Closes the clock app"
        onPressed: root.requestClose()
    }

    IpcHandler {
        target: "clock"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        /// alarms | worldClock | timer | stopwatch | pomodoro | bedtime
        function openTab(tab: string): void {
            root.requestOpen(String(tab ?? ""));
        }
    }
}
