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
    /**
     * The outputs worth offering in a picker: without the sinks whose port is
     * reported unplugged - the HDMI/DisplayPort outputs of a GPU with no screen
     * on them. The default sink always stays, whatever its port says. Modes and
     * EasyEffects keep `outputDevices`, so they can still target such an output.
     */
    readonly property list<var> selectableOutputDevices: root.outputDevices.filter(node =>
        !root.unavailableSinkNames.includes(node.name) || node.id === root.sink?.id)
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

    readonly property string analogOutputScript: `${Directories.scriptPath}/audio/analog-output.py`
    readonly property string analogOutputPython: {
        const venv = Quickshell.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV");
        return venv ? venv.replace(/^~\//, Quickshell.env("HOME") + "/") + "/bin/python" : "python3";
    }
    readonly property bool analogOutputSwitching: analogOutputSwitch.running
    signal analogOutputSwitchFinished(bool success)

    function switchAnalogOutput(choice) {
        if (root.analogOutputSwitching || multiOutputProc.running) return;
        analogOutputSwitch.command = [root.analogOutputPython, root.analogOutputScript, "switch",
            choice.card, choice.port, choice.profile];
        analogOutputSwitch.running = true;
    }

    Process {
        id: analogOutputSwitch
        stdout: StdioCollector { id: analogOutputResult }
        stderr: StdioCollector { id: analogOutputError }
        onExited: exitCode => {
            const sinkName = analogOutputResult.text.trim();
            const success = exitCode === 0 && sinkName.length > 0;
            if (success && root.multiOutputActive)
                root.setMultiOutputSinks([sinkName]);
            if (!success)
                console.warn("[Audio] " + analogOutputError.text.trim());
            root.analogOutputSwitchFinished(success);
        }
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
        root.watchBluetoothDeparture();
    }

    // ── Bluetooth fallback ───────────────────────────────────────────────────
    // When the default Bluetooth sink goes away WirePlumber falls back to the
    // highest priority.session, and a USB microphone's jack sink outranks the
    // laptop speaker - the sound went into the microphone. The shell picks the
    // replacement instead (scripts/audio/fallback-sink.py): another Bluetooth
    // sink, else a sink with a real output. Setting the default by hand would
    // stop WirePlumber switching back when the headset returns, so that is done
    // here too, as long as the fallback is still what plays.
    readonly property string fallbackSinkScript: `${Directories.scriptPath}/audio/fallback-sink.py`
    property string lastSinkName: ""
    property string departedBluetoothSink: ""
    property int fallbackAttempts: 0
    property string autoFallbackFrom: ""
    property string autoFallbackTo: ""

    function sinkNodeByName(name) {
        return Pipewire.nodes.values.find(n => n.name === name && n.isSink && !n.isStream && n.audio) ?? null;
    }

    function watchBluetoothDeparture() {
        const name = root.sink?.name ?? "";
        if (name === "")
            return; // The default is briefly null between two sinks.
        const previous = root.lastSinkName;
        root.lastSinkName = name;
        if (root.autoFallbackTo !== "" && name !== root.autoFallbackTo && name !== root.autoFallbackFrom) {
            // Chosen by hand since: no switching back behind the user's back.
            root.autoFallbackFrom = "";
            root.autoFallbackTo = "";
        }
        if (previous.startsWith("bluez_output.") && name !== previous) {
            root.departedBluetoothSink = previous;
            root.fallbackAttempts = 0;
            fallbackDelay.restart();
        }
    }

    Timer {
        id: fallbackDelay
        interval: 700
        onTriggered: {
            const departed = root.departedBluetoothSink;
            // Still there: a hand-picked switch (or a virtual sink taking over), not a disconnect.
            if (departed === "" || root.sinkNodeByName(departed) || fallbackProc.running)
                return;
            fallbackProc.command = [root.analogOutputPython, root.fallbackSinkScript, departed];
            fallbackProc.running = true;
        }
    }

    Process {
        id: fallbackProc
        stdout: StdioCollector { id: fallbackResult }
        onExited: exitCode => {
            const departed = root.departedBluetoothSink;
            if (exitCode === 3 && ++root.fallbackAttempts < 5) {
                // The headset's card is still there: a profile switch, or the
                // disconnect has not landed yet. Ask again shortly.
                fallbackDelay.restart();
                return;
            }
            root.departedBluetoothSink = "";
            const chosen = exitCode === 0 ? fallbackResult.text.trim() : "";
            if (chosen === "" || chosen === (root.sink?.name ?? ""))
                return;
            const node = root.sinkNodeByName(chosen);
            if (node)
                Pipewire.preferredDefaultAudioSink = node;
            else
                Quickshell.execDetached(["pactl", "set-default-sink", chosen]);
            root.autoFallbackFrom = departed;
            root.autoFallbackTo = chosen;
        }
    }

    // Port availability is not on the PipeWire node, so pactl is asked; once per
    // change of the sink list, and whenever a picker opens (refreshSinkAvailability),
    // since plugging a screen in flips a port without adding a node.
    property list<string> unavailableSinkNames: []

    function refreshSinkAvailability() {
        if (sinkAvailabilityProc.running)
            sinkAvailabilityDebounce.restart();
        else
            sinkAvailabilityProc.running = true;
    }

    Timer {
        id: sinkAvailabilityDebounce
        interval: 400
        onTriggered: root.refreshSinkAvailability()
    }

    Process {
        id: sinkAvailabilityProc
        command: ["pactl", "-f", "json", "list", "sinks"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const unavailable = [];
                    for (const sink of JSON.parse(text || "[]")) {
                        const ports = sink.ports ?? [];
                        if (ports.length === 0)
                            continue;
                        const active = ports.find(port => port.name === sink.active_port);
                        if ((active && active.availability === "not available")
                                || ports.every(port => port.availability === "not available"))
                            unavailable.push(sink.name);
                    }
                    if (JSON.stringify(unavailable) !== JSON.stringify(root.unavailableSinkNames))
                        root.unavailableSinkNames = unavailable;
                } catch (e) {
                    console.warn("[Audio] could not read sink availability:", e);
                }
            }
        }
    }

    onOutputDevicesChanged: {
        sinkAvailabilityDebounce.restart();
        if (root.autoFallbackFrom === "")
            return;
        const back = root.sinkNodeByName(root.autoFallbackFrom);
        if (!back)
            return;
        if ((root.sink?.name ?? "") === root.autoFallbackTo)
            Pipewire.preferredDefaultAudioSink = back;
        root.autoFallbackFrom = "";
        root.autoFallbackTo = "";
    }

    Component.onCompleted: {
        if (sink && sink.audio) {
            root.value = sink.audio.volume;
            root.muted = sink.audio.muted;
        }
        root.lastSinkName = sink?.name ?? "";
        root.refreshSinkAvailability();
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
