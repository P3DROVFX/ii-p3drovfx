pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs

/**
 * The scrolloverview plugin's overview, opened behind the search on zscroll.
 *
 * Super always opens the shell's search. On a zscroll workspace with the plugin
 * loaded, the search asks zscroll.lua (`shell_overview`, over hyprctl eval) to
 * bring the plugin's overview up behind its bar instead of drawing its own: the
 * plugin hands the keyboard to a focused top layer, so typing still searches.
 * While the answer is pending the search keeps its own overview out, and a
 * refusal (option off, plugin missing, not a zscroll workspace) lets it draw.
 */
Singleton {
    id: root

    /// The plugin's overview is up behind the search.
    property bool active: false
    /// Asked for, not answered yet.
    readonly property bool pending: openProcess.running
    /// The search should not draw its own overview.
    readonly property bool hosting: root.active || root.pending

    property double _openedAt: 0
    readonly property string _module: 'package.loaded["hyprland.layouts.zscroll"]'

    function open() {
        if (root.hosting)
            return;
        openProcess.running = true;
    }

    function close() {
        if (openProcess.running)
            openProcess.closeWhenDone = true;
        if (!root.active)
            return;
        root.active = false;
        Quickshell.execDetached(["hyprctl", "eval", `local m = ${root._module}; if m and m.shell_overview then m.shell_overview(false) end`]);
    }

    Process {
        id: openProcess
        property bool closeWhenDone: false
        command: ["hyprctl", "eval", `local m = ${root._module}; if not (m and m.shell_overview and m.shell_overview(true)) then error("unavailable") end`]
        onRunningChanged: if (running) closeWhenDone = false
        onExited: (exitCode, exitStatus) => {
            root.active = exitCode === 0;
            root._openedAt = Date.now();
            if (root.active && closeWhenDone)
                root.close();
        }
    }

    // Picking a window or a workspace in the plugin closes its overview, and with
    // it goes the search that was waiting in front of it. Walking to another
    // workspace inside the overview sends the same events but leaves it open, so
    // each one starts a short poll of zscroll.lua's `plugin_overview_open()`
    // (the plugin restores its option overrides once its close animation ends).
    Connections {
        target: Hyprland
        enabled: root.active
        function onRawEvent(event) {
            if (event.name !== "activewindowv2" && event.name !== "workspacev2")
                return;
            if (Date.now() - root._openedAt < 300)
                return;
            probeTimer.remaining = 8;
            probeTimer.restart();
        }
    }

    Timer {
        id: probeTimer
        property int remaining: 0
        interval: 200
        repeat: true
        running: false
        onTriggered: {
            if (!root.active || remaining <= 0) {
                stop();
                return;
            }
            remaining--;
            if (!probeProcess.running)
                probeProcess.running = true;
        }
    }

    Process {
        id: probeProcess
        command: ["hyprctl", "eval", `local m = ${root._module}; if not (m and m.plugin_overview_open and m.plugin_overview_open()) then error("closed") end`]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 || !root.active)
                return;
            probeTimer.stop();
            root.active = false;
            if (GlobalStates.overviewOpen)
                GlobalStates.closeOverview();
        }
    }
}
