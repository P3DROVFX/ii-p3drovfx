pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * EasyEffects in the shell: the keybinds and the IPC target, and the app window.
 *
 * The Scope stays loaded whatever the app setting says, so switching presets from a
 * keybind or a script works for everyone; only the window is gated. It is the clock
 * app's RetainedLoader: built when the app opens, kept hidden 30 s after it closes so a
 * quick reopen is instant, then destroyed with everything in it.
 */
Scope {
    id: root

    readonly property var tabIds: ["presets", "effects", "devices"]
    readonly property bool appEnabled: Config.options.easyEffects?.appEnable ?? true

    function requestOpen(tab = ""): void {
        if (!root.appEnabled)
            return;
        GlobalStates.openEasyEffectsApp(root.tabIds.includes(tab) ? tab : "");
    }

    function requestClose(): void {
        GlobalStates.easyEffectsAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.easyEffectsAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        requested: GlobalStates.easyEffectsAppOpen && root.appEnabled
        retainFor: 30000
        sourceComponent: EasyEffectsAppWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "easyEffectsToggle"
        description: "Toggles the EasyEffects app"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "easyEffectsNextPreset"
        description: "Switches to the next EasyEffects preset for the output device"
        onPressed: EasyEffects.cyclePreset(1)
    }

    GlobalShortcut {
        name: "easyEffectsPreviousPreset"
        description: "Switches to the previous EasyEffects preset for the output device"
        onPressed: EasyEffects.cyclePreset(-1)
    }

    GlobalShortcut {
        name: "easyEffectsBypassToggle"
        description: "Turns EasyEffects' effects off or back on"
        onPressed: {
            EasyEffects.toggle();
            GlobalStates.osdPillRequested("graphic_eq", EasyEffects.active
                ? Translation.tr("Sound effects off") : Translation.tr("Sound effects on"),
                EasyEffects.active ? "off" : "on");
        }
    }

    IpcHandler {
        target: "easyeffects"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        /// presets | effects | devices
        function openTab(tab: string): void {
            root.requestOpen(String(tab ?? ""));
        }

        /// Loads an output preset by name.
        function preset(name: string): void {
            EasyEffects.loadPreset(String(name ?? ""), "output", true);
        }

        function inputPreset(name: string): void {
            EasyEffects.loadPreset(String(name ?? ""), "input", true);
        }

        function next(): void {
            EasyEffects.cyclePreset(1);
        }

        function previous(): void {
            EasyEffects.cyclePreset(-1);
        }

        /// on | off | toggle: "on" turns the effects off (bypass on).
        function bypass(state: string): void {
            if (state === "on")
                EasyEffects.disable();
            else if (state === "off")
                EasyEffects.enable();
            else
                EasyEffects.toggle();
        }

        function status(): string {
            return JSON.stringify({
                available: EasyEffects.available,
                running: EasyEffects.running,
                bypassed: EasyEffects.bypassed,
                output: EasyEffects.outputPreset,
                input: EasyEffects.inputPreset,
                device: EasyEffects.outputDeviceName,
                deviceDefault: EasyEffects.outputDeviceDefault,
                cycle: EasyEffects.devicePresets
            });
        }
    }
}
