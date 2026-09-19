pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.services

/**
 * Takes keyboard focus away from a window that was sent to a workspace no longer on screen.
 *
 * A silent move (Super + Alt + number, the overview's drag and drop) asks Hyprland to refocus,
 * but its refocus hit-tests the cursor, lands on the wallpaper - a layer surface that takes no
 * keyboard - and gives up. The window that just left keeps the keys: typing still reaches it,
 * and type-to-search never arms on the desktop it left empty.
 *
 * Hyprland does refocus properly when a layer surface that held the keyboard unmaps: it falls
 * back to the workspace's own focus history, which on an emptied workspace is nothing. So a
 * one-pixel, input-transparent surface grabs the keyboard for a moment and lets go again. No
 * workspace switch, so no animation, no workspace history change and no workspace destroyed.
 *
 * When windows remain on the workspace Hyprland already hands focus to one of them, and the
 * active window is then on screen - nothing to do.
 */
Singleton {
    id: root

    readonly property bool active: grabLoader.active

    /// The move event lands before the window list and active workspace are refreshed, and a
    /// following move switches workspace a beat later. Judge once both have settled.
    Timer {
        id: settleTimer
        interval: 200
        onTriggered: {
            const toplevel = ToplevelManager.activeToplevel;
            if (!toplevel || GlobalStates.screenLocked)
                return;
            if (HyprlandData.toplevelOnScreen(toplevel))
                return;
            grabLoader.active = true;
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "movewindowv2")
                return;
            settleTimer.restart();
        }
    }

    LazyLoader {
        id: grabLoader

        PanelWindow {
            id: grabWindow
            screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name)
                ?? Quickshell.screens[0]
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:focusRelease"
            WlrLayershell.keyboardFocus: grabWindow.holding ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            /**
             * Unmapping would not do: Hyprland then refocuses from the cursor, finds the
             * wallpaper and hands the keys straight back to the window. Dropping to no
             * interactivity while still mapped is the one path that clears the keyboard.
             */
            property bool holding: true

            Timer {
                running: true
                interval: 150
                onTriggered: {
                    if (grabWindow.holding) {
                        grabWindow.holding = false;
                        restart();
                        return;
                    }
                    grabLoader.active = false;
                }
            }
        }
    }
}
