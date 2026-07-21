pragma Singleton
pragma ComponentBehavior: Bound;
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property bool active: Config.ready ? Config.options.sounds.monoAudio : false

    property int loadedModuleIndex: -1     // pactl load-module returns module index
    property string savedDefaultSinkName: "" // para restaurar
    readonly property string monoSinkName: "ii_mono_downmix"

    onActiveChanged: {
        if (active) {
            enable();
        } else {
            disable();
        }
    }

    Component.onCompleted: {
        if (active) {
            enable();
        }
    }

    function toggle() {
        if (Config.ready) {
            Config.options.sounds.monoAudio = !Config.options.sounds.monoAudio;
        }
    }

    function enable() {
        if (loadedModuleIndex !== -1) return; // Already enabled
        const masterSinkName = (Audio.sink && Audio.sink.name) ? Audio.sink.name : "";
        if (!masterSinkName) {
            // Audio sink not ready yet, retry when ready
            retryTimer.start();
            return;
        }
        retryTimer.stop();
        root.savedDefaultSinkName = masterSinkName;
        enableProc.command = ["bash", "-c",
            `pactl load-module module-remap-sink sink_name=${root.monoSinkName} master=${masterSinkName} channels=2 channel_map=mono,mono master_channel_map=left,right sink_properties=device.description='ii-Mono'`]
        enableProc.running = true;
    }

    function disable() {
        retryTimer.stop();
        if (loadedModuleIndex === -1) return;
        disableProc.command = ["bash", "-c",
            `pactl unload-module ${root.loadedModuleIndex}` +
            (root.savedDefaultSinkName ? `; pactl set-default-sink ${root.savedDefaultSinkName}` : "")]
        disableProc.running = true;
    }

    Timer {
        id: retryTimer
        interval: 1000
        repeat: true
        onTriggered: root.enable()
    }

    Process {
        id: enableProc
        stdout: SplitParser {
            onRead: d => {
                const idx = parseInt(d.trim());
                if (!isNaN(idx)) {
                    root.loadedModuleIndex = idx;
                    Quickshell.execDetached(["pactl", "set-default-sink", root.monoSinkName]);
                }
            }
        }
    }

    Process {
        id: disableProc
        onExited: (code, st) => {
            root.loadedModuleIndex = -1;
            root.savedDefaultSinkName = "";
        }
    }
}
