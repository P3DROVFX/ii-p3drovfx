pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import "../../../services/easyEffects/EasyEffectsLogic.js" as Logic
import "../../../services/easyEffects/EasyEffectsPlugins.js" as Plugins

/**
 * The preset the app edits: the one loaded on the pipeline shown, read from its file.
 *
 * Knob changes are written into the in-memory preset and, when live apply is on, sent
 * to the running pipeline a beat later (batched per property, so a dragged slider sends
 * its last value, not every step). Nothing reaches the file until `save()`. Changing
 * the chain itself (adding, removing, reordering) cannot be done live: those save the
 * preset at once, edits included, and reload it.
 *
 * Lives with the app window and goes with it.
 */
QtObject {
    id: root

    property string pipeline: "output"
    readonly property string presetName: root.pipeline === "input" ? EasyEffects.inputPreset : EasyEffects.outputPreset
    readonly property bool liveApply: Config.options.easyEffects?.liveApply ?? true
    readonly property var table: Plugins.plugins

    property var data: null
    property string savedText: ""
    property bool loading: false
    property bool saving: false
    property string error: ""
    readonly property bool dirty: root.data !== null && JSON.stringify(root.data) !== root.savedText
    readonly property var chain: Logic.chainOf(root.data, root.pipeline)
    readonly property bool ready: root.data !== null && !root.loading

    signal saved()

    onPresetNameChanged: root.reload()
    onPipelineChanged: root.reload()
    Component.onCompleted: root.reload()

    function reload(): void {
        root._flushLive(true);
        root.error = "";
        if (root.presetName.length === 0) {
            root.data = null;
            root.savedText = "";
            return;
        }
        const wanted = root.presetName;
        const pipeline = root.pipeline;
        root.loading = true;
        EasyEffects.readPreset(pipeline, wanted, preset => {
            if (wanted !== root.presetName || pipeline !== root.pipeline)
                return;
            root.loading = false;
            if (!preset) {
                root.data = null;
                root.savedText = "";
                root.error = Translation.tr("Couldn't read \"%1\"").arg(wanted);
                return;
            }
            // A preset for the other pipeline would edit nothing; start it an empty chain.
            if (!preset[pipeline])
                preset[pipeline] = { blocklist: [], plugins_order: [] };
            root.savedText = JSON.stringify(preset);
            root.data = preset;
        });
    }

    // ── Reading ──────────────────────────────────────────────────────────
    function blockOf(instance: string): var {
        return root.data?.[root.pipeline]?.[instance] ?? null;
    }

    function specOf(instance: string): var {
        return root.table[Logic.instanceParts(instance).plugin] ?? null;
    }

    function nameOf(instance: string): string {
        const parts = Logic.instanceParts(instance);
        const base = root.table[parts.plugin]?.name ?? Logic.labelFor(parts.plugin.replace(/_/g, "-"));
        const siblings = root.chain.filter(id => Logic.instanceParts(id).plugin === parts.plugin).length;
        return siblings > 1 ? `${base} ${parts.index + 1}` : base;
    }

    function value(instance: string, section: string, key: string): var {
        return Logic.valueAt(root.data, root.pipeline, instance, section, key);
    }

    // ── Editing ──────────────────────────────────────────────────────────
    /**
     * One control's new value. `band` and `channel` locate a banded key: the section is
     * "band3" for a multiband effect, "left/band3" for an equalizer channel.
     */
    function setValue(instance: string, control: var, value: var, band: int, channel: string): void {
        const section = control.propPattern
            ? (channel ? `${channel}/band${band}` : `band${band}`)
            : (control.section ?? "");
        root.data = Logic.setValue(root.data, root.pipeline, instance, section, control.key, value);
        if (!root.liveApply)
            return;
        const path = Logic.socketPath(instance, control, band, channel || "");
        const encoded = Logic.encodeValue(control, value);
        if (path.length === 0 || encoded === null)
            return;
        root._live[path] = encoded;
        liveTimer.restart();
    }

    function setBypass(instance: string, on: bool): void {
        root.setValue(instance, { key: "bypass", prop: "bypass", type: "bool" }, on, 0, "");
    }

    function resetEffect(instance: string): void {
        const plugin = Logic.instanceParts(instance).plugin;
        const block = Logic.defaultBlock(root.table, plugin);
        if (!block)
            return;
        const next = JSON.parse(JSON.stringify(root.data));
        next[root.pipeline][instance] = block;
        root.data = next;
        root.save();
    }

    function addEffect(plugin: string): void {
        root.data = Logic.addEffect(root.data, root.pipeline, root.table, plugin, -1);
        root.save();
    }

    function removeEffect(instance: string): void {
        root.data = Logic.removeEffect(root.data, root.pipeline, instance);
        root.save();
    }

    function moveEffect(from: int, to: int): void {
        root.data = Logic.moveEffect(root.data, root.pipeline, from, to);
        root.save();
    }

    /// Writes the preset and loads it again, so EasyEffects runs exactly what is on disk.
    function save(): void {
        if (!root.data || root.presetName.length === 0)
            return;
        root._flushLive(true);
        const name = root.presetName;
        const pipeline = root.pipeline;
        const snapshot = JSON.parse(JSON.stringify(root.data));
        root.saving = true;
        EasyEffects.writePreset(pipeline, name, snapshot, ok => {
            root.saving = false;
            if (!ok) {
                root.error = Translation.tr("Couldn't save \"%1\"").arg(name);
                return;
            }
            root.savedText = JSON.stringify(snapshot);
            EasyEffects.loadPreset(name, pipeline, false);
            root.saved();
        });
    }

    /// Drops the unsaved edits, on screen and in the running pipeline.
    function revert(): void {
        root._live = ({});
        liveTimer.stop();
        if (root.presetName.length > 0)
            EasyEffects.loadPreset(root.presetName, root.pipeline, false);
        root.reload();
    }

    // ── Live apply ───────────────────────────────────────────────────────
    property var _live: ({})

    function _flushLive(drop: bool): void {
        const pending = root._live;
        root._live = ({});
        liveTimer.stop();
        if (drop)
            return;
        Object.keys(pending).forEach(path => EasyEffects.setProperty(root.pipeline, path, pending[path]));
    }

    property Timer liveTimer: Timer {
        interval: 90
        onTriggered: root._flushLive(false)
    }
}
