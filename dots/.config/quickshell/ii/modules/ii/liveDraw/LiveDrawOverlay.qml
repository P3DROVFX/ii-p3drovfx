pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.draw

/**
 * Live draw on the desktop: annotate the screen, over every application, while
 * recording it or sharing it.
 *
 * The tablet's pen tray, ported: the same sheets, the same tray, the same store
 * (services/LiveDraw.qml). What changes is what it is for. On the tablet it is a pen
 * coming out of its slot; here it is somebody pointing at something in a video call or a
 * screencast — so the tray can be dragged off whatever is being shown and folded down to
 * the pen, and the ink still belongs to the workspace it was drawn on.
 *
 * Opened from the keybind (Super+Alt+D), the dashboard's quick toggle, the bar's utility
 * buttons, the dock's widget, the recording controls in the bar popup and the island,
 * the search and `qs -c ii ipc call liveDraw toggle`. All of them call LiveDraw.toggle().
 *
 * One surface per screen, and only while there is a reason: the tray is open, or that
 * screen has ink on one of its workspaces. An always-mapped Overlay layer is a surface
 * the compositor blends over every frame for nothing — and one that keeps a fullscreen
 * game off direct scanout.
 */
Scope {
    id: root

    GlobalShortcut {
        name: "liveDrawToggle"
        description: "Draw on the screen"
        onPressed: LiveDraw.toggle()
    }

    IpcHandler {
        target: "liveDraw"

        function draw(): string {
            LiveDraw.open();
            return "Drawing. The pencil puts the pen down; close puts the toolbar away.";
        }

        function stop(): string {
            LiveDraw.close();
            return "Toolbar closed. Anything drawn stays on its workspace.";
        }

        function toggle(): string {
            return LiveDraw.trayOpen ? stop() : draw();
        }

        /// Files the focused screen's sheet into Notes, as the tray's button does.
        function save(): string {
            GlobalStates.liveDrawSaveRequest++;
            return "Saving the focused screen's sheet to Notes.";
        }

        function clear(): string {
            LiveDraw.clearAll();
            LiveDraw.close();
            return "Every sheet rubbed out.";
        }
    }

    // The search and the touch gestures reach live draw through the family's handler.
    Component.onCompleted: GlobalStates.liveDrawHandler = () => LiveDraw.toggle()

    Component.onDestruction: {
        if (GlobalStates.liveDrawHandler)
            GlobalStates.liveDrawHandler = null;
        // Leaving the family must take the pen with it, or the next family opens with a
        // full-screen input grab nobody asked for. A live reload rebuilds this scope too,
        // and that one keeps the pen where it was (the store survives it).
        if (!PanelFamily.isIi)
            LiveDraw.close();
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                // The tray lives on the focused monitor only, so the other monitors need a
                // surface only for ink of their own.
                readonly property bool focused: String(Hyprland.focusedMonitor?.name ?? "") === screenScope.modelData.name
                active: LiveDraw.enabled
                    && ((LiveDraw.trayOpen && focused) || LiveDraw.screenHasInk(screenScope.modelData.name))

                sourceComponent: LiveDrawWindow {
                    screen: screenScope.modelData
                    namespace: "quickshell:liveDraw"
                    // Surfaces that replace the desktop: ink over them would annotate the
                    // wrong thing.
                    coveredByShell: GlobalStates.overviewOpen
                        || GlobalStates.sessionOpen
                        || GlobalStates.screenLocked
                    // Tools that need the pointer for a moment. The ink stays, since it is
                    // usually what the screenshot or the translation is of.
                    inputSuspended: GlobalStates.regionSelectorOpen
                        || GlobalStates.screenTranslatorOpen
                    trayMovable: true
                    // Just above the dock when it sits at the bottom, which is the dock's
                    // own published thickness at rest (the lens never moves the tray).
                    // A bottom bar is cleared the same way.
                    trayBottomMargin: {
                        const inset = GlobalStates.dockInsets[screenScope.modelData.name];
                        return (inset?.side === "bottom" ? inset.thickness : 0)
                            + (BarPlacement.bottom && !BarPlacement.vertical ? Appearance.sizes.barHeight : 0)
                            + Appearance.sizes.elevationMargin * 2;
                    }
                    parallaxEnabled: Config.options?.tablet?.liveDraw?.workspaceParallax ?? true
                }
            }
        }
    }
}
