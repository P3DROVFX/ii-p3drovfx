pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property bool windowListLoaded: false
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    /**
     * The workspaces on screen at the monitor holding the keyboard: the one that monitor
     * shows, plus a special workspace pulled over it. A workspace lives on exactly one
     * monitor, so this also answers "is it on the screen being used" once a second one
     * is plugged in.
     */
    readonly property var visibleWorkspaceIds: {
        const ids = [];
        const activeId = Number(root.activeWorkspace?.id ?? NaN);
        if (isFinite(activeId))
            ids.push(activeId);

        const monitorId = Number(Hyprland.focusedMonitor?.id ?? NaN);
        const monitor = Array.from(root.monitors ?? [])
            .find(candidate => Number(candidate?.id ?? NaN) === monitorId);
        const specialId = Number(monitor?.specialWorkspace?.id ?? 0);
        if (isFinite(specialId) && specialId !== 0)
            ids.push(specialId);

        return ids;
    }

    /**
     * Whether a toplevel sits on a workspace the user is currently looking at.
     *
     * Hyprland leaves keyboard focus - and with it the toplevel's `activated` flag - on a
     * window that was sent away with a silent move: Super + Alt + a number, or a drag in the
     * overview. It does ask for a refocus, but a refocus only clears the keyboard when
     * nothing at all is under the cursor, and the wallpaper is a layer surface, so something
     * always is. `activated` therefore marks windows that are not on screen at all, and
     * anything asking "is this the window in front of me" has to ask this instead.
     *
     * A window that cannot be placed counts as on screen: that is the reading that changes
     * nothing for the caller.
     */
    function toplevelOnScreen(toplevel) {
        const client = root.clientForToplevel(toplevel);
        const ids = root.visibleWorkspaceIds;
        if (!client || ids.length === 0)
            return true;
        const workspaceId = Number(client.workspace?.id ?? NaN);
        return ids.some(id => id === workspaceId);
    }

    // Internals

    property bool _windowListNeedsUpdate: false
    property bool _monitorsNeedsUpdate: false
    property bool _layersNeedsUpdate: false
    property bool _workspacesNeedsUpdate: false
    property bool _activeWorkspaceNeedsUpdate: false

    function updateWindowList() {
        if (getClients.running) {
            root._windowListNeedsUpdate = true;
        } else {
            getClients.running = true;
        }
    }

    function updateLayers() {
        if (getLayers.running) {
            root._layersNeedsUpdate = true;
        } else {
            getLayers.running = true;
        }
    }

    function updateMonitors() {
        if (getMonitors.running) {
            root._monitorsNeedsUpdate = true;
        } else {
            getMonitors.running = true;
        }
    }

    function updateWorkspaces() {
        if (getWorkspaces.running) {
            root._workspacesNeedsUpdate = true;
        } else {
            getWorkspaces.running = true;
        }

        if (getActiveWorkspace.running) {
            root._activeWorkspaceNeedsUpdate = true;
        } else {
            getActiveWorkspace.running = true;
        }
    }

    function updateAll() {
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        updateAll();
        if (Config.ready) {
            syncWorkspaceMap();
            const useMap = Config.options.bar.workspaces.useWorkspaceMap;
            const shown = Config.options.bar.workspaces.shown || 10;
            syncWorkspaceGroupSize(useMap ? shown : 10);
        }
    }

    // Window titles can change at very high frequency (browsers,
    // terminals, media applications, etc.). Debounce these events
    // and refresh only the client/window list after title activity settles.
    Timer {
        id: windowTitleUpdateDebounce
        interval: 250
        repeat: false
        onTriggered: root.updateWindowList()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            // console.log("Hyprland raw event:", event.name);

            // Keep window titles eventually consistent without causing
            // repeated hyprctl calls during continuous title changes.
            if (event.name === "windowtitle"
                    || event.name === "windowtitlev2") {
                windowTitleUpdateDebounce.restart();
                return;
            }

            switch (event.name) {
                case "workspace":
                case "workspacev2":
                case "focusedmon":
                case "activespecial":
                case "activespecialv2":
                    root.updateMonitors();
                    root.updateWorkspaces();
                    root.updateWindowList();
                    break;

                case "activewindow":
                case "activewindowv2":
                    root.updateWindowList();
                    root.updateWorkspaces();
                    break;

                case "openwindow":
                case "closewindow":
                case "movewindow":
                case "movewindowv2":
                    root.updateWindowList();
                    root.updateWorkspaces();
                    break;

                case "changefloatingmode":
                case "fullscreen":
                case "urgent":
                case "minimize":
                    root.updateWindowList();
                    break;

                case "createworkspace":
                case "destroyworkspace":
                case "moveworkspace":
                case "renameworkspace":
                    root.updateWorkspaces();
                    break;

                case "monitoradded":
                case "monitorremoved":
                    root.updateMonitors();
                    root.updateWorkspaces();
                    break;
            }
        }
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                root.windowList = JSON.parse(clientsCollector.text)
                root.windowListLoaded = true;
                let tempWinByAddress = {};
                for (var i = 0; i < root.windowList.length; ++i) {
                    var win = root.windowList[i];
                    tempWinByAddress[win.address] = win;
                }
                root.windowByAddress = tempWinByAddress;
                root.addresses = root.windowList.map(win => win.address);

                if (root._windowListNeedsUpdate) {
                    root._windowListNeedsUpdate = false;
                    getClients.running = true;
                }
            }
        }
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                root.monitors = JSON.parse(monitorsCollector.text);

                if (root._monitorsNeedsUpdate) {
                    root._monitorsNeedsUpdate = false;
                    getMonitors.running = true;
                }
            }
        }
    }

    Process {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                root.layers = JSON.parse(layersCollector.text);

                if (root._layersNeedsUpdate) {
                    root._layersNeedsUpdate = false;
                    getLayers.running = true;
                }
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                var rawWorkspaces = JSON.parse(workspacesCollector.text);
                // Filter out invalid workspace ids (e.g. lock-screen temp workspace 2147483647 - N)
                root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                let tempWorkspaceById = {};
                for (var i = 0; i < root.workspaces.length; ++i) {
                    var ws = root.workspaces[i];
                    tempWorkspaceById[ws.id] = ws;
                }
                root.workspaceById = tempWorkspaceById;
                root.workspaceIds = root.workspaces.map(ws => ws.id);

                if (root._workspacesNeedsUpdate) {
                    root._workspacesNeedsUpdate = false;
                    getWorkspaces.running = true;
                }
            }
        }
    }

    Process {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);

                if (root._activeWorkspaceNeedsUpdate) {
                    root._activeWorkspaceNeedsUpdate = false;
                    getActiveWorkspace.running = true;
                }
            }
        }
    }

    Process {
        id: syncWorkspaceMapProcess
    }

    function syncWorkspaceMap() {
        if (!Config.ready || !Config.options.bar.workspaces.useWorkspaceMap) return;
        const map = Config.options.bar.workspaces.workspaceMap;
        if (!map || map.length === 0) return;
        const monitorNames = root.monitors.map(m => m.name);
        if (monitorNames.length === 0) return;
        const shown = Config.options.bar.workspaces.shown || 10;
        
        syncWorkspaceMapProcess.command = [
            "python3",
            `${Directories.scriptPath}/hyprland/sync_workspace_map.py`,
            JSON.stringify(map),
            JSON.stringify(monitorNames),
            shown.toString()
        ];
        syncWorkspaceMapProcess.running = true;
    }

    function syncWorkspaceGroupSize(shown) {
        let script = `touch "$HOME/.config/hypr/custom/variables.lua" && sed -i '/workspaceGroupSize =/d' "$HOME/.config/hypr/custom/variables.lua" && echo "workspaceGroupSize = ${shown}" >> "$HOME/.config/hypr/custom/variables.lua" && hyprctl reload`;
        Quickshell.execDetached(["bash", "-c", script]);
    }

    // Trigger sync functions on changes
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                root.syncWorkspaceMap();
                const useMap = Config.options.bar.workspaces.useWorkspaceMap;
                const shown = Config.options.bar.workspaces.shown || 10;
                root.syncWorkspaceGroupSize(useMap ? shown : 10);
            }
        }
    }

    Connections {
        target: Config.ready ? Config.options.bar.workspaces : null
        ignoreUnknownSignals: true

        function onWorkspaceMapChanged() {
            root.syncWorkspaceMap();
        }

        function onUseWorkspaceMapChanged() {
            root.syncWorkspaceMap();
            const useMap = Config.options.bar.workspaces.useWorkspaceMap;
            const shown = Config.options.bar.workspaces.shown || 10;
            root.syncWorkspaceGroupSize(useMap ? shown : 10);
        }

        function onShownChanged() {
            root.syncWorkspaceMap();
            const useMap = Config.options.bar.workspaces.useWorkspaceMap;
            const shown = Config.options.bar.workspaces.shown || 10;
            root.syncWorkspaceGroupSize(useMap ? shown : 10);
        }
    }

    onMonitorsChanged: {
        root.syncWorkspaceMap();
    }
}