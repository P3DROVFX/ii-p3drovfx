pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property real value: 0
    property bool muted: false
    
    function friendlyDeviceName(node) {
        if (!node) return Translation.tr("Unknown");
        if (node.name === root.multiOutputSinkName) return Translation.tr("Multi-output");
        return (node.nickname || node.description || Translation.tr("Unknown"));
     }
    function appNodeDisplayName(node) {
        return (node.properties["application.name"] || node.description || node.name)
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    // The combined sink and the streams it feeds its members with are plumbing:
    // the members are listed as devices, the combined sink is never picked by hand.
    function isMultiOutputNode(node) {
        return node.name === root.multiOutputSinkName || node.name.startsWith(`output.${root.multiOutputSinkName}_`)
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream && !root.isMultiOutputNode(node)
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream && !root.isMultiOutputNode(node)
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    function toggleMute() {
        Audio.sink.audio.muted = !Audio.sink.audio.muted
    }

    // Mic mute
    function toggleMicMute() {
        Audio.source.audio.muted = !Audio.source.audio.muted
    }

    function incrementVolume() {
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
        Audio.sink.audio.volume = Math.min(1, Audio.sink.audio.volume + step);
    }
    
    function decrementVolume() {
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
        Audio.sink.audio.volume -= step;
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Sends one app's stream to a sink. pipewire-pulse turns the move into the
    // stream's target.object and WirePlumber remembers it for that app.
    function routeStream(stream, sink) {
        const serial = stream?.properties["object.serial"];
        if (serial === undefined || !sink) return;
        Quickshell.execDetached(["pactl", "move-sink-input", String(serial), sink.name]);
    }

    function outputDeviceIcon(node) {
        if (!node) return "media_output";
        if (node.name === root.multiOutputSinkName) return "speaker_group";
        const name = node.name;
        const formFactor = node.properties["device.form-factor"] ?? "";
        if (name.startsWith("bluez_") || formFactor === "headphone" || formFactor === "headset") return "headphones";
        if (name.indexOf("hdmi") !== -1 || name.indexOf("HDMI") !== -1 || name.indexOf("DisplayPort") !== -1) return "tv";
        if (name === "easyeffects_sink") return "graphic_eq";
        return "speaker";
    }

    // Multi-output: one combined sink (scripts/audio/multi-output.sh) that plays
    // on every member at once. Its state lives in PipeWire, so a reload reads it
    // back instead of keeping a copy.
    readonly property string multiOutputSinkName: "ii_multi_output"
    property list<string> multiOutputSinks: []
    readonly property bool multiOutputActive: multiOutputSinks.length >= 2
    property list<string> pendingMultiOutputSinks: []
    property bool multiOutputPending: false

    // 2+ names combine them and make the result default; 1 name drops the
    // combined sink and makes that sink default.
    function setMultiOutputSinks(names) {
        root.multiOutputSinks = names; // Optimistic, corrected by the script's report
        root.pendingMultiOutputSinks = names;
        root.multiOutputPending = true;
        if (!multiOutputProc.running) root.flushMultiOutput();
    }
    function flushMultiOutput() {
        if (!root.multiOutputPending) return;
        root.multiOutputPending = false;
        multiOutputProc.command = [multiOutputProc.script, "set", ...root.pendingMultiOutputSinks];
        multiOutputProc.running = true;
    }

    onSinkChanged: {
        if (sink && sink.audio) {
            root.value = sink.audio.volume;
            root.muted = sink.audio.muted;
        }
    }

    Component.onCompleted: {
        if (sink && sink.audio) {
            root.value = sink.audio.volume;
            root.muted = sink.audio.muted;
        }
        multiOutputProc.command = [multiOutputProc.script, "status"];
        multiOutputProc.running = true;
    }

    Process {
        id: multiOutputProc
        readonly property string script: `${Directories.scriptPath}/audio/multi-output.sh`
        property var lines: []
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line.length > 0) multiOutputProc.lines.push(line);
            }
        }
        onExited: {
            const reported = multiOutputProc.lines;
            multiOutputProc.lines = [];
            if (root.multiOutputPending) {
                root.flushMultiOutput();
                return;
            }
            root.multiOutputSinks = reported.length >= 2 ? reported : [];
        }
    }



    // Internals
    PwObjectTracker {
        objects: [sink, source]
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (sink && sink.audio) {
                const oldValue = root.value;
                root.value = sink.audio.volume;
                // oldValue > 0 skips the initial readout on startup/reload
                if (!isNaN(root.value) && oldValue > 0 && Math.abs(root.value - oldValue) > 0.0001) {
                    SoundService.playEvent("volumeChange", "audio-volume-change");
                }
            }
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
        function onMutedChanged() {
            if (sink && sink.audio) {
                const wasMuted = root.muted;
                root.muted = sink.audio.muted;
                // Blip on unmute as confirmation; a blip on mute would be
                // inaudible through the now-muted sink anyway.
                if (wasMuted && !root.muted) {
                    SoundService.playEvent("volumeChange", "audio-volume-change");
                }
            }
        }
    }

}
