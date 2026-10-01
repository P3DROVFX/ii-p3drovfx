pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property string presetsFilePath: Directories.config + "/illogical-impulse/dock-presets.json"

    property var presetsList: []
    property int currentPresetIndex: 0

    readonly property bool canSwitchPresets: (Config.options?.dock?.switchPresetsOnScroll ?? true) && (presetsList ? presetsList.length > 1 : false)
    readonly property int presetsCount: presetsList ? presetsList.length : 0

    // Transition & magnification states
    property bool isSwitchingPreset: false
    property bool magnificationSuspended: false
    property real dipProgress: 0.0
    property var _pendingPreset: null

    SequentialAnimation {
        id: switchAnimation

        // 1. Lower the dock down
        NumberAnimation {
            target: root
            property: "dipProgress"
            from: 0.0
            to: 1.0
            duration: Math.max(1, Math.round(180 * Appearance.animMultiplier))
            easing.type: Easing.InQuad
        }

        // 2. Apply the preset while lowered/off-screen
        ScriptAction {
            script: {
                if (root._pendingPreset) {
                    root.applyPreset(root._pendingPreset);
                    root._pendingPreset = null;
                }
            }
        }

        // Brief pause to allow the QML layout and repeaters to settle
        PauseAnimation {
            duration: Math.max(1, Math.round(50 * Appearance.animMultiplier))
        }

        // 3. Return the dock back up without magnification
        NumberAnimation {
            target: root
            property: "dipProgress"
            from: 1.0
            to: 0.0
            duration: Math.max(1, Math.round(220 * Appearance.animMultiplier))
            easing.type: Easing.OutCubic
        }

        // 4. Finish animation: dock has fully returned!
        ScriptAction {
            script: {
                root.isSwitchingPreset = false;
                animationSafetyTimer.stop();
                magResumeTimer.restart();
            }
        }
    }

    Timer {
        id: magResumeTimer
        interval: Math.max(1, Math.round(80 * Appearance.animMultiplier))
        repeat: false
        onTriggered: {
            root.magnificationSuspended = false;
        }
    }

    Timer {
        id: animationSafetyTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.isSwitchingPreset) {
                root.isSwitchingPreset = false;
                root.magnificationSuspended = false;
                root.dipProgress = 0.0;
                root._pendingPreset = null;
            }
        }
    }

    FileView {
        id: presetsFile
        path: root.presetsFilePath
        printErrors: false
        onLoaded: root.loadPresetsFromJson()
        onLoadFailed: root.presetsList = []
        onAdapterUpdated: root.loadPresetsFromJson()
    }

    function loadPresetsFromJson() {
        try {
            const raw = typeof presetsFile.text === "function" ? presetsFile.text() : presetsFile.text;
            if (!raw || raw.trim() === "") {
                presetsList = [];
                return;
            }
            let data = JSON.parse(raw);
            if (Array.isArray(data)) {
                presetsList = data;
            } else {
                presetsList = [];
            }
        } catch (e) {
            console.log("[DockPresets] Error parsing dock-presets.json:", e);
            presetsList = [];
        }
    }

    function savePresetsToFile(list) {
        try {
            presetsList = list;
            const json = JSON.stringify(list, null, 2);
            if (typeof presetsFile.setText === "function") {
                presetsFile.setText(json);
            } else {
                presetsFile.text = json;
            }
        } catch (e) {
            console.log("[DockPresets] Error saving dock-presets.json:", e);
        }
    }

    function findMatchingPresetIndex() {
        if (!presetsList || presetsList.length === 0) return -1;
        const currentApps = JSON.stringify(Config.options?.dock?.pinnedApps ?? []);
        const currentOrder = JSON.stringify(Config.options?.dock?.order ?? []);
        for (let i = 0; i < presetsList.length; i++) {
            const p = presetsList[i];
            if (!p) continue;
            if (p.pinnedApps && JSON.stringify(p.pinnedApps) !== currentApps) continue;
            if (p.order && JSON.stringify(p.order) !== currentOrder) continue;
            if (p.enableMediaWidget !== undefined && p.enableMediaWidget !== Config.options?.dock?.enableMediaWidget) continue;
            if (p.enableWeatherWidget !== undefined && p.enableWeatherWidget !== Config.options?.dock?.enableWeatherWidget) continue;
            if (p.enableSportsWidget !== undefined && p.enableSportsWidget !== Config.options?.dock?.enableSportsWidget) continue;
            if (p.enableLivePreviewWidget !== undefined && p.enableLivePreviewWidget !== Config.options?.dock?.enableLivePreviewWidget) continue;
            return i;
        }
        return -1;
    }

    function applyPreset(preset) {
        if (!preset) return;
        if (!Config.options?.dock) return;

        if (preset.pinnedApps) Config.options.dock.pinnedApps = Array.from(preset.pinnedApps);
        if (preset.pinnedFiles) Config.options.dock.pinnedFiles = Array.from(preset.pinnedFiles);
        if (preset.appGroups !== undefined) Config.options.dock.appGroups = Array.from(preset.appGroups);
        if (preset.order) Config.options.dock.order = Array.from(preset.order);
        if (preset.enableMediaWidget !== undefined) Config.options.dock.enableMediaWidget = preset.enableMediaWidget;
        if (preset.enableWeatherWidget !== undefined) Config.options.dock.enableWeatherWidget = preset.enableWeatherWidget;
        if (preset.enableSportsWidget !== undefined) Config.options.dock.enableSportsWidget = preset.enableSportsWidget;
        if (preset.enableLivePreviewWidget !== undefined) Config.options.dock.enableLivePreviewWidget = preset.enableLivePreviewWidget;
        if (preset.livePreviewAppId !== undefined) Config.options.dock.livePreviewAppId = preset.livePreviewAppId;
        if (preset.livePreviewSlots !== undefined) Config.options.dock.livePreviewSlots = preset.livePreviewSlots;
        if (preset.showPinButton !== undefined) Config.options.dock.showPinButton = preset.showPinButton;
        if (preset.showOverviewButton !== undefined) Config.options.dock.showOverviewButton = preset.showOverviewButton;
        if (preset.showTrashButton !== undefined) Config.options.dock.showTrashButton = preset.showTrashButton;
        if (preset.showPhoneButton !== undefined) Config.options.dock.showPhoneButton = preset.showPhoneButton;
        console.log("[DockPresets] Preset applied:", preset.name ?? "unnamed");
    }

    function saveCurrentAsPreset(name) {
        if (!name || name.trim() === "") return;
        if (!Config.options?.dock) return;

        let newPreset = {
            name: name.trim(),
            pinnedApps: Array.from(Config.options.dock.pinnedApps ?? []),
            pinnedFiles: Array.from(Config.options.dock.pinnedFiles ?? []),
            order: Array.from(Config.options.dock.order ?? []),
            appGroups: Array.from(Config.options.dock.appGroups ?? []),
            enableMediaWidget: Config.options.dock.enableMediaWidget,
            enableWeatherWidget: Config.options.dock.enableWeatherWidget,
            enableSportsWidget: Config.options.dock.enableSportsWidget,
            enableLivePreviewWidget: Config.options.dock.enableLivePreviewWidget,
            livePreviewAppId: Config.options.dock.livePreviewAppId,
            livePreviewSlots: Config.options.dock.livePreviewSlots,
            showPinButton: Config.options.dock.showPinButton,
            showOverviewButton: Config.options.dock.showOverviewButton,
            showTrashButton: Config.options.dock.showTrashButton,
            showPhoneButton: Config.options.dock.showPhoneButton
        };

        let current = Array.from(presetsList);
        let existingIdx = current.findIndex(p => p.name === newPreset.name);
        if (existingIdx >= 0) {
            current[existingIdx] = newPreset;
        } else {
            current.push(newPreset);
        }
        savePresetsToFile(current);
    }

    function deletePreset(index) {
        let current = Array.from(presetsList);
        if (index >= 0 && index < current.length) {
            current.splice(index, 1);
            savePresetsToFile(current);
        }
    }

    function cyclePreset(step) {
        if (!canSwitchPresets) return;
        if (isSwitchingPreset || switchAnimation.running) return;

        let activeIdx = findMatchingPresetIndex();
        if (activeIdx < 0) {
            activeIdx = currentPresetIndex;
        }
        if (activeIdx < 0 || activeIdx >= presetsList.length) {
            activeIdx = 0;
        }

        let nextIdx = (activeIdx + step) % presetsList.length;
        if (nextIdx < 0) {
            nextIdx += presetsList.length;
        }

        currentPresetIndex = nextIdx;
        let preset = presetsList[nextIdx];
        console.log("[DockPresets] Switching preset via scroll to [" + nextIdx + "]:", preset?.name);

        if (Appearance.reducedMotion) {
            applyPreset(preset);
            return;
        }

        _pendingPreset = preset;
        isSwitchingPreset = true;
        magnificationSuspended = true;
        animationSafetyTimer.restart();
        switchAnimation.restart();
    }

    property int accumulatedDelta: 0

    Timer {
        id: resetDeltaTimer
        interval: 350
        repeat: false
        onTriggered: {
            root.accumulatedDelta = 0;
        }
    }

    function handleWheelScroll(deltaY, deltaX) {
        if (!canSwitchPresets) return false;
        if (isSwitchingPreset || switchAnimation.running) return true;

        let d = deltaY !== 0 ? deltaY : deltaX;
        if (d === 0) return false;

        accumulatedDelta += d;
        resetDeltaTimer.restart();

        if (accumulatedDelta <= -100) {
            accumulatedDelta = 0;
            cyclePreset(1);
            return true;
        } else if (accumulatedDelta >= 100) {
            accumulatedDelta = 0;
            cyclePreset(-1);
            return true;
        }

        return true;
    }
}
