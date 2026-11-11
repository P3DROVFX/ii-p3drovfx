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
    readonly property bool deckEnabled: root.opts?.deck?.enable ?? true
    readonly property bool wallpaperEnabled: root.opts?.wallpaper?.enable ?? true
    readonly property bool callsEnabled: root.opts?.calls?.enable ?? true
    readonly property bool notifsEnabled: root.opts?.notifications?.enable ?? true
    readonly property bool shareEnabled: root.opts?.share?.enable ?? true
    readonly property bool clipEnabled: root.opts?.clipboard?.enable ?? true
    readonly property bool shotsEnabled: root.opts?.screenshots?.enable ?? true
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
        .concat(root.deckEnabled ? ["deck"] : [])
        .concat(root.wallpaperEnabled ? ["wallpaper"] : [])
        .concat(root.callsEnabled ? ["calls"] : [])
        .concat(root.notifsEnabled ? ["notifs"] : [])
        .concat(root.shareEnabled ? ["share"] : [])
        .concat(root.clipEnabled ? ["clip"] : [])
        .concat(root.shotsEnabled ? ["shots"] : [])

    // What is on right now, read from the same state the shell itself draws from.
    readonly property bool _aodUp: (GlobalStates.oledSaverMonitors ?? []).length > 0
    readonly property var activeActions: {
        if (!root.remoteEnabled)
            return root._deckActive;
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
        return on.concat(root._deckActive);
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

    // ── Deck ────────────────────────────────────────────────────────────
    // The shell's action catalog (the one gestures and bubbles bind to), the custom
    // commands from Settings → ii tools, and apps on request. Ids are namespaced:
    // `g:<gesture action>`, `c:<command id>`, `app:<desktop id>`, `discordMute`…

    // Not offered: tablet- and pen-only entries, and what only means something on a
    // touchscreen in front of the PC.
    readonly property var _deckSkip: ["none", "back", "home", "recents", "appDrawer", "dragWindow", "osk", "hubMode", "welcome"]
    function _deckGroup(id): string {
        if (["regionScreenshot", "fullscreenScreenshot", "regionSearch", "regionOcr", "screenTranslate", "colorPicker", "regionRecord", "regionRecordWithSound", "liveDraw"].includes(id))
            return "capture";
        if (["mediaControls", "mediaPlayPause", "mediaNext", "mediaPrev", "audioMute", "micMute"].includes(id))
            return "media";
        if (["scratchpad", "closeWindow", "toggleFullscreen", "toggleFloating", "workspaceNext", "workspacePrev", "overview"].includes(id))
            return "windows";
        if (["wallpaperSelector", "wallpaperRandom", "toggleLightDark", "barToggle", "brightnessUp", "brightnessDown"].includes(id))
            return "look";
        return "shell";
    }
    // Gesture actions with a state worth lighting a key for.
    readonly property var _deckToggles: ["lock", "oledSaver", "scratchpad", "micMute", "audioMute", "mediaPlayPause", "regionRecord", "regionRecordWithSound", "toggleLightDark", "barToggle"]

    readonly property var deckCommands: Array.from(root.opts?.deck?.commands ?? [])

    function _deck(): var {
        const list = TouchGestureActionRegistry.availableActionsForFamily("ii", false)
            .filter(a => !root._deckSkip.includes(a.id))
            .map(a => ({ id: `g:${a.id}`, name: Translation.tr(a.name), icon: a.icon, group: root._deckGroup(a.id), toggle: root._deckToggles.includes(a.id) }));
        list.push({ id: "discordMute", name: Translation.tr("Discord mute"), icon: "mic_off", group: "discord", toggle: true });
        list.push({ id: "discordDeafen", name: Translation.tr("Discord deafen"), icon: "headset_off", group: "discord", toggle: true });
        for (const c of root.deckCommands) {
            if (c?.id && c?.command)
                list.push({ id: `c:${c.id}`, name: String(c.name || c.id), icon: String(c.icon || "terminal"), group: "custom", toggle: false });
        }
        return { t: "deck", list: list };
    }

    readonly property bool _recording: Persistent.states?.screenRecord?.active ?? false
    readonly property var _deckActive: {
        if (!root.deckEnabled || !root.phoneConnected)
            return [];
        const on = [];
        const add = (id, cond) => {
            if (cond)
                on.push(id);
        };
        add("g:lock", GlobalStates.screenLocked);
        add("g:oledSaver", root._aodUp);
        add("g:scratchpad", GlobalStates.scratchpadOpen);
        add("g:micMute", Audio.source?.audio?.muted ?? false);
        add("g:audioMute", Audio.sink?.audio?.muted ?? false);
        add("g:mediaPlayPause", MprisController.activePlayer?.isPlaying ?? false);
        add("g:regionRecord", root._recording);
        add("g:regionRecordWithSound", root._recording);
        add("g:toggleLightDark", Appearance.m3colors.darkmode);
        add("g:barToggle", GlobalStates.barOpen);
        add("discordMute", DiscordVoice.channel !== null && DiscordVoice.muted);
        add("discordDeafen", DiscordVoice.channel !== null && DiscordVoice.deafened);
        return on;
    }

    function _runDeck(id): string {
        if (id.startsWith("g:")) {
            const action = id.slice(2);
            if (root._deckSkip.includes(action) || !TouchGestureActionRegistry.actions.some(a => a.id === action))
                return "not_found";
            if (action === "lock" && GlobalStates.screenLocked)
                return "locked";
            TouchGestureActionRegistry.trigger(action, Hyprland.focusedMonitor?.name ?? "");
            return "";
        }
        if (id.startsWith("c:")) {
            const c = root.deckCommands.find(c => `c:${c?.id}` === id);
            if (!c?.command)
                return "not_found";
            Quickshell.execDetached(["bash", "-c", String(c.command)]);
            return "";
        }
        if (id.startsWith("app:")) {
            const entry = DesktopEntries.byId(id.slice(4));
            if (!entry)
                return "not_found";
            entry.execute();
            return "";
        }
        if (id === "discordMute" || id === "discordDeafen") {
            if (DiscordVoice.channel === null)
                return "unavailable";
            if (id === "discordMute")
                DiscordVoice.setMuted(!DiscordVoice.muted);
            else
                DiscordVoice.setDeafened(!DiscordVoice.deafened);
            return "";
        }
        return "not_found";
    }

    /// Installed apps, sent only when the phone asks (its picker is open).
    function _apps(): var {
        const list = Array.from(DesktopEntries.applications.values)
            .filter(e => !e.noDisplay)
            .map(e => ({ id: e.id, name: e.name, icon: e.icon }))
            .sort((a, b) => a.name.localeCompare(b.name));
        return { t: "apps", list: list };
    }

    // ── Calls ───────────────────────────────────────────────────────────
    // The app reports the phone's call state (it opens the link itself when a call
    // rings, even from the background) and takes answer / end / silence / dial.

    /// dev id → the capabilities that phone announced (`caps`), e.g. ["calls"].
    property var phoneCaps: ({})
    /// The connected phone that reports calls; "" when none (PhoneCallService then
    /// falls back to ADB).
    readonly property string callDev: {
        if (!root.callsEnabled)
            return "";
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("calls"))
                return id;
        }
        return "";
    }
    readonly property bool callsLive: root.callDev !== ""
    // A phone that reports calls needs PhoneCallService loaded, whichever surface (the
    // island or the corner popup) shows the call.
    onCallsLiveChanged: {
        if (root.callsLive)
            PhoneCallService.callState;
    }

    /// state: "idle", "ringing" or "talking"; name: the caller as the phone shows it.
    signal callReported(string state, string name)

    /// answer, end, silence, or dial with the number as `arg`. False when no phone listens.
    function phoneCommand(action, arg): bool {
        if (!root.callsLive)
            return false;
        root.sendTo(root.callDev, arg === undefined ? { t: "phone", a: action } : { t: "phone", a: action, arg: String(arg) });
        return true;
    }

    // ── Notifications ───────────────────────────────────────────────────
    // The app mirrors the phone's notifications while the link is up (it opens it for a
    // burst and keeps it 2 min after): a full list on connect, then each change. The
    // Phone tab (KdeConnectService) and the desktop popups read them from here.

    readonly property string iconDir: `${root.stateDir}/icons`
    /// [{ key, pkg, app, title, text, time, image, actions: [{ i, label, reply, hint }] }]
    property var linkNotifications: []
    /// Live updates sent over the link: the same payload as an `iilive1:` relay.
    property var linkLives: []
    readonly property string notifDev: {
        if (!root.notifsEnabled)
            return "";
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("notifs"))
                return id;
        }
        return "";
    }
    readonly property bool notifsLive: root.notifDev !== ""
    /// A phone has mirrored notifications since the shell started: KDE Connect's popups
    /// of the same notifications are hidden from then on (both travel the same LAN).
    property bool mirrorsNotifications: false
    onNotifsLiveChanged: {
        if (root.notifsLive)
            root.mirrorsNotifications = true;
    }

    function iconFor(pkg): string {
        return /^[A-Za-z0-9._]+$/.test(pkg ?? "") ? `${root.iconDir}/${pkg}.png` : "";
    }

    function _notif(n): var {
        const actions = Array.isArray(n?.actions) ? n.actions : [];
        return {
            key: String(n?.key ?? ""),
            pkg: String(n?.pkg ?? ""),
            app: String(n?.app ?? ""),
            title: String(n?.title ?? ""),
            text: String(n?.text ?? ""),
            time: Number(n?.time ?? Date.now()),
            image: typeof n?.image === "string" && n.image !== "" ? `data:image/jpeg;base64,${n.image}` : "",
            actions: actions.map(a => ({ i: Number(a?.i ?? 0), label: String(a?.label ?? ""), reply: a?.reply === true, hint: String(a?.hint ?? "") }))
        };
    }

    function _upsertNotif(n): void {
        const list = root.linkNotifications.filter(x => x.key !== n.key);
        list.push(n);
        root.linkNotifications = list;
    }

    /// A new notification (not an update of the same text) pops up like any phone one.
    function _popupNotif(n, previous): void {
        if (previous && previous.title === n.title && previous.text === n.text)
            return;
        if (!(Config.options?.phone?.mirrorNotificationsToDesktop ?? true) || Notifications.popupInhibited)
            return;
        if (KdeConnectService.isRepeatedPhoneNotification(n.title, n.text))
            return;
        Notifications.publishInternalNotification({
            appName: n.app,
            appIcon: root.iconFor(n.pkg),
            summary: n.title || n.app,
            body: n.text,
            phone: true,
            sound: true,
            actions: [{ identifier: "__qs_phonelive_open", text: Translation.tr("Open") }],
            actionPayload: { publicId: `ii:${n.key}` }
        });
    }

    function _send(m): void {
        if (root.notifsLive)
            root.sendTo(root.notifDev, m);
    }
    function notifDismiss(key): void {
        root._send({ t: "notifAct", key: String(key), a: "dismiss" });
        root.linkNotifications = root.linkNotifications.filter(x => x.key !== key);
    }
    function notifAction(key, index): void {
        root._send({ t: "notifAct", key: String(key), a: "action", i: Number(index) });
    }
    function notifReply(key, index, text): void {
        root._send({ t: "notifAct", key: String(key), a: "reply", i: Number(index), text: String(text) });
    }

    // ── Clipboard ───────────────────────────────────────────────────────
    // Copied here → the phone (live while the link is up, and the latest on connect).
    // From the phone → this clipboard, marked as the shell's own copy so it is neither
    // announced nor sent back.

    readonly property string clipDev: {
        if (!root.clipEnabled)
            return "";
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("clip"))
                return id;
        }
        return "";
    }
    /// Images bigger than this stay on the PC (a link message is at most 8 MiB, base64 grows it).
    readonly property int clipImageMax: 5 * 1024 * 1024
    /// The cliphist id last sent, so a reconnecting phone only gets what is new.
    property string _clipSent: ""

    Connections {
        target: root.clipDev !== "" ? Cliphist : null
        function onEntryAdded(entry) {
            root._sendClip(entry);
        }
    }
    onClipDevChanged: {
        // A phone that just connected gets the latest copy, if it has not had it.
        if (root.clipDev !== "" && Cliphist.entries.length > 0)
            root._sendClip(Cliphist.entries[0]);
    }

    function _sendClip(entry): void {
        const key = Cliphist.entryKey(entry);
        if (root.clipDev === "" || key === "" || key === root._clipSent)
            return;
        root._clipSent = key;
        // From cliphist itself: its list shows only a preview, and Quickshell's own
        // clipboard text does not follow copies made in other apps. One process per copy.
        clipDecode.dev = root.clipDev;
        clipDecode.image = Cliphist.entryIsImage(entry);
        // Text as it is (Qt reads it as UTF-8); an image as base64 for the JSON message.
        clipDecode.command = ["sh", "-c", `${Cliphist.cliphistBinary} decode "$1" | head -c ${root.clipImageMax + 1}${clipDecode.image ? " | base64 -w0" : ""}`, "sh", key];
        clipDecode.running = true;
    }

    Process {
        id: clipDecode
        property string dev: ""
        property bool image: false
        stdout: StdioCollector {
            onStreamFinished: {
                const data = this.text;
                if (data.length === 0)
                    return;
                if (!clipDecode.image) {
                    root.sendTo(clipDecode.dev, { t: "clip", text: data });
                    return;
                }
                // Past the limit (the base64 of max + 1 bytes): the image stays on the PC.
                if (data.trim().length <= Math.ceil(root.clipImageMax / 3) * 4)
                    root.sendTo(clipDecode.dev, { t: "clip", mime: "image/png", data: data.trim() });
            }
        }
    }

    /// Text from the phone (`clip` command).
    function _clipFromPhone(dev, arg): string {
        const text = String(arg?.text ?? "");
        if (text.length === 0)
            return "bad_arg";
        Cliphist.markInternalCopy();
        Quickshell.clipboardText = text;
        root._announceClip(dev, text.replace(/\s+/g, " ").trim().slice(0, 160));
        return "";
    }

    /// Says a copy arrived: a popup only (phone-like: never kept in the history).
    function _announceClip(dev, body): void {
        const phone = root.connections[dev]?.name || Translation.tr("the phone");
        Notifications.publishInternalNotification({
            appName: "ii tools",
            appIcon: "edit-paste",
            summary: Translation.tr("Copied from %1").arg(phone),
            body: body,
            phone: true
        });
    }

    // ── Screenshots ─────────────────────────────────────────────────────
    // PC → phone: a region snip (the preview's image) or a full-screen shot (an image
    // copied at exactly a monitor's size: Print, Ctrl+Print and the gesture all copy
    // it) is copied to the outbox and sent to the phone's gallery when it is connected,
    // now or later. Phone → PC: see _handleFile ("screenshot").

    readonly property string outboxDir: `${root.stateDir}/outbox`
    readonly property string phoneShotDir: `${FileUtils.trimFileProtocol(Directories.pictures)}/Screenshots/Phone`
    readonly property string shotDev: {
        if (!root.shotsEnabled)
            return "";
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("shots"))
                return id;
        }
        return "";
    }
    /// Only the last few wait for a phone that is away.
    readonly property int outboxMax: 5
    property double _lastShotAt: 0

    readonly property bool _watchShots: root.enabled && root.shotsEnabled && root.hasPeers
    Connections {
        target: root._watchShots ? GlobalStates : null
        function onScreenshotOverlayImagePathChanged() {
            const path = GlobalStates.screenshotOverlayImagePath;
            // A phone screenshot shown in the preview is not sent back.
            if (path !== "" && !path.startsWith(root.phoneShotDir))
                root._queueShot(path, "");
        }
    }
    Connections {
        target: root._watchShots ? Cliphist : null
        function onEntryAdded(entry) {
            const size = /(\d+)x(\d+) \]\]$/.exec(String(entry));
            if (!size || !Cliphist.entryIsImage(entry))
                return;
            const w = Number(size[1]), h = Number(size[2]);
            const fullScreen = (HyprlandData.monitors ?? []).some(m => (m.width === w && m.height === h) || (m.width === h && m.height === w));
            // A region snip copies too: it is already queued from the preview.
            if (fullScreen && Date.now() - root._lastShotAt > 3000)
                root._queueShot("", Cliphist.entryKey(entry));
        }
    }

    /// From a file, or from a cliphist entry; then send if a phone is there.
    function _queueShot(path, cliphistId): void {
        root._lastShotAt = Date.now();
        const dest = `${root.outboxDir}/pc-${Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss-zzz")}.png`;
        // The snip's file may still be being written when the preview opens: wait for it.
        const source = path !== "" ? `for i in $(seq 30); do [ -s "$2" ] && break; sleep 0.1; done; cp -- "$2" "$3"`
            : `${Cliphist.cliphistBinary} decode "$2" > "$3"`;
        // Copy, then keep only the newest few.
        shotQueue.command = ["sh", "-c", `mkdir -p -m 700 -- "$1" && ${source} && ls -1t -- "$1" | tail -n +${root.outboxMax + 1} | while read f; do rm -f -- "$1/$f"; done`,
            "sh", root.outboxDir, path !== "" ? path : cliphistId, dest];
        shotQueue.running = true;
    }
    Process {
        id: shotQueue
        onExited: code => {
            if (code === 0)
                root._flushShots();
        }
    }

    onShotDevChanged: root._flushShots()

    property int _fileSerial: 1
    function _flushShots(): void {
        if (root.shotDev === "" || shotList.running)
            return;
        shotList.running = true;
    }
    Process {
        id: shotList
        command: ["sh", "-c", `ls -1tr -- "$1" 2>/dev/null`, "sh", root.outboxDir]
        stdout: SplitParser {
            onRead: name => {
                if (root.shotDev === "" || name.trim() === "")
                    return;
                // The helper deletes each file once it is on its way.
                root.send({ op: "sendFile", dev: root.shotDev, id: 900000 + root._fileSerial++, path: `${root.outboxDir}/${name.trim()}`,
                    name: name.trim(), purpose: "screenshot", delete: true });
            }
        }
    }

    // ── Shared from the phone ───────────────────────────────────────────
    // "Send to PC" in Android's share sheet. Text arrives as the `share` command, files
    // as uploads with purpose "share" (see _handleFile).

    /**
     * The file arriving for "Send to PC", for the corner popup:
     * { id, dev, from, name, size, received, state: "receiving" | "done" | "failed", path }.
     */
    property var transfer: null

    function _setTransfer(fields): void {
        root.transfer = Object.assign({}, root.transfer ?? {}, fields);
    }

    function _transferMatches(dev, id): bool {
        return root.transfer !== null && root.transfer.dev === dev && root.transfer.id === Number(id);
    }

    /// Where shared files land: Downloads, as KDE Connect does.
    readonly property string shareDir: FileUtils.trimFileProtocol(Directories.downloads)

    function _askAi(text): void {
        const context = Ai.shellContext.makeContext("phone", "phone-share", Translation.tr("Shared from the phone"), text, false);
        if (Ai.attachContext(context))
            GlobalStates.openLeftSidebar();
    }

    /// {to, text}; returns "" when done, or why not.
    function _share(arg): string {
        const text = String(arg?.text ?? "").trim();
        if (text.length === 0)
            return "bad_arg";
        const firstLine = text.split("\n")[0].trim();
        const rest = text.slice(text.indexOf("\n") + 1).trim();
        switch (String(arg?.to ?? "")) {
        case "browser":
            // Web links only: a shared text is never opened as a file or a command.
            if (!/^https?:\/\/\S+$/i.test(text))
                return "bad_arg";
            Qt.openUrlExternally(text);
            return "";
        case "ai":
            root._askAi(text);
            return "";
        case "note": {
            const result = NotesService.create(firstLine.slice(0, 60), text, null);
            return result?.ok ? "" : String(result?.error ?? "failed");
        }
        case "reminder":
            RemindersService.create({ title: firstLine.slice(0, 120), notes: text.includes("\n") ? rest : "" });
            return "";
        case "task":
            Todo.addTask(text);
            return "";
        }
        return "bad_arg";
    }

    // ── Files from the phone ────────────────────────────────────────────
    // The helper lands a finished upload in its incoming/ folder; here it becomes what
    // it was sent for, or is deleted.

    readonly property var _imageName: /\.(jpe?g|png|webp|avif|bmp|gif|jxl|heic|heif)$/i
    property var _pendingWallpaper: null

    function _handleFile(dev, ev): void {
        const id = Number(ev.id ?? 0);
        const path = String(ev.path ?? "");
        const name = String(ev.name ?? "");
        const refuse = code => {
            Quickshell.execDetached(["rm", "-f", "--", path]);
            root.sendTo(dev, { t: "err", id: id, code: code });
        };
        // An app's icon for the notifications, filed once per app.
        if (ev.purpose === "appIcon") {
            const pkg = name.replace(/\.png$/, "");
            const dest = root.iconFor(pkg);
            if (dest === "")
                return refuse("bad_arg");
            Quickshell.execDetached(["sh", "-c", 'mkdir -p -m 700 -- "$1" && mv -f -- "$2" "$3"', "sh", root.iconDir, path, dest]);
            root.sendTo(dev, { t: "ok", id: id });
            return;
        }
        // A screenshot taken on the phone: kept with the others, on this clipboard, and
        // shown in the screenshot preview.
        if (ev.purpose === "screenshot") {
            if (!root.shotsEnabled)
                return refuse("disabled");
            if (!root._imageName.test(name))
                return refuse("bad_arg");
            const dest = `${root.phoneShotDir}/${name}`;
            Cliphist.markInternalCopy();
            phoneShot.dest = dest;
            phoneShot.command = ["sh", "-c", 'mkdir -p -- "$1" && mv -f -- "$2" "$3" && chmod 644 -- "$3" && wl-copy --type image/png < "$3"', "sh", root.phoneShotDir, path, dest];
            phoneShot.running = true;
            root.sendTo(dev, { t: "ok", id: id });
            return;
        }
        // An image copied on the phone: onto this clipboard, then gone from disk.
        if (ev.purpose === "clip") {
            if (!root.clipEnabled)
                return refuse("disabled");
            if (!root._imageName.test(name))
                return refuse("bad_arg");
            const mime = /\.png$/i.test(name) ? "image/png" : /\.webp$/i.test(name) ? "image/webp" : "image/jpeg";
            Cliphist.markInternalCopy();
            Quickshell.execDetached(["sh", "-c", 'wl-copy --type "$1" < "$2"; rm -f -- "$2"', "sh", mime, path]);
            root._announceClip(dev, Translation.tr("An image"));
            root.sendTo(dev, { t: "ok", id: id });
            return;
        }
        if (ev.purpose === "share") {
            if (!root.shareEnabled)
                return refuse("disabled");
            const target = String(ev.target ?? "downloads");
            if (target === "ai" && !root._imageName.test(name))
                return refuse("bad_arg");
            if (shareMove.running)
                return refuse("busy");
            shareMove.pending = { dev: dev, id: id, name: name, target: target };
            // The original name, and "name (1).ext" when it is taken: never overwrite.
            shareMove.command = ["sh", "-c", `
                dir="$1"; src="$2"; name="$3"
                mkdir -p -- "$dir" || exit 1
                case "$name" in ?*.*) base="\${name%.*}"; ext=".\${name##*.}" ;; *) base="$name"; ext="" ;; esac
                dest="$dir/$name"; n=1
                while [ -e "$dest" ]; do dest="$dir/$base ($n)$ext"; n=$((n + 1)); done
                mv -f -- "$src" "$dest" && chmod 644 -- "$dest" && printf %s "$dest"`, "sh", root.shareDir, path, name];
            shareMove.running = true;
            return;
        }
        if (ev.purpose !== "wallpaper")
            return refuse("unknown_action");
        if (!root.wallpaperEnabled)
            return refuse("disabled");
        if (!root._imageName.test(name))
            return refuse("bad_arg");
        if (wallpaperMove.running)
            return refuse("busy");
        const folder = FileUtils.trimFileProtocol(Wallpapers.defaultFolder.toString());
        // Dated, so a phone photo never overwrites a wallpaper of the same name.
        const dest = `${folder}/phone-${Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")}-${name}`;
        root._pendingWallpaper = { dev: dev, id: id, dest: dest, target: String(ev.target ?? "desktop") };
        wallpaperMove.command = ["sh", "-c", 'mkdir -p -- "$1" && mv -f -- "$2" "$3"', "sh", folder, path, dest];
        wallpaperMove.running = true;
    }

    Process {
        id: phoneShot
        property string dest: ""
        onExited: code => {
            if (code !== 0)
                return;
            GlobalStates.screenshotOverlayMonitor = Hyprland.focusedMonitor?.name ?? "";
            GlobalStates.screenshotOverlayRegionX = 0;
            GlobalStates.screenshotOverlayRegionY = 0;
            GlobalStates.screenshotOverlayRegionW = 0;
            GlobalStates.screenshotOverlayRegionH = 0;
            GlobalStates.screenshotOverlayImagePath = phoneShot.dest;
            GlobalStates.screenshotOverlayOpen = true;
        }
    }

    Process {
        id: shareMove
        property var pending: null
        stdout: StdioCollector {
            id: shareDest
        }
        onExited: code => {
            const p = shareMove.pending;
            shareMove.pending = null;
            const dest = String(shareDest.text ?? "").trim();
            if (!p)
                return;
            if (code !== 0 || dest === "") {
                if (root._transferMatches(p.dev, p.id))
                    root._setTransfer({ state: "failed" });
                return root.sendTo(p.dev, { t: "err", id: p.id, code: "write" });
            }
            if (p.target === "ai") {
                Ai.attachFile(dest);
                GlobalStates.openLeftSidebar();
            } else if (p.target === "shelf") {
                FileShelf.add([dest]);
            }
            // The popup turns into "Received", with Open and Show in folder.
            if (root._transferMatches(p.dev, p.id))
                root._setTransfer({ state: "done", path: dest, name: dest.split("/").pop() });
            root.sendTo(p.dev, { t: "ok", id: p.id });
        }
    }

    Process {
        id: wallpaperMove
        onExited: code => {
            const p = root._pendingWallpaper;
            root._pendingWallpaper = null;
            if (!p)
                return;
            if (code !== 0) {
                root.sendTo(p.dev, { t: "err", id: p.id, code: "write" });
                return;
            }
            if (p.target !== "lock")
                Wallpapers.select(p.dest);
            if (p.target === "lock" || p.target === "both")
                Wallpapers.selectLockscreen(p.dest);
            root.sendTo(p.dev, { t: "ok", id: p.id });
        }
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
    readonly property string _deckKey: (root.phoneConnected && root.deckEnabled) ? JSON.stringify(root._deck()) : ""
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
    on_DeckKeyChanged: root._publish("deck", root._deckKey)
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
        if (root.deckEnabled)
            root.sendTo(dev, root._deck());
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
            if (action === "clip")
                why = root.clipEnabled ? root._clipFromPhone(dev, m.arg) : "disabled";
            else if (action === "share")
                why = root.shareEnabled ? root._share(m.arg) : "disabled";
            else if (action === "deck")
                why = root.deckEnabled ? root._runDeck(String(m.arg ?? "")) : "disabled";
            else if (root._remoteArgActions.includes(action))
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
        case "caps": {
            const next = Object.assign({}, root.phoneCaps);
            next[dev] = Array.isArray(m.caps) ? m.caps.map(String) : [];
            root.phoneCaps = next;
            return;
        }
        case "notifs":
            if (dev === root.notifDev)
                root.linkNotifications = Array.isArray(m.list) ? m.list.map(root._notif).filter(n => n.key !== "") : [];
            return;
        case "notif": {
            if (dev !== root.notifDev)
                return;
            const n = root._notif(m.n);
            if (n.key === "")
                return;
            const previous = root.linkNotifications.find(x => x.key === n.key) ?? null;
            root._upsertNotif(n);
            root._popupNotif(n, previous);
            return;
        }
        case "notifGone":
            root.linkNotifications = root.linkNotifications.filter(x => x.key !== String(m.key ?? ""));
            return;
        case "live": {
            if (dev !== root.notifDev || !m.p || typeof m.p !== "object")
                return;
            const id = String(m.p.id ?? "");
            root.linkLives = root.linkLives.filter(x => String(x.id ?? "") !== id).concat([m.p]);
            return;
        }
        case "liveGone":
            root.linkLives = root.linkLives.filter(x => String(x.id ?? "") !== String(m.id ?? ""));
            return;
        case "call":
            if (root.callsEnabled && dev === root.callDev)
                root.callReported(String(m.state ?? "idle"), String(m.name ?? ""));
            return;
        case "get":
            if (m.what === "apps" && root.deckEnabled)
                root.sendTo(dev, root._apps());
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
            const caps = Object.assign({}, root.phoneCaps);
            delete caps[ev.dev];
            root.phoneCaps = caps;
            // Without the phone that sent them they go stale: KDE Connect's list takes over.
            if (!root.notifsLive) {
                root.linkNotifications = [];
                root.linkLives = [];
            }
            break;
        }
        case "fileStart":
            // Only "Send to PC" files are announced; wallpapers and app icons show themselves.
            if (ev.purpose === "share" && root.shareEnabled) {
                root.transfer = {
                    id: Number(ev.id ?? 0), dev: String(ev.dev), from: root.connections[ev.dev]?.name ?? "",
                    name: String(ev.name ?? ""), size: Number(ev.size ?? 0), received: 0, state: "receiving", path: ""
                };
                GlobalStates.phoneFilePopupOpen = true;
            }
            break;
        case "fileProgress":
            if (root._transferMatches(String(ev.dev), ev.id))
                root._setTransfer({ received: Number(ev.received ?? 0) });
            break;
        case "fileAbort":
            if (root._transferMatches(String(ev.dev), ev.id) && root.transfer.state === "receiving")
                root._setTransfer({ state: "failed" });
            break;
        case "file":
            if (root._transferMatches(String(ev.dev), ev.id))
                root._setTransfer({ received: root.transfer.size });
            root._handleFile(String(ev.dev), ev);
            break;
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
        /// The notifications mirrored over the link: app, title and actions, newest last.
        function notifications(): string {
            return JSON.stringify(root.linkNotifications.map(n => ({ app: n.app, title: n.title, text: n.text, actions: n.actions.length, image: n.image !== "" })));
        }
        function status(): string {
            return JSON.stringify({
                enabled: root.enabled,
                running: root.running,
                binary: root.binaryPresent,
                peers: root.peers,
                connected: root.connectedList,
                pairing: root.pairing ? root.pairing.url : null,
                notifications: root.linkNotifications.length,
                lives: root.linkLives.length,
                mirrorsNotifications: root.mirrorsNotifications,
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
