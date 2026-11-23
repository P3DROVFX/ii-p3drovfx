pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.modules.common

/**
 * The phone as a monitor (ROADMAP 3.1): extend this PC onto it, or mirror a screen.
 *
 * Over USB (raw TCP + `adb reverse`) or Wi-Fi (side WebSocket on the ii link). The phone
 * asks over ii link (`{"t":"screen","a":"start"}`); this service resolves the transport,
 * makes the output (a headless one the phone's size to extend, a chosen/focused screen to
 * mirror), maps the helper's touchscreen onto it, and starts capture in the helper
 * (screen.rs) with a one-time token. Everything it made goes when the phone leaves,
 * closes the stream, or the setting is turned off.
 *
 * Hyprland forgets monitor and device rules made with `hyprctl eval` on a config
 * reload, so they are applied again then.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.iiTools?.screen?.enable ?? true
    readonly property bool wirelessEnabled: Config.options?.iiTools?.screen?.wireless ?? true
    property bool adbPresent: false

    readonly property string headlessName: "II-PHONE"
    // Hyprland's name for the helper's "ii tools screen" device.
    readonly property string deviceName: "ii-tools-screen"

    /// "idle", "starting" (adb/token, the output, the helper), "ready" (the phone may connect), "live".
    property string state: "idle"
    /// Resolved transport for the active session: "usb", "wifi", or "" when idle.
    property string transport: ""
    property string dev: ""
    property string mode: ""
    property string output: ""
    property string serial: ""
    property string token: ""
    property int port: 0
    property int sid: 0
    property int w: 0
    property int h: 0
    property string encoder: ""
    property string lastError: ""
    property bool _helperUp: false
    property bool _adaptive: true
    property string _wantTransport: "auto"
    // What the phone asked for (its settings): the extended output's size, refresh,
    // scale and side, and the stream's bitrate.
    property int _phoneW: 0
    property int _phoneH: 0
    property real _res: 1
    property int fps: 60
    property real scale: 1.5
    property string side: "right"
    property string orient: "landscape"
    property int bitrateMbps: 16
    /// The stream's codec the phone asked for: "hevc" (its default) or "h264" (older apps).
    property string codec: "h264"
    /// Current target bitrate (Mbps) reported by adaptive rate control, or 0 when idle.
    property real liveBitrate: 0
    /// The extended output's place in the layout, "XxY", once worked out.
    property string position: "auto-right"
    // The screen the extended one sits beside: the focused one when it started.
    property string _anchor: ""
    // The screen to mirror the phone asked for ("" for the focused one).
    property string _wantMirror: ""
    // Panel family remembered on the first phone-driven switch, restored on end if untouched.
    property string _savedFamily: ""
    property string _switchedFamily: ""
    property string _sentToolsKey: ""
    property bool _rulesPending: false

    onEnabledChanged: {
        if (!root.enabled)
            root.stop("disabled");
    }

    onWirelessEnabledChanged: {
        if (!root.wirelessEnabled && root.transport === "wifi")
            root.stop("disabled");
    }

    Component.onCompleted: {
        adbCheck.running = true;
        // A shell that went away mid-session left the phone's sink as the default: undo it.
        Quickshell.execDetached(["sh", "-c", root._audioOffScript("")]);
    }

    // ── The PC's sound on the phone (Wi-Fi sessions) ─────────────────────
    // When keepPcAudio is on, capture the default sink's monitor directly so both PC and
    // phone play; when off, a virtual sink takes the default and every stream while on.
    readonly property bool keepPcAudio: Config.options?.iiTools?.screen?.keepPcAudio ?? true
    readonly property string audioSink: "ii_tools_phone"
    /// Whether the phone hears the PC now (the helper confirmed it).
    property bool audioOn: false
    property bool _audioWanted: false
    property bool _audioShared: false
    property string _audioSource: ""
    property string _audioPrev: ""

    function _monitorSource(): string {
        const name = String(Audio.sink?.name ?? "");
        return (name !== "" && name !== root.audioSink) ? `${name}.monitor` : "@DEFAULT_MONITOR@";
    }

    function _audioOffScript(prev): string {
        const sink = root.audioSink;
        const back = prev !== "" ? `pactl set-default-sink '${prev}'; for i in $(pactl list short sink-inputs | cut -f1); do pactl move-sink-input "$i" '${prev}'; done; ` : "";
        return `${back}pactl list short modules | grep 'sink_name=${sink}' | cut -f1 | xargs -r -n1 pactl unload-module`;
    }

    function setAudio(on): void {
        if (on === root._audioWanted) {
            // Still waiting for the helper's first packet: the confirmation (or the
            // timeout) answers. A `false` here turned the phone's switch back off.
            if (on && !root.audioOn)
                return;
            return root._reply({ audio: root.audioOn });
        }
        if (on && (root.transport !== "wifi" || root.state === "idle"))
            return root._reply({ audio: false });
        root._audioWanted = on;
        if (on) {
            // Asked while the session is still starting: applied at `ready`.
            if (root.state === "ready" || root.state === "live")
                root._audioStart();
        } else {
            audioPending.stop();
            IiLinkService.send({ op: "screen", a: "audio", on: false });
            root._audioDown();
        }
    }

    // A capture that never sends a packet (a source that hangs) must not leave the phone waiting.
    Timer {
        id: audioPending
        interval: 5000
        onTriggered: {
            if (!root._audioWanted || root.audioOn)
                return;
            console.warn("[PhoneScreen] the PC's sound did not start in time");
            IiLinkService.send({ op: "screen", a: "audio", on: false });
            root._audioDown();
        }
    }

    function _audioStart(): void {
        audioPending.restart();
        if (root.keepPcAudio) {
            root._audioShared = true;
            root._audioPrev = "";
            root._audioSource = root._monitorSource();
            IiLinkService.send({ op: "screen", a: "audio", on: true, source: root._audioSource });
        } else {
            root._audioShared = false;
            root._audioSource = `${root.audioSink}.monitor`;
            audioUp.running = true;
        }
    }

    function _audioDown(): void {
        audioPending.stop();
        if (!root._audioShared)
            Quickshell.execDetached(["sh", "-c", root._audioOffScript(root._audioPrev)]);
        root._audioPrev = "";
        root._audioShared = false;
        root._audioSource = "";
        root._audioWanted = false;
        root.audioOn = false;
        root._reply({ audio: false });
    }

    onKeepPcAudioChanged: {
        if (!root._audioWanted || (root.state !== "ready" && root.state !== "live"))
            return;
        if (root.keepPcAudio && !root._audioShared) {
            const prev = root._audioPrev;
            if (!audioUp.running) {
                Quickshell.execDetached(["sh", "-c", root._audioOffScript(prev)]);
                root._audioPrev = "";
                root._audioShared = true;
                root._audioSource = prev !== "" ? `${prev}.monitor` : root._monitorSource();
                IiLinkService.send({ op: "screen", a: "audio", on: true, source: root._audioSource });
            }
        } else if (!root.keepPcAudio && root._audioShared) {
            root._audioShared = false;
            root._audioSource = `${root.audioSink}.monitor`;
            audioUp.running = true;
        }
    }

    Connections {
        target: Audio
        function onSinkChanged(): void {
            if (!root._audioWanted || !root._audioShared)
                return;
            if (root.state !== "ready" && root.state !== "live")
                return;
            const name = String(Audio.sink?.name ?? "");
            if (name === "" || name === root.audioSink)
                return;
            const next = `${name}.monitor`;
            if (next === root._audioSource)
                return;
            root._audioSource = next;
            IiLinkService.send({ op: "screen", a: "audio", on: true, source: next });
        }
    }

    // Prints the default sink before, then makes the phone's sink the default with every stream on it.
    Process {
        id: audioUp
        command: ["sh", "-c", `prev=$(pactl get-default-sink); ${root._audioOffScript("")}; `
            + `pactl load-module module-null-sink sink_name=${root.audioSink} rate=48000 channels=2 sink_properties=device.description=Phone >/dev/null || exit 1; `
            + `pactl set-default-sink ${root.audioSink}; for i in $(pactl list short sink-inputs | cut -f1); do pactl move-sink-input "$i" ${root.audioSink}; done; echo "$prev"`]
        stdout: StdioCollector {
            id: audioUpOut
        }
        onExited: code => {
            const prev = audioUpOut.text.trim();
            if (code !== 0 || !root._audioWanted || root.state === "idle") {
                root._audioPrev = prev;
                return root._audioDown();
            }
            const cleanPrev = prev === root.audioSink ? "" : prev;
            if (root.keepPcAudio) {
                Quickshell.execDetached(["sh", "-c", root._audioOffScript(cleanPrev)]);
                root._audioPrev = "";
                root._audioShared = true;
                root._audioSource = cleanPrev !== "" ? `${cleanPrev}.monitor` : root._monitorSource();
                IiLinkService.send({ op: "screen", a: "audio", on: true, source: root._audioSource });
                return;
            }
            root._audioPrev = cleanPrev;
            IiLinkService.send({ op: "screen", a: "audio", on: true, source: `${root.audioSink}.monitor` });
        }
    }

    Process {
        id: adbCheck
        command: ["sh", "-c", "command -v adb"]
        onExited: code => root.adbPresent = code === 0
    }

    function _reply(m): void {
        if (root.dev !== "")
            IiLinkService.sendTo(root.dev, Object.assign({ t: "screen" }, m));
    }

    function handleMessage(dev, m): void {
        switch (String(m.a ?? "")) {
        case "start":
            root.start(dev, m);
            return;
        case "monitors":
            IiLinkService.sendTo(dev, { t: "screen", monitors: root._monitors() });
            return;
        case "switch":
            if (dev === root.dev)
                root.switchMirror(String(m.output ?? ""));
            return;
        case "orient":
            if (dev === root.dev)
                root._setOrient(String(m.to ?? ""));
            return;
        case "draw":
            // Live draw on the phone's screen: focus it, then the same toggle as everywhere.
            if (dev === root.dev && root.output !== "") {
                Hyprland.dispatch(`hl.dsp.focus({ monitor = ${JSON.stringify(root.output)} })`);
                LiveDraw.toggle();
            }
            return;
        case "pointer":
            if (dev === root.dev && root.output !== "")
                root._warpPointer();
            return;
        case "workspace":
            if (dev === root.dev && root.output !== "")
                root._switchWorkspace(m.to);
            return;
        case "family":
            if (dev === root.dev && root.state !== "idle")
                root._selectFamily(String(m.to ?? ""));
            return;
        case "launcher":
            if (dev === root.dev && root.output !== "")
                root._openLauncher();
            return;
        case "audio":
            if (dev === root.dev)
                root.setAudio(m.on === true);
            return;
        case "stop":
            if (dev === root.dev)
                root.stop("phone");
            return;
        }
    }

    function _warpPointer(): void {
        const mon = Hyprland.monitors.values.find(m => m.name === root.output);
        const info = mon?.lastIpcObject ?? HyprlandData.monitors?.find(m => m.name === root.output) ?? null;
        if (!mon && !info)
            return;
        const x = Number(info?.x ?? mon?.x ?? 0);
        const y = Number(info?.y ?? mon?.y ?? 0);
        const pw = Number(info?.width ?? mon?.width ?? root.w);
        const ph = Number(info?.height ?? mon?.height ?? root.h);
        const rawScale = Number(info?.scale ?? mon?.scale ?? (root.mode === "extend" ? root.scale : 1));
        const s = rawScale > 0 ? rawScale : 1;
        const turned = Number(info?.transform ?? 0) % 2 === 1;
        const lw = (turned ? ph : pw) / s;
        const lh = (turned ? pw : ph) / s;
        const cx = Math.round(x + lw / 2);
        const cy = Math.round(y + lh / 2);
        Hyprland.dispatch(`hl.dsp.cursor.move({ x = ${cx}, y = ${cy} })`);
    }

    function _switchWorkspace(to): void {
        const target = String(to ?? "");
        if (target === "next" || target === "prev") {
            Hyprland.dispatch(`hl.dsp.focus({ monitor = ${JSON.stringify(root.output)} })`);
            Hyprland.dispatch(`hl.dsp.focus({ workspace = '${target === "next" ? "m+1" : "m-1"}' })`);
            return;
        }
        const n = Number(to);
        if (!Number.isInteger(n) || n < 1 || n > 100)
            return;
        Hyprland.dispatch(`hl.dsp.focus({ monitor = ${JSON.stringify(root.output)} })`);
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${n} })`);
    }

    function _selectFamily(to): void {
        if (!PanelFamily.entry(to) || to === PanelFamily.current)
            return;
        if (root._savedFamily === "")
            root._savedFamily = PanelFamily.current;
        root._switchedFamily = to;
        PanelFamily.select(to);
    }

    function _openLauncher(): void {
        Hyprland.dispatch(`hl.dsp.focus({ monitor = ${JSON.stringify(root.output)} })`);
        if (PanelFamily.isTablet)
            GlobalStates.toggleAppDrawer(root.output);
        else if (PanelFamily.isWaffle)
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        else
            GlobalStates.toggleOverview(root.output);
    }

    function _toolsMsg(): var {
        const mon = Hyprland.monitors.values.find(m => m.name === root.output);
        const activeId = Number(mon?.activeWorkspace?.id ?? -1);
        const byId = HyprlandData.workspaceById ?? {};
        const workspaces = (Hyprland.workspaces?.values ?? [])
            .filter(w => w && Number(w.id) > 0 && !String(w.name ?? "").startsWith("special:") && (w.monitor?.name ?? "") === root.output)
            .map(w => ({
                id: Number(w.id),
                name: String(w.name ?? w.id),
                active: activeId > 0 ? Number(w.id) === activeId : Boolean(w.active),
                windows: Number(byId[w.id]?.windows ?? w.lastIpcObject?.windows ?? w.toplevels?.values?.length ?? 0)
            }))
            .sort((a, b) => a.id - b.id);
        return {
            workspaces: workspaces,
            family: PanelFamily.current
        };
    }

    readonly property string _toolsKey: root.state === "live" && root.output !== ""
        ? JSON.stringify(root._toolsMsg())
        : ""
    on_ToolsKeyChanged: {
        if (root._toolsKey === "") {
            toolsPushTimer.stop();
            root._sentToolsKey = "";
        } else if (root._sentToolsKey === "") {
            toolsPushTimer.stop();
            root._sentToolsKey = root._toolsKey;
            root._reply(JSON.parse(root._toolsKey));
        } else {
            toolsPushTimer.restart();
        }
    }
    Timer {
        id: toolsPushTimer
        interval: 100
        onTriggered: {
            const key = root._toolsKey;
            if (key === "" || key === root._sentToolsKey)
                return;
            root._sentToolsKey = key;
            root._reply(JSON.parse(key));
        }
    }

    function start(dev, m): void {
        const mode = String(m.mode ?? "extend");
        const phoneW = Number(m.w ?? 0), phoneH = Number(m.h ?? 0);
        const wantTransport = ["usb", "wifi", "auto"].includes(String(m.transport ?? "")) ? String(m.transport) : "auto";
        if (!root.enabled)
            return IiLinkService.sendTo(dev, { t: "screen", err: "disabled" });
        if (wantTransport === "usb" && !root.adbPresent)
            return IiLinkService.sendTo(dev, { t: "screen", err: "adb" });
        if (wantTransport === "wifi" && !root.wirelessEnabled)
            return IiLinkService.sendTo(dev, { t: "screen", err: "wireless" });
        if (wantTransport === "auto" && !root.adbPresent && !root.wirelessEnabled)
            return IiLinkService.sendTo(dev, { t: "screen", err: "adb" });
        if (root.state !== "idle") {
            if (dev !== root.dev)
                return IiLinkService.sendTo(dev, { t: "screen", err: "busy" });
            root.stop("restart");
        }
        const wifiOnly = wantTransport === "wifi" || (wantTransport === "auto" && !root.adbPresent);
        root.sid += 1;
        root.dev = dev;
        root.mode = mode === "mirror" ? "mirror" : "extend";
        root.orient = root.mode === "extend" && String(m.orient ?? "") === "portrait" ? "portrait" : "landscape";
        root._phoneW = Math.max(320, Math.min(7680, Math.round(Math.max(phoneW, phoneH))));
        root._phoneH = Math.max(240, Math.min(4320, Math.round(Math.min(phoneW, phoneH))));
        root._res = [0.5, 0.75, 1].includes(Number(m.res)) ? Number(m.res) : 1;
        root.fps = [30, 60, 90, 120].includes(Number(m.fps)) ? Number(m.fps) : 60;
        root.scale = [1, 1.25, 1.5, 2].includes(Number(m.scale)) ? Number(m.scale) : 1.5;
        root.side = ["left", "right", "above", "below"].includes(String(m.side)) ? String(m.side) : "right";
        root.bitrateMbps = Math.max(2, Math.min(60, Math.round(Number(m.bitrate ?? 16))));
        root.codec = String(m.codec ?? "") === "hevc" ? "hevc" : "h264";
        root.liveBitrate = root.bitrateMbps;
        root._adaptive = m.adaptive !== false;
        root._wantTransport = wantTransport;
        root.transport = wifiOnly ? "wifi" : "usb";
        root.position = "auto-right";
        root._anchor = String(Hyprland.focusedMonitor?.name ?? "");
        root._wantMirror = String(m.output ?? "");
        root.lastError = "";
        root.state = "starting";
        root._reply({ state: "starting", mode: root.mode });
        if (wifiOnly)
            tokenGen.running = true;
        else
            adbFind.running = true;
    }

    /// Ends the session and removes what it made at once; the helper's own end, which
    /// follows, finds nothing left.
    function stop(reason): void {
        if (root.state === "idle")
            return;
        if (root._helperUp)
            IiLinkService.send({ op: "screen", a: "stop" });
        root._cleanup(reason);
    }

    /// The PC's screens the phone can mirror: its own extended one is not among them.
    function _monitors(): var {
        return Hyprland.monitors.values.filter(mon => mon.name !== root.headlessName && !(mon.lastIpcObject?.disabled ?? false)).map(mon => {
            const info = mon.lastIpcObject ?? {};
            return {
                name: String(mon.name),
                label: String(info.model || info.description || mon.name).trim(),
                w: Number(info.width ?? mon.width ?? 0),
                h: Number(info.height ?? mon.height ?? 0),
                focused: mon.name === Hyprland.focusedMonitor?.name
            };
        });
    }

    /// Mirror another screen without stopping: "next" goes round them. The capture
    /// starts again there, the touchscreen follows, and the phone is told the new shape.
    function switchMirror(name): void {
        if (root.mode !== "mirror" || (root.state !== "ready" && root.state !== "live"))
            return;
        const list = root._monitors();
        if (list.length === 0)
            return;
        const at = list.findIndex(x => x.name === root.output);
        const pick = name === "next" || name === "" ? list[(at + 1) % list.length] : list.find(x => x.name === name);
        if (!pick || pick.name === root.output)
            return;
        root.output = pick.name;
        root.w = pick.w;
        root.h = pick.h;
        root._applyRules();
        IiLinkService.send({ op: "screen", a: "output", output: root.output });
        root._reply({ state: "size", w: root.w, h: root.h, output: root.output, label: pick.label });
    }

    /// Swap the extended output between landscape and portrait while live, re-applying
    /// rules and re-placing against the anchor; wf-recorder exit triggers helper restart.
    function _setOrient(to): void {
        if (root.mode !== "extend" || (root.state !== "ready" && root.state !== "live"))
            return;
        if ((to !== "landscape" && to !== "portrait") || to === root.orient)
            return;
        const prevW = root.w;
        root.w = root.h;
        root.h = prevW;
        root.orient = to;
        const monitors = (HyprlandData.monitors ?? []).length > 0
            ? HyprlandData.monitors
            : (Hyprland.monitors?.values ?? []).map(m => m.lastIpcObject).filter(Boolean);
        root.position = root._place(monitors);
        root._applyRules();
        root._reply({ state: "size", w: root.w, h: root.h, output: root.output, orient: root.orient });
    }

    /// A change to the extended output from the Displays page: kept for the rest of the
    /// session (config reloads apply it again) and applied now. A new mode restarts the
    /// capture in the helper, which the phone follows.
    function adjust(m): void {
        if (root.state === "idle" || root.mode !== "extend" || m.name !== root.headlessName)
            return;
        if (m.scale > 0)
            root.scale = m.scale;
        root.position = `${Math.round(m.x)}x${Math.round(m.y)}`;
        if (m.width > 0 && m.height > 0 && (m.width !== root.w || m.height !== root.h)) {
            root.w = m.width;
            root.h = m.height;
            if (root.w !== root.h)
                root.orient = root.h > root.w ? "portrait" : "landscape";
            root._reply({ state: "size", w: root.w, h: root.h, output: root.output, orient: root.orient });
        }
        if (m.refreshRate > 0)
            root.fps = Math.round(m.refreshRate);
        root._applyRules();
    }

    function _fail(code): void {
        root.lastError = code;
        root._reply({ err: code });
        root.stop(code);
    }

    // A token from the kernel's RNG without touching adb (wireless path).
    Process {
        id: tokenGen
        command: ["sh", "-c", "head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \\n'"]
        stdout: StdioCollector {
            id: tokenOut
        }
        onExited: code => {
            if (root.state !== "starting")
                return;
            root.token = tokenOut.text.trim();
            if (root.token.length < 16)
                return root._fail("wireless");
            root.serial = "";
            root._setupOutput();
        }
    }

    // A token from the kernel's RNG, then the USB devices.
    Process {
        id: adbFind
        command: ["sh", "-c", "head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \\n'; echo; adb devices -l"]
        stdout: StdioCollector {
            id: adbOut
        }
        onExited: code => {
            if (root.state !== "starting")
                return;
            const lines = adbOut.text.split("\n");
            root.token = lines.shift().trim();
            const devices = lines.map(l => l.trim().split(/\s+/)).filter(f => f.length >= 2 && f[0] !== "List");
            // USB only: wireless adb lists the same phone again, without `usb:`.
            const ready = devices.filter(f => f[1] === "device" && f.some(x => x.startsWith("usb:")));
            const want = String(IiLinkService.connections[root.dev]?.model ?? "").replace(/[^A-Za-z0-9]/g, "_");
            const match = ready.find(f => want !== "" && f.some(x => x === `model:${want}`)) ?? (ready.length === 1 ? ready[0] : null);
            if (root.token.length < 16)
                return root._fail(root._wantTransport === "auto" && root.wirelessEnabled ? "wireless" : "adb");
            if (!match) {
                if (root._wantTransport === "auto" && root.wirelessEnabled) {
                    root.transport = "wifi";
                    root.serial = "";
                    root._setupOutput();
                    return;
                }
                return root._fail(devices.some(f => f[1] === "unauthorized") ? "unauthorized" : "usb");
            }
            root.transport = "usb";
            root.serial = match[0];
            root._setupOutput();
        }
    }

    function _setupOutput(): void {
        if (root.mode === "extend") {
            // Even sides: the encoders want them.
            const even = v => Math.max(2, Math.round(v / 2) * 2);
            const portrait = root.orient === "portrait";
            root.output = root.headlessName;
            root.w = even((portrait ? root._phoneH : root._phoneW) * root._res);
            root.h = even((portrait ? root._phoneW : root._phoneH) * root._res);
            // Made, then the layout read to place it against the focused screen.
            hyprPlace.command = ["sh", "-c", `hyprctl output create headless ${root.headlessName} >/dev/null; ${root._rulesScript()}; hyprctl monitors -j`];
            hyprPlace.running = true;
            return;
        } else {
            const pick = root._monitors().find(x => x.name === root._wantMirror) ?? root._monitors().find(x => x.focused);
            root.output = String(pick?.name ?? "");
            root.w = Number(pick?.w ?? 1920);
            root.h = Number(pick?.h ?? 1080);
            if (root.output === "")
                return root._fail("output");
            hyprSetup.command = ["sh", "-c", root._rulesScript()];
        }
        hyprSetup.running = true;
    }

    /// The extended output's mode and the touchscreen's output, as Hyprland rules.
    function _rulesScript(): string {
        let lua = `hl.device({ name = '${root.deviceName}', output = '${root.output}' })`;
        if (root.mode === "extend")
            lua = `hl.monitor({ output = '${root.headlessName}', mode = '${root.w}x${root.h}@${root.fps}', position = '${root.position}', scale = ${root.scale} }) ` + lua;
        return `hyprctl eval "${lua}" >/dev/null`;
    }

    Process {
        id: hyprPlace
        stdout: StdioCollector {
            id: placeOut
        }
        onExited: code => {
            if (root.state !== "starting")
                return;
            try {
                root.position = root._place(JSON.parse(placeOut.text));
            } catch (e) {
                root.position = "auto-right";
            }
            hyprSetup.command = ["sh", "-c", root._rulesScript()];
            hyprSetup.running = true;
        }
    }

    /// Where the extended output goes: against the screen that had focus, on the side the
    /// phone chose (centred along it), or the next side that is free, so the pointer
    /// crosses straight over. Logical pixels, as Hyprland lays monitors out.
    function _place(monitors): string {
        const logical = mon => {
            const turned = mon.transform % 2 === 1;
            const s = mon.scale > 0 ? mon.scale : 1;
            return { name: mon.name, x: mon.x, y: mon.y, w: Math.round((turned ? mon.height : mon.width) / s), h: Math.round((turned ? mon.width : mon.height) / s) };
        };
        const all = monitors.filter(mon => !mon.disabled).map(logical);
        // Its own size from what was asked: the rule may not have landed when this was read.
        const me = { w: Math.round(root.w / root.scale), h: Math.round(root.h / root.scale) };
        const others = all.filter(mon => mon.name !== root.headlessName);
        const anchor = others.find(mon => mon.name === root._anchor) ?? others[0];
        if (!anchor)
            return "auto-right";
        const at = side => {
            switch (side) {
            case "left":
                return { x: anchor.x - me.w, y: anchor.y + Math.round((anchor.h - me.h) / 2) };
            case "above":
                return { x: anchor.x + Math.round((anchor.w - me.w) / 2), y: anchor.y - me.h };
            case "below":
                return { x: anchor.x + Math.round((anchor.w - me.w) / 2), y: anchor.y + anchor.h };
            default:
                return { x: anchor.x + anchor.w, y: anchor.y + Math.round((anchor.h - me.h) / 2) };
            }
        };
        const overlaps = p => others.some(o => p.x < o.x + o.w && p.x + me.w > o.x && p.y < o.y + o.h && p.y + me.h > o.y);
        const order = [root.side].concat(["right", "left", "above", "below"].filter(x => x !== root.side));
        const p = order.map(at).find(q => !overlaps(q)) ?? at(root.side);
        return `${p.x}x${p.y}`;
    }

    /// The captured output's refresh rate (Hz), 0 when unknown.
    function _outputRefresh(): real {
        const info = (HyprlandData.monitors ?? []).find(m => m.name === root.output)
            ?? Hyprland.monitors.values.find(m => m.name === root.output)?.lastIpcObject;
        return Number(info?.refreshRate ?? 0);
    }

    Process {
        id: hyprSetup
        onExited: code => {
            if (root.state !== "starting")
                return;
            root._helperUp = true;
            const op = {
                op: "screen",
                a: "start",
                dev: root.dev,
                sid: root.sid,
                output: root.output,
                token: root.token,
                w: root.w,
                h: root.h,
                bitrate: root.bitrateMbps * 1000000,
                // A cap on the capture's rate only for a screen faster than the stream (a 180 Hz
                // one mirrored: without it NVENC's CBR overshoots by that ratio). At or under the
                // screen's own rate (always for extend: the output runs at fps) the cap is
                // wf-recorder's fps filter, which held every frame back one frame (~7 ms at 120).
                rate: root._outputRefresh() > root.fps + 1 ? root.fps : 0,
                // The encoder's frame rate for its rate control (ii-wf-recorder's --ii-rate,
                // stock wf-recorder's -r): without one, VA-API starved the bitrate (1.1 of 30 Mbit/s).
                fps: root.fps,
                codec: root.codec
            };
            if (root.transport === "wifi") {
                op.transport = "ws";
                op.adaptive = root._adaptive;
            }
            IiLinkService.send(op);
        }
    }

    function _applyRules(): void {
        if (hyprRules.running) {
            root._rulesPending = true;
            return;
        }
        hyprRules.command = ["sh", "-c", root._rulesScript()];
        hyprRules.running = true;
    }

    Process {
        id: hyprRules
        onExited: {
            if (!root._rulesPending)
                return;
            root._rulesPending = false;
            if (root.state !== "idle" && root.output !== "")
                root._applyRules();
        }
    }

    Process {
        id: adbReverse
        onExited: code => {
            if (root.state !== "starting")
                return;
            if (code !== 0)
                return root._fail("adb");
            root.state = "ready";
            root._reply({ state: "ready", transport: "usb", port: root.port, token: root.token, w: root.w, h: root.h, mode: root.mode, output: root.output, orient: root.orient, screens: root._monitors().length });
        }
    }

    function handleEvent(ev): void {
        if (Number(ev.sid ?? -1) !== root.sid)
            return;
        switch (ev.ev) {
        case "screen":
            root.port = Number(ev.port ?? 0);
            // A helper built before the Wi-Fi path answers a `ws` start with a USB port and
            // never serves the phone's socket: the phone sat on a black screen until it gave up.
            if (root.transport === "wifi" && ev.transport !== "ws")
                return root._fail("outdated");
            if (root.transport === "wifi" || ev.transport === "ws" || root.port <= 0) {
                root.state = "ready";
                root._reply({ state: "ready", transport: "wifi", token: root.token, w: root.w, h: root.h, mode: root.mode, output: root.output, orient: root.orient, screens: root._monitors().length });
                if (root._audioWanted && !root.audioOn && root.transport === "wifi")
                    root._audioStart();
            } else {
                adbReverse.command = ["adb", "-s", root.serial, "reverse", `tcp:${root.port}`, `tcp:${root.port}`];
                adbReverse.running = true;
            }
            break;
        case "screenAudio":
            // The helper's capture: confirmed, or ended (ffmpeg died, the source went).
            if (ev.on === true && root._audioWanted) {
                audioPending.stop();
                root.audioOn = true;
                root._reply({ audio: true });
            } else if (ev.on !== true) {
                root._audioDown();
            }
            break;
        case "screenRate": {
            const bps = Number(ev.bitrate ?? 0);
            if (bps > 0)
                root.liveBitrate = Math.round(bps / 100000) / 10;
            break;
        }
        case "screenLive":
            root.state = "live";
            root.encoder = String(ev.encoder ?? "");
            root._reply({ state: "live", encoder: root.encoder });
            break;
        case "screenEnd": {
            const reason = String(ev.reason ?? "");
            if (reason === "encoder" || reason === "timeout" || reason === "bind" || reason === "encoder_exit") {
                root.lastError = reason;
                root._reply({ err: reason });
            }
            root._cleanup(reason);
            break;
        }
        }
    }

    function _cleanup(reason): void {
        toolsPushTimer.stop();
        if (root._audioWanted || root.audioOn)
            root._audioDown();
        root._sentToolsKey = "";
        if (root._savedFamily !== "" && PanelFamily.current === root._switchedFamily)
            PanelFamily.select(root._savedFamily);
        root._savedFamily = "";
        root._switchedFamily = "";
        if (root.transport !== "wifi" && root.port > 0 && root.serial !== "")
            Quickshell.execDetached(["adb", "-s", root.serial, "reverse", "--remove", `tcp:${root.port}`]);
        if (root.mode === "extend" && root.output !== "")
            Quickshell.execDetached(["hyprctl", "output", "remove", root.headlessName]);
        root._reply({ state: "stopped", reason: String(reason ?? "") });
        root.state = "idle";
        root._helperUp = false;
        root.dev = "";
        root.output = "";
        root.serial = "";
        root.token = "";
        root.port = 0;
        root.transport = "";
        root.liveBitrate = 0;
        root._adaptive = true;
        root._wantTransport = "auto";
        root.orient = "landscape";
        root._rulesPending = false;
        root.encoder = "";
    }

    Connections {
        target: Hyprland
        function onRawEvent(event): void {
            if (event.name === "configreloaded" && root.state !== "idle" && root.output !== "")
                root._applyRules();
        }
    }

    IpcHandler {
        target: "phoneScreen"

        function status(): string {
            return JSON.stringify({ state: root.state, transport: root.transport, mode: root.mode, orient: root.orient, dev: root.dev, output: root.output, serial: root.serial, port: root.port, size: `${root.w}x${root.h}`, fps: root.fps, scale: root.scale, position: root.position, bitrate: root.bitrateMbps, liveBitrate: root.liveBitrate, encoder: root.encoder, error: root.lastError, adb: root.adbPresent });
        }

        function stop(): string {
            root.stop("ipc");
            return "ok";
        }
    }
}
