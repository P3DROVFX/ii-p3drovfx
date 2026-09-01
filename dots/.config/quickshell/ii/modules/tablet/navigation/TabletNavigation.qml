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

    /// Close everything and land on an empty workspace, which is this family's home screen.
    function home() {
        root.closeShellSurfaces();
        Hyprland.dispatch("hl.dsp.focus({ workspace = 'empty' })");
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
