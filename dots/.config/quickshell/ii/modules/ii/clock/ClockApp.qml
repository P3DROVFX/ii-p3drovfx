pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.modules.common

/**
 * The clock app: its lifecycle and its ways in.
 *
 * Only this Scope lives with the shell — a keybind and an IPC target. The window and every
 * tab are built when it opens and destroyed when it closes, then collected, so a closed
 * clock holds no tree, no timers and no cache. Alarms, timers and the pomodoro keep
 * running in their services, exactly as they do for the bar and the sidebar.
 */
Scope {
    id: root

    readonly property var tabIds: ["alarms", "worldClock", "timer", "stopwatch", "pomodoro"]

    function collectClosedWindow(): void {
        if (!GlobalStates.clockAppOpen && !windowLoader.item && typeof gc === "function")
            gc();
    }

    function releaseClosedWindow(): void {
        if (GlobalStates.clockAppOpen)
            return;
        windowLoader.active = false;
        Qt.callLater(root.collectClosedWindow);
    }

    Connections {
        target: GlobalStates
        function onClockAppOpenChanged() {
            if (GlobalStates.clockAppOpen)
                windowLoader.active = true;
            else
                Qt.callLater(root.releaseClosedWindow);
        }
    }
    Component.onCompleted: windowLoader.active = GlobalStates.clockAppOpen

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

    Loader {
        id: windowLoader
        active: false
        sourceComponent: ClockAppWindow {
            onCloseRequested: root.requestClose()
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

        /// alarms | worldClock | timer | stopwatch | pomodoro
        function openTab(tab: string): void {
            root.requestOpen(String(tab ?? ""));
        }
    }
}
