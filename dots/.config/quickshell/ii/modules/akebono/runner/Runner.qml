pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggle the Akebono runner"
        onPressed: GlobalStates.desktopRunnerOpen = !GlobalStates.desktopRunnerOpen
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggle the Akebono runner on release (tap Super)"

        // Debounce: prevents double-fire from the global shortcuts protocol.
        // When SUPER_L is bound as both modifier (SUPER) and trigger key (SUPER_L),
        // the compositor sends `released` twice: once for the key release and once
        // for the modifier state change. The 50ms window catches both without
        // affecting normal press-release cycles.
        property int _lastToggleTime: 0

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            const now = Date.now();
            if (now - _lastToggleTime < 50)
                return;
            _lastToggleTime = now;

            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.desktopRunnerOpen = !GlobalStates.desktopRunnerOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of the runner being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Open the Akebono runner in clipboard mode"
        onPressed: {
            GlobalStates.desktopRunnerPendingQuery = Config.options.search.prefix.clipboard;
            GlobalStates.desktopRunnerOpen = true;
        }
    }
    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Open the Akebono glyph picker, or the runner in emoji mode"
        onPressed: {
            if (Config.options.akebono.runner.glyphPicker) {
                GlobalStates.desktopGlyphPickerOpen = !GlobalStates.desktopGlyphPickerOpen;
                return;
            }
            GlobalStates.desktopRunnerPendingQuery = Config.options.search.prefix.emojis;
            GlobalStates.desktopRunnerOpen = true;
        }
    }

    IpcHandler {
        target: "akebonoRunner"
        function toggle(): void { GlobalStates.desktopRunnerOpen = !GlobalStates.desktopRunnerOpen }
        function open(): void { GlobalStates.desktopRunnerOpen = true }
        function close(): void { GlobalStates.desktopRunnerOpen = false }
    }
}
