import QtQuick
import qs.services
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * Which device the app is looking at, apart from the one the system is playing through.
 *
 * EasyEffects processes one device at a time (the default one), but every device can have
 * a preset saved for the moment it becomes the default. This is that choice: the connected
 * devices of the pipeline, the one being looked at (the default one until another is
 * picked), and what it starts with. Looking at another device changes nothing about the
 * sound; choosing its preset only saves it for later, and `use()` makes it the output.
 */
QtObject {
    id: root

    property string pipeline: "output"
    property string wantedOutput: ""
    property string wantedInput: ""

    readonly property bool input: root.pipeline === "input"
    // The one playing first, then the ones with a preset saved, then the rest.
    readonly property var devices: {
        const rank = node => node === root.current ? 0 : root.savedFor(node).length > 0 ? 1 : 2;
        return Array.from(root.input ? Audio.inputDevices : Audio.outputDevices)
            .filter(node => !String(node.name).startsWith("easyeffects_"))
            .map((node, index) => ({ node: node, index: index }))
            .sort((a, b) => rank(a.node) - rank(b.node) || a.index - b.index)
            .map(entry => entry.node);
    }
    /// The device the system plays through (or records from) now.
    readonly property var current: root.input ? EasyEffects.inputDevice : EasyEffects.outputDevice
    readonly property string wanted: root.input ? root.wantedInput : root.wantedOutput
    readonly property var node: root.devices.find(candidate => candidate.name === root.wanted) ?? root.current
    readonly property bool isCurrent: root.node === root.current
    readonly property string name: root.node?.name ?? ""
    readonly property string label: Audio.friendlyDeviceName(root.node)
    readonly property string route: Logic.routeFor(root.node?.properties)
    readonly property var entries: root.input ? EasyEffects.inputAutoload : EasyEffects.outputAutoload
    /// The preset this device starts with, "" when it has none.
    readonly property string saved: Logic.autoloadFor(root.entries, root.name, root.route)?.["preset-name"] ?? ""
    /// What is "in use" on this device: what is loaded when it is the one playing, otherwise
    /// what it will start with.
    readonly property string preset: root.isCurrent ? (root.input ? EasyEffects.inputPreset : EasyEffects.outputPreset) : root.saved

    function look(deviceName: string): void {
        if (root.input)
            root.wantedInput = deviceName;
        else
            root.wantedOutput = deviceName;
    }

    function savedFor(node: var): string {
        return Logic.autoloadFor(root.entries, node?.name ?? "", Logic.routeFor(node?.properties))?.["preset-name"] ?? "";
    }

    function symbolFor(node: var): string {
        return Logic.deviceSymbol(`${node?.properties?.["device.form-factor"] ?? ""} ${node?.properties?.["device.icon-name"] ?? ""} ${node?.description ?? ""} ${node?.name ?? ""}`, root.pipeline);
    }

    /// Saves `preset` as what the looked-at device starts with ("" clears it).
    function save(preset: string, done: var): void {
        EasyEffects.setDeviceDefault(root.pipeline, root.node, preset, done);
    }

    /// Makes the looked-at device the system's output (or input).
    function use(): void {
        if (!root.node)
            return;
        if (root.input)
            Audio.setDefaultSource(root.node);
        else
            Audio.setDefaultSink(root.node);
        root.look("");
    }

    // A device that went away is no longer being looked at.
    onDevicesChanged: {
        if (root.wanted.length > 0 && !root.devices.some(candidate => candidate.name === root.wanted))
            root.look("");
    }
}
