pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * ii link: the channel to the ii tools Android app (~/Projects/ii-tools).
 *
 * The `ii_link` helper owns the network — TLS, the WebSocket, pairing and the paired
 * devices — and relays what an authenticated phone says (scripts/iiLink/PROTOCOL.md).
 * This side decides what a message does: a phone can only ask for an action listed in
 * `actions`, and only while its integration is switched on in Settings → ii tools.
 *
 * Costs nothing until a phone is paired: the paired devices are read from the helper's
 * peers.json, and the helper runs only while that list is non-empty or a pairing is
 * open. Users without the app never start it.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.iiTools ?? null
    readonly property bool enabled: Config.ready && (root.opts?.enable ?? true)
    readonly property bool remoteEnabled: root.opts?.remote?.enable ?? true
    readonly property bool audioEnabled: root.opts?.audio?.enable ?? true
    readonly property int port: root.opts?.port ?? 47210

    readonly property string helperDir: `${Directories.scriptPath}/iiLink`
    readonly property string binaryPath: `${root.helperDir}/ii_link`
    readonly property string stateDir: FileUtils.trimFileProtocol(`${Directories.state}/user/iilink`)

    // ── Helper lifecycle ────────────────────────────────────────────────
    property bool binaryPresent: false
    property bool probed: false
    /// True once the helper announced itself.
    property bool running: false
    property bool _restarting: false
    /// Pid of the helper while it runs, for Settings → ii tools → Diagnostics.
    readonly property int helperPid: helper.running ? helper.processId : 0

    readonly property RustHelperBuild helperBuild: RustHelperBuild {
        label: "IiLink"
        sourceDir: `${root.helperDir}/ii_link_src`
        crateName: "ii_link"
        onFinished: ok => {
            root.checkBinary();
            if (ok)
                root.restart();
        }
    }

    // ── Paired devices, known without running the helper ────────────────
    /// [{ id, name, model, pairedAt, lastSeen }]
    property var peers: []
    readonly property bool hasPeers: root.peers.length > 0

    FileView {
        id: peersFile
        path: root.enabled ? `${root.stateDir}/peers.json` : ""
        watchChanges: true
        printErrors: false
        onFileChanged: peersFile.reload()
        onLoaded: root._setPeers(peersFile.text())
        onLoadFailed: root.peers = []
    }

    function _setPeers(text): void {
        try {
            const list = JSON.parse(text);
            root.peers = Array.isArray(list) ? list.map(p => ({
                id: String(p.id ?? ""), name: String(p.name ?? ""), model: String(p.model ?? ""),
                pairedAt: Number(p.pairedAt ?? 0), lastSeen: Number(p.lastSeen ?? 0)
            })) : [];
        } catch (e) {
            root.peers = [];
        }
    }

    // ── What the helper reported ────────────────────────────────────────
    property string fingerprint: ""
    property string hostName: ""
    property var addresses: []
    property bool discovery: false
    /// "" or what last went wrong (a port in use, a broken state dir).
    property string lastError: ""

    /// The open pairing: { url, qr: ["0101…", …], expires }; null when none.
    property var pairing: null
    property bool pairingRequested: false
    /// The device that paired last, for the "Paired" confirmation.
    property var lastPaired: null

    /// dev id → { id, name, model, addr, since }
    property var connections: ({})
    readonly property var connectedList: Object.values(root.connections)
    readonly property bool phoneConnected: root.connectedList.length > 0

    // ── Actions a phone can ask for ─────────────────────────────────────
    /// The whole catalog. A phone sees (and can run) only those whose integration is on.
    /// `toggle` actions have a state the phone shows and keeps in step (`state`).
    readonly property var actions: [
        { id: "lock", name: Translation.tr("Lock"), icon: "lock", toggle: true },
        { id: "lockAod", name: Translation.tr("Lock and AOD"), icon: "screen_lock_portrait", toggle: true },
        { id: "oledSaver", name: Translation.tr("Always-on display"), icon: "brightness_empty", toggle: true },
        { id: "mediaMode", name: Translation.tr("Media mode"), icon: "music_note", toggle: true },
        { id: "scratchpad", name: Translation.tr("Scratchpad"), icon: "inventory_2", toggle: true }
    ]
    readonly property var allowedActions: root.remoteEnabled ? root.actions : []
    readonly property var capabilities: (root.remoteEnabled ? ["remote", "workspaces", "modes", "presets"] : [])
        .concat(root.audioEnabled ? ["audio"] : [])

    // What is on right now, read from the same state the shell itself draws from.
    readonly property bool _aodUp: (GlobalStates.oledSaverMonitors ?? []).length > 0
    readonly property var activeActions: {
        if (!root.remoteEnabled)
            return [];
        const on = [];
        if (GlobalStates.screenLocked)
            on.push("lock");
        if (GlobalStates.screenLocked && root._aodUp)
            on.push("lockAod");
        if (!GlobalStates.screenLocked && root._aodUp)
            on.push("oledSaver");
        if (GlobalStates.mediaModeActive)
            on.push("mediaMode");
        if (GlobalStates.scratchpadOpen)
            on.push("scratchpad");
        return on;
    }
    // A string, so the push happens on a real change and not on every re-evaluation.
    readonly property string _stateKey: root.activeActions.join(",")
    on_StateKeyChanged: {
        if (root.phoneConnected)
            root.sendTo("*", root._state());
    }

    function _state(): var {
        return { t: "state", on: root.activeActions };
    }

    /// Runs an action; returns "" when done, or why not.
    function _run(actionId): string {
        const active = root.activeActions.includes(actionId);
        switch (actionId) {
        case "lock":
            // Unlocking stays with the PC's own authentication.
            if (GlobalStates.screenLocked)
                return "locked";
            ShellActionRegistry.trigger("lock", "");
            return "";
        case "lockAod":
            if (active) {
                // Back to the lock screen; still locked.
                GlobalStates.oledSaverMonitors = [];
                return "";
            }
            if (!GlobalStates.screenLocked)
                ShellActionRegistry.trigger("lock", "");
            // The lock raises its AOD on the same monitors list once it is up.
            lockAodTimer.restart();
            return "";
        case "oledSaver":
            if (GlobalStates.screenLocked)
                return "locked";
            GlobalStates.toggleOledSaver();
            return "";
        case "mediaMode":
            GlobalStates.requestMediaMode("toggle");
            return "";
        case "scratchpad":
            Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
            return "";
        }
        return "unknown_action";
    }

    // ── Live topics: workspaces, modes, presets, audio ──────────────────
    // Each is pushed whole on a real change, keyed on its text. A key is "" while no
    // phone is connected (or its integration is off), so nothing is computed for nobody.
    // Going live is a change too: that is how the first phone (or a topic switched on in
    // Settings) gets each topic. A second phone gets them from `_topics`.

    function _workspaces(): var {
        const list = Array.from(HyprlandData.workspaces ?? []).map(w => ({ id: w.id, windows: w.windows ?? 0 }));
        list.sort((a, b) => a.id - b.id);
        return { t: "workspaces", active: HyprlandData.activeWorkspace?.id ?? 0, list: list };
    }

    function _modes(): var {
        if (!Modes.enabled)
            return { t: "modes", active: "", list: [] };
        return {
            t: "modes",
            active: Modes.activeModeId,
            list: Array.from(Modes.modes ?? []).map(m => ({ id: m.id, name: m.name, icon: m.icon }))
        };
    }

    /// Preset names, from `presets.sh list`: read on connect and when the folder changes.
    property var _presetNames: []
    function _presets(): var {
        return { t: "presets", active: PresetStore.activePreset, list: root._presetNames };
    }

    function _vol(v): real {
        return Math.round((v ?? 0) * 100) / 100;
    }
    function _node(n): var {
        return { id: n.id, name: Audio.friendlyDeviceName(n), vol: root._vol(n.audio?.volume), mute: n.audio?.muted ?? false };
    }
    function _audio(): var {
        const ee = EasyEffects.available ? {
            on: EasyEffects.active,
            preset: EasyEffects.outputPreset,
            presets: Array.from(EasyEffects.outputPresets)
        } : null;
        return {
            t: "audio",
            out: Audio.sink?.id ?? -1,
            "in": Audio.source?.id ?? -1,
            outputs: Array.from(Audio.outputDevices).map(root._node),
            inputs: Array.from(Audio.inputDevices).map(root._node),
            apps: Array.from(Audio.outputAppNodes).map(n => ({
                id: n.id, name: Audio.appNodeDisplayName(n), vol: root._vol(n.audio?.volume), mute: n.audio?.muted ?? false
            })),
            ee: ee
        };
    }

    readonly property bool _remoteLive: root.phoneConnected && root.remoteEnabled
    readonly property bool _audioLive: root.phoneConnected && root.audioEnabled

    // Volumes are read only from nodes Pipewire is asked to track: devices and app
    // streams, only while a phone listens.
    PwObjectTracker {
        objects: root._audioLive ? Array.from(Audio.outputDevices).concat(Array.from(Audio.inputDevices), Array.from(Audio.outputAppNodes)) : []
    }

    readonly property string _workspacesKey: root._remoteLive ? JSON.stringify(root._workspaces()) : ""
    readonly property string _modesKey: root._remoteLive ? JSON.stringify(root._modes()) : ""
    readonly property string _presetsKey: root._remoteLive ? JSON.stringify(root._presets()) : ""
    readonly property string _audioKey: root._audioLive ? JSON.stringify(root._audio()) : ""

    property var _sentKeys: ({})
    function _publish(name, key): void {
        const prev = root._sentKeys[name] ?? "";
        root._sentKeys[name] = key;
        if (key !== "" && key !== prev)
            root.sendTo("*", JSON.parse(key));
    }
    on_WorkspacesKeyChanged: root._publish("workspaces", root._workspacesKey)
    on_ModesKeyChanged: root._publish("modes", root._modesKey)
    on_PresetsKeyChanged: root._publish("presets", root._presetsKey)
    // A volume dragged on the PC changes many times a second: coalesce to ~16 pushes/s.
    on_AudioKeyChanged: {
        if (root._audioKey === "")
            root._sentKeys["audio"] = "";
        else if (!audioPush.running)
            audioPush.start();
    }
    Timer {
        id: audioPush
        interval: 60
        onTriggered: root._publish("audio", root._audioKey)
    }

    /// The topics, for a phone that connects while another is already live.
    function _topics(dev): void {
        if (root.remoteEnabled) {
            root.sendTo(dev, root._workspaces());
            root.sendTo(dev, root._modes());
            root.sendTo(dev, root._presets());
        }
        if (root.audioEnabled)
            root.sendTo(dev, root._audio());
    }

    function _listPresets(): void {
        presetList.running = false;
        presetList.running = true;
    }
    Connections {
        // Not a reference while no phone listens, so the store is never loaded for this.
        target: root._remoteLive ? PresetStore : null
        function onPresetFilesChanged() {
            root._listPresets();
        }
    }
    Process {
        id: presetList
        command: [`${Directories.scriptPath}/presets.sh`, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = [];
                for (const line of this.text.split("\n")) {
                    try {
                        const p = JSON.parse(line);
                        if (p?.name)
                            names.push(String(p.name));
                    } catch (e) {}
                }
                root._presetNames = names;
            }
        }
    }

    function _nodeById(id): var {
        return Pipewire.nodes.values.find(n => n.id === Number(id)) ?? null;
    }

    /// Runs a command that carries an argument; returns "" when done, or why not.
    function _runArg(action, arg): string {
        switch (action) {
        case "workspace": {
            const n = Number(arg);
            if (!Number.isInteger(n) || n < 1 || n > 100)
                return "bad_arg";
            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${n} })`);
            return "";
        }
        case "mode": {
            const id = String(arg ?? "");
            if (id === "")
                return Modes.deactivate("manual") ? "" : "not_found";
            if (!Modes.modeById(id))
                return "not_found";
            Modes.toggle(id);
            return "";
        }
        case "preset": {
            const name = String(arg ?? "");
            if (!root._presetNames.includes(name))
                return "not_found";
            if (PresetStore.activePreset !== name)
                PresetStore.applyPreset(name);
            return "";
        }
        case "volume":
        case "mute": {
            const node = root._nodeById(arg?.id);
            if (!node?.audio)
                return "not_found";
            if (action === "volume")
                node.audio.volume = Math.max(0, Math.min(1, Number(arg.vol ?? 0)));
            else
                node.audio.muted = arg.mute === true;
            return "";
        }
        case "default": {
            const node = root._nodeById(arg);
            if (!node || node.isStream || !node.audio)
                return "not_found";
            if (node.isSink)
                Audio.setDefaultSink(node);
            else
                Audio.setDefaultSource(node);
            return "";
        }
        case "eePreset": {
            const name = String(arg ?? "");
            if (!Array.from(EasyEffects.outputPresets).includes(name))
                return "not_found";
            EasyEffects.loadPreset(name, "output");
            return "";
        }
        case "eeBypass":
            EasyEffects.setBypass(arg === true);
            return "";
        }
        return "unknown_action";
    }

    readonly property var _remoteArgActions: ["workspace", "mode", "preset"]
    readonly property var _audioArgActions: ["volume", "mute", "default", "eePreset", "eeBypass"]

    Timer {
        id: lockAodTimer
        interval: 700
        onTriggered: {
            if (GlobalStates.screenLocked && (Config.options?.oledSaver?.enable ?? true))
                GlobalStates.oledSaverMonitors = Quickshell.screens.map(s => s.name);
        }
    }

    // ── Public API ──────────────────────────────────────────────────────
    function startPairing(): void {
        root.lastPaired = null;
        root.pairingRequested = true;
        if (root.running)
            root.send({ op: "pair" });
        // Otherwise the helper starts now and `ready` opens the pairing.
    }

    function cancelPairing(): void {
        root.pairingRequested = false;
        root.pairing = null;
        if (root.running)
            root.send({ op: "pairCancel" });
    }

    function unpair(id): void {
        if (root.running)
            root.send({ op: "unpair", id: String(id) });
        else
            Quickshell.execDetached([root.binaryPath, "unpair", "--state-dir", root.stateDir, "--id", String(id)]);
    }

    function disconnect(id): void {
        root.send({ op: "kick", dev: String(id) });
    }

    /// Sends `message` to one phone, or to every connected one with dev "*".
    function sendTo(dev, message): void {
        root.send({ op: "send", dev: String(dev), m: message });
    }

    function send(obj): void {
        if (!helper.running)
            return;
        helper.write(JSON.stringify(obj) + "\n");
    }

    // ── Protocol ────────────────────────────────────────────────────────
    function _hello(): var {
        return {
            t: "hello",
            v: 1,
            name: root.hostName,
            caps: root.capabilities,
            actions: root.allowedActions
        };
    }

    // Integrations switched on or off in Settings reach a connected phone at once. Keyed
    // on the text, since the arrays are rebuilt (and "change") on any re-evaluation.
    readonly property string _helloKey: JSON.stringify(root._hello())
    on_HelloKeyChanged: {
        if (root.phoneConnected) {
            root.sendTo("*", root._hello());
            root.sendTo("*", root._state());
        }
    }

    function _handleMessage(dev, m): void {
        switch (m.t) {
        case "cmd": {
            const id = Number(m.id ?? 0);
            const action = String(m.a ?? "");
            let why;
            if (root._remoteArgActions.includes(action))
                why = root.remoteEnabled ? root._runArg(action, m.arg) : "disabled";
            else if (root._audioArgActions.includes(action))
                why = root.audioEnabled ? root._runArg(action, m.arg) : "disabled";
            else if (root.allowedActions.some(a => a.id === action))
                why = root._run(action);
            else
                why = root.remoteEnabled ? "unknown_action" : "disabled";
            root.sendTo(dev, why === "" ? { t: "ok", id: id } : { t: "err", id: id, code: why });
            return;
        }
        case "ping":
            root.sendTo(dev, { t: "pong", id: Number(m.id ?? 0) });
            return;
        }
    }

    function handleLine(line): void {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        switch (ev.ev) {
        case "ready":
            root.running = true;
            root._failures = 0;
            root.lastError = "";
            root.fingerprint = String(ev.fp ?? "");
            root.hostName = String(ev.name ?? "");
            root.addresses = ev.addrs ?? [];
            root.discovery = ev.discovery === true;
            if (root.pairingRequested && !root.pairing)
                root.send({ op: "pair" });
            break;
        case "peers":
            root._setPeers(JSON.stringify(ev.list ?? []));
            break;
        case "pairing":
            root.pairing = { url: String(ev.url ?? ""), qr: ev.qr ?? [], expires: Number(ev.expires ?? 0) };
            break;
        case "pairingEnd":
            root.pairing = null;
            root.pairingRequested = false;
            break;
        case "paired":
            root.lastPaired = ev.dev ?? null;
            if (ev.dev && !root.peers.some(p => p.id === ev.dev.id))
                root.peers = root.peers.concat([{ id: String(ev.dev.id), name: String(ev.dev.name ?? ""), model: String(ev.dev.model ?? ""), pairedAt: Date.now(), lastSeen: Date.now() }]);
            break;
        case "connected": {
            // hello first; assigning `connections` then makes the topics live, which
            // sends them to the first phone.
            const wasLive = root.phoneConnected;
            root.sendTo(ev.dev, root._hello());
            root.sendTo(ev.dev, root._state());
            const next = Object.assign({}, root.connections);
            next[ev.dev] = { id: String(ev.dev), name: String(ev.name ?? ""), model: String(ev.model ?? ""), addr: String(ev.addr ?? ""), since: Date.now() };
            root.connections = next;
            if (wasLive)
                root._topics(ev.dev);
            if (root.remoteEnabled)
                root._listPresets();
            break;
        }
        case "disconnected": {
            const next = Object.assign({}, root.connections);
            delete next[ev.dev];
            root.connections = next;
            break;
        }
        case "msg":
            if (ev.m && typeof ev.m === "object")
                root._handleMessage(String(ev.dev), ev.m);
            break;
        case "error":
            root.lastError = String(ev.msg ?? "");
            console.warn("[IiLink]", root.lastError);
            break;
        }
    }

    // ── IPC ─────────────────────────────────────────────────────────────
    IpcHandler {
        target: "iiLink"

        /// Opens a pairing; `status` then carries its link.
        function pair(): void {
            root.startPairing();
        }
        function cancelPairing(): void {
            root.cancelPairing();
        }
        function unpair(id: string): void {
            root.unpair(id);
        }
        function status(): string {
            return JSON.stringify({
                enabled: root.enabled,
                running: root.running,
                binary: root.binaryPresent,
                peers: root.peers,
                connected: root.connectedList,
                pairing: root.pairing ? root.pairing.url : null,
                error: root.lastError
            });
        }
    }

    // ── Process ─────────────────────────────────────────────────────────
    readonly property bool wanted: root.enabled && (root.hasPeers || root.pairingRequested || root._linger)

    // Unpairing the last phone: stay up a moment so the phone hears "unpaired" before
    // the socket goes away with the process.
    property bool _linger: false
    onHasPeersChanged: {
        if (!root.hasPeers && root.running) {
            root._linger = true;
            lingerTimer.restart();
        }
    }
    Timer {
        id: lingerTimer
        interval: 1000
        onTriggered: root._linger = false
    }
    onWantedChanged: {
        if (root.wanted && !root.probed)
            root.checkBinary();
    }

    function checkBinary(): void {
        probe.running = false;
        probe.running = true;
    }

    function restart(): void {
        root._restarting = true;
        Qt.callLater(() => root._restarting = false);
    }

    onPortChanged: {
        if (helper.running)
            root.restart();
    }

    Component.onCompleted: {
        if (root.wanted)
            root.checkBinary();
    }

    Process {
        id: probe
        command: ["sh", "-c", `[ -x "${root.binaryPath}" ] && echo 1 || echo 0`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.binaryPresent = this.text.trim() === "1";
                root.probed = true;
            }
        }
    }

    /// Crashes restart it with a growing pause, so a helper that dies on start cannot spin.
    property int _failures: 0
    Timer {
        id: backoff
        onTriggered: root._restarting = false
    }

    Process {
        id: helper
        running: root.wanted && root.probed && root.binaryPresent && !root._restarting
        stdinEnabled: true
        command: [root.binaryPath, "--state-dir", root.stateDir, "--port", String(root.port)]

        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("[IiLink]", data)
        }

        onExited: (code, status) => {
            root.running = false;
            root.connections = ({});
            root.pairing = null;
            if (root._restarting || !root.wanted)
                return;
            if (code !== 0) {
                console.warn(`[IiLink] helper exited with code ${code}`);
                root._failures += 1;
                root._restarting = true;
                backoff.interval = Math.min(300000, 2000 * Math.pow(2, Math.min(7, root._failures)));
                backoff.restart();
            }
        }
    }
}
