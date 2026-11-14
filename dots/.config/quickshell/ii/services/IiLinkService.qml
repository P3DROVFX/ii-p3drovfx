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
import qs.modules.ii.overlay.perfMonitor

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
    readonly property string _phoneService: Config.options?.phone?.service ?? ""
    readonly property bool _kdeFlag: Config.options?.phone?.kdeconnectEnabled ?? true
    readonly property bool _policyAllowed: (Config.options?.policies?.phone ?? 1) !== 0
    // Mutually exclusive selection with KDE Connect:
    // explicit "iiTools" runs ii tools; "kdeconnect" / "off" keep it dormant;
    // "" (legacy/auto) activates when paired peers exist, pairing starts, or KDE Connect is off.
    readonly property bool serviceSelected: Config.ready && root._policyAllowed && (root.opts?.enable ?? true)
        && (root._phoneService === "iiTools"
            || (root._phoneService === "" && (root.hasPeers || root.pairingRequested || !root._kdeFlag)))
    readonly property bool enabled: root.serviceSelected
    readonly property bool remoteEnabled: root.opts?.remote?.enable ?? true
    readonly property bool audioEnabled: root.opts?.audio?.enable ?? true
    readonly property bool deckEnabled: root.opts?.deck?.enable ?? true
    readonly property bool wallpaperEnabled: root.opts?.wallpaper?.enable ?? true
    readonly property bool callsEnabled: root.opts?.calls?.enable ?? true
    readonly property bool notifsEnabled: root.opts?.notifications?.enable ?? true
    readonly property bool shareEnabled: root.opts?.share?.enable ?? true
    readonly property bool clipEnabled: root.opts?.clipboard?.enable ?? true
    readonly property bool shotsEnabled: root.opts?.screenshots?.enable ?? true
    readonly property bool phoneDataEnabled: root.opts?.phoneData?.enable ?? true
    readonly property bool dndEnabled: root.opts?.dnd?.enable ?? true
    readonly property bool wolEnabled: root.opts?.wol?.enable ?? true
    readonly property bool perfEnabled: root.opts?.perf?.enable ?? true
    readonly property bool mediaEnabled: root.opts?.media?.enable ?? true
    // The helper turns the phone's players into MPRIS ones itself; it only needs telling.
    onMediaEnabledChanged: root.send({ op: "config", media: root.mediaEnabled })
    readonly property bool pcLiveEnabled: root.opts?.pcLive?.enable ?? true
    readonly property bool pcMediaEnabled: root.opts?.pcMedia?.enable ?? true
    readonly property bool lookEnabled: root.opts?.look?.enable ?? true
    readonly property bool filesEnabled: root.opts?.files?.enable ?? true
    readonly property bool galleryEnabled: root.opts?.gallery?.enable ?? true
    readonly property bool touchpadEnabled: root.opts?.touchpad?.enable ?? true
    readonly property bool drawEnabled: root.opts?.draw?.enable ?? true
    readonly property bool presentEnabled: root.opts?.present?.enable ?? true
    // Touch frames go straight to the helper's input thread; it only needs telling.
    onTouchpadEnabledChanged: root.send({ op: "config", touchpad: root.touchpadEnabled })
    onPresentEnabledChanged: {
        root.send({ op: "config", present: root.presentEnabled });
        if (!root.presentEnabled)
            root._presentDev = "";
    }
    readonly property bool shotsAutoToPhone: root.opts?.screenshots?.autoToPhone ?? true
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
        path: `${root.stateDir}/peers.json`
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
    /// [{ iface, mac, broadcast, wifi }] from the helper: what a phone needs to wake this PC.
    property var wakeTargets: []
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
        .concat(root.phoneDataEnabled ? ["phoneData"] : [])
        .concat(root.dndEnabled ? ["dnd"] : [])
        .concat(root.pcLiveEnabled ? ["pcLive"] : [])
        .concat(root.perfEnabled ? ["perf"] : [])
        .concat(root.mediaEnabled ? ["media"] : [])
        .concat(root.pcMediaEnabled ? ["pcMedia"] : [])
        .concat(root.filesEnabled ? ["files"] : [])
        .concat(root.galleryEnabled ? ["gallery"] : [])
        .concat(root.touchpadEnabled ? ["touchpad"] : [])
        .concat(root.drawEnabled && LiveDraw.enabled ? ["draw"] : [])
        .concat(root.presentEnabled ? ["present"] : [])
        .concat(PhoneScreenService.enabled ? ["screen"] : [])

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
            outputs: Array.from(Audio.outputDevices).filter(Boolean).map(root._node),
            inputs: Array.from(Audio.inputDevices).filter(Boolean).map(root._node),
            apps: Array.from(Audio.outputAppNodes).filter(Boolean).map(n => ({
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
    // The phone sends its list on connect, but its notification access can come up after
    // the link (the app just updated), and a shell reload loses the list: ask for it
    // whenever a phone starts mirroring.
    onNotifDevChanged: {
        if (root.notifDev !== "")
            root.sendTo(root.notifDev, { t: "get", what: "notifs" });
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
            // The sender's photo: an avatar, never the content preview.
            avatar: typeof n?.avatar === "string" && n.avatar !== "" ? `data:image/jpeg;base64,${n.avatar}` : "",
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
            image: n.avatar,
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

    // ── Phone data: alarm, battery, network, contacts ───────────────────
    // `status` arrives on connect and on change; the alarm goes on to PhoneAlarmService.
    // Contacts are asked for on connect with the version this PC has; the phone sends
    // the list only when it changed, then each missing photo as a file. Both are kept
    // in the state folder (PhoneContactsService reads contacts.json itself).

    /// { battery: { level, charging, plug, temp, health }, net: { type, signal }, at } or null.
    property var phoneStatus: null
    readonly property string contactsDir: `${root.stateDir}/contacts`

    FileView {
        id: contactsFile
        path: root.phoneDataEnabled ? `${root.stateDir}/contacts.json` : ""
        printErrors: false
        blockLoading: true
    }
    function _contactsHash(): string {
        try {
            return String(JSON.parse(contactsFile.text())?.hash ?? "");
        } catch (e) {
            return "";
        }
    }

    readonly property string dataDev: {
        if (!root.phoneDataEnabled)
            return "";
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("contacts"))
                return id;
        }
        return "";
    }
    onDataDevChanged: {
        if (root.dataDev !== "")
            root.sendTo(root.dataDev, { t: "get", what: "contacts", have: root._contactsHash() });
    }

    function _status(m): void {
        root.phoneStatus = { battery: m.battery ?? null, net: m.net ?? null, at: Date.now() };
        if ("alarm" in m)
            PhoneAlarmService.fromLink(m.alarm);
    }

    function _contacts(dev, m): void {
        const list = Array.isArray(m.list) ? m.list : [];
        contactsFile.setText(JSON.stringify({ hash: String(m.hash ?? ""), list: list }));
        // Photos this PC does not have yet: asked for by key, sent as files.
        const keys = list.map(c => String(c.photo ?? "")).filter(k => /^[0-9a-f]{8,64}$/.test(k));
        photoCheck.dev = dev;
        photoCheck.wanted = keys;
        photoCheck.command = ["sh", "-c", `mkdir -p -m 700 -- "$1" && ls -1 -- "$1"`, "sh", root.contactsDir];
        photoCheck.running = true;
    }
    Process {
        id: photoCheck
        property string dev: ""
        property var wanted: []
        stdout: StdioCollector {
            onStreamFinished: {
                const have = new Set(this.text.split("\n").map(f => f.replace(/\.jpg$/, "")));
                const missing = [...new Set(photoCheck.wanted)].filter(k => !have.has(k));
                if (missing.length > 0)
                    root.sendTo(photoCheck.dev, { t: "get", what: "photos", keys: missing });
            }
        }
    }

    // ── Do Not Disturb, both ways ───────────────────────────────────────
    // The phone is told only when what it should be changes (a mode starting, the shell's
    // DND toggled), never re-told: turning its DND off by hand during a mode sticks. The
    // phone reports its own changes (not the ones asked from here).

    function _capDev(cap): string {
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes(cap))
                return id;
        }
        return "";
    }
    readonly property string dndDev: root.dndEnabled ? root._capDev("dnd") : ""
    /// The phone's DND as last reported; null until it says.
    property var phoneDnd: null
    /// The mode this side turned on because of the phone, to turn it off with it.
    property string _modeFromPhone: ""

    readonly property bool wantPhoneDnd: {
        if (!root.dndEnabled)
            return false;
        const o = root.opts?.dnd;
        return ((o?.phoneFollowsShell ?? true) && Notifications.silent)
            || Array.from(o?.modes ?? []).includes(Modes.activeModeId);
    }
    onWantPhoneDndChanged: root._tellPhoneDnd()
    onDndDevChanged: {
        // A phone that just connected: only if it disagrees with a state set while it was away.
        if (root.dndDev !== "" && root._dndOwed)
            root._tellPhoneDnd();
    }
    property bool _dndOwed: false

    function _tellPhoneDnd(): void {
        if (root.phoneDnd === root.wantPhoneDnd) {
            root._dndOwed = false;
            return;
        }
        if (root.dndDev === "") {
            root._dndOwed = true;
            return;
        }
        root._dndOwed = false;
        root.sendTo(root.dndDev, { t: "dnd", on: root.wantPhoneDnd });
    }

    function _phoneDndChanged(on): void {
        root.phoneDnd = on;
        const o = root.opts?.dnd;
        if (!root.dndEnabled || !(o?.shellFollowsPhone ?? true))
            return;
        const mode = String(o?.phoneTurnsOn ?? "");
        if (mode === "") {
            Notifications.silent = on;
            return;
        }
        if (on && Modes.activeModeId !== mode && Modes.activate(mode, "phone"))
            root._modeFromPhone = mode;
        else if (!on && root._modeFromPhone !== "" && Modes.activeModeId === root._modeFromPhone) {
            Modes.deactivate("phone");
            root._modeFromPhone = "";
        }
    }

    // ── The PC's live activity on the phone ─────────────────────────────
    // Recording, the pomodoro, the stopwatch, countdowns, a ringing alarm and progress,
    // pushed whole (`pcLive`) on change. Times are absolute (when it started or ends),
    // so the phone counts on its own and the topic changes only when something does.

    readonly property string liveDev: root.pcLiveEnabled ? root._capDev("pcLive") : ""

    function _pcLive(): var {
        const items = [];
        const rec = Persistent.states?.screenRecord;
        if (rec?.active)
            items.push({ id: "rec", kind: "record", title: Translation.tr("Recording the screen"),
                start: Date.now() - Number(rec.seconds ?? 0) * 1000, actions: [{ id: "stop", label: Translation.tr("Stop") }] });
        const pomo = Persistent.states?.timer?.pomodoro;
        if (pomo?.running || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)) {
            const title = TimerService.pomodoroLongBreak ? Translation.tr("Long break") : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus");
            items.push(pomo?.running
                ? { id: "pomodoro", kind: "timer", title: title, end: (Number(pomo.start) + TimerService.pomodoroLapDuration) * 1000,
                    total: TimerService.pomodoroLapDuration, actions: [{ id: "pause", label: Translation.tr("Pause") }] }
                : { id: "pomodoro", kind: "timer", title: title, paused: true, remaining: TimerService.pomodoroSecondsLeft,
                    total: TimerService.pomodoroLapDuration, actions: [{ id: "resume", label: Translation.tr("Resume") }] });
        }
        const sw = Persistent.states?.timer?.stopwatch;
        if (sw?.running) {
            // `start` is in 10 ms units in a 32-bit int, which overflows; the shell's own
            // subtraction wraps back to the right elapsed time, and so does this.
            const elapsed10 = (((Math.floor(Date.now() / 10) - Number(sw.start)) % 4294967296) + 4294967296) % 4294967296;
            // Rounded to the second, so the topic does not change on every evaluation.
            const start = Math.round((Date.now() - elapsed10 * 10) / 1000) * 1000;
            items.push({ id: "stopwatch", kind: "stopwatch", title: Translation.tr("Stopwatch"), start: start });
        }
        for (const c of Array.from(TimerService.countdowns ?? [])) {
            if (c.notified)
                continue;
            items.push(c.paused
                ? { id: c.id, kind: "timer", title: c.label, paused: true, remaining: Math.round(Number(c.remaining ?? 0) / 1000),
                    total: c.durationSeconds, actions: [{ id: "resume", label: Translation.tr("Resume") }] }
                : { id: c.id, kind: "timer", title: c.label, end: Number(c.endsAt), total: c.durationSeconds,
                    actions: [{ id: "pause", label: Translation.tr("Pause") }] });
        }
        const alarm = AlarmService.ringingAlarm;
        if (alarm)
            items.push({ id: "alarm", kind: "alarm", title: Translation.tr("Alarm"), text: [alarm.time, alarm.label].filter(Boolean).join(" · "),
                actions: [{ id: "snooze", label: Translation.tr("Snooze") }, { id: "stop", label: Translation.tr("Stop") }] });
        for (const j of Array.from(ProgressService.jobs ?? [])) {
            if (j.state !== "running")
                continue;
            items.push({ id: `job:${j.source}:${j.id}`, kind: "progress", title: String(j.appName || Translation.tr("Working")),
                text: String(j.message ?? ""), progress: Math.max(0, Math.min(100, Math.round(Number(j.percent ?? 0)))) });
        }
        return { t: "pcLive", items: items };
    }

    // "" while no phone wants it, so nothing is computed for nobody.
    readonly property string _liveKey: root.liveDev !== "" ? JSON.stringify(root._pcLive()) : ""
    // Progress can move many times a second: at most two pushes a second.
    on_LiveKeyChanged: {
        if (root._liveKey === "")
            root._sentKeys["pcLive"] = "";
        else if (!livePush.running)
            livePush.start();
    }
    Timer {
        id: livePush
        interval: 500
        onTriggered: root._publish("pcLive", root._liveKey)
    }

    /// A button on the phone's live update: {id, action}.
    function _runLive(arg): string {
        const id = String(arg?.id ?? "");
        const action = String(arg?.action ?? "");
        if (id === "rec" && action === "stop") {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "region", "record"]);
            return "";
        }
        if (id === "pomodoro" && (action === "pause" || action === "resume")) {
            TimerService.togglePomodoro();
            return "";
        }
        if (id === "alarm") {
            if (action === "snooze")
                AlarmService.snooze();
            else
                AlarmService.stopRinging();
            return "";
        }
        if (TimerService.findCountdown(id) && (action === "pause" || action === "resume")) {
            TimerService.toggleCountdown(id);
            return "";
        }
        return "not_found";
    }

    // ── The PC's media on the phone ─────────────────────────────────────
    // The shell's active player goes to the phone that asked (`pcMedia` in its caps) as
    // one topic, pushed on change; the position only rides along, and is re-sent when it
    // jumps (a seek), since the phone runs the clock itself. The cover goes as a file,
    // once per image. The phone's own players (the helper's `iitools_` buses) are never
    // sent back to it.

    readonly property string pcMediaDev: root.pcMediaEnabled ? root._capDev("pcMedia") : ""

    function _isPhonePlayer(player): bool {
        return (player?.dbusName ?? "").startsWith("org.mpris.MediaPlayer2.iitools_");
    }

    readonly property var pcMediaPlayer: {
        if (root.pcMediaDev === "")
            return null;
        const active = MprisController.activePlayer;
        if (active && !root._isPhonePlayer(active))
            return active;
        const list = Array.from(MprisController.players).filter(p => !root._isPhonePlayer(p));
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }

    readonly property string _pcArtPath: root.pcMediaPlayer ? CoverArt.localPath(root.pcMediaPlayer.trackArtUrl ?? "") : ""
    readonly property string _pcArt: root._pcArtPath !== "" ? Qt.md5(root._pcArtPath) : ""

    function _pcMedia(): var {
        const p = root.pcMediaPlayer;
        if (!p)
            return { t: "pcMedia", on: false };
        return {
            t: "pcMedia",
            on: true,
            id: p.dbusName ?? "",
            app: p.identity ?? "",
            title: p.trackTitle ?? "",
            artist: p.trackArtist ?? "",
            album: p.trackAlbum ?? "",
            playing: p.isPlaying ?? false,
            length: Math.round(MprisController.trackLengthOf(p) * 1000),
            rate: p.rate ?? 1,
            canPlay: p.canPlay ?? false,
            canPause: p.canPause ?? false,
            canNext: p.canGoNext ?? false,
            canPrevious: p.canGoPrevious ?? false,
            canSeek: (p.canSeek ?? false) && MprisController.hasTrackLength(p),
            art: root._pcArt
        };
    }

    readonly property string _pcMediaKey: root.pcMediaDev !== "" ? JSON.stringify(root._pcMedia()) : ""
    /// What the phone was last told about the position: {pos (s), wall (ms), playing, rate}.
    property var _pcSent: null
    property bool _pcForce: false

    // A track change lands as several property changes in a row: one push for all.
    on_PcMediaKeyChanged: {
        if (root._pcMediaKey === "") {
            root._sentKeys["pcMedia"] = "";
            root._pcSent = null;
        } else if (!pcMediaPush.running) {
            pcMediaPush.start();
        }
    }
    Timer {
        id: pcMediaPush
        interval: 150
        onTriggered: {
            const key = root._pcMediaKey;
            if (key === "" || (!root._pcForce && key === (root._sentKeys["pcMedia"] ?? "")))
                return;
            root._pcForce = false;
            root._sentKeys["pcMedia"] = key;
            const m = JSON.parse(key);
            const p = root.pcMediaPlayer;
            if (m.on && p) {
                const pos = MprisController.trackPositionOf(p);
                m.position = Math.round(pos * 1000);
                root._pcSent = { pos: pos, wall: Date.now(), playing: m.playing, rate: m.rate || 1 };
            }
            root.sendTo(root.pcMediaDev, m);
        }
    }
    Connections {
        target: root.pcMediaPlayer
        // Seeks, and the 1 s ticks of whatever widget shows the player: only a jump
        // away from where the phone's clock stands is worth a push.
        function onPositionChanged() {
            const s = root._pcSent;
            const p = root.pcMediaPlayer;
            if (!s || !p)
                return;
            const expected = s.pos + (s.playing ? (Date.now() - s.wall) / 1000 * s.rate : 0);
            if (Math.abs(MprisController.trackPositionOf(p) - expected) > 2) {
                root._pcForce = true;
                pcMediaPush.restart();
            }
        }
    }

    property string _pcArtSent: ""
    on_PcArtChanged: root._sendPcArt()
    onPcMediaDevChanged: {
        root._pcArtSent = "";
        root._sendPcArt();
    }
    function _sendPcArt(): void {
        if (root.pcMediaDev === "" || root._pcArt === "" || root._pcArt === root._pcArtSent)
            return;
        root._pcArtSent = root._pcArt;
        root.send({ op: "sendFile", dev: root.pcMediaDev, id: 700000 + root._fileSerial++, path: root._pcArtPath,
            name: root._pcArt, purpose: "pcMediaArt" });
    }

    // ── The shell's look on the phone ───────────────────────────────────
    // The desktop wallpaper behind the phone's PC card: a JPEG at most 1080 px wide
    // (a video's first frame), made when the wallpaper changes or a phone that asks for
    // it (`look`) connects, sent once per image per connection, then named in the topic.
    // Nothing runs for a phone that does not ask.

    readonly property string lookDev: root.lookEnabled ? root._capDev("look") : ""
    readonly property string lookDir: `${root.stateDir}/look`
    readonly property string _wallPath: Config.options?.background?.wallpaperPath ?? ""
    readonly property string _lookName: root._wallPath !== "" ? Qt.md5(root._wallPath) : ""
    property string _lookSent: ""
    onLookDevChanged: {
        root._lookSent = "";
        root._makeLook();
    }
    on_LookNameChanged: root._makeLook()

    function _makeLook(): void {
        if (root.lookDev === "" || root._lookName === "" || root._lookName === root._lookSent || lookProc.running)
            return;
        const out = `${root.lookDir}/${root._lookName}.jpg`;
        const video = /\.(mp4|mkv|webm|mov|avi|gif)$/i.test(root._wallPath);
        // Made once per wallpaper and kept; older ones go.
        const make = video
            ? `ffmpeg -y -loglevel error -i "$2" -frames:v 1 -vf "scale='min(1080,iw)':-2" -q:v 4 "$3"`
            : `magick "$2[0]" -resize '1080x1080>' -quality 82 "$3"`;
        lookProc.out = out;
        lookProc.name = root._lookName;
        lookProc.command = ["sh", "-c",
            `mkdir -p -m 700 -- "$1" && find "$1" -type f ! -name "$4.jpg" -delete && { [ -s "$3" ] || ${make}; }`,
            "sh", root.lookDir, root._wallPath, out, root._lookName];
        lookProc.running = true;
    }
    Process {
        id: lookProc
        property string out
        property string name
        onExited: code => {
            if (code === 0 && root.lookDev !== "") {
                root._lookSent = lookProc.name;
                root.send({ op: "sendFile", dev: root.lookDev, id: 600000 + root._fileSerial++, path: lookProc.out,
                    name: lookProc.name, purpose: "look" });
                root.sendTo(root.lookDev, { t: "look", wall: lookProc.name });
            }
            // The wallpaper changed again while this one was being made.
            if (root._lookName !== lookProc.name)
                root._makeLook();
        }
    }

    /// A button on the phone's player: {a: play|pause|toggle|next|previous|seek, value (ms)}.
    function _runPcMedia(arg): string {
        const p = root.pcMediaPlayer;
        if (!p)
            return "not_found";
        switch (String(arg?.a ?? "")) {
        case "play":
            p.play();
            return "";
        case "pause":
            p.pause();
            return "";
        case "toggle":
            p.togglePlaying();
            return "";
        case "next":
            p.next();
            return "";
        case "previous":
            p.previous();
            return "";
        case "seek": {
            const length = MprisController.trackLengthOf(p);
            if (!p.canSeek || length <= 0)
                return "unsupported";
            MprisController.seekFraction(p, Number(arg.value ?? 0) / 1000 / length);
            root._pcForce = true;
            pcMediaPush.restart();
            return "";
        }
        }
        return "bad_arg";
    }

    // ── The phone as a slide clicker ────────────────────────────────────
    // The helper types its keys (arrows, F5, Esc, B) into whatever has focus; the
    // laser is a dot the shell draws over the focused screen (PresenterLaser.qml).
    // The phone's laser pad takes that screen's shape, from `aspect`.

    property string _presentDev: ""
    /// The laser's spot on `presentScreen`, x and y in 0–1, or null while no finger is down.
    property var presentLaser: null
    property string presentScreen: ""
    on_PresentDevChanged: {
        if (root._presentDev === "")
            root.presentLaser = null;
    }

    function _present(dev, m): void {
        if (m.err !== undefined)
            return;
        if (m.laser !== undefined) {
            if (dev !== root._presentDev)
                return;
            const p = m.laser;
            if (Array.isArray(p) && p.length >= 2) {
                if (root.presentLaser === null)
                    root.presentScreen = String(Hyprland.focusedMonitor?.name ?? "");
                root.presentLaser = { x: Math.max(0, Math.min(1, Number(p[0]))), y: Math.max(0, Math.min(1, Number(p[1]))) };
            } else {
                root.presentLaser = null;
            }
            return;
        }
        switch (String(m.a ?? "")) {
        case "start": {
            root._presentDev = dev;
            const mon = Hyprland.focusedMonitor;
            root.sendTo(dev, { t: "present", aspect: mon && mon.height > 0 ? mon.width / mon.height : 16 / 9 });
            return;
        }
        case "stop":
            if (root._presentDev === dev)
                root._presentDev = "";
            return;
        }
    }

    // ── The phone as a drawing pad for live draw ────────────────────────
    // The phone's pad maps onto the focused screen (it is shaped like it, from `aspect`);
    // strokes go into live draw's own surface (LiveDraw.remoteStroke). The pen's state
    // is a topic while the pad is open, so the phone's toolbar shows what the PC uses.

    property string _drawDev: ""

    function _drawState(): var {
        const mon = Hyprland.focusedMonitor;
        const key = LiveDraw.keyFor(String(mon?.name ?? ""));
        return {
            t: "draw",
            open: LiveDraw.trayOpen,
            tool: LiveDraw.tool,
            eraser: LiveDraw.eraser,
            color: String(LiveDraw.color),
            width: LiveDraw.width,
            palette: LiveDraw.palette,
            aspect: mon && mon.height > 0 ? mon.width / mon.height : 16 / 9,
            canUndo: LiveDraw.canUndo(key),
            canRedo: LiveDraw.canRedo(key)
        };
    }
    readonly property string _drawKey: root._drawDev !== "" ? JSON.stringify(root._drawState()) : ""
    on_DrawKeyChanged: {
        if (root._drawKey === "")
            root._sentKeys["draw"] = "";
        else if (root._drawDev !== "" && root._drawKey !== (root._sentKeys["draw"] ?? "")) {
            root._sentKeys["draw"] = root._drawKey;
            root.sendTo(root._drawDev, JSON.parse(root._drawKey));
        }
    }

    function _draw(dev, m): void {
        if (!root.drawEnabled || !LiveDraw.enabled)
            return root.sendTo(dev, { t: "draw", err: "disabled" });
        if (m.s !== undefined) {
            if (dev === root._drawDev && LiveDraw.trayOpen)
                LiveDraw.remoteStroke(String(m.s), Array.isArray(m.p) ? m.p : []);
            return;
        }
        switch (String(m.a ?? "")) {
        case "start":
            root._drawDev = dev;
            LiveDraw.open();
            root._sentKeys["draw"] = "";
            root.sendTo(dev, root._drawState());
            return;
        case "stop":
            // Leaving the pad puts live draw away too (the ink stays, as with the tray).
            if (root._drawDev === dev) {
                root._drawDev = "";
                LiveDraw.close();
            }
            return;
        case "tool":
            if (String(m.tool) === "eraser")
                LiveDraw.eraser = true;
            else
                LiveDraw.setTool(String(m.tool));
            LiveDraw.drawing = true;
            return;
        case "color":
            LiveDraw.color = String(m.color ?? LiveDraw.color);
            LiveDraw.eraser = false;
            return;
        case "width":
            LiveDraw.width = Math.max(1, Math.min(64, Number(m.width ?? LiveDraw.width)));
            return;
        case "undo":
        case "redo":
        case "clear":
            LiveDraw.command(String(m.a), null);
            return;
        case "close":
            LiveDraw.close();
            return;
        }
    }

    // ── The phone's files in the file manager ───────────────────────────
    // As KDE Connect does: the phone runs an SFTP server while the PC has it mounted.
    // It is asked for over the link, which also carries a fresh password and the host
    // key (pinned in a known_hosts of our own), and sshfs mounts it under the runtime
    // dir; the mount goes when the phone disconnects.

    readonly property string filesRoot: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/ii-tools`
    /// dev → mount point, while mounted.
    property var filesMounts: ({})
    property var _filesMountCallbacks: ({})
    property var _filesMounting: ({})

    function _filesDir(dev): string {
        const peer = root.peers.find(p => p.id === dev);
        const name = String(peer?.name || peer?.model || dev).replace(/[\/\0]/g, "_");
        return `${root.filesRoot}/${name}`;
    }

    function _resolveFilesMount(dev, dir, openPath, err): void {
        const mounting = Object.assign({}, root._filesMounting);
        delete mounting[dev];
        root._filesMounting = mounting;
        const cbs = root._filesMountCallbacks[dev] ?? [];
        const nextCbs = Object.assign({}, root._filesMountCallbacks);
        delete nextCbs[dev];
        root._filesMountCallbacks = nextCbs;
        for (const cb of cbs) {
            try {
                cb(dir, openPath, err);
            } catch (e) {}
        }
    }

    /// Mounts the phone's storage over SFTP without opening a file manager;
    /// calls `callback(mountDir, openPath, err)` once ready (or on failure).
    function mountPhoneFiles(dev, callback): bool {
        if (!root.filesEnabled || root.connections[dev] === undefined || !(root.phoneCaps[dev] ?? []).includes("files"))
            return false;
        const existing = root.filesMounts[dev];
        if (existing) {
            if (callback)
                callback(existing.dir, existing.open, "");
            return true;
        }
        if (callback) {
            const nextCbs = Object.assign({}, root._filesMountCallbacks);
            nextCbs[dev] = (nextCbs[dev] ?? []).concat([callback]);
            root._filesMountCallbacks = nextCbs;
        }
        if (!root._filesMounting[dev]) {
            const mounting = Object.assign({}, root._filesMounting);
            mounting[dev] = true;
            root._filesMounting = mounting;
            root.sendTo(dev, { t: "files", a: "start" });
        }
        return true;
    }

    /// Opens the phone's storage in the file manager, mounting it first.
    function browsePhoneFiles(dev): bool {
        return root.mountPhoneFiles(dev, (dir, openPath) => {
            if (dir !== "")
                root._openFiles(dev, openPath || dir);
        });
    }

    /// Shown where the button was pressed (the Phone tab's feedback, which Do Not
    /// Disturb does not hide), and as a notification.
    function _filesProblem(text): void {
        console.warn("[IiLinkService] phone files:", text);
        KdeConnectService.dispatchActionFeedback(text, false);
        Notifications.publishInternalNotification({ appName: "ii tools", appIcon: "smartphone", summary: Translation.tr("Phone files"), body: text });
    }

    function _openFiles(dev, path): void {
        Quickshell.execDetached(["gio", "open", path]);
    }

    function _filesReply(dev, m): void {
        if (m.err) {
            const why = m.err === "permission"
                ? Translation.tr("Allow \"All files access\" for ii tools on the phone (tap its notification), then try again")
                : Translation.tr("The phone could not share its files (%1)").arg(String(m.err));
            root._filesProblem(why);
            root._resolveFilesMount(dev, "", "", why);
            return;
        }
        const addr = root.connections[dev]?.addr ?? "";
        const port = Number(m.port ?? 0);
        const key = String(m.hostKey ?? "");
        if (addr === "" || !(port > 0) || !/^[a-z0-9-]+ [A-Za-z0-9+\/=]+$/.test(key)) {
            root._resolveFilesMount(dev, "", "", "bad_reply");
            return;
        }
        const dir = root._filesDir(dev);
        const paths = Array.isArray(m.paths) ? m.paths.map(String) : [];
        // Internal storage first; the folder above it shows every volume.
        const open = paths.length === 1 ? `${dir}${paths[0]}` : (paths.length > 0 ? `${dir}${paths[0]}` : dir);
        filesMount.dev = dev;
        filesMount.dir = dir;
        filesMount.open = open;
        filesMount.environment = { IILINK_PW: String(m.password ?? "") };
        filesMount.command = ["bash", "-c",
            'set -e; mkdir -p -m 700 -- "$1"; '
            + 'printf "[%s]:%s %s\n" "$2" "$3" "$4" > "$5"; '
            + 'if mountpoint -q -- "$1"; then fusermount3 -uz -- "$1" || true; fi; '
            + 'printf %s "$IILINK_PW" | sshfs -p "$3" -o password_stdin,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,'
            + 'UserKnownHostsFile="$5",StrictHostKeyChecking=yes,PubkeyAuthentication=no,idmap=user,'
            + 'uid=$(id -u),gid=$(id -g),follow_symlinks,fsname=ii-tools '
            + '"$6@$2:/" "$1"',
            "mount", dir, addr, String(port), key, `${root.stateDir}/files_known_hosts`, String(m.user ?? "iitools")];
        filesMount.running = true;
    }

    Process {
        id: filesMount
        property string dev: ""
        property string dir: ""
        property string open: ""
        stderr: StdioCollector { id: filesMountErr }
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("[IiLinkService] sshfs failed:", filesMountErr.text);
                const msg = Translation.tr("Could not mount the phone's storage: %1").arg(filesMountErr.text.trim() || exitCode);
                root._filesProblem(msg);
                root._resolveFilesMount(filesMount.dev, "", "", msg);
                return;
            }
            const next = Object.assign({}, root.filesMounts);
            next[filesMount.dev] = { dir: filesMount.dir, open: filesMount.open };
            root.filesMounts = next;
            root._resolveFilesMount(filesMount.dev, filesMount.dir, filesMount.open, "");
        }
    }

    /// The phone went away (or stops sharing): let the mount go, lazily, so an open
    /// file manager window does not keep it busy.
    function _unmountFiles(dev, tellPhone): void {
        root._resolveFilesMount(dev, "", "", "unmounted");
        const m = root.filesMounts[dev];
        if (!m)
            return;
        Quickshell.execDetached(["fusermount3", "-uz", "--", m.dir]);
        const next = Object.assign({}, root.filesMounts);
        delete next[dev];
        root.filesMounts = next;
        if (tellPhone)
            root.sendTo(dev, { t: "files", a: "stop" });
    }

    function unmountPhoneFiles(dev): void {
        root._unmountFiles(dev, true);
    }

    // ── Launcher icons for the Android Apps page ────────────────────────
    // The phone draws them (the launcher's own look) and sends each as a file, into the
    // per-device cache PhoneAppIconService already reads; adb extraction stays for KDE
    // Connect phones.

    readonly property string launcherIconDev: root._capDev("launcherIcons")
    /// A launcher icon landed on disk.
    signal launcherIconReady(string pkg, string path)

    /// The cache folder PhoneAppIconService (and its adb extractor) use for this phone.
    function launcherIconDir(dev): string {
        const id = `iitools:${dev}`.replace(/[^A-Za-z0-9._-]/g, "_");
        return `${FileUtils.trimFileProtocol(Directories.cache)}/phone_app_icons/${id}`;
    }

    function requestLauncherIcons(pkgs): bool {
        const dev = root.launcherIconDev;
        if (dev === "")
            return false;
        const list = Array.from(pkgs ?? []).map(String).filter(p => /^[A-Za-z0-9._]+$/.test(p));
        for (let i = 0; i < list.length; i += 64)
            root.sendTo(dev, { t: "get", what: "launcherIcons", pkgs: list.slice(i, i + 64) });
        return true;
    }

    // Moved one at a time, so the page is told only once the file is in place.
    property var _iconMoves: []
    function _moveIcons(): void {
        if (iconMover.running || root._iconMoves.length === 0)
            return;
        const next = root._iconMoves.shift();
        iconMover.pkg = next.pkg;
        iconMover.dest = `${next.dir}/${next.pkg}.png`;
        iconMover.command = ["sh", "-c", 'mkdir -p -- "$1" && mv -f -- "$2" "$3"', "sh", next.dir, next.from, iconMover.dest];
        iconMover.running = true;
    }
    Process {
        id: iconMover
        property string pkg: ""
        property string dest: ""
        onExited: exitCode => {
            if (exitCode === 0)
                root.launcherIconReady(iconMover.pkg, iconMover.dest);
            Qt.callLater(root._moveIcons);
        }
    }

    // ── Performance panel ───────────────────────────────────────────────
    // The phone subscribes while its panel is on screen (`sub perf`); only then does a
    // sampler run (the same one as the performance HUD: CPU, RAM, the GPU, MangoHud's
    // frame rate), and one sample a second goes out.

    property string _perfDev: ""
    PerfSampler {
        id: perfSampler
        active: root.perfEnabled && root._perfDev !== "" && root.connections[root._perfDev] !== undefined
    }
    Timer {
        interval: 1000
        repeat: true
        running: perfSampler.active && perfSampler.ready
        onTriggered: root.sendTo(root._perfDev, {
            t: "perf",
            cpu: Object.assign({ name: perfSampler.cpuModel }, perfSampler.cpu),
            ram: perfSampler.ram,
            gpu: Object.assign({ name: perfSampler.selectedGpu?.name ?? "" }, perfSampler.gpu),
            fps: perfSampler.fps,
            gamemode: perfSampler.gamemode !== null && (perfSampler.gamemode?.length ?? 0) > 0
        })
    }

    // ── The phone as a KDE Connect-like device ──────────────────────────
    // KdeConnectService lists the paired phone as one of its devices (`iitools:<id>`),
    // so the Phone tab, the dock, widgets and quick toggles work with ii tools alone;
    // its actions come here when that device is the one picked.

    /// The paired phone, as KdeConnectService's devices look; null when none.
    readonly property var phoneDevice: {
        if (!root.enabled || root.peers.length === 0)
            return null;
        const peer = root.peers[0];
        const conn = root.connections[peer.id] ?? null;
        const caps = root.phoneCaps[peer.id] ?? [];
        const st = root.phoneStatus;
        const plugins = ["kdeconnect_share", "kdeconnect_findmyphone", "kdeconnect_ping"];
        if (caps.includes("notifs")) plugins.push("kdeconnect_notifications");
        if (caps.includes("clip")) plugins.push("kdeconnect_clipboard");
        if (caps.includes("calls")) plugins.push("kdeconnect_telephony");
        if (caps.includes("contacts")) plugins.push("kdeconnect_contacts");
        if (caps.includes("status")) plugins.push("kdeconnect_battery", "kdeconnect_connectivity_report");
        if (caps.includes("files") && root.filesEnabled) plugins.push("kdeconnect_sftp");
        return {
            id: `iitools:${peer.id}`,
            name: peer.name || peer.model || Translation.tr("Phone"),
            type: "smartphone",
            icon: "smartphone",
            reachable: conn !== null,
            paired: true,
            charge: conn && st?.battery ? Number(st.battery.level ?? -1) : -1,
            charging: !!(conn && st?.battery?.charging),
            signalType: st?.net?.type === "wifi" ? "Wi-Fi" : st?.net?.type === "cellular" ? Translation.tr("Mobile") : "",
            signalStrength: Math.max(0, Number(st?.net?.signal ?? 0)),
            supportedPlugins: plugins,
            loadedPlugins: plugins,
            reachableAddresses: conn ? [conn.addr] : [],
            backend: "iitools"
        };
    }

    function _peerOf(deviceId): string {
        return String(deviceId ?? "").replace(/^iitools:/, "");
    }

    /// An action for the phone (`act`): ring, ping, url, text. False when it is away.
    function phoneAct(deviceId, action, fields): bool {
        const dev = root._peerOf(deviceId);
        if (root.connections[dev] === undefined)
            return false;
        root.sendTo(dev, Object.assign({ t: "act", a: action }, fields ?? {}));
        return true;
    }

    /// A file for the phone's Downloads, with a notification there.
    function sendFileToPhone(deviceId, path): bool {
        const dev = root._peerOf(deviceId);
        if (root.connections[dev] === undefined || !path)
            return false;
        root.send({ op: "sendFile", dev: dev, id: 800000 + root._fileSerial++, path: path, purpose: "share" });
        return true;
    }

    /// What is on this clipboard now, to the phone (the "send clipboard" button).
    function sendClipboardToPhone(): bool {
        if (root.clipDev === "" || Cliphist.entries.length === 0)
            return false;
        root._clipSent = "";
        root._sendClip(Cliphist.entries[0]);
        return true;
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

    readonly property bool _watchShots: root.enabled && root.shotsEnabled && root.shotsAutoToPhone && root.hasPeers
    /// The screenshot preview's "Save to phone gallery": shown when sending is by hand.
    readonly property bool canSaveShotToPhone: root.enabled && root.shotsEnabled && !root.shotsAutoToPhone && root.hasPeers
    /// The phone it goes to, by name, for the button and the message.
    readonly property string shotPhoneName: root.connections[root.shotDev]?.name || (root.peers[0]?.name ?? "")

    /**
     * From the preview: the image as shown (cropped like the preview when it has a region),
     * into the outbox, to the phone now or when it next connects.
     */
    function saveShotToPhone(path, region): void {
        if (!root.canSaveShotToPhone || path === "")
            return;
        root._lastShotAt = Date.now();
        const dest = `${root.outboxDir}/pc-${Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss-zzz")}.png`;
        // Like the automatic path: the preview's capture is a raw PPM; a real PNG goes.
        shotQueue.command = ["sh", "-c", `mkdir -p -m 700 -- "$1" && magick "$2" ${root._cropArgs(region)} "$3"`, "sh", root.outboxDir, path, dest];
        shotQueue.running = true;
        Notifications.publishInternalNotification({
            appName: "ii tools",
            appIcon: "camera-photo",
            summary: root.shotDev !== "" ? Translation.tr("Saving to %1").arg(root.shotPhoneName) : Translation.tr("Saved when %1 connects").arg(root.shotPhoneName || Translation.tr("the phone")),
            body: Translation.tr("Screenshot, into the phone's gallery"),
            phone: true
        });
    }
    Connections {
        target: root._watchShots ? GlobalStates : null
        function onScreenshotOverlayImagePathChanged() {
            const path = GlobalStates.screenshotOverlayImagePath;
            // A phone screenshot shown in the preview is not sent back.
            if (path === "" || path.startsWith(root.phoneShotDir))
                return;
            // The region is set right after the path, in the same handler: read it then.
            Qt.callLater(() => root._queueShot(path, "", root._overlayRegion()));
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
                root._queueShot("", Cliphist.entryKey(entry), null);
        }
    }

    function _overlayRegion(): var {
        return { x: GlobalStates.screenshotOverlayRegionX, y: GlobalStates.screenshotOverlayRegionY,
            w: GlobalStates.screenshotOverlayRegionW, h: GlobalStates.screenshotOverlayRegionH };
    }

    /// `magick` arguments that crop to a region, when it has one.
    function _cropArgs(region): string {
        return region && region.w > 0 && region.h > 0
            ? `-crop ${Math.round(region.w)}x${Math.round(region.h)}+${Math.round(region.x)}+${Math.round(region.y)} +repage`
            : "";
    }

    /**
     * From a file (the preview's capture) or a cliphist entry; then send if a phone is
     * there. The preview's capture is a raw PPM of the whole monitor, still being written
     * when the preview opens: wait until it stops growing, then crop it to what the
     * preview shows and write a real PNG (a phone cannot open PPM; it showed black).
     */
    function _queueShot(path, cliphistId, region): void {
        root._lastShotAt = Date.now();
        const dest = `${root.outboxDir}/pc-${Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss-zzz")}.png`;
        const settle = `last=-1; for i in $(seq 40); do now=$(stat -c %s -- "$2" 2>/dev/null || echo 0); [ "$now" -gt 0 ] && [ "$now" = "$last" ] && break; last=$now; sleep 0.1; done`;
        const source = path !== "" ? `${settle}; magick "$2" ${root._cropArgs(region)} "$3"`
            : `${Cliphist.cliphistBinary} decode "$2" | magick - "$3"`;
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
        // A contact's photo, by the key the contacts list gave it.
        if (ev.purpose === "contactPhoto") {
            const key = name.replace(/\.jpg$/, "");
            if (!root.phoneDataEnabled || !/^[0-9a-f]{8,64}$/.test(key))
                return refuse("bad_arg");
            Quickshell.execDetached(["sh", "-c", 'mkdir -p -m 700 -- "$1" && mv -f -- "$2" "$1/$3.jpg"', "sh", root.contactsDir, path, key]);
            root.sendTo(dev, { t: "ok", id: id });
            return;
        }
        // A launcher icon for the Android Apps page, into the cache that page reads.
        if (ev.purpose === "launcherIcon") {
            const pkg = name.replace(/\.png$/, "");
            if (!/^[A-Za-z0-9._]+$/.test(pkg))
                return refuse("bad_arg");
            root._iconMoves.push({ pkg: pkg, from: path, dir: root.launcherIconDir(dev) });
            root._moveIcons();
            root.sendTo(dev, { t: "ok", id: id });
            return;
        }
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
            phoneShot.command = ["sh", "-c", 'mkdir -p -- "$1" && mv -f -- "$2" "$3" && chmod 644 -- "$3" && "$4" "$3"', "sh", root.phoneShotDir, path, dest, `${Directories.scriptPath}/clipboard/copy_image_to_clipboard.py`];
            phoneShot.running = true;
            root.sendTo(dev, { t: "ok", id: id });
            return;
        }
        // An image copied on the phone: onto this clipboard as PNG, then gone from disk.
        if (ev.purpose === "clip") {
            if (!root.clipEnabled)
                return refuse("disabled");
            if (!root._imageName.test(name))
                return refuse("bad_arg");
            Cliphist.markInternalCopy();
            Quickshell.execDetached([`${Directories.scriptPath}/clipboard/copy_image_to_clipboard.py`, "--delete", path]);
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
            actions: root.allowedActions,
            // Kept by the phone with the pairing: it is needed exactly when the PC is off.
            wake: root.wolEnabled ? root.wakeTargets : []
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
            if (action === "live")
                why = root.pcLiveEnabled ? root._runLive(m.arg) : "disabled";
            else if (action === "pcMedia")
                why = root.pcMediaEnabled ? root._runPcMedia(m.arg) : "disabled";
            else if (action === "clip")
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
        case "sub":
            if (m.what === "perf")
                root._perfDev = m.on === true ? dev : (root._perfDev === dev ? "" : root._perfDev);
            return;
        case "dnd":
            if (dev === root.dndDev)
                root._phoneDndChanged(m.on === true);
            return;
        case "status":
            if (root.phoneDataEnabled)
                root._status(m);
            return;
        case "contacts":
            if (root.phoneDataEnabled && dev === root.dataDev)
                root._contacts(dev, m);
            return;
        case "files":
            root._filesReply(dev, m);
            return;
        case "draw":
            root._draw(dev, m);
            return;
        case "present":
            root._present(dev, m);
            return;
        case "screen":
            PhoneScreenService.handleMessage(dev, m);
            return;
        case "gallery":
            PhoneGalleryService.handleMessage(dev, m);
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
            root.wakeTargets = ev.wake ?? [];
            root.send({ op: "config", media: root.mediaEnabled, touchpad: root.touchpadEnabled, present: root.presentEnabled });
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
            if (root._perfDev === ev.dev)
                root._perfDev = "";
            root._unmountFiles(ev.dev, false);
            if (root._drawDev === ev.dev) {
                root._drawDev = "";
                LiveDraw.close();
            }
            if (root._presentDev === ev.dev)
                root._presentDev = "";
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
        case "screen":
        case "screenLive":
        case "screenEnd":
            PhoneScreenService.handleEvent(ev);
            break;
        case "galleryThumbs":
        case "galleryProgress":
        case "galleryFile":
        case "galleryAbort":
            PhoneGalleryService.handleEvent(ev);
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
        /// Opens the first connected phone's storage in the file manager.
        function browseFiles(): string {
            const dev = Object.keys(root.connections)[0] ?? "";
            return root.browsePhoneFiles(dev) ? "ok" : "unavailable";
        }
        function notifications(): string {
            return JSON.stringify(root.linkNotifications.map(n => ({ app: n.app, title: n.title, text: n.text, actions: n.actions.length, image: n.image !== "", avatar: n.avatar !== "" })));
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
                phoneStatus: root.phoneStatus,
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
