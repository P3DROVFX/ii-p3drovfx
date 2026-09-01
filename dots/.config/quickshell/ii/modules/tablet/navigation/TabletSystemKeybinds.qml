import QtQuick
import Quickshell
import qs
import Quickshell.Hyprland
import Quickshell.Wayland

import qs.modules.common
import qs.modules.tablet.appWindow

/**
 * Global shortcuts whose meaning changes with the Tablet Family.
 *
 * The Hyprland binds keep stable IPC target names across families. The owner of each target
 * is selected by the composition root, which lets Super open the tablet app drawer without
 * loading the desktop Overview or reactivating its legacy overlays.
 */
Scope {
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Opens the tablet app drawer on Super release"

        // SUPER_L is both modifier and trigger, so Hyprland can report two releases. Match
        // the desktop debounce and its interrupt contract: Super+another key must not open
        // the drawer after the modified shortcut finishes.
        property int lastToggleTime: 0

        onPressed: GlobalStates.superReleaseMightTrigger = true
        onReleased: {
            const now = Date.now();
            if (now - lastToggleTime < 50)
                return;
            lastToggleTime = now;
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.toggleAppDrawer("");
        }
    }

    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Prevents a modified Super shortcut from opening the app drawer"
        onPressed: GlobalStates.superReleaseMightTrigger = false
    }

    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Opens tablet recents"
        onPressed: GlobalStates.toggleRecents("")
    }

    // The policies keybind opens the first policies app instead of a sidebar this family
    // does not have. GlobalStates owns the shortcut — it is shared by every family — so the
    // redirect is installed as a handler rather than by registering a second shortcut of
    // the same name.
    Component.onCompleted: {
        GlobalStates.leftSidebarHandler = () => {
            const first = TabletSystemApps.available.find(app => app.id.startsWith("policies."));
            if (first)
                GlobalStates.toggleTabletApp(first.id);
        };
        // Back is the gesture a phone user reaches for most, so it has to be bindable like
        // any other. TabletNavigation knows the order to unwind in; GlobalStates does not.
        GlobalStates.navigateBackHandler = () => TabletNavigation.back();
    }
    Component.onDestruction: {
        GlobalStates.leftSidebarHandler = null;
        GlobalStates.navigateBackHandler = null;
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Opens Keybinds as a tablet application"
        onPressed: GlobalStates.toggleTabletApp("keybinds")
    }

    GlobalShortcut {
        name: "usageToggle"
        description: "Opens App Usage as a tablet application"
        onPressed: GlobalStates.toggleTabletApp("usage")
    }

    GlobalShortcut {
        name: "modesToggle"
        description: "Opens Modes & Routines as a tablet application"
        onPressed: GlobalStates.toggleTabletApp("modes")
    }
}
