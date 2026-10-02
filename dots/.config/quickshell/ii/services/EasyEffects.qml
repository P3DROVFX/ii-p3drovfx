pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs
import qs.modules.common
import "easyEffects/EasyEffectsLogic.js" as Logic

/**
 * EasyEffects: whether it runs, which preset each pipeline has, the presets on disk and
 * the per-device defaults, and every action the shell takes on it.
 *
 * Nothing here polls on its own. Whether EasyEffects runs is its sink existing in
 * PipeWire; the preset lists and the device defaults are folders the model watches.
 * The live state (bypass, loaded presets) lives only inside EasyEffects, so it is asked
 * over its local socket at the moments it can change from here: EasyEffects starting,
 * the output device changing, and after every command this service sends. A surface
 * that wants it fresh while open (the app, the quick dialog, the island card) holds a
 * refresh (`hold`), and only while one is held does a slow re-ask run.
 *
 * Commands go over EasyEffects' socket (one connection, opened on demand and dropped
 * when idle). Without it (EasyEffects 7, a sandbox that hides it) the command line
 * does the same for loading presets and bypass.
 */
Singleton {
    id: root

    // ── Install ─────────────────────────────────────────────────────────
    property bool available: false
    property bool isFlatpak: false
    property int majorVersion: 8
    readonly property string flatpakId: "com.github.wwmm.easyeffects"

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") ?? ""
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (root.home + "/.local/share")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (root.home + "/.config")
    readonly property string sandboxRoot: root.home + "/.var/app/" + root.flatpakId
    /// Where presets live: EasyEffects 8 keeps them in the data dir, 7 in the config dir.
    readonly property string presetsDir: {
        if (root.isFlatpak)
            return root.sandboxRoot + (root.majorVersion >= 8 ? "/data" : "/config") + "/easyeffects";
        return (root.majorVersion >= 8 ? root.dataHome : root.configHome) + "/easyeffects";
    }
    readonly property var socketCandidates: root.isFlatpak
        ? [root.runtimeDir + "/app/" + root.flatpakId + "/EasyEffectsServer", root.runtimeDir + "/EasyEffectsServer"]
        : [root.runtimeDir + "/EasyEffectsServer"]

    // ── Live state ──────────────────────────────────────────────────────
    readonly property bool running: root.available && root._sinkPresent
    readonly property bool _sinkPresent: Pipewire.nodes.values.some(node => node?.name === "easyeffects_sink")
    property bool starting: false
    property bool bypassed: false
    /// Effects are on: EasyEffects runs and is not bypassed. What every on/off surface shows.
    readonly property bool active: root.running && !root.bypassed
    property string outputPreset: ""
    property string inputPreset: ""

    // ── Presets and device defaults ─────────────────────────────────────
    property list<string> outputPresets: []
    property list<string> inputPresets: []
    property var outputAutoload: []
    property var inputAutoload: []

    readonly property PwNode outputDevice: Pipewire.defaultAudioSink
    readonly property PwNode inputDevice: Pipewire.defaultAudioSource
    readonly property string outputDeviceName: root.outputDevice?.name ?? ""
    readonly property string outputRoute: Logic.routeFor(root.outputDevice?.properties)
    readonly property string inputDeviceName: root.inputDevice?.name ?? ""
    readonly property string inputRoute: Logic.routeFor(root.inputDevice?.properties)
    /// The preset EasyEffects loads for the current output device, "" when none is set.
    readonly property string outputDeviceDefault: Logic.autoloadFor(root.outputAutoload, root.outputDeviceName, root.outputRoute)?.["preset-name"] ?? ""
    readonly property string inputDeviceDefault: Logic.autoloadFor(root.inputAutoload, root.inputDeviceName, root.inputRoute)?.["preset-name"] ?? ""

    readonly property var options: Config.options?.easyEffects ?? null
    readonly property string cycleScope: root.options?.cycleScope ?? "device"
    /// What the quick switchers offer for the output device in use.
    readonly property var devicePresets: Logic.presetsForDevice(root.outputPresets, root.outputDeviceDefault,
        root.outputPreset, root.cycleScope)

    signal presetsChanged(string pipeline)
    signal presetFileWritten(string pipeline, string name)

    // ── Naming helpers, shared by every surface ─────────────────────────
    function iconFor(name: string): string {
        return Logic.iconFor(name);
    }

    function shortName(name: string): string {
        return Logic.shortName(name);
    }

    function familyOf(name: string): string {
        return Logic.familyOf(name);
    }

    function presetPath(pipeline: string, name: string): string {
        return `${root.presetsDir}/${pipeline}/${name}.json`;
    }

    // ── Actions ─────────────────────────────────────────────────────────
    /// Compatibility: callers used to poll this. State now arrives by itself.
    function fetchActiveState(): void {
        root.refreshState();
    }

    function enable(): void {
        if (!root.running) {
            root._pendingBypass = 0;
            root.start();
            return;
        }
        root.setBypass(false);
    }

    function disable(): void {
        if (root.running)
            root.setBypass(true);
    }

    function toggle(): void {
        if (root.active)
            root.disable();
        else
            root.enable();
    }

    function start(): void {
        if (!root.available || root.running || root.starting)
            return;
        root.starting = true;
        root._launchedHere = true;
        startTimeout.restart();
        const args = root.majorVersion >= 8 ? ["--service-mode", "--hide-window"] : ["--gapplication-service"];
        Quickshell.execDetached(root.isFlatpak ? ["flatpak", "run", root.flatpakId].concat(args) : ["easyeffects"].concat(args));
    }

    function quit(): void {
        if (!root.running)
            return;
        if (!root._send("quit_app"))
            root._cli(["-q"]);
    }

    function openNativeWindow(): void {
        if (!root.running) {
            Quickshell.execDetached(root.isFlatpak ? ["flatpak", "run", root.flatpakId] : ["easyeffects"]);
            return;
        }
        if (!root._send("show_window"))
            Quickshell.execDetached(root.isFlatpak ? ["flatpak", "run", root.flatpakId] : ["easyeffects"]);
    }

    function setBypass(on: bool): void {
        if (!root.running)
            return;
        root.bypassed = on;
        if (!root._send(`global_bypass:${on ? 1 : 0}`))
            root._cli(["-b", on ? "1" : "2"]);
        root._afterCommand();
    }

    function toggleBypass(): void {
        root.setBypass(!root.bypassed);
    }

    /**
     * Loads a preset. `announce` shows the OSD pill: the quick switchers pass it, the app
     * and the editor's own reloads do not.
     */
    function loadPreset(name: string, pipeline = "output", announce = false): void {
        if (!root.available || name.length === 0)
            return;
        if (!root.running) {
            root._pendingPreset = { name: name, pipeline: pipeline, announce: announce };
            root.start();
            return;
        }
        if (pipeline === "input")
            root.inputPreset = name;
        else
            root.outputPreset = name;
        if (!root._send(`load_preset:${pipeline}:${name}`))
            root._cli(["-l", name]);
        if (announce)
            root.announce(name);
        root._afterCommand();
    }

    /// The next (or previous) preset for the output device, wrapping around.
    function cyclePreset(step = 1): void {
        const next = Logic.stepPreset(root.devicePresets, root.outputPreset, step);
        if (next.length > 0)
            root.loadPreset(next, "output", true);
    }

    function announce(name: string): void {
        if (!(root.options?.osdOnSwitch ?? true))
            return;
        GlobalStates.osdNoticeRequested(Logic.iconFor(name), "EasyEffects", name);
    }

    // ── Live values (the app's editor) ──────────────────────────────────
    /// Sets one property on the running pipeline. Not saved: the preset file is.
    function setProperty(pipeline: string, path: string, value: string): void {
        if (path.length > 0 && value !== null)
            root._send(`set_property:${pipeline}:${path}:${value}`);
    }

    /// Reads properties off the running pipeline; `done` gets the raw replies in order.
    function getProperties(pipeline: string, paths: var, done: var): void {
        const list = Array.from(paths ?? []);
        const replies = new Array(list.length).fill(undefined);
        if (list.length === 0 || !root.running) {
            done(replies);
            return;
        }
        let remaining = list.length;
        list.forEach((path, i) => {
            const sent = root._send(`get_property:${pipeline}:${path}`, reply => {
                replies[i] = reply;
                if (--remaining === 0)
                    done(replies);
            });
            if (!sent && --remaining === 0)
                done(replies);
        });
    }

    // ── Refresh ─────────────────────────────────────────────────────────
    function refreshState(): void {
        if (!root.running)
            return;
        // Bypass answers with a bare digit and no newline, so it always rides in front
        // of a query whose answer ends the line (see _onLine).
        root._send("get_global_bypass", reply => {
            if (reply !== null)
                root.bypassed = reply === "1";
        }, true);
        root._send("get_last_loaded_preset:output", reply => {
            if (reply !== null)
                root.outputPreset = reply;
        });
        root._send("get_last_loaded_preset:input", reply => {
            if (reply !== null)
                root.inputPreset = reply;
        });
    }

    function refreshPresets(): void {
        outputFolder.rebuild();
        inputFolder.rebuild();
        root.refreshAutoload();
    }

    property var _holds: ({})
    readonly property bool held: Object.keys(root._holds).length > 0

    /// A surface that shows live state asks for it to stay fresh while it is open.
    function hold(key: string, on: bool): void {
        const next = Object.assign({}, root._holds);
        if (on)
            next[key] = true;
        else
            delete next[key];
        root._holds = next;
        if (on)
            root.refreshState();
    }

    Timer {
        id: heldRefresh
        interval: 4000
        repeat: true
        running: root.held && root.running
        onTriggered: root.refreshState()
    }

    function _afterCommand(): void {
        settleRefresh.restart();
    }

    // A command lands asynchronously; ask again once it has.
    Timer {
        id: settleRefresh
        interval: 700
        onTriggered: root.refreshState()
    }

    // ── Starting and the device default ─────────────────────────────────
    property var _pendingPreset: null
    property int _pendingBypass: -1

    onRunningChanged: {
        if (!root.running) {
            root._dropSocket();
            root._socketIndex = 0;
            root._socketFailed = false;
            return;
        }
        root.starting = false;
        startTimeout.stop();
        // EasyEffects' own start runs a beat after its sink appears.
        startSettle.restart();
    }

    Timer {
        id: startSettle
        interval: 1500
        onTriggered: root._onStarted()
    }

    Timer {
        id: startTimeout
        interval: 15000
        onTriggered: root.starting = false
    }

    function _onStarted(): void {
        if (root._pendingBypass === 0) {
            root._pendingBypass = -1;
            root.setBypass(false);
        }
        if (root._pendingPreset) {
            const pending = root._pendingPreset;
            root._pendingPreset = null;
            root.loadPreset(pending.name, pending.pipeline, pending.announce);
            return;
        }
        root.refreshState();
        // EasyEffects does not apply the device's autoload preset when it starts on a
        // Pro Audio sink (wwmm/easyeffects#5275), so apply it here - but only to a start
        // that just happened. After a shell reload EasyEffects has been running all along
        // and may hold a preset picked since; its process age tells the two apart, where
        // the sink appearing cannot (PipeWire lists its nodes a moment after the shell).
        if (!(root.options?.applyDeviceDefaultOnStart ?? true) || root.outputDeviceDefault.length === 0)
            return;
        uptimeProc.running = false;
        uptimeProc.running = true;
    }

    Process {
        id: uptimeProc
        command: ["bash", "-c", "ps -o etimes= -C easyeffects 2>/dev/null | sort -n | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seconds = parseInt(String(this.text).trim(), 10);
                // Flatpak's process may not be visible by that name; a start we launched
                // ourselves counts as fresh either way.
                const fresh = isNaN(seconds) ? root._launchedHere : seconds < 30;
                root._launchedHere = false;
                if (fresh && root.outputDeviceDefault.length > 0 && root.outputPreset !== root.outputDeviceDefault)
                    root.loadPreset(root.outputDeviceDefault, "output", false);
            }
        }
    }

    property bool _launchedHere: false
    Component.onCompleted: detectProc.running = true

    // Switching the default device switches the preset: the one saved for the new device
    // (its autoload entry) is loaded. EasyEffects is meant to do that itself, but it
    // doesn't reliably (Pro Audio sinks, a service started without a window, Bluetooth
    // devices that reconnect), so the shell does it and EasyEffects' own switch, when it
    // happens, is only the same load twice. A device with no default keeps what is loaded.
    // Only a change of device (or of its route) triggers it, never the user's own pick.
    property string _pendingDevicePipeline: ""

    onOutputDeviceNameChanged: root._deviceChanged("output")
    onOutputRouteChanged: root._deviceChanged("output")
    onInputDeviceNameChanged: root._deviceChanged("input")
    onInputRouteChanged: root._deviceChanged("input")

    function _deviceChanged(pipeline: string): void {
        if (!root.running)
            return;
        root._pendingDevicePipeline = root._pendingDevicePipeline === "" || root._pendingDevicePipeline === pipeline ? pipeline : "both";
        deviceSettle.restart();
    }

    function applyDeviceDefault(pipeline: string): void {
        const wanted = pipeline === "input" ? root.inputDeviceDefault : root.outputDeviceDefault;
        const loaded = pipeline === "input" ? root.inputPreset : root.outputPreset;
        if (wanted.length === 0 || wanted === loaded)
            return;
        if (!(pipeline === "input" ? root.inputPresets : root.outputPresets).includes(wanted))
            return;
        root.loadPreset(wanted, pipeline, true);
    }

    // The new device's entry and EasyEffects' own switch both need a moment: wait, read
    // what EasyEffects did, then fill in what it left.
    Timer {
        id: deviceSettle
        interval: 1200
        onTriggered: {
            root.refreshState();
            deviceApply.restart();
        }
    }

    Timer {
        id: deviceApply
        interval: 600
        onTriggered: {
            const pending = root._pendingDevicePipeline;
            root._pendingDevicePipeline = "";
            if (!(root.options?.applyDeviceDefaultOnSwitch ?? true))
                return;
            if (pending === "output" || pending === "both")
                root.applyDeviceDefault("output");
            if (pending === "input" || pending === "both")
                root.applyDeviceDefault("input");
        }
    }

    Process {
        id: detectProc
        command: ["bash", "-c", "if command -v easyeffects >/dev/null 2>&1; then "
            + "v=$(easyeffects --version 2>/dev/null | grep -o '[0-9]\\+' | head -1); echo \"native ${v:-8}\"; "
            + "elif command -v flatpak >/dev/null 2>&1 && flatpak info com.github.wwmm.easyeffects >/dev/null 2>&1; then "
            + "v=$(flatpak info com.github.wwmm.easyeffects 2>/dev/null | awk '/Version:/{print $2}' | cut -d. -f1); "
            + "echo \"flatpak ${v:-8}\"; else echo none; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(this.text).trim().split(/\s+/);
                if (parts[0] !== "native" && parts[0] !== "flatpak")
                    return;
                root.isFlatpak = parts[0] === "flatpak";
                root.majorVersion = parseInt(parts[1], 10) || 8;
                root.available = true;
            }
        }
    }

    // ── Preset folders ──────────────────────────────────────────────────
    component PresetFolder: FolderListModel {
        id: folder
        required property string pipeline
        required property string subdir
        property list<string> names: []

        function rebuild(): void {
            // An empty folder URL makes the model list the working directory instead.
            if (!root.available) {
                folder.names = [];
                return;
            }
            const list = [];
            for (let i = 0; i < folder.count; i++)
                list.push(String(folder.get(i, "fileBaseName")));
            list.sort((a, b) => a.localeCompare(b));
            folder.names = list;
        }

        folder: root.available ? `file://${root.presetsDir}/${folder.subdir}` : ""
        nameFilters: ["*.json"]
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
        onCountChanged: rebuildTimer.restart()
        onStatusChanged: {
            if (folder.status === FolderListModel.Ready)
                rebuildTimer.restart();
        }

        // Several rows arrive at once on the first listing; collect them in one pass.
        property Timer rebuildTimer: Timer {
            interval: 120
            onTriggered: folder.rebuild()
        }
    }

    PresetFolder {
        id: outputFolder
        pipeline: "output"
        subdir: "output"
        onNamesChanged: {
            root.outputPresets = outputFolder.names;
            root.presetsChanged("output");
        }
    }

    PresetFolder {
        id: inputFolder
        pipeline: "input"
        subdir: "input"
        onNamesChanged: {
            root.inputPresets = inputFolder.names;
            root.presetsChanged("input");
        }
    }

    PresetFolder {
        id: outputAutoloadFolder
        pipeline: "output"
        subdir: "autoload/output"
        onNamesChanged: root.refreshAutoload()
    }

    PresetFolder {
        id: inputAutoloadFolder
        pipeline: "input"
        subdir: "autoload/input"
        onNamesChanged: root.refreshAutoload()
    }

    function refreshAutoload(): void {
        if (!root.available)
            return;
        // Killing a read in flight would hand its cut-off output to the parser.
        if (autoloadProc.running) {
            root._autoloadAgain = true;
            return;
        }
        autoloadProc.running = true;
    }

    property bool _autoloadAgain: false

    // Every autoload entry in one read: a pipeline tab, then the file on one line.
    Process {
        id: autoloadProc
        onRunningChanged: {
            if (autoloadProc.running || !root._autoloadAgain)
                return;
            root._autoloadAgain = false;
            Qt.callLater(root.refreshAutoload);
        }
        command: ["bash", "-c", "for p in output input; do for f in \"$1/autoload/$p\"/*.json; do "
            + "[ -f \"$f\" ] || continue; printf '%s\\t' \"$p\"; tr -d '\\n' < \"$f\"; echo; done; done",
            "_", root.presetsDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const output = [];
                const input = [];
                String(this.text).split("\n").forEach(line => {
                    const tab = line.indexOf("\t");
                    if (tab <= 0)
                        return;
                    try {
                        const entry = JSON.parse(line.slice(tab + 1));
                        (line.slice(0, tab) === "input" ? input : output).push(entry);
                    } catch (error) {
                        console.warn("[EasyEffects] Unreadable autoload entry:", error);
                    }
                });
                root.outputAutoload = output;
                root.inputAutoload = input;
            }
        }
    }

    // ── Preset files ────────────────────────────────────────────────────
    /// Reads a preset; `done(object)` gets null when it is missing or unreadable.
    function readPreset(pipeline: string, name: string, done: var): void {
        root._job(["cat", root.presetPath(pipeline, name)], (code, text) => {
            if (code !== 0) {
                done(null);
                return;
            }
            try {
                done(JSON.parse(text));
            } catch (error) {
                console.warn("[EasyEffects] Unreadable preset", name, error);
                done(null);
            }
        });
    }

    /**
     * Reads every preset of a pipeline in one pass; `done({ name: preset })` gets the ones
     * that parse. One process instead of one `cat` per file, for the page that draws a
     * card (and a curve) for each preset.
     */
    function readAllPresets(pipeline: string, done: var): void {
        root._job(["bash", "-c", "for f in \"$1\"/*.json; do [ -f \"$f\" ] || continue; b=$(basename \"$f\" .json); "
            + "printf '%s\\t' \"$b\"; tr -d '\\n\\r' < \"$f\"; printf '\\n'; done", "_", `${root.presetsDir}/${pipeline}`], (code, text) => {
            const found = {};
            String(text).split("\n").forEach(line => {
                const tab = line.indexOf("\t");
                if (tab <= 0)
                    return;
                try {
                    found[line.slice(0, tab)] = JSON.parse(line.slice(tab + 1));
                } catch (error) {
                    console.warn("[EasyEffects] Unreadable preset", line.slice(0, tab));
                }
            });
            done(found);
        });
    }

    /**
     * Writes a preset. The previous file is kept in `.ii-backup/` beside it first, one
     * copy per preset, so an edit that goes wrong can be put back by hand.
     */
    function writePreset(pipeline: string, name: string, preset: var, done: var): void {
        const text = JSON.stringify(preset, null, 4);
        root._job(["bash", "-c", "set -e; d=\"$1\"; f=\"$d/$2.json\"; mkdir -p \"$d/.ii-backup\"; "
            + "[ -f \"$f\" ] && cp -f \"$f\" \"$d/.ii-backup/$2.json\"; printf '%s\\n' \"$3\" > \"$f.ii-tmp\"; "
            + "mv -f \"$f.ii-tmp\" \"$f\"", "_", `${root.presetsDir}/${pipeline}`, name, text], code => {
            if (code === 0)
                root.presetFileWritten(pipeline, name);
            if (done)
                done(code === 0);
        });
    }

    function deletePreset(pipeline: string, name: string, done: var): void {
        root._job(["bash", "-c", "d=\"$1\"; mkdir -p \"$d/.ii-backup\"; mv -f \"$d/$2.json\" \"$d/.ii-backup/$2.json\"",
            "_", `${root.presetsDir}/${pipeline}`, name], code => {
            if (done)
                done(code === 0);
        });
    }

    function renamePreset(pipeline: string, from: string, to: string, done: var): void {
        root._job(["bash", "-c", "d=\"$1\"; [ ! -e \"$d/$3.json\" ] && mv \"$d/$2.json\" \"$d/$3.json\"",
            "_", `${root.presetsDir}/${pipeline}`, from, to], code => {
            if (code === 0) {
                if (pipeline === "output" && root.outputPreset === from)
                    root.loadPreset(to, "output", false);
                if (pipeline === "input" && root.inputPreset === from)
                    root.loadPreset(to, "input", false);
            }
            if (done)
                done(code === 0);
        });
    }

    function duplicatePreset(pipeline: string, from: string, to: string, done: var): void {
        root._job(["bash", "-c", "d=\"$1\"; [ ! -e \"$d/$3.json\" ] && cp \"$d/$2.json\" \"$d/$3.json\"",
            "_", `${root.presetsDir}/${pipeline}`, from, to], code => {
            if (done)
                done(code === 0);
        });
    }

    /// Copies a preset file in; its pipeline comes from the file's own top-level key.
    function importPreset(path: string, done: var): void {
        root._job(["cat", path], (code, text) => {
            let preset = null;
            try {
                preset = code === 0 ? JSON.parse(text) : null;
            } catch (error) {
                preset = null;
            }
            const pipeline = preset?.output ? "output" : preset?.input ? "input" : "";
            if (!pipeline) {
                if (done)
                    done(false, "");
                return;
            }
            const base = Logic.sanitizePresetName(String(path).split("/").pop().replace(/\.json$/i, ""));
            const taken = pipeline === "input" ? root.inputPresets : root.outputPresets;
            const name = Logic.uniqueName(base || "Imported", taken);
            root.writePreset(pipeline, name, preset, ok => {
                if (done)
                    done(ok, name);
            });
        });
    }

    /// Asks for a preset file (kdialog or zenity, whichever is installed) and imports it.
    function pickAndImport(done: var): void {
        root._job(["bash", "-c", "if command -v kdialog >/dev/null 2>&1; then "
            + "kdialog --getopenfilename \"$HOME\" '*.json' 2>/dev/null; elif command -v zenity >/dev/null 2>&1; then "
            + "zenity --file-selection --file-filter='EasyEffects presets | *.json' 2>/dev/null; else exit 3; fi"], (code, text) => {
            const path = String(text).trim();
            if (code === 3 || path.length === 0) {
                if (done)
                    done(false, "", code === 3);
                return;
            }
            root.importPreset(path, (ok, name) => {
                if (done)
                    done(ok, name, false);
            });
        });
    }

    /**
     * Makes `preset` the one EasyEffects loads whenever `device` is the default, in the
     * file EasyEffects itself reads. An empty preset removes the entry.
     */
    function setDeviceDefault(pipeline: string, device: var, preset: string, done: var): void {
        if (!device)
            return;
        const route = Logic.routeFor(device.properties);
        const dir = `${root.presetsDir}/autoload/${pipeline}`;
        const file = Logic.autoloadFileName(device.name, route);
        const text = JSON.stringify({
            "device": device.name,
            "device-description": device.description ?? "",
            "device-profile": route,
            "preset-name": preset
        }, null, 4);
        const script = preset.length > 0
            ? "mkdir -p \"$1\" && printf '%s\\n' \"$3\" > \"$1/$2\""
            : "rm -f \"$1/$2\"";
        root._job(["bash", "-c", script, "_", dir, file, text], code => {
            root.refreshAutoload();
            if (done)
                done(code === 0);
        });
    }

    // One-shot processes: the output and the exit code, whichever arrives last.
    Component {
        id: jobComponent

        Process {
            id: job
            property var callback: null
            property int exitCode: -1
            property bool exited: false
            property bool drained: false

            function finish(): void {
                if (!job.exited || !job.drained)
                    return;
                const callback = job.callback;
                job.callback = null;
                if (callback)
                    callback(job.exitCode, collector.text);
                job.destroy();
            }

            stdout: StdioCollector {
                id: collector
                onStreamFinished: {
                    job.drained = true;
                    job.finish();
                }
            }
            onExited: code => {
                job.exitCode = code;
                job.exited = true;
                job.finish();
            }
        }
    }

    function _job(argv: var, done: var): void {
        const job = jobComponent.createObject(root, { command: argv });
        // Assigned after creation: initial properties are copied, and a function must
        // stay the caller's own closure.
        job.callback = done ?? null;
        job.running = true;
    }

    function _cli(args: var): void {
        const base = root.isFlatpak ? ["flatpak", "run", root.flatpakId] : ["easyeffects"];
        Quickshell.execDetached(base.concat(args));
    }

    // ── Socket ──────────────────────────────────────────────────────────
    // EasyEffects answers some commands with a line, one with a bare digit, and most
    // with nothing, all on one connection and in order. `_pending` lists the answers
    // still owed; `prefix` marks the bare digit, which arrives glued to the next line.
    property var _socket: null
    property var _pending: []
    property var _outbox: []
    property string _buffer: ""
    property int _socketIndex: 0
    property bool _socketFailed: false

    Component {
        id: socketComponent

        Socket {
            id: socket
            parser: SplitParser {
                splitMarker: ""
                onRead: data => root._onData(data)
            }
            onConnectedChanged: {
                if (socket.connected) {
                    root._flushOutbox();
                } else if (root._socket === socket) {
                    root._onSocketLost();
                }
            }
            onError: {
                if (root._socket === socket && !socket.connected)
                    root._onSocketLost();
            }
        }
    }

    /**
     * Sends one command. `reply` receives its answer (null when none came); commands
     * that answer nothing pass no callback. False when there is no socket to send on,
     * so the caller can fall back to the command line.
     */
    function _send(line: string, reply: var, prefix: bool): bool {
        if (!root.running || root._socketFailed) {
            if (reply)
                reply(null);
            return false;
        }
        if (!root._socket) {
            root._buffer = "";
            root._socket = socketComponent.createObject(root, {
                path: root.socketCandidates[Math.min(root._socketIndex, root.socketCandidates.length - 1)],
                connected: true
            });
        }
        if (reply) {
            root._pending = root._pending.concat([{ callback: reply, prefix: prefix === true }]);
            replyTimeout.restart();
        }
        root._outbox = root._outbox.concat([line + "\n"]);
        if (root._socket.connected)
            root._flushOutbox();
        idleClose.restart();
        return true;
    }

    function _flushOutbox(): void {
        if (!root._socket || !root._socket.connected || root._outbox.length === 0)
            return;
        root._socket.write(root._outbox.join(""));
        root._socket.flush();
        root._outbox = [];
    }

    function _onData(data: string): void {
        root._buffer += data;
        let newline = root._buffer.indexOf("\n");
        while (newline !== -1) {
            let line = root._buffer.slice(0, newline);
            root._buffer = root._buffer.slice(newline + 1);
            while (root._pending.length > 0 && root._pending[0].prefix) {
                const owed = root._pending[0];
                root._pending = root._pending.slice(1);
                owed.callback(line.charAt(0));
                line = line.slice(1);
            }
            if (root._pending.length > 0) {
                const owed = root._pending[0];
                root._pending = root._pending.slice(1);
                owed.callback(line);
            }
            newline = root._buffer.indexOf("\n");
        }
        if (root._pending.length === 0)
            replyTimeout.stop();
        else
            replyTimeout.restart();
    }

    function _onSocketLost(): void {
        // Lines still in the outbox never reached EasyEffects: the socket did not open.
        const unsent = root._outbox.map(line => line.trim()).filter(line => !line.startsWith("get_"));
        const neverConnected = root._outbox.length > 0;
        root._dropSocket();
        if (!neverConnected || !root.running)
            return;
        // Try the next place the socket could be; after the last, use the command line.
        if (root._socketIndex + 1 < root.socketCandidates.length) {
            root._socketIndex++;
            unsent.forEach(line => root._send(line));
            return;
        }
        root._socketFailed = true;
        console.warn("[EasyEffects] No local socket; falling back to the command line");
        unsent.forEach(line => root._replayOnCli(line));
    }

    function _replayOnCli(line: string): void {
        const load = line.match(/^load_preset:(input|output):(.+)$/);
        if (load)
            root._cli(["-l", load[2]]);
        else if (line === "global_bypass:1" || line === "global_bypass:0")
            root._cli(["-b", line.endsWith("1") ? "1" : "2"]);
        else if (line === "quit_app")
            root._cli(["-q"]);
    }

    function _dropSocket(): void {
        const owed = root._pending;
        root._pending = [];
        root._outbox = [];
        root._buffer = "";
        replyTimeout.stop();
        owed.forEach(entry => entry.callback(null));
        const socket = root._socket;
        root._socket = null;
        if (socket)
            socket.destroy();
    }

    // An answer that never comes would stall every later one behind it.
    Timer {
        id: replyTimeout
        interval: 2500
        onTriggered: {
            console.warn("[EasyEffects] Socket stopped answering; reconnecting on the next command");
            root._dropSocket();
        }
    }

    // Nothing to say for a while: let the connection go.
    Timer {
        id: idleClose
        interval: 15000
        onTriggered: {
            if (root._pending.length === 0)
                root._dropSocket();
            else
                idleClose.restart();
        }
    }
}
