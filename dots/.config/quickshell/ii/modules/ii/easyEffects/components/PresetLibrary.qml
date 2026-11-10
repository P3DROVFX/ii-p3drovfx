pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * What the preset cards show about each preset: how many effects it chains, which, and
 * the tone curve of its equalizers. Read from the preset files in one pass for the
 * pipeline shown, again when the folder changes or a preset is written, and kept as
 * plain summaries so the files are not held in memory.
 */
QtObject {
    id: root

    property string pipeline: "output"
    /// name -> { count, plugins, curve, hasEqualizer }
    property var info: ({})
    readonly property var frequencies: Logic.logFrequencies(64, 20, 20000)
    readonly property var flat: root.frequencies.map(() => 0)

    function infoOf(name: string): var {
        return root.info[name] ?? { count: 0, plugins: [], curve: root.flat, known: false };
    }

    function refresh(): void {
        const pipeline = root.pipeline;
        EasyEffects.readAllPresets(pipeline, presets => {
            if (pipeline !== root.pipeline)
                return;
            const next = {};
            Object.keys(presets).forEach(name => {
                const plugins = Logic.chainPlugins(presets[name], pipeline);
                next[name] = {
                    count: plugins.length,
                    plugins: plugins,
                    curve: Logic.chainResponse(presets[name], pipeline, root.frequencies),
                    // A curve only means something when an equalizer is switched on.
                    hasEqualizer: Logic.chainOf(presets[name], pipeline).some(id => /^(midside_)?equalizer#/.test(id)
                        && presets[name][pipeline]?.[id]?.bypass !== true),
                    known: true
                };
            });
            root.info = next;
        });
    }

    property Timer settle: Timer {
        interval: 200
        onTriggered: root.refresh()
    }

    property Connections service: Connections {
        target: EasyEffects
        function onPresetsChanged(pipeline: string): void {
            if (pipeline === root.pipeline)
                settle.restart();
        }
        function onPresetFileWritten(pipeline: string, name: string): void {
            if (pipeline === root.pipeline)
                settle.restart();
        }
    }

    onPipelineChanged: root.refresh()
    Component.onCompleted: root.refresh()
}
