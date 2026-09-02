pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

/**
 * Back, home and recents for the tablet family.
 *
 * One place, because three things need them and they must agree: the dock's navigation
 * buttons, the edge gestures, and any keybind. Having the dock own this meant a gesture
 * could only reach it by reaching into a window.
 */
Singleton {
    id: root

    /// Whether any shell surface is covering the desktop. "Home" means none of them are.
    readonly property bool anyShellSurfaceOpen: GlobalStates.tabletAppId.length > 0
        || GlobalStates.appDrawerOpen
        || GlobalStates.recentsOpen
        || GlobalStates.dashboardPanelOpen
        || GlobalStates.sidebarLeftOpen

    /**
     * Android's back: leave whatever shell surface is on top, innermost first.
     *
     * There is no generic "previous screen" for an arbitrary application, so this stops at
     * the shell's own surfaces and is inert on a bare home screen — exactly as Android's
     * back is once there is nothing left to pop.
     */
    function back() {
        if (GlobalStates.tabletAppId.length > 0) {
            GlobalStates.closeTabletApp();
            return true;
        }
        if (GlobalStates.appDrawerOpen) {
            GlobalStates.appDrawerOpen = false;
            return true;
        }
        if (GlobalStates.recentsOpen) {
            GlobalStates.recentsOpen = false;
            return true;
        }
        if (GlobalStates.dashboardPanelOpen) {
            GlobalStates.dashboardPanelOpen = false;
            return true;
        }
        if (GlobalStates.sidebarLeftOpen) {
            GlobalStates.sidebarLeftOpen = false;
            return true;
        }
        return false;
    }

    /**
     * Which workspace this family treats as the home screen of a monitor.
     *
     * Home has to be the same place every time. The icons the user arranges are stored per
     * workspace, so a Home that lands on "whichever workspace happens to be free right now"
     * shows a blank screen and leaves the arrangement behind on the workspace it was made
     * on — reachable only by swiping past whatever is open there. On Android, Home is always
     * the same page of the launcher.
     *
     * Auto means the lowest ordinary workspace of that monitor, which is what a default
     * Hyprland gives each output. Special workspaces are negative and never a home.
     */
    function homeWorkspaceId(monitorName) {
        const configured = Number(Config.options?.tablet?.homeWorkspace ?? 0);
        if (configured > 0)
            return configured;

        const name = (monitorName && monitorName.length > 0)
            ? monitorName
            : (Hyprland.focusedMonitor?.name ?? "");

        let lowest = -1;
        for (const workspace of (Hyprland.workspaces?.values ?? [])) {
            const id = Number(workspace?.id ?? -1);
            if (id <= 0)
                continue;
            if (name.length > 0 && (workspace.monitor?.name ?? "") !== name)
                continue;
            if (lowest === -1 || id < lowest)
                lowest = id;
        }
        // Nothing to read yet on a session that has only just come up. Workspace 1 is the
        // one Hyprland creates first, so it is the right guess rather than a made-up one.
        return lowest === -1 ? 1 : lowest;
    }

    /// Close everything and land on the home screen — the same one every time.
    function home(screenName) {
        root.closeShellSurfaces();
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${root.homeWorkspaceId(screenName ?? "")} })`);
    }

    function recents(screenName) {
        root.closeShellSurfaces();
        GlobalStates.openRecents(screenName ?? "");
    }

    function appDrawer(screenName) {
        GlobalStates.openAppDrawer(screenName ?? "");
    }

    function closeShellSurfaces() {
        GlobalStates.closeTabletApp();
        GlobalStates.appDrawerOpen = false;
        GlobalStates.recentsOpen = false;
    }

    /// True when the current workspace has nothing open on it — the home screen proper.
    function onHomeScreen() {
        const workspaceId = HyprlandData.activeWorkspace?.id ?? -1;
        if (workspaceId === -1)
            return true;
        return HyprlandData.hyprlandClientsForWorkspace(workspaceId).length === 0;
    }
}
