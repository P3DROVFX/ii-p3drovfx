pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common

/**
 * Draw on the screen with a pen, and keep it or file it.
 *
 * The reference is what a Galaxy Tab does when the stylus comes out: the screen becomes
 * something you can write on, over whatever was already there. Here the sheet belongs to
 * the workspace it was drawn on and stays there — over the applications, out of their
 * way — until it is rubbed out or saved into Notes.
 *
 * One surface per screen, loaded only while there is a reason: drawing mode, or ink on a
 * sheet somewhere. An always-mapped Overlay layer per monitor is a surface the
 * compositor composites forever for nothing.
 */
Scope {
    id: root

    readonly property bool enabled: Config.ready && (Config.options?.tablet?.liveDraw?.enable ?? true)

    /// `qs -c ii ipc call liveDraw draw` — the same door the bubble and the gestures use.
    IpcHandler {
        target: "liveDraw"

        function draw(): string {
            if (!root.enabled)
                return "Live draw is switched off in Settings.";
            TabletLiveDrawStore.ensureTools();
            TabletLiveDrawStore.drawing = true;
            return "Drawing. Tap the tray to keep it, save it, or put the pen down.";
        }

        function stop(): string {
            TabletLiveDrawStore.drawing = false;
            return "Pen down. Anything drawn stays on its workspace.";
        }

        function toggle(): string {
            return TabletLiveDrawStore.drawing ? stop() : draw();
        }

        /// Files the focused screen's sheet into Notes, as the tray's button does.
        ///
        /// Routed through a counter on GlobalStates rather than called directly: the ink
        /// and the canvas that can write it live in the per-screen surface, and only that
        /// surface knows whether it is the one the user is looking at.
        function save(): string {
            GlobalStates.liveDrawSaveRequest++;
            return "Saving the focused screen's sheet to Notes.";
        }

        function clear(): string {
            TabletLiveDrawStore.clearAll();
            TabletLiveDrawStore.drawing = false;
            return "Every sheet rubbed out.";
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: root.enabled
                    && (TabletLiveDrawStore.drawing || TabletLiveDrawStore.sheetCount > 0)

                sourceComponent: TabletLiveDrawWindow {
                    screen: screenScope.modelData
                }
            }
        }
    }

    // Live draw is a tablet surface, and the family unloading has to take the pen with
    // it — otherwise switching to the desktop shell leaves `drawing` set and the next
    // switch back opens with a full-screen input grab nobody asked for.
    Component.onDestruction: TabletLiveDrawStore.drawing = false
}
