pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland
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
    readonly property bool powerEnabled: root.remoteEnabled && (root.opts?.remote?.power ?? true)
    readonly property bool audioEnabled: root.opts?.audio?.enable ?? true
    readonly property bool deckEnabled: root.opts?.deck?.enable ?? true
    readonly property bool wallpaperEnabled: root.opts?.wallpaper?.enable ?? true
    readonly property bool callsEnabled: root.opts?.calls?.enable ?? true
    readonly property bool notifsEnabled: root.opts?.notifications?.enable ?? true
    readonly property bool shareEnabled: root.opts?.share?.enable ?? true
    readonly property bool clipEnabled: root.opts?.clipboard?.enable ?? true
    readonly property bool clipHistoryEnabled: root.clipEnabled && (root.opts?.clipboard?.history ?? true)
    onClipHistoryEnabledChanged: {
        if (!root.clipHistoryEnabled) {
            root._clipHistoryDev = "";
            root._clipThumbQueue = [];
        }
    }
    readonly property bool shotsEnabled: root.opts?.screenshots?.enable ?? true
    readonly property bool phoneDataEnabled: root.opts?.phoneData?.enable ?? true
    readonly property bool dndEnabled: root.opts?.dnd?.enable ?? true
    readonly property bool wolEnabled: root.opts?.wol?.enable ?? true
    readonly property bool tailscaleEnabled: root.opts?.tailscale?.enable ?? false
    readonly property bool pcLinkEnabled: root.opts?.pcLink?.enable ?? true
    readonly property bool pcClipEnabled: root.pcLinkEnabled && (root.opts?.pcLink?.clipboard ?? true)
    onPcLinkEnabledChanged: root.send({ op: "config", pcLink: root.pcLinkEnabled })

    /// Where a phone can reach this PC (`hello.routes`): the LAN addresses, and the
    /// tailnet one while remote access is on and Tailscale runs. A phone drops any
    /// tailnet address it knew when this has none.
    readonly property var routes: {
        const out = root.addresses.filter(a => !root.isTailnet(a)).map(a => ({ kind: "lan", addr: String(a) }));
        if (root.tailscaleEnabled && TailscaleService.active && TailscaleService.tailscaleIp4 !== "")
            out.push({ kind: "tailscale", addr: TailscaleService.tailscaleIp4, dns: TailscaleService.dnsName });
        return out;
    }

    function isTailnet(addr): bool {
        const p = String(addr).split(".").map(Number);
        return p.length === 4 && p[0] === 100 && p[1] >= 64 && p[1] < 128;
    }

    // Remote access reads Tailscale's state only when it can matter (the helper starting,
    // a phone connecting, the switch turned on), never on a timer, and brings it up if
    // it is stopped.
    function _syncTailscale(): void {
        if (root.tailscaleEnabled && root.running)
            TailscaleService.refresh();
    }
    onTailscaleEnabledChanged: root._syncTailscale()
    onRunningChanged: root._syncTailscale()
    Connections {
        target: TailscaleService
        enabled: root.tailscaleEnabled && root.running
        function onStatusUpdated() {
            TailscaleService.ensureUp();
        }
    }
    readonly property bool perfEnabled: root.opts?.perf?.enable ?? true
    readonly property bool mediaEnabled: root.opts?.media?.enable ?? true
    // The helper turns the phone's players into MPRIS ones itself; it only needs telling.
    onMediaEnabledChanged: root.send({ op: "config", media: root.mediaEnabled })
    readonly property bool pcLiveEnabled: root.opts?.pcLive?.enable ?? true
    readonly property bool focusEnabled: root.opts?.focus?.enable ?? true
    readonly property bool voiceEnabled: root.opts?.voice?.enable ?? true
    onVoiceEnabledChanged: {
        if (!root.voiceEnabled) {
            root._voiceDev = "";
            root._sentKeys["voiceSummary"] = "";
        }
    }
    readonly property bool pcMediaEnabled: root.opts?.pcMedia?.enable ?? true
    onPcMediaEnabledChanged: {
        if (!root.pcMediaEnabled)
            root._clearPcLyricsWatchers();
    }
    readonly property bool lookEnabled: root.opts?.look?.enable ?? true
    readonly property bool filesEnabled: root.opts?.files?.enable ?? true
    readonly property bool galleryEnabled: root.opts?.gallery?.enable ?? true
    readonly property bool cameraEnabled: root.opts?.camera?.enable ?? true
    readonly property bool micEnabled: root.opts?.mic?.enable ?? true
    readonly property bool touchpadEnabled: root.opts?.touchpad?.enable ?? true
    readonly property bool drawEnabled: root.opts?.draw?.enable ?? true
    readonly property bool presentEnabled: root.opts?.present?.enable ?? true
    readonly property bool usageEnabled: root.opts?.usage?.enable ?? true
    readonly property bool vitalsEnabled: root.opts?.vitals?.enable ?? false
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
    readonly property string appIconCacheDir: `${FileUtils.trimFileProtocol(Directories.cache)}/iilink/appicons`
    readonly property string clipThumbCacheDir: `${FileUtils.trimFileProtocol(Directories.cache)}/iilink/clipthumbs`
    readonly property string voiceAvatarCacheDir: `${FileUtils.trimFileProtocol(Directories.cache)}/iilink/voiceavatars`

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
            // A download that failed (offline, a fork, no release yet) falls back to a
            // compile when cargo is here, once.
            if (!ok && root.helperBuild.fetchResult === "failed" && root._autoInstalling && root.helperBuild.cargoAvailable) {
                root._autoInstalling = false;
                root.helperBuild.build();
                return;
            }
            root._autoInstalling = false;
            root.checkBinary();
            // The stamp check below restarts the helper; reading now covers a missed event.
            if (ok)
                stampFile.reload();
        }
    }

    // ── Kept current by itself ───────────────────────────────────────────
    // Whenever the link is wanted and the helper is missing or older than its sources
    // (an update, a pull), the shell downloads the CI's build of these sources, and
    // builds it here only if that cannot be had. Once per shell start: a failure stays
    // on screen (Settings → ii tools → Helper) with Download and Rebuild buttons.
    property bool _autoInstalled: false
    property bool _autoInstalling: false
    readonly property bool _helperNeedsInstall: root.enabled && root.wanted && root.probed
        && root.helperBuild.prebuilt && (!root.binaryPresent || root.helperBuild.outdated)
    on_HelperNeedsInstallChanged: {
        if (!root._helperNeedsInstall || root._autoInstalled || root.helperBuild.building || root.helperBuild.fetching)
            return;
        root._autoInstalled = true;
        root._autoInstalling = true;
        console.info("[IiLink] the helper is missing or older than its sources: downloading it");
        root.helperBuild.fetch();
    }

    // ── A new binary restarts the helper ─────────────────────────────────
    // rust-helpers.sh moves the new binary in, then writes this stamp (a source hash and
    // the build time, so every build changes it). Builds from the update script never
    // passed through `helperBuild`, so the old helper kept running a deleted binary: a
    // shell newer than its helper offered the phone a Wi-Fi screen it could not serve.
    /// The stamp on disk, "" while there is none.
    property string _stamp: ""
    property bool _stampRead: false
    /// The stamp the running helper started under; "pending" when it started before the
    /// first read (shell start), which then takes the stamp read rather than restart.
    property string _runningStamp: ""

    function _restartIfReplaced(): void {
        if (root._runningStamp === "pending") {
            root._runningStamp = root._stamp;
            return;
        }
        if (!helper.running || root._stamp === "" || root._stamp === root._runningStamp)
            return;
        console.info("[IiLink] the helper binary was replaced, restarting it");
        root._runningStamp = root._stamp;
        root.checkBinary();
        root.restart();
    }

    FileView {
        id: stampFile
        path: `${root.helperDir}/.ii_link.stamp`
        watchChanges: true
        printErrors: false
        onFileChanged: stampFile.reload()
        onLoaded: {
            // Written with `>`: an empty read is the truncation before the write.
            const stamp = stampFile.text().trim();
            if (stamp === "")
                return;
            root._stampRead = true;
            root._stamp = stamp;
            root._restartIfReplaced();
        }
        // No stamp (a helper built by hand): the first stamp to appear is a new binary.
        onLoadFailed: {
            root._stampRead = true;
            if (root._runningStamp === "pending")
                root._runningStamp = "";
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

    // ── Linked PCs (PC link), also known without running the helper ─────
    /// [{ fp, name, hosts, pairedAt, lastSeen }]
    property var pcPeers: []
    /// fp → { name, since } for the linked PCs connected right now.
    property var pcConnections: ({})
    readonly property bool hasPcPeers: root.pcPeers.length > 0
    readonly property bool pcConnected: Object.keys(root.pcConnections).length > 0

    FileView {
        id: pcsFile
        path: `${root.stateDir}/pcs.json`
        watchChanges: true
        printErrors: false
        onFileChanged: pcsFile.reload()
        onLoaded: root._setPcPeers(pcsFile.text())
        onLoadFailed: root.pcPeers = []
    }

    function _setPcPeers(text): void {
        try {
            const list = JSON.parse(text);
            root.pcPeers = Array.isArray(list) ? list.map(p => ({
                fp: String(p.fp ?? ""), name: String(p.name ?? ""), hosts: p.hosts ?? [],
                pairedAt: Number(p.pairedAt ?? 0), lastSeen: Number(p.lastSeen ?? 0), canWake: (p.wake ?? []).length > 0
            })) : [];
        } catch (e) {
            root.pcPeers = [];
        }
    }

    function unpairPc(fp): void {
        root.send({ op: "pcUnpair", pc: String(fp) });
    }

    // ── Linking without the phone: a 6-digit code ───────────────────────
    /// This PC's open code: { code, check, expires } or null.
    property var localPair: null
    /// Other PCs found on the LAN: [{ fp, name, port, addr, check }].
    property var pcFound: []
    property bool pcDiscovering: false
    /// "" | "working" | "ok" | an error code, for the code typed here.
    property string localJoin: ""

    /// What both screens show, so a stranger on the LAN answering the broadcast is caught.
    function fpCheck(fp): string {
        const s = String(fp ?? "").toUpperCase();
        return s.length >= 8 ? `${s.slice(0, 4)} ${s.slice(4, 8)}` : "";
    }

    function _pcLocal(op): void {
        const req = ++root._pcReqSerial;
        const next = Object.assign({}, root._pcReqs);
        next[req] = { dev: "local", id: 0 };
        root._pcReqs = next;
        root.send(Object.assign({ req: req }, op));
    }

    function openPcCode(): void {
        root.localPair = null;
        root._pcLocal({ op: "pcPairOpen", code: true });
    }

    function closePcCode(): void {
        root.send({ op: "pcPairClose" });
        root.localPair = null;
    }

    function discoverPcs(): void {
        root.pcDiscovering = true;
        root.localJoin = "";
        root.send({ op: "pcDiscover" });
    }

    function joinPcByCode(found, code): void {
        const c = String(code ?? "").replace(/\D/g, "");
        if (!found || c.length !== 6)
            return;
        root.localJoin = "working";
        root._pcLocal({ op: "pcPairJoin", fp: found.fp, hosts: [found.addr], port: Number(found.port ?? 0), secret: c, name: String(found.name ?? "") });
    }

    /// Wake-on-LAN for a linked PC that is off, from the adapters it last told about.
    function wakePc(fp): void {
        root.send({ op: "pcWake", pc: String(fp) });
    }

    /// Phone requests waiting on the helper (`req` → { dev, id }).
    property var _pcReqs: ({})
    property int _pcReqSerial: 0

    function _pcRequest(dev, m, op): void {
        const id = Number(m.id ?? 0);
        const reply = m.t === "pcPairOpen" ? "pcPairInfo" : "pcPairResult";
        if (!root.pcLinkEnabled) {
            root.sendTo(dev, reply === "pcPairInfo" ? { t: reply, id: id, err: "disabled" } : { t: reply, id: id, ok: false, code: "disabled" });
            return;
        }
        const req = ++root._pcReqSerial;
        const next = Object.assign({}, root._pcReqs);
        next[req] = { dev: String(dev), id: id };
        root._pcReqs = next;
        root.send(Object.assign({ req: req }, op));
    }

    function _pcTakeReq(req): var {
        const r = root._pcReqs[req] ?? null;
        if (r) {
            const next = Object.assign({}, root._pcReqs);
            delete next[req];
            root._pcReqs = next;
        }
        return r;
    }

    function _pcName(fp): string {
        return root.pcConnections[fp]?.name || root.pcPeers.find(p => p.fp === fp)?.name || Translation.tr("the other PC");
    }

    function _handlePcEvent(ev): void {
        switch (ev.ev) {
        case "pcPeers":
            root.pcPeers = (ev.list ?? []).map(p => ({ fp: String(p.fp), name: String(p.name ?? ""), hosts: p.hosts ?? [], pairedAt: Number(p.pairedAt ?? 0), lastSeen: Number(p.lastSeen ?? 0), canWake: p.canWake === true }));
            break;
        case "pcConnected": {
            const next = Object.assign({}, root.pcConnections);
            next[ev.pc] = { name: String(ev.name ?? ""), since: Date.now() };
            root.pcConnections = next;
            break;
        }
        case "pcDisconnected": {
            const next = Object.assign({}, root.pcConnections);
            delete next[ev.pc];
            root.pcConnections = next;
            const prog = Object.assign({}, root.pcShelfProgress);
            for (const k of Object.keys(prog))
                if (k.startsWith(`${ev.pc}:`))
                    delete prog[k];
            root.pcShelfProgress = prog;
            root.pcShelfRevision++;
            break;
        }
        case "pcPairOpen": {
            const r = root._pcTakeReq(ev.req);
            if (!r)
                break;
            if (r.dev === "local") {
                root.localPair = ev.err ? null : { code: String(ev.secret), check: root.fpCheck(ev.fp), expires: Date.now() + 120000 };
                break;
            }
            root.sendTo(r.dev, ev.err ? { t: "pcPairInfo", id: r.id, err: String(ev.err) }
                : { t: "pcPairInfo", id: r.id, secret: ev.secret, fp: ev.fp, port: ev.port, name: ev.name, hosts: ev.hosts ?? [] });
            break;
        }
        case "pcPaired": {
            const r = ev.req !== undefined ? root._pcTakeReq(ev.req) : null;
            if (r && r.dev === "local")
                root.localJoin = "ok";
            else if (r)
                root.sendTo(r.dev, { t: "pcPairResult", id: r.id, ok: true, name: String(ev.name ?? "") });
            else
                root.localPair = null;
            Notifications.publishInternalNotification({
                appName: "ii tools",
                appIcon: "computer",
                summary: Translation.tr("Linked with %1").arg(String(ev.name ?? "") || Translation.tr("another PC")),
                body: root.pcClipEnabled ? Translation.tr("What you copy here now reaches it too.") : ""
            });
            break;
        }
        case "pcPairFailed": {
            const r = root._pcTakeReq(ev.req);
            if (r && r.dev === "local")
                root.localJoin = String(ev.code ?? "failed");
            else if (r)
                root.sendTo(r.dev, { t: "pcPairResult", id: r.id, ok: false, code: String(ev.code ?? "failed") });
            break;
        }
        case "pcPairClosed":
            root.localPair = null;
            break;
        case "pcFound":
            root.pcDiscovering = false;
            root.pcFound = (ev.list ?? []).map(f => ({ fp: String(f.fp), name: String(f.name ?? ""), port: Number(f.port ?? 0), addr: String(f.addr ?? ""), check: root.fpCheck(f.fp) }))
                .filter(f => !root.pcPeers.some(p => p.fp === f.fp));
            break;
        case "pcMsg":
            root._handlePcMessage(String(ev.pc), ev.m ?? {});
            break;
        case "pcFileProgress": {
            const key = `${ev.pc}:${ev.id}`;
            if (root.pcShelfProgress[key] !== undefined) {
                const next = Object.assign({}, root.pcShelfProgress);
                next[key] = Number(ev.p ?? 0);
                root.pcShelfProgress = next;
                root.pcShelfRevision++;
            }
            break;
        }
        }
    }

    function _handlePcMessage(fp, m): void {
        switch (m.t) {
        case "shelf":
            root._setPcShelf(fp, m.items ?? []);
            return;
        case "shelfGet":
            root._serveShelf(fp, String(m.id ?? ""));
            return;
        case "mediaHandoff":
            root._receiveMediaHandoff(fp, m);
            return;
        case "shelfGone":
        case "fileFailed":
            root._pcFileDone(fp, String(m.id ?? ""), "");
            return;
        case "file":
            if (m.purpose === "put")
                root._receivePut(fp, String(m.name ?? ""), String(m.path ?? ""));
            else
                root._pcFileDone(fp, String(m.id ?? ""), String(m.path ?? ""));
            return;
        }
        if (m.t !== "clip" || !root.pcClipEnabled)
            return;
        if (m.path) {
            // An image the helper already wrote out: onto this clipboard as PNG, then gone.
            Cliphist.markInternalCopy();
            Quickshell.execDetached([`${Directories.scriptPath}/clipboard/copy_image_to_clipboard.py`, "--delete", String(m.path)]);
            root._announcePcClip(fp, Translation.tr("An image"));
        } else if (typeof m.text === "string" && m.text.length > 0) {
            Cliphist.markInternalCopy();
            Quickshell.clipboardText = m.text;
            root._announcePcClip(fp, m.text.replace(/\s+/g, " ").trim().slice(0, 160));
        }
    }

    // ── Shared shelf (PC link, stage 2) ─────────────────────────────────
    // This PC's shelf goes to the linked PCs as names and thumbnails; a file travels only
    // when the other PC drags or opens it (`shelfGet`). Theirs show here the same way.

    /// fp → [{ id, name, image, video, thumbPath }] as the linked PC last sent it.
    property var pcShelves: ({})
    /// "fp:id" → the copy here, once fetched.
    property var pcShelfLocal: ({})
    /// "fp:id" → 0..1 while it is on its way.
    property var pcShelfProgress: ({})
    /// Bumps when any of the three change, for bindings on FileShelf's functions.
    property int pcShelfRevision: 0
    readonly property string shelfThumbDir: `${FileUtils.trimFileProtocol(Directories.cache)}/iilink/shelfthumbs`
    readonly property int _shelfMax: 24

    function _setPcShelf(fp, items): void {
        const next = Object.assign({}, root.pcShelves);
        next[fp] = items.map(it => ({ id: String(it.id ?? ""), name: String(it.name ?? ""), image: it.image === true, video: it.video === true,
            thumbPath: it.thumbPath ? `file://${it.thumbPath}?${Date.now()}` : "" })).filter(it => it.id !== "");
        root.pcShelves = next;
        root.pcShelfRevision++;
    }

    function shelfId(path): string {
        return Qt.md5(String(path));
    }

    /// Asks [fp] for its shelf item [id] (once while it is on its way).
    function pcShelfGet(fp, id): void {
        const key = `${fp}:${id}`;
        if (root.pcShelfLocal[key] || root.pcShelfProgress[key] !== undefined || !root.pcConnections[fp])
            return;
        const next = Object.assign({}, root.pcShelfProgress);
        next[key] = 0;
        root.pcShelfProgress = next;
        root.pcShelfRevision++;
        root.send({ op: "pcSend", pc: fp, m: { t: "shelfGet", id: id } });
    }

    function _pcFileDone(fp, id, path): void {
        const key = `${fp}:${id}`;
        const prog = Object.assign({}, root.pcShelfProgress);
        delete prog[key];
        root.pcShelfProgress = prog;
        if (path !== "") {
            const local = Object.assign({}, root.pcShelfLocal);
            local[key] = path;
            root.pcShelfLocal = local;
        }
        root.pcShelfRevision++;
    }

    /// The other PC wants one of this shelf's files.
    function _serveShelf(fp, id): void {
        const path = FileShelf.items.find(p => root.shelfId(p) === id);
        if (!path) {
            root.send({ op: "pcSend", pc: fp, m: { t: "shelfGone", id: id } });
            return;
        }
        root.send({ op: "pcSendFile", pc: fp, path: FileUtils.trimFileProtocol(String(path)), id: id, purpose: "shelf", name: FileShelf.name(path) });
    }

    /// Files dropped on "Send to <PC>": they land in that PC's Downloads and on its shelf.
    function sendToPc(fp, paths): void {
        for (const raw of Array.from(paths ?? [])) {
            const path = decodeURIComponent(FileUtils.trimFileProtocol(String(raw)));
            if (path === "" || FileShelf.isPhone(path) || FileShelf.isPc(path))
                continue;
            root.send({ op: "pcSendFile", pc: fp, path: path, id: Qt.md5(path + Date.now()).slice(0, 16), purpose: "put" });
        }
    }

    property var _putQueue: []
    function _receivePut(fp, name, path): void {
        if (path === "")
            return;
        root._putQueue.push({ fp: fp, name: name, path: path });
        root._nextPut();
    }
    function _nextPut(): void {
        if (putMove.running || root._putQueue.length === 0)
            return;
        const next = root._putQueue.shift();
        putMove.pending = next;
        const dir = FileUtils.trimFileProtocol(Directories.downloads) || `${FileUtils.trimFileProtocol(Directories.home)}/Downloads`;
        // "name (1).ext" when it is taken: never overwrite.
        putMove.command = ["sh", "-c", 'mkdir -p -- "$1" && n="$2" && b="${n%.*}" && e="${n##*.}" && [ "$b" = "$n" ] && e="" ; d="$1/$n"; i=1; while [ -e "$d" ]; do if [ -n "$e" ]; then d="$1/$b ($i).$e"; else d="$1/$n ($i)"; fi; i=$((i+1)); done; mv -f -- "$3" "$d" && rmdir -- "$(dirname -- "$3")" 2>/dev/null; printf "%s" "$d"', "sh", dir, next.name, next.path];
        putMove.running = true;
    }
    Process {
        id: putMove
        property var pending: null
        stdout: StdioCollector {
            id: putMoveOut
        }
        onExited: code => {
            const p = putMove.pending;
            const dest = putMoveOut.text.trim();
            if (code === 0 && dest !== "" && p) {
                FileShelf.add([dest]);
                Notifications.publishInternalNotification({
                    appName: "ii tools",
                    appIcon: "folder-download",
                    summary: Translation.tr("Received from %1").arg(root._pcName(p.fp)),
                    body: p.name
                });
            }
            putMove.pending = null;
            Qt.callLater(root._nextPut);
        }
    }

    // Publishing this shelf: on any change and when a PC connects, debounced; images get a
    // small thumbnail once (cached by id), rendered one at a time.
    property var _shelfThumbs: ({})
    property var _thumbQueue: []
    readonly property var _shelfKey: root.pcLinkEnabled && root.pcConnected ? JSON.stringify(FileShelf.items) + Object.keys(root.pcConnections).join(",") : ""
    on_ShelfKeyChanged: if (root._shelfKey !== "") shelfPublish.restart()
    Timer {
        id: shelfPublish
        interval: 400
        onTriggered: root._publishShelf()
    }

    function _publishShelf(): void {
        if (!root.pcConnected)
            return;
        const local = FileShelf.items.slice().reverse().slice(0, root._shelfMax);
        const items = local.map(path => {
            const id = root.shelfId(path);
            const image = FileShelf.isImage(path);
            if (image && root._shelfThumbs[id] === undefined)
                root._queueThumb(id, path);
            return { id: id, name: FileShelf.name(path), image: image, video: /\.(mp4|mkv|webm|mov|avi)$/i.test(String(path)),
                thumb: root._shelfThumbs[id] || "" };
        });
        root.send({ op: "pcShelf", pc: "*", items: items });
    }

    function _queueThumb(id, path): void {
        root._shelfThumbs[id] = "";
        root._thumbQueue.push({ id: id, path: FileUtils.trimFileProtocol(String(path)) });
        root._nextThumb();
    }
    function _nextThumb(): void {
        if (shelfThumb.running || root._thumbQueue.length === 0)
            return;
        const next = root._thumbQueue.shift();
        shelfThumb.pending = next;
        shelfThumb.command = ["sh", "-c", 'mkdir -p -- "$1" && magick "$2[0]" -auto-orient -thumbnail "192x192^" -gravity center -extent 192x192 -quality 78 "$1/$3.jpg"', "sh", root.shelfThumbDir, next.path, next.id];
        shelfThumb.running = true;
    }
    Process {
        id: shelfThumb
        property var pending: null
        onExited: code => {
            const p = shelfThumb.pending;
            if (p && code === 0) {
                const next = Object.assign({}, root._shelfThumbs);
                next[p.id] = `${root.shelfThumbDir}/${p.id}.jpg`;
                root._shelfThumbs = next;
                if (root._thumbQueue.length === 0)
                    shelfPublish.restart();
            }
            shelfThumb.pending = null;
            Qt.callLater(root._nextThumb);
        }
    }

    function _announcePcClip(fp, body): void {
        Notifications.publishInternalNotification({
            appName: "ii tools",
            appIcon: "edit-paste",
            summary: Translation.tr("Copied from %1").arg(root._pcName(fp)),
            body: body
        });
    }

    // Copied here → the linked PCs, as it happens (never on a timer, nothing on connect:
    // an old copy turning up on the other PC would only overwrite what it has).
    property string _pcClipSent: ""
    Connections {
        target: root.pcClipEnabled && root.pcConnected ? Cliphist : null
        function onEntryAdded(entry) {
            const key = Cliphist.entryKey(entry);
            if (key === "" || key === root._pcClipSent)
                return;
            root._pcClipSent = key;
            root._enqueueClipDecode("pc:*", key, Cliphist.entryIsImage(entry), 0);
        }
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
    readonly property var capabilities: (root.remoteEnabled ? ["remote", "workspaces", "modes", "presets", "unlock"] : [])
        .concat(root.remoteEnabled ? ["display", "modeActions"] : [])
        .concat(root.powerEnabled ? ["power"] : [])
        .concat(root.audioEnabled ? ["audio"] : [])
        .concat(root.deckEnabled ? ["deck", "appIcons", "deckFocus"] : [])
        .concat(root.wallpaperEnabled ? ["wallpaper"] : [])
        .concat(root.wallSyncEnabled ? ["wallSave"] : [])
        .concat(root.callsEnabled ? ["calls"] : [])
        .concat(root.notifsEnabled ? ["notifs", "notifFilter"] : [])
        .concat(root.shareEnabled ? ["share"] : [])
        .concat(root.clipEnabled ? ["clip"] : [])
        .concat(root.pcLinkEnabled ? ["pcLink"] : [])
        .concat(["wakeRelay"])
        .concat(root.clipHistoryEnabled ? ["clipHistory"] : [])
        .concat(root.shotsEnabled ? ["shots"] : [])
        .concat(root.phoneDataEnabled ? ["phoneData"] : [])
        .concat(root.dndEnabled ? ["dnd"] : [])
        .concat(root.pcLiveEnabled ? ["pcLive"] : [])
        .concat(root.focusEnabled ? ["focus"] : [])
        .concat(root.voiceEnabled ? ["voice"] : [])
        .concat(root.perfEnabled ? ["perf"] : [])
        .concat(root.mediaEnabled ? ["media"] : [])
        .concat(root.pcMediaEnabled ? ["pcMedia", "pcLyrics"] : [])
        .concat(root.filesEnabled ? ["files"] : [])
        .concat(root.galleryEnabled ? ["gallery"] : [])
        .concat(root.touchpadEnabled ? ["touchpad"] : [])
        .concat(root.drawEnabled ? ["draw"] : [])
        .concat(root.presentEnabled ? ["present"] : [])
        .concat(PhoneScreenService.enabled ? (PhoneScreenService.wirelessEnabled ? ["screen", "screenWifi", "screenTools", "screenAudio", "screenUdp"] : ["screen", "screenTools"]) : [])
        .concat(root.cameraEnabled ? ["camera"] : [])
        .concat(root.micEnabled ? ["mic"] : [])
        .concat(root.usageEnabled ? ["usage"] : [])
        .concat(root.vitalsEnabled ? ["vitals"] : [])
        .concat(["mirrorRadio", "quiet", "have", "fileLane"])

    /// True while at least one wireless scrcpy session is active on the shell.
    property bool mirrorActive: false

    function setMirrorActive(on: bool): void {
        const next = !!on
        if (root.mirrorActive === next) return
        root.mirrorActive = next
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("mirrorRadio")) {
                root.sendTo(id, { t: "mirror", on: next })
            }
        }
    }

    // What is on right now, read from the same state the shell itself draws from.
    readonly property bool _aodUp: (GlobalStates.oledSaverMonitors ?? []).length > 0
    readonly property var activeActions: {
        const on = [];
        if (GlobalStates.screenLocked)
            on.push("lock");
        if (!root.remoteEnabled)
            return on.concat(root._deckActive);
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
            if (GlobalStates.screenLocked)
                return "locked";
            GlobalStates.requestMediaMode("toggle");
            return "";
        case "scratchpad":
            if (GlobalStates.screenLocked)
                return "locked";
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

    // ── Power: shut down or restart from the phone ───────────────────────
    // The phone confirms before it sends. The reply goes out first, then the timer runs
    // the session action, so the phone sees "ok" rather than a dropped link.
    property string _pendingPower: ""

    function _runPower(kind): string {
        if (kind !== "poweroff" && kind !== "reboot")
            return "unknown_action";
        root._pendingPower = kind;
        powerTimer.restart();
        return "";
    }

    Timer {
        id: powerTimer
        interval: 800
        onTriggered: {
            const kind = root._pendingPower;
            root._pendingPower = "";
            if (kind === "poweroff")
                Session.poweroff();
            else if (kind === "reboot")
                Session.reboot();
        }
    }

    function _runDeck(id): string {
        if (GlobalStates.screenLocked)
            return "locked";
        if (id.startsWith("g:")) {
            const action = id.slice(2);
            if (root._deckSkip.includes(action) || !TouchGestureActionRegistry.actions.some(a => a.id === action))
                return "not_found";
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
            .map(e => ({ id: e.id, name: e.name, icon: AppSearch.entryIcon(e) || e.icon }))
            .sort((a, b) => a.name.localeCompare(b.name));
        return { t: "apps", list: list };
    }

    // ── App icons for the deck ──────────────────────────────────────────
    // Resolved in the active icon theme, rendered to 96x96 PNG once per name into
    // appIconCacheDir and sent back as {"t":"appIcon","name","png"} in one Process per batch.
    property var _appIconQueue: []

    function _requestAppIcons(dev, icons): void {
        if (!Array.isArray(icons))
            return;
        const batch = [];
        const seen = {};
        for (let i = 0; i < icons.length && batch.length < 32; i++) {
            const name = String(icons[i] ?? "");
            if (name === "" || seen[name])
                continue;
            seen[name] = true;
            batch.push(name);
        }
        if (batch.length === 0)
            return;
        root._appIconQueue.push({ dev: dev, icons: batch });
        root._nextAppIconBatch();
    }

    function _nextAppIconBatch(): void {
        if (appIconProc.running || root._appIconQueue.length === 0)
            return;
        const next = root._appIconQueue.shift();
        if (!root.connections[next.dev]) {
            Qt.callLater(root._nextAppIconBatch);
            return;
        }
        const theme = (Config.options?.appearance?.icons?.enableThemed ?? false)
            ? "DynamicTheme"
            : String(Config.options?.appearance?.iconTheme ?? "");
        appIconProc.dev = next.dev;
        appIconProc.command = ["python3", `${root.helperDir}/render_app_icons.py`, root.appIconCacheDir, theme].concat(next.icons);
        appIconProc.running = true;
    }

    Process {
        id: appIconProc
        property string dev: ""
        stdout: SplitParser {
            onRead: line => {
                let obj;
                try {
                    obj = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (obj?.name && obj?.png && root.connections[appIconProc.dev]) {
                    root.sendTo(appIconProc.dev, { t: "appIcon", name: String(obj.name), png: String(obj.png) });
                }
            }
        }
        onExited: Qt.callLater(root._nextAppIconBatch)
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
    /// Apps seen by the phone's notification listener: [{ pkg, name, blocked }]
    property var notifApps: []
    signal appIconReady(string pkg, string path)

    FileView {
        id: notifAppsFile
        path: root.enabled && root.hasPeers && root.notifsEnabled ? `${root.stateDir}/notif_apps.json` : ""
        printErrors: false
        onLoaded: root._loadNotifApps(notifAppsFile.text())
        onLoadFailed: root.notifApps = []
    }
    function _normalizeNotifApps(list): var {
        if (!Array.isArray(list))
            return [];
        const out = [];
        for (const item of list) {
            if (!item || typeof item !== "object")
                continue;
            const pkg = String(item.pkg ?? "");
            if (pkg === "")
                continue;
            out.push({
                pkg: pkg,
                name: String(item.name ?? pkg) || pkg,
                blocked: Boolean(item.blocked),
            });
        }
        return out;
    }
    function _loadNotifApps(raw): void {
        try {
            root.notifApps = root._normalizeNotifApps(JSON.parse(raw));
        } catch (e) {
            root.notifApps = [];
        }
    }
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
        if (!(Config.options?.phone?.mirrorNotificationsToDesktop ?? true))
            return;
        // A code is copied even under Do Not Disturb (only its popup is held back).
        if (root.otpEnabled) {
            const code = root.otpCode(`${n.title} ${n.text}`);
            if (code !== "") {
                root._popupOtp(n, code);
                return;
            }
        }
        if (Notifications.popupInhibited)
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

    // ── Verification codes ──────────────────────────────────────────────
    // A code in a mirrored notification (SMS or app) is copied and offered in a popup
    // of its own. The copy is marked sensitive: wl-clipboard flags it, cliphist skips
    // it, and it is wiped after `otp.clearAfter` seconds if still there.

    readonly property bool otpEnabled: root.notifsEnabled && (root.opts?.otp?.enable ?? true)
    property string _otpCopied: ""

    /// The code in a notification's text, or "" when it carries none.
    function otpCode(text): string {
        const t = String(text ?? "");
        const key = /(c[óo]digo|code|verifica|verify|token|senha|password|pin\b|otp|one[- ]time|autentica|authenticat|2fa)/i.exec(t);
        if (!key)
            return "";
        const re = /(\d{3}[- ]\d{3}|\d{4,8})(?!\d)/g;
        let best = "";
        let bestDist = 1e9;
        let m;
        while ((m = re.exec(t)) !== null) {
            const before = m.index > 0 ? t[m.index - 1] : "";
            const after = t.slice(m.index + m[0].length, m.index + m[0].length + 3);
            // A longer number's tail, money, a time, a date, a percentage, a decimal.
            if (/[\d.,$€£]/.test(before) || /[$€£]\s*$/.test(t.slice(0, m.index)))
                continue;
            if (/^([.,]\d|[:\/%h]|\s?(reais|usd|min|hora|dias|km))/i.test(after))
                continue;
            const dist = Math.abs(m.index - key.index);
            // After the keyword beats before it ("seu código é 123456" over "123456 é o código" ties).
            const score = m.index >= key.index ? dist : dist + 40;
            if (score < bestDist) {
                bestDist = score;
                best = m[0];
            }
        }
        return best.replace(/[- ]/g, "");
    }

    /// Copies `code` for pasting, marked sensitive, and arms its wipe.
    function copyOtp(code): void {
        const c = String(code ?? "");
        if (!/^\d{3,10}$/.test(c))
            return;
        Quickshell.execDetached(["wl-copy", "--sensitive", c]);
        root._otpCopied = c;
        const after = Number(root.opts?.otp?.clearAfter ?? 60);
        if (after > 0) {
            otpClear.interval = after * 1000;
            otpClear.restart();
        } else {
            otpClear.stop();
        }
    }

    Timer {
        id: otpClear
        repeat: false
        onTriggered: {
            const c = root._otpCopied;
            root._otpCopied = "";
            if (c === "")
                return;
            // Only when the clipboard still holds the code: never wipe something newer.
            Quickshell.execDetached(["sh", "-c", 'cur=$(wl-paste --no-newline 2>/dev/null); [ "$cur" = "$1" ] && wl-copy --clear', "sh", c]);
        }
    }

    Connections {
        target: Notifications
        function onInternalActionInvoked(identifier, notificationId, payload) {
            if (identifier !== "__qs_otp_copy")
                return;
            root.copyOtp(payload?.code);
            Notifications.discardNotification(notificationId);
        }
    }

    /// Shows the code: popup with Copy, and the copy itself unless auto-copy is off.
    function _popupOtp(n, code): void {
        const auto = root.opts?.otp?.autoCopy ?? true;
        if (auto)
            root.copyOtp(code);
        if (Notifications.popupInhibited)
            return;
        Notifications.publishInternalNotification({
            appName: n.app,
            appIcon: root.iconFor(n.pkg),
            summary: Translation.tr("Code %1").arg(code.replace(/^(\d{3})(\d{3})$/, "$1 $2")),
            body: auto ? Translation.tr("Copied · %1").arg(n.title || n.app) : (n.title || n.app),
            phone: true,
            sound: true,
            actions: [{ identifier: "__qs_otp_copy", text: auto ? Translation.tr("Copy again") : Translation.tr("Copy") }],
            actionPayload: { code: code }
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
    function setNotifBlocked(pkg, blocked): void {
        const cleanPkg = String(pkg ?? "");
        if (cleanPkg === "")
            return;
        const dev = root.notifDev !== ""
            ? root.notifDev
            : (root.connectedList.length > 0 ? String(root.connectedList[0].id ?? "") : "");
        if (dev === "")
            return;
        const nextBlocked = Boolean(blocked);
        root.sendTo(dev, { t: "notifFilter", pkg: cleanPkg, blocked: nextBlocked });
        root.notifApps = root.notifApps.map(app => app.pkg === cleanPkg
            ? ({ pkg: app.pkg, name: app.name, blocked: nextBlocked })
            : app);
        notifAppsFile.setText(JSON.stringify(root.notifApps));
        if (nextBlocked)
            root.linkNotifications = root.linkNotifications.filter(x => x.pkg !== cleanPkg);
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
    property var _clipDecodeQueue: []

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
        root._enqueueClipDecode(root.clipDev, key, Cliphist.entryIsImage(entry), 0);
    }

    function _enqueueClipDecode(dev, key, isImage, cmdId): void {
        root._clipDecodeQueue.push({ dev: dev, key: key, image: Boolean(isImage), cmdId: Number(cmdId ?? 0) });
        root._nextClipDecode();
    }

    function _nextClipDecode(): void {
        if (clipDecode.running || root._clipDecodeQueue.length === 0)
            return;
        const next = root._clipDecodeQueue.shift();
        if (!root.connections[next.dev]) {
            Qt.callLater(root._nextClipDecode);
            return;
        }
        // From cliphist itself: its list shows only a preview, and Quickshell's own
        // clipboard text does not follow copies made in other apps. One process per copy.
        clipDecode.dev = next.dev;
        clipDecode.image = next.image;
        clipDecode.cmdId = next.cmdId;
        clipDecode._streamDone = false;
        clipDecode._exited = false;
        // Text as it is (Qt reads it as UTF-8); an image as base64 for the JSON message.
        clipDecode.command = ["sh", "-c", `${Cliphist.cliphistBinary} decode "$1" | head -c ${root.clipImageMax + 1}${next.image ? " | base64 -w0" : ""}`, "sh", next.key];
        clipDecode.running = true;
    }

    function _finishClipDecode(data): void {
        if (data.length === 0) {
            if (clipDecode.cmdId > 0)
                root.sendTo(clipDecode.dev, { t: "err", id: clipDecode.cmdId, code: "not_found" });
            return;
        }
        if (!clipDecode.image) {
            root.sendTo(clipDecode.dev, { t: "clip", text: data });
            if (clipDecode.cmdId > 0)
                root.sendTo(clipDecode.dev, { t: "ok", id: clipDecode.cmdId });
            return;
        }
        // Past the limit (the base64 of max + 1 bytes): the image stays on the PC.
        const trimmed = data.trim();
        if (trimmed.length <= Math.ceil(root.clipImageMax / 3) * 4) {
            root.sendTo(clipDecode.dev, { t: "clip", mime: "image/png", data: trimmed });
            if (clipDecode.cmdId > 0)
                root.sendTo(clipDecode.dev, { t: "ok", id: clipDecode.cmdId });
        } else if (clipDecode.cmdId > 0) {
            root.sendTo(clipDecode.dev, { t: "err", id: clipDecode.cmdId, code: "too_large" });
        }
    }

    Process {
        id: clipDecode
        property string dev: ""
        property bool image: false
        property int cmdId: 0
        property bool _streamDone: false
        property bool _exited: false
        stdout: StdioCollector {
            onStreamFinished: {
                clipDecode._streamDone = true;
                root._finishClipDecode(this.text);
                if (clipDecode._exited)
                    Qt.callLater(root._nextClipDecode);
            }
        }
        onExited: {
            clipDecode._exited = true;
            if (clipDecode._streamDone)
                Qt.callLater(root._nextClipDecode);
        }
    }

    // ── Clipboard history ───────────────────────────────────────────────
    // Paged cliphist browsing (`get clipHistory`), on-demand thumbnails (`get clipThumbs`),
    // pulling an entry to the phone without echoing back to the PC (`clipPull`), and
    // copying an entry onto the PC's clipboard (`clipCopyPc`). Blocked while locked.

    property string _clipHistoryDev: ""
    readonly property bool _clipHistorySubActive: root.clipHistoryEnabled && root._clipHistoryDev !== "" && root.connections[root._clipHistoryDev] !== undefined
    property bool _clipHistoryDirtyWhileLocked: false
    property var _clipThumbQueue: []
    property bool _clipThumbCacheMayExist: false
    property bool _clipThumbPrunedOnce: false

    function _scheduleClipHistoryChanged(): void {
        if (!root._clipHistorySubActive)
            return;
        if (GlobalStates.screenLocked) {
            root._clipHistoryDirtyWhileLocked = true;
            return;
        }
        clipHistoryChangeTimer.restart();
    }

    Timer {
        id: clipHistoryChangeTimer
        interval: 1000
        onTriggered: {
            if (root._clipHistorySubActive && !GlobalStates.screenLocked)
                root.sendTo(root._clipHistoryDev, { t: "clipHistoryChanged" });
        }
    }

    Connections {
        target: root._clipHistorySubActive ? Cliphist : null
        function onClipboardUpdated() {
            root._scheduleClipHistoryChanged();
        }
        function onPinnedEntriesChanged() {
            root._scheduleClipHistoryChanged();
        }
    }

    Connections {
        target: root._clipHistorySubActive ? GlobalStates : null
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked && root._clipHistoryDirtyWhileLocked) {
                root._clipHistoryDirtyWhileLocked = false;
                clipHistoryChangeTimer.restart();
            }
        }
    }

    Connections {
        target: root.enabled && root.clipHistoryEnabled && root.hasPeers ? Cliphist : null
        function onClipboardUpdated() {
            if (root._clipThumbCacheMayExist || !root._clipThumbPrunedOnce)
                clipThumbPruneTimer.restart();
        }
    }

    Timer {
        id: clipThumbPruneTimer
        interval: 1000
        onTriggered: root._pruneClipThumbs()
    }

    function _pruneClipThumbs(): void {
        if (clipThumbPruneProc.running)
            return;
        root._clipThumbPrunedOnce = true;
        const ids = [];
        for (const entry of Cliphist.entries) {
            if (!Cliphist.entryIsImage(entry))
                continue;
            const id = Cliphist.entryKey(entry);
            if (/^\d+$/.test(id))
                ids.push(id);
        }
        clipThumbPruneProc.command = [
            "sh", "-c",
            'printf "%s\\n" "$1" | python3 "$2" prune "$3"',
            "sh", ids.join("\n"), `${root.helperDir}/render_clip_thumbs.py`, root.clipThumbCacheDir
        ];
        clipThumbPruneProc.running = true;
    }

    Process {
        id: clipThumbPruneProc
        stdout: StdioCollector {
            onStreamFinished: {
                root._clipThumbCacheMayExist = this.text.trim() === "nonempty";
            }
        }
    }

    function _clipHistoryEntries(): var {
        const liveEntries = Array.from(Cliphist.entries ?? []);
        const liveByClean = ({});
        for (let i = 0; i < liveEntries.length; i++) {
            const e = liveEntries[i];
            const clean = StringUtils.cleanCliphistEntry(e);
            if (liveByClean[clean] === undefined)
                liveByClean[clean] = e;
        }
        const out = [];
        const seenIds = ({});
        const pinned = Array.from(Cliphist.pinnedEntries ?? []);
        for (let i = 0; i < pinned.length; i++) {
            const p = pinned[i];
            const clean = StringUtils.cleanCliphistEntry(p);
            const live = liveEntries.indexOf(p) !== -1 ? p : (liveByClean[clean] ?? null);
            const actual = live ?? p;
            const isImg = Cliphist.entryIsImage(actual);
            if (live === null && isImg)
                continue;
            const id = Cliphist.entryKey(actual);
            if (id === "" || seenIds[id])
                continue;
            seenIds[id] = true;
            out.push({ entry: actual, id: id, text: clean.slice(0, 200), image: isImg, pinned: true });
        }
        for (let i = 0; i < liveEntries.length; i++) {
            const e = liveEntries[i];
            if (Cliphist.isPinned(e))
                continue;
            const id = Cliphist.entryKey(e);
            if (id === "" || seenIds[id])
                continue;
            seenIds[id] = true;
            out.push({ entry: e, id: id, text: StringUtils.cleanCliphistEntry(e).slice(0, 200), image: Cliphist.entryIsImage(e), pinned: false });
        }
        return out;
    }

    function _findClipEntryById(key): string {
        for (const e of Array.from(Cliphist.entries ?? [])) {
            if (Cliphist.entryKey(e) === key)
                return e;
        }
        for (const e of Array.from(Cliphist.pinnedEntries ?? [])) {
            if (Cliphist.entryKey(e) === key)
                return e;
        }
        return "";
    }

    function _sendClipHistory(dev, offset, limit): void {
        if (!root.clipHistoryEnabled) {
            root.sendTo(dev, { t: "err", code: "disabled", what: "clipHistory" });
            return;
        }
        if (GlobalStates.screenLocked) {
            if (root._clipHistoryDev === dev)
                root._clipHistoryDirtyWhileLocked = true;
            root.sendTo(dev, { t: "err", code: "locked", what: "clipHistory" });
            return;
        }
        const all = root._clipHistoryEntries();
        const off = Math.max(0, Math.floor(Number(offset ?? 0)) || 0);
        const lim = Math.max(1, Math.min(200, Math.floor(Number(limit ?? 50)) || 50));
        const page = all.slice(off, off + lim).map(x => ({
            id: x.id,
            text: x.text,
            image: x.image,
            pinned: x.pinned
        }));
        root.sendTo(dev, { t: "clipHistory", offset: off, total: all.length, list: page });
    }

    function _requestClipThumbs(dev, ids): void {
        if (!root.clipHistoryEnabled) {
            root.sendTo(dev, { t: "err", code: "disabled", what: "clipThumbs" });
            return;
        }
        if (GlobalStates.screenLocked) {
            if (root._clipHistoryDev === dev)
                root._clipHistoryDirtyWhileLocked = true;
            root.sendTo(dev, { t: "err", code: "locked", what: "clipThumbs" });
            return;
        }
        if (!Array.isArray(ids))
            return;
        const imageIds = ({});
        for (const e of Array.from(Cliphist.entries ?? [])) {
            if (!Cliphist.entryIsImage(e))
                continue;
            const k = Cliphist.entryKey(e);
            if (k !== "")
                imageIds[k] = true;
        }
        const batch = [];
        const seen = ({});
        for (let i = 0; i < ids.length && batch.length < 24; i++) {
            const id = String(ids[i] ?? "").trim();
            if (!/^\d+$/.test(id) || seen[id] || !imageIds[id])
                continue;
            seen[id] = true;
            batch.push(id);
        }
        if (batch.length === 0)
            return;
        root._clipThumbQueue.push({ dev: dev, ids: batch });
        root._nextClipThumbBatch();
    }

    function _nextClipThumbBatch(): void {
        if (clipThumbProc.running || root._clipThumbQueue.length === 0)
            return;
        const next = root._clipThumbQueue.shift();
        if (!root.clipHistoryEnabled || GlobalStates.screenLocked || !root.connections[next.dev]) {
            Qt.callLater(root._nextClipThumbBatch);
            return;
        }
        root._clipThumbCacheMayExist = true;
        clipThumbProc.dev = next.dev;
        clipThumbProc.command = ["python3", `${root.helperDir}/render_clip_thumbs.py`, "render", root.clipThumbCacheDir, Cliphist.cliphistBinary].concat(next.ids);
        clipThumbProc.running = true;
    }

    Process {
        id: clipThumbProc
        property string dev: ""
        stdout: SplitParser {
            onRead: line => {
                if (!root.clipHistoryEnabled || GlobalStates.screenLocked || !root.connections[clipThumbProc.dev])
                    return;
                let obj;
                try {
                    obj = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (obj?.id && obj?.png)
                    root.sendTo(clipThumbProc.dev, { t: "clipThumb", id: String(obj.id), png: String(obj.png) });
            }
        }
        onExited: Qt.callLater(root._nextClipThumbBatch)
    }

    function _clipPull(dev, cmdId, arg): void {
        if (!root.clipHistoryEnabled) {
            root.sendTo(dev, { t: "err", id: cmdId, code: "disabled" });
            return;
        }
        if (GlobalStates.screenLocked) {
            root.sendTo(dev, { t: "err", id: cmdId, code: "locked" });
            return;
        }
        const key = String(typeof arg === "object" && arg !== null ? (arg.id ?? "") : (arg ?? "")).trim();
        if (!/^\d+$/.test(key)) {
            root.sendTo(dev, { t: "err", id: cmdId, code: "bad_arg" });
            return;
        }
        for (const e of Array.from(Cliphist.entries ?? [])) {
            if (Cliphist.entryKey(e) === key) {
                root._enqueueClipDecode(dev, key, Cliphist.entryIsImage(e), cmdId);
                return;
            }
        }
        for (const e of Array.from(Cliphist.pinnedEntries ?? [])) {
            if (Cliphist.entryKey(e) === key) {
                if (Cliphist.entryIsImage(e)) {
                    root.sendTo(dev, { t: "err", id: cmdId, code: "not_found" });
                    return;
                }
                root.sendTo(dev, { t: "clip", text: StringUtils.cleanCliphistEntry(e) });
                root.sendTo(dev, { t: "ok", id: cmdId });
                return;
            }
        }
        root.sendTo(dev, { t: "err", id: cmdId, code: "not_found" });
    }

    function _clipCopyPc(arg): string {
        if (!root.clipHistoryEnabled)
            return "disabled";
        if (GlobalStates.screenLocked)
            return "locked";
        const key = String(typeof arg === "object" && arg !== null ? (arg.id ?? "") : (arg ?? "")).trim();
        if (!/^\d+$/.test(key))
            return "bad_arg";
        const entry = root._findClipEntryById(key);
        if (entry === "")
            return "not_found";
        Cliphist.copy(entry);
        return "";
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

    /// { battery: { level, charging, plug, temp, health }, net: { type, signal }, ringer, peripherals: [{ id, name, kind, level }], at } or null.
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

    function _sanitizePeripherals(raw): var {
        if (!Array.isArray(raw))
            return [];
        const out = [];
        for (const item of raw) {
            if (!item || typeof item !== "object")
                continue;
            const id = String(item.id ?? "").trim();
            const name = String(item.name ?? "").trim();
            if (!id || !name)
                continue;
            const level = Number(item.level);
            if (!Number.isFinite(level) || level < 0 || level > 100)
                continue;
            const entry = {
                id: id,
                name: name,
                kind: String(item.kind ?? "other").trim() || "other",
                level: Math.round(level)
            };
            out.push(entry);
        }
        return out;
    }

    function peripheralIcon(kind): string {
        switch (kind) {
        case "earbuds":
            return "earbuds";
        case "watch":
            return "watch";
        case "headset":
            return "headphones";
        case "speaker":
            return "speaker";
        case "keyboard":
            return "keyboard";
        case "mouse":
            return "mouse";
        default:
            return "bluetooth";
        }
    }

    function _status(m): void {
        root.phoneStatus = {
            battery: m.battery ?? null,
            net: m.net ?? null,
            ringer: String(m.ringer ?? ""),
            peripherals: root._sanitizePeripherals(m.peripherals),
            at: Date.now()
        };
        if ("alarm" in m)
            PhoneAlarmService.fromLink(m.alarm);
    }

    // ── Phone performance (`phonePerf`) ─────────────────────────────────
    // The reverse of `perf`: the phone's own load for the Phone tab's Stats panel. The
    // phone samples (every 2 s) only while a panel here watches; an app from before
    // announces no `phonePerf`, and one that announces it but stays silent is taken as
    // old too, so the Stats tab never shows empty.

    /// The connected phone that reports its load; "" when none (no ii tools, or an old one).
    readonly property string phonePerfDev: {
        if (!root.phoneDataEnabled)
            return "";
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("phonePerf") && !root._phonePerfSilent[id])
                return id;
        }
        return "";
    }
    /// The Stats tab shows: a phone that reports its load is (or was, this session) here.
    readonly property bool phonePerfAvailable: root.phonePerfDev !== "" || (root.phoneDataEnabled && root.phonePerf !== null)
    /// The last sample: { dev, name, device, uptime, ram, storage, thermal, battery, net, cpu, at }, or null.
    property var phonePerf: null
    /// The last 30 samples of RAM in use (0–1), oldest first, for the memory graph.
    property list<real> phonePerfRam: []
    /// dev id → true when it announced `phonePerf` but never answered a watch.
    property var _phonePerfSilent: ({})
    property int _phonePerfWatchers: 0
    property string _phonePerfSubDev: ""

    /// A panel showing the phone's load appears (true) or goes (false).
    function watchPhonePerf(on: bool): void {
        root._phonePerfWatchers = Math.max(0, root._phonePerfWatchers + (on ? 1 : -1));
        root._syncPhonePerfSub();
    }
    onPhonePerfDevChanged: root._syncPhonePerfSub()

    function _syncPhonePerfSub(): void {
        const want = root._phonePerfWatchers > 0 ? root.phonePerfDev : "";
        if (want === root._phonePerfSubDev)
            return;
        if (root._phonePerfSubDev !== "" && root.connections[root._phonePerfSubDev] !== undefined)
            root.sendTo(root._phonePerfSubDev, { t: "sub", what: "phonePerf", on: false });
        root._phonePerfSubDev = want;
        if (want !== "") {
            root.sendTo(want, { t: "sub", what: "phonePerf", on: true });
            phonePerfSilence.dev = want;
            phonePerfSilence.retried = false;
            phonePerfSilence.restart();
        } else {
            phonePerfSilence.stop();
        }
    }

    // A watch sent while the phone was still connecting can be lost: ask once more
    // before taking the app for an old one.
    Timer {
        id: phonePerfSilence
        property string dev: ""
        property bool retried: false
        interval: 8000
        onTriggered: {
            if (root._phonePerfSubDev !== dev || (root.phonePerf?.dev === dev && Date.now() - root.phonePerf.at < interval))
                return;
            if (!retried) {
                retried = true;
                root.sendTo(dev, { t: "sub", what: "phonePerf", on: true });
                restart();
                return;
            }
            const silent = Object.assign({}, root._phonePerfSilent);
            silent[dev] = true;
            root._phonePerfSilent = silent;
        }
    }

    /// What the phone reads as the shell user through Shizuku (optional): CPU use, sensor
    /// temperatures, GPU use, the busiest processes, battery health and storage by type.
    function _phonePerfShell(sh): var {
        if (!sh || typeof sh !== "object")
            return null;
        const num = v => (typeof v === "number" && isFinite(v)) ? v : null;
        const temps = {};
        for (const k of ["cpu", "gpu", "ram", "modem", "npu", "skin"]) {
            const v = num(sh.temps?.[k]) ?? (k === "skin" ? num(sh.hal?.skin) : null);
            if (v !== null)
                temps[k] = v;
        }
        if (num(sh.hal?.usb) !== null)
            temps.usb = sh.hal.usb;
        const storage = {};
        for (const k of ["apps", "appData", "photos", "videos", "audio", "downloads", "system", "other"]) {
            if (num(sh.storage?.[k]) !== null)
                storage[k] = sh.storage[k];
        }
        return {
            cpu: sh.cpu && num(sh.cpu.usage) !== null ? { usage: sh.cpu.usage, cores: Array.isArray(sh.cpu.cores) ? sh.cpu.cores.map(Number) : [] } : null,
            temps: temps,
            gpu: num(sh.gpu),
            procs: Array.isArray(sh.procs) ? sh.procs.slice(0, 4).map(p => ({
                name: String(p.label || p.name || ""),
                cpu: num(p.cpu) ?? 0,
                rssKb: num(p.rssKb) ?? 0
            })).filter(p => p.name.length > 0) : [],
            health: num(sh.health),
            storage: Object.keys(storage).length > 0 ? storage : (root.phonePerf?.shell?.storage ?? null)
        };
    }

    function _phonePerfSample(dev, m): void {
        const num = v => (typeof v === "number" && isFinite(v)) ? v : null;
        const ram = m.ram ?? null;
        const sample = {
            dev: dev,
            name: String(root.connections[dev]?.name ?? ""),
            device: m.device ?? null,
            uptime: num(m.uptime),
            ram: ram && num(ram.total) > 0 ? { total: ram.total, avail: num(ram.avail) ?? 0, low: ram.low === true } : null,
            storage: m.storage && num(m.storage.total) > 0 ? { total: m.storage.total, free: num(m.storage.free) ?? 0 } : (root.phonePerf?.storage ?? null),
            thermal: m.thermal ? { status: num(m.thermal.status) ?? 0, headroom: num(m.thermal.headroom) } : null,
            battery: m.battery ? { level: num(m.battery.level), charging: m.battery.charging === true, temp: num(m.battery.temp), mv: num(m.battery.mv), ma: num(m.battery.ma) } : null,
            net: m.net ? { rx: num(m.net.rx) ?? 0, tx: num(m.net.tx) ?? 0 } : null,
            cpu: m.cpu ? { cores: num(m.cpu.cores) ?? 0, freq: Array.isArray(m.cpu.freq) ? m.cpu.freq.map(Number) : [], max: Array.isArray(m.cpu.max) ? m.cpu.max.map(Number) : [] } : null,
            shell: root._phonePerfShell(m.shell),
            at: Date.now()
        };
        root.phonePerf = sample;
        if (sample.ram) {
            const next = root.phonePerfRam.slice(-29);
            next.push(1 - sample.ram.avail / sample.ram.total);
            root.phonePerfRam = next;
        }
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

    // ── Phone calendar ──────────────────────────────────────────────────
    // The phone's calendars for the Timetable (CalendarService merges them with khal's).
    // Asked for on connect and whenever the Timetable's window grows, with the version
    // this PC has; the phone answers only when it changed and pushes each change after.
    // The last list is kept on disk, so the events stay while the phone is away
    // (read-only until it is back).

    readonly property bool calendarEnabled: root.opts?.calendar?.enable ?? true
    readonly property string calendarDev: {
        if (!root.calendarEnabled)
            return "";
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("calendar"))
                return id;
        }
        return "";
    }
    /// The phone offers its calendar and lets this PC edit it.
    readonly property bool calendarWritable: root.calendarDev !== "" && (root.phoneCaps[root.calendarDev] ?? []).includes("calendarWrite")
    /// When the phone's list last arrived (ms), 0 if never this session.
    property real calendarAt: 0
    property int _calendarSeq: 1
    property var _calendarCallbacks: ({})

    FileView {
        id: calendarFile
        path: root.calendarEnabled && root.enabled ? `${root.stateDir}/calendar.json` : ""
        printErrors: false
        onLoaded: {
            if (CalendarService.phoneFeed !== null)
                return;
            try {
                const cached = JSON.parse(calendarFile.text());
                if (cached && Array.isArray(cached.events))
                    CalendarService.setPhoneFeed(cached, false);
            } catch (e) {}
        }
    }

    onCalendarEnabledChanged: {
        if (!root.calendarEnabled)
            CalendarService.setPhoneFeed(null, false);
    }
    onCalendarDevChanged: {
        // A new connection gets the whole list: `have` stays empty until it arrives.
        root.phoneLiveFeed = false;
        if (root.calendarDev !== "") {
            root._askCalendar();
        } else if (CalendarService.phoneFeed !== null) {
            // Away: the cached list stays, read-only.
            CalendarService.setPhoneFeed(CalendarService.phoneFeed, false);
            root._failCalendarEdits("offline");
        }
    }

    function _askCalendar(): void {
        if (root.calendarDev === "")
            return;
        const feed = CalendarService.phoneFeed;
        root.sendTo(root.calendarDev, {
            t: "get",
            what: "calendar",
            from: Qt.formatDate(CalendarService.rangeStart, "yyyy-MM-dd"),
            to: Qt.formatDate(CalendarService.rangeEnd, "yyyy-MM-dd"),
            have: root.phoneLiveFeed ? String(feed?.hash ?? "") : ""
        });
    }
    /// The feed came over this connection (not from the disk cache).
    property bool phoneLiveFeed: false

    // The Timetable reached a month outside the window: ask again, once it settles.
    Connections {
        target: root.calendarDev !== "" ? CalendarService : null
        function onRangeStartChanged() { calendarAskTimer.restart(); }
        function onRangeEndChanged() { calendarAskTimer.restart(); }
    }
    Timer {
        id: calendarAskTimer
        interval: 400
        onTriggered: root._askCalendar()
    }

    function _calendar(dev, m): void {
        const feed = {
            calendars: Array.isArray(m.calendars) ? m.calendars : [],
            events: Array.isArray(m.events) ? m.events : [],
            series: (m.series && typeof m.series === "object") ? m.series : {},
            write: m.write === true,
            hash: String(m.hash ?? ""),
            from: String(m.from ?? ""),
            to: String(m.to ?? ""),
            at: Date.now()
        };
        root.phoneLiveFeed = true;
        root.calendarAt = feed.at;
        CalendarService.setPhoneFeed(feed, true);
        calendarFile.setText(JSON.stringify(feed));
    }

    /// Sends one edit (`calendarEdit`: create / update / delete); `callback(reply)` gets `{ ok, error }`.
    function calendarEdit(request, callback): void {
        if (root.calendarDev === "" || !root.calendarWritable) {
            if (typeof callback === "function")
                callback({ ok: false, error: "offline" });
            return;
        }
        const id = root._calendarSeq++;
        const callbacks = Object.assign({}, root._calendarCallbacks);
        callbacks[id] = { callback: callback, at: Date.now() };
        root._calendarCallbacks = callbacks;
        root.sendTo(root.calendarDev, Object.assign({ t: "calendarEdit", id: id }, request));
        calendarEditTimeout.restart();
    }

    function _calendarResult(m): void {
        const id = Number(m.id);
        const entry = root._calendarCallbacks[id];
        if (!entry)
            return;
        const callbacks = Object.assign({}, root._calendarCallbacks);
        delete callbacks[id];
        root._calendarCallbacks = callbacks;
        if (typeof entry.callback === "function")
            entry.callback({ ok: m.ok === true, error: String(m.error ?? "") });
    }

    function _failCalendarEdits(reason): void {
        const pending = root._calendarCallbacks;
        root._calendarCallbacks = ({});
        for (const id of Object.keys(pending)) {
            if (typeof pending[id].callback === "function")
                pending[id].callback({ ok: false, error: reason });
        }
    }

    // An edit the phone never answered (it went away mid-way) fails after 15 s.
    Timer {
        id: calendarEditTimeout
        interval: 15000
        onTriggered: {
            const now = Date.now();
            const pending = root._calendarCallbacks;
            const kept = {};
            for (const id of Object.keys(pending)) {
                if (now - pending[id].at >= 15000) {
                    if (typeof pending[id].callback === "function")
                        pending[id].callback({ ok: false, error: "timeout" });
                } else {
                    kept[id] = pending[id];
                }
            }
            root._calendarCallbacks = kept;
            if (Object.keys(kept).length > 0)
                calendarEditTimeout.restart();
        }
    }

    // ── Phone usage (screen time) ───────────────────────────────────────
    // Kept in `${stateDir}/phone_usage/<YYYY-MM-DD>.json`, 60 days retained, read lazily
    // by AppStats and BedtimeService only while `iiTools.usage.enable` is on.

    readonly property string phoneUsageDir: `${root.stateDir}/phone_usage`
    property string _newestPhoneUsageDate: "" // "" = unchecked, "none" = empty/missing
    property bool _pendingPhoneUsageReq: false
    property var _phoneUsageQueue: []
    signal phoneUsageUpdated(var dates, var sessionsByDate)

    readonly property string usageDev: {
        if (!root.usageEnabled)
            return "";
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("usage"))
                return id;
        }
        return "";
    }
    onUsageDevChanged: {
        if (root.usageDev !== "")
            root.requestPhoneUsage();
    }

    function requestPhoneUsage(): bool {
        const dev = root.usageDev;
        if (dev === "")
            return false;
        if (root._newestPhoneUsageDate === "") {
            root._pendingPhoneUsageReq = true;
            if (!phoneUsageScan.running) {
                phoneUsageScan.command = ["sh", "-c", 'ls -1 -- "$1" 2>/dev/null | grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.json$" | sort | tail -n 1 || true', "sh", root.phoneUsageDir];
                phoneUsageScan.running = true;
            }
            return true;
        }
        const msg = { t: "get", what: "phoneUsage" };
        if (/^\d{4}-\d{2}-\d{2}$/.test(root._newestPhoneUsageDate))
            msg.since = root._newestPhoneUsageDate;
        root.sendTo(dev, msg);
        return true;
    }

    Process {
        id: phoneUsageScan
        stdout: StdioCollector {
            onStreamFinished: {
                const name = String(this.text ?? "").trim().replace(/\.json$/, "");
                root._newestPhoneUsageDate = /^\d{4}-\d{2}-\d{2}$/.test(name) ? name : "none";
                if (root._pendingPhoneUsageReq) {
                    root._pendingPhoneUsageReq = false;
                    root.requestPhoneUsage();
                }
            }
        }
    }

    function _savePhoneUsage(dev, m): void {
        if (!root.usageEnabled || (root.usageDev !== "" && dev !== root.usageDev))
            return;
        const rawDays = Array.isArray(m?.days) ? m.days : [];
        const days = [];
        const sessionsByDate = {};
        for (const d of rawDays) {
            const date = String(d?.date ?? "");
            if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
                continue;
            const apps = [];
            for (const a of Array.isArray(d.apps) ? d.apps : []) {
                const pkg = String(a?.pkg ?? "");
                if (!/^[A-Za-z0-9._-]+$/.test(pkg))
                    continue;
                const h = [];
                const rawH = Array.isArray(a.h) ? a.h : [];
                for (let hr = 0; hr < 24; hr++)
                    h.push(Math.max(0, Math.min(3600, Math.round(Number(rawH[hr] ?? 0)))));
                apps.push({ pkg: pkg, name: String(a.name ?? pkg), h: h });
            }
            const sessions = [];
            for (const s of Array.isArray(d.sessions) ? d.sessions : []) {
                if (!Array.isArray(s) || s.length < 2)
                    continue;
                const startMs = Number(s[0] ?? 0);
                const endMs = Number(s[1] ?? 0);
                if (Number.isFinite(startMs) && Number.isFinite(endMs) && endMs > startMs)
                    sessions.push([Math.round(startMs), Math.round(endMs)]);
            }
            days.push({ date: date, apps: apps, sessions: sessions });
            sessionsByDate[date] = sessions;
            if (root._newestPhoneUsageDate === "" || root._newestPhoneUsageDate === "none" || date > root._newestPhoneUsageDate)
                root._newestPhoneUsageDate = date;
        }
        if (days.length === 0)
            return;
        root._phoneUsageQueue.push({
            dates: days.map(d => d.date),
            sessionsByDate: sessionsByDate,
            payload: JSON.stringify({ dir: root.phoneUsageDir, days: days })
        });
        root._flushPhoneUsageQueue();
    }

    function _flushPhoneUsageQueue(): void {
        if (phoneUsageWriter.running || root._phoneUsageQueue.length === 0)
            return;
        const next = root._phoneUsageQueue.shift();
        phoneUsageWriter.pendingDates = next.dates;
        phoneUsageWriter.pendingSessions = next.sessionsByDate;
        phoneUsageWriter.pendingPayload = next.payload;
        phoneUsageWriter.running = true;
    }

    Process {
        id: phoneUsageWriter
        property var pendingDates: []
        property var pendingSessions: ({})
        property string pendingPayload: ""
        stdinEnabled: true
        command: [
            "python3",
            "-c",
            "import json, os, sys\nreq = json.loads(sys.stdin.readline())\ndir_path = req['dir']\nos.makedirs(dir_path, mode=0o700, exist_ok=True)\nfor day in req['days']:\n    d = day.get('date', '')\n    if len(d) != 10 or d[4] != '-' or d[7] != '-':\n        continue\n    tmp = os.path.join(dir_path, '.' + d + '.tmp')\n    dst = os.path.join(dir_path, d + '.json')\n    with open(tmp, 'w', encoding='utf-8') as f:\n        json.dump(day, f, separators=(',', ':'))\n    os.chmod(tmp, 0o600)\n    os.replace(tmp, dst)\nfiles = sorted(f for f in os.listdir(dir_path) if len(f) == 15 and f.endswith('.json') and f[4] == '-' and f[7] == '-')\nfor old in files[:-60]:\n    try:\n        os.unlink(os.path.join(dir_path, old))\n    except OSError:\n        pass\n"
        ]
        onStarted: {
            if (phoneUsageWriter.pendingPayload !== "")
                phoneUsageWriter.write(phoneUsageWriter.pendingPayload + "\n");
        }
        onExited: code => {
            const dates = phoneUsageWriter.pendingDates;
            const sessions = phoneUsageWriter.pendingSessions;
            phoneUsageWriter.pendingPayload = "";
            phoneUsageWriter.pendingDates = [];
            phoneUsageWriter.pendingSessions = ({});
            if (code === 0 && dates.length > 0)
                root.phoneUsageUpdated(dates, sessions);
            Qt.callLater(root._flushPhoneUsageQueue);
        }
    }

    // ── Vitals (health data) ────────────────────────────────────────────
    // VitalsService keeps the store and decides what to ask; this only finds the phone
    // and carries the messages. Referencing the service here is what creates it.

    readonly property string vitalsDev: {
        if (!root.vitalsEnabled)
            return "";
        for (const id of Object.keys(root.connections)) {
            if ((root.phoneCaps[id] ?? []).includes("vitals"))
                return id;
        }
        return "";
    }
    onVitalsDevChanged: {
        if (root.vitalsDev !== "")
            VitalsService.connected();
    }

    /// Sends a `get` for vitals to the phone that shares them; false when none does.
    function sendVitals(message): bool {
        if (root.vitalsDev === "")
            return false;
        root.sendTo(root.vitalsDev, message);
        return true;
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
        const pomoActive = Boolean(pomo?.running) || Boolean(pomo?.isBreak) || Number(pomo?.cycle ?? 0) > 0
            || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0);
        if (pomoActive) {
            const phase = TimerService.pomodoroLongBreak ? "longBreak" : TimerService.pomodoroBreak ? "break" : "focus";
            const cycle = Number(TimerService.pomodoroCycle ?? 0);
            const cycles = Math.max(1, Number(TimerService.cyclesBeforeLongBreak ?? 4));
            const title = TimerService.pomodoroLongBreak ? Translation.tr("Long break") : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus");
            items.push(pomo?.running
                ? { id: "pomodoro", kind: "timer", title: title, phase: phase, cycle: cycle, cycles: cycles,
                    end: (Number(pomo.start) + TimerService.pomodoroLapDuration) * 1000,
                    total: TimerService.pomodoroLapDuration, actions: [{ id: "pause", label: Translation.tr("Pause") }] }
                : { id: "pomodoro", kind: "timer", title: title, phase: phase, cycle: cycle, cycles: cycles,
                    paused: true, remaining: TimerService.pomodoroSecondsLeft,
                    total: TimerService.pomodoroLapDuration, actions: [{ id: "resume", label: Translation.tr("Resume") }] });
        }
        const sw = Persistent.states?.timer?.stopwatch;
        const swLaps = Array.from(TimerService.stopwatchLaps ?? []).map(t => Math.round(Number(t) * 10));
        if (sw?.running) {
            // `start` is in 10 ms units in a 32-bit int, which overflows; the shell's own
            // subtraction wraps back to the right elapsed time, and so does this.
            const elapsed10 = (((Math.floor(Date.now() / 10) - Number(sw.start)) % 4294967296) + 4294967296) % 4294967296;
            // Rounded to the second, so the topic does not change on every evaluation.
            const start = Math.round((Date.now() - elapsed10 * 10) / 1000) * 1000;
            items.push({ id: "stopwatch", kind: "stopwatch", title: Translation.tr("Stopwatch"), start: start, laps: swLaps,
                actions: [{ id: "pause", label: Translation.tr("Pause") }] });
        } else if (TimerService.stopwatchTime > 0 || swLaps.length > 0) {
            // Only read when paused, so the 10 ms stopwatch tick never triggers `_liveKey`.
            const elapsedMs = Math.max(0, Math.round(Number(TimerService.stopwatchTime) * 10));
            items.push({ id: "stopwatch", kind: "stopwatch", title: Translation.tr("Stopwatch"), paused: true,
                remaining: Math.round(elapsedMs / 1000), elapsedMs: elapsedMs, laps: swLaps,
                actions: [{ id: "resume", label: Translation.tr("Resume") }] });
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

    function _flushPcLive(): void {
        if (root.liveDev === "")
            return;
        livePush.stop();
        root._publish("pcLive", root._liveKey);
    }

    function _timers(): var {
        const presets = Array.from(Config.options?.time?.timer?.presets ?? [60, 300, 600, 900, 1800, 3600])
            .map(Number)
            .filter(n => Number.isFinite(n) && n > 0);
        return {
            t: "timers",
            presets: presets,
            pomodoro: {
                focus: Math.max(60, Number(TimerService.focusTime ?? 1500)),
                breakTime: Math.max(60, Number(TimerService.breakTime ?? 300)),
                longBreak: Math.max(60, Number(TimerService.longBreakTime ?? 900)),
                cycles: Math.max(1, Number(TimerService.cyclesBeforeLongBreak ?? 4))
            }
        };
    }

    /// Focus & timers command from the phone: pomodoro, countdowns, stopwatch, ringing alarm.
    function _runFocus(arg): string {
        const a = String(arg?.a ?? "");
        const op = String(arg?.op ?? arg?.action ?? "");
        switch (a) {
        case "pomodoro":
            if (op === "start" || op === "resume") {
                if (!TimerService.pomodoroRunning)
                    TimerService.togglePomodoro();
            } else if (op === "pause") {
                if (TimerService.pomodoroRunning)
                    TimerService.togglePomodoro();
            } else if (op === "toggle") {
                TimerService.togglePomodoro();
            } else if (op === "reset") {
                TimerService.resetPomodoro();
            } else if (op === "skip") {
                TimerService.skipPomodoroPhase();
            } else {
                return "bad_arg";
            }
            break;
        case "timerStart": {
            const seconds = Math.round(Number(arg?.seconds ?? 0));
            if (!Number.isFinite(seconds) || seconds <= 0 || seconds > 604800)
                return "bad_arg";
            TimerService.addCountdownSeconds(seconds, String(arg?.label ?? "").trim());
            break;
        }
        case "timer": {
            const id = String(arg?.id ?? "");
            if (!TimerService.findCountdown(id))
                return "not_found";
            if (op === "pause") {
                TimerService.pauseCountdown(id);
            } else if (op === "resume") {
                TimerService.resumeCountdown(id);
            } else if (op === "toggle") {
                TimerService.toggleCountdown(id);
            } else if (op === "reset") {
                TimerService.restartCountdown(id);
                TimerService.pauseCountdown(id);
            } else if (op === "extend") {
                const extra = Math.max(1, Math.round(Number(arg?.seconds ?? 60)));
                TimerService.extendCountdown(id, extra);
            } else if (op === "remove") {
                TimerService.removeCountdown(id);
            } else {
                return "bad_arg";
            }
            break;
        }
        case "stopwatch":
            if (op === "start" || op === "resume") {
                if (!TimerService.stopwatchRunning)
                    TimerService.stopwatchResume();
            } else if (op === "pause") {
                if (TimerService.stopwatchRunning)
                    TimerService.stopwatchPause();
            } else if (op === "toggle") {
                TimerService.toggleStopwatch();
            } else if (op === "reset") {
                TimerService.stopwatchReset();
            } else if (op === "lap") {
                if (TimerService.stopwatchRunning)
                    TimerService.stopwatchRecordLap();
            } else {
                return "bad_arg";
            }
            break;
        case "alarm":
            if (op === "stop" || op === "dismiss") {
                if (AlarmService.ringingAlarmIndex !== -1)
                    AlarmService.stopRinging();
            } else if (op === "snooze") {
                if (AlarmService.ringingAlarmIndex !== -1)
                    AlarmService.snooze(Number(arg?.minutes ?? 0) || undefined);
            } else {
                return "bad_arg";
            }
            break;
        default:
            return "bad_arg";
        }
        Qt.callLater(root._flushPcLive);
        return "";
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
        if (id === "stopwatch" && (action === "pause" || action === "resume")) {
            TimerService.toggleStopwatch();
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

    // ── Voice & meeting console ─────────────────────────────────────────
    // Summary (`voiceSummary`) rides on change while connected for the home card without
    // waking `Privacy` or transferring avatars. Full state (`voice`) and speaking ids
    // (`voiceSpeak`, coalesced to ~10/s) run only while a phone subscribes (`sub voice`).

    function _voiceSummary(): var {
        return {
            t: "voiceSummary",
            inCall: DiscordVoice.inVoice,
            channel: String(DiscordVoice.channel?.name ?? ""),
            mute: DiscordVoice.muted === true,
            deaf: DiscordVoice.deafened === true
        };
    }

    readonly property string _voiceSummaryKey: (root.phoneConnected && root.voiceEnabled)
        ? JSON.stringify(root._voiceSummary())
        : ""
    on_VoiceSummaryKeyChanged: root._publish("voiceSummary", root._voiceSummaryKey)

    property string _voiceDev: ""
    readonly property bool _voiceLive: root.voiceEnabled && root._voiceDev !== "" && root.connections[root._voiceDev] !== undefined
    property string _voiceSentKey: ""
    property string _voiceSpeakSentKey: ""
    property string _voicePrevChannelId: ""
    property var _voicePrevUsers: ({})
    property var _voiceAvatarFiles: ({})
    property var _voiceAvatarSent: ({})
    property var _voiceAvatarQueue: []

    function _voiceAvatarKey(u): string {
        const id = String(u?.id ?? "");
        const av = String(u?.avatar ?? "");
        if (id === "" || av === "")
            return "";
        return `${id}_${av}`.replace(/[^A-Za-z0-9_-]/g, "");
    }

    function _voicePrivacy(): var {
        const seen = {};
        const out = [];
        for (const it of (Privacy.activeItems ?? [])) {
            const kind = String(it?.kind ?? "");
            if (kind !== "camera" && kind !== "microphone" && kind !== "screen")
                continue;
            const app = String(it?.app ?? "");
            const k = `${kind}\0${app}`;
            if (seen[k])
                continue;
            seen[k] = true;
            out.push({ kind: kind, app: app });
        }
        return out;
    }

    function _voiceState(): var {
        const c = DiscordVoice.channel;
        const inCall = c !== null;
        const users = inCall ? (DiscordVoice.participants ?? []).map(u => ({
            id: String(u?.id ?? ""),
            name: String(u?.nick || u?.username || "Unknown"),
            avatar: root._voiceAvatarKey(u),
            mute: u?.mute === true,
            deaf: u?.deaf === true,
            volume: Math.round(Number(u?.volume ?? 100)),
            localMute: u?.localMute === true
        })) : [];
        return {
            t: "voice",
            channel: inCall ? { id: String(c.id ?? ""), name: String(c.name || "Voice channel") } : null,
            since: inCall ? Math.round(Number(DiscordVoice.channelSince ?? 0)) : 0,
            status: String(DiscordVoice.status ?? ""),
            backend: String(DiscordVoice.backend ?? ""),
            self: {
                id: String(DiscordVoice.selfId ?? ""),
                mute: DiscordVoice.muted === true,
                deaf: DiscordVoice.deafened === true,
                mode: String(DiscordVoice.inputMode ?? ""),
                pttShortcut: String(DiscordVoice.pttShortcut ?? ""),
                video: false,
                canMode: DiscordVoice.supportsInputMode === true,
                canUserVoice: DiscordVoice.supportsUserVoice === true,
                canVideo: DiscordVoice.supportsVideo === true
            },
            users: users,
            privacy: root._voicePrivacy()
        };
    }

    readonly property string _voiceKey: root._voiceLive ? JSON.stringify(root._voiceState()) : ""

    on_VoiceLiveChanged: {
        Privacy.externalWanted = root._voiceLive;
        if (!root._voiceLive) {
            voicePush.stop();
            voiceSpeakPush.stop();
            root._voiceSentKey = "";
            root._voiceSpeakSentKey = "";
            root._voicePrevChannelId = "";
            root._voicePrevUsers = ({});
            root._voiceAvatarSent = ({});
            root._voiceAvatarQueue = [];
            return;
        }
        root._sendVoiceNow();
        root._sendVoiceSpeakNow();
    }

    on_VoiceKeyChanged: {
        if (!root._voiceLive || root._voiceKey === "") {
            voicePush.stop();
            return;
        }
        if (!voicePush.running)
            voicePush.start();
    }

    Timer {
        id: voicePush
        interval: 40
        onTriggered: root._sendVoiceNow()
    }

    function _sendVoiceNow(): void {
        if (!root._voiceLive)
            return;
        const key = root._voiceKey;
        if (key === "" || key === root._voiceSentKey)
            return;
        root._voiceSentKey = key;
        const payload = JSON.parse(key);
        root._diffVoiceUsers(payload);
        root._syncVoiceAvatars(DiscordVoice.participants ?? []);
        root.sendTo(root._voiceDev, payload);
    }

    function _diffVoiceUsers(payload): void {
        const cid = String(payload?.channel?.id ?? "");
        const prevCid = root._voicePrevChannelId;
        const prev = root._voicePrevUsers;
        const next = {};
        for (const u of (payload?.users ?? [])) {
            if (u?.id)
                next[u.id] = u.name;
        }
        root._voicePrevChannelId = cid;
        root._voicePrevUsers = next;
        // Skip the initial roster snapshot on joining a channel.
        if (cid === "" || cid !== prevCid)
            return;
        const selfId = String(payload?.self?.id ?? "");
        for (const id of Object.keys(next)) {
            if (id !== selfId && prev[id] === undefined)
                root.sendTo(root._voiceDev, { t: "voiceEvent", kind: "join", id: id, name: next[id] });
        }
        for (const id of Object.keys(prev)) {
            if (id !== selfId && next[id] === undefined)
                root.sendTo(root._voiceDev, { t: "voiceEvent", kind: "leave", id: id, name: prev[id] });
        }
    }

    readonly property var _voiceSpeakingIds: {
        if (!root._voiceLive || !DiscordVoice.inVoice)
            return [];
        const ids = [];
        for (const u of (DiscordVoice.participants ?? [])) {
            if (u?.speaking === true && u?.id)
                ids.push(String(u.id));
        }
        ids.sort();
        return ids;
    }
    readonly property string _voiceSpeakKey: root._voiceLive ? JSON.stringify(root._voiceSpeakingIds) : ""
    on_VoiceSpeakKeyChanged: {
        if (!root._voiceLive || root._voiceSpeakKey === "") {
            root._voiceSpeakSentKey = "";
            voiceSpeakPush.stop();
            return;
        }
        if (!voiceSpeakPush.running)
            voiceSpeakPush.start();
    }
    Timer {
        id: voiceSpeakPush
        interval: 100
        onTriggered: root._sendVoiceSpeakNow()
    }
    function _sendVoiceSpeakNow(): void {
        if (!root._voiceLive)
            return;
        const key = root._voiceSpeakKey;
        if (key === "" || key === root._voiceSpeakSentKey)
            return;
        root._voiceSpeakSentKey = key;
        root.sendTo(root._voiceDev, { t: "voiceSpeak", ids: JSON.parse(key) });
    }

    function _syncVoiceAvatars(users): void {
        if (!root._voiceLive)
            return;
        for (const u of users) {
            const id = String(u?.id ?? "");
            const av = String(u?.avatar ?? "");
            const key = root._voiceAvatarKey(u);
            if (key === "" || root._phoneHas(root._voiceDev, "voiceAvatar", key) || root._voiceAvatarSent[key])
                continue;
            const cached = root._voiceAvatarFiles[key];
            if (cached) {
                root._voiceAvatarSent[key] = true;
                root.send({ op: "sendFile", dev: root._voiceDev, id: 750000 + root._fileSerial++, path: cached, name: key, purpose: "voiceAvatar" });
                continue;
            }
            if (!root._voiceAvatarQueue.some(q => q.key === key) && voiceAvatarFetch.pending?.key !== key)
                root._voiceAvatarQueue.push({ key: key, url: `https://cdn.discordapp.com/avatars/${id}/${av}.png?size=128` });
        }
        root._nextVoiceAvatar();
    }

    function _nextVoiceAvatar(): void {
        if (voiceAvatarFetch.running || root._voiceAvatarQueue.length === 0)
            return;
        const next = root._voiceAvatarQueue.shift();
        const dest = `${root.voiceAvatarCacheDir}/${next.key}.png`;
        voiceAvatarFetch.pending = { key: next.key, dest: dest };
        voiceAvatarFetch.command = [
            "sh", "-c",
            'mkdir -p -m 700 -- "$1" && { [ -s "$2" ] || { curl -fsSL --max-time 8 -o "$2.part" -- "$3" && mv -f -- "$2.part" "$2"; }; }',
            "sh", root.voiceAvatarCacheDir, dest, next.url
        ];
        voiceAvatarFetch.running = true;
    }

    Process {
        id: voiceAvatarFetch
        property var pending: null
        onExited: exitCode => {
            const p = voiceAvatarFetch.pending;
            voiceAvatarFetch.pending = null;
            if (exitCode === 0 && p) {
                root._voiceAvatarFiles[p.key] = p.dest;
                if (root._voiceLive && !root._phoneHas(root._voiceDev, "voiceAvatar", p.key) && !root._voiceAvatarSent[p.key]) {
                    root._voiceAvatarSent[p.key] = true;
                    root.send({ op: "sendFile", dev: root._voiceDev, id: 750000 + root._fileSerial++, path: p.dest, name: p.key, purpose: "voiceAvatar" });
                }
            }
            Qt.callLater(root._nextVoiceAvatar);
        }
    }

    function _runVoice(arg): string {
        const a = String(arg?.a ?? "");
        if (a === "connect") {
            DiscordVoice.connect();
            return "";
        }
        if (a === "authorize") {
            if (DiscordVoice.status !== "auth_required")
                return "unavailable";
            DiscordVoice.authorize();
            return "";
        }
        switch (a) {
        case "mute": {
            if (!DiscordVoice.inVoice)
                return "unavailable";
            const target = typeof arg?.on === "boolean" ? arg.on : !DiscordVoice.muted;
            DiscordVoice.setMuted(target);
            return "";
        }
        case "deaf": {
            if (!DiscordVoice.inVoice)
                return "unavailable";
            const target = typeof arg?.on === "boolean" ? arg.on : !DiscordVoice.deafened;
            DiscordVoice.setDeafened(target);
            return "";
        }
        case "mode": {
            if (!DiscordVoice.inVoice)
                return "unavailable";
            if (!DiscordVoice.supportsInputMode)
                return "unsupported";
            const mode = String(arg?.mode ?? "");
            if (mode === "PUSH_TO_TALK" || mode === "VOICE_ACTIVITY")
                DiscordVoice.setInputMode(mode);
            else if (mode === "")
                DiscordVoice.togglePushToTalk();
            else
                return "bad_arg";
            return "";
        }
        case "userVolume": {
            if (!DiscordVoice.inVoice)
                return "unavailable";
            if (!DiscordVoice.supportsUserVoice)
                return "unsupported";
            const uid = String(arg?.id ?? "");
            const vol = Number(arg?.vol);
            if (uid === "" || uid === DiscordVoice.selfId || !Number.isFinite(vol))
                return "bad_arg";
            DiscordVoice.setUserVolume(uid, Math.max(0, Math.min(200, Math.round(vol))));
            return "";
        }
        case "userMute": {
            if (!DiscordVoice.inVoice)
                return "unavailable";
            if (!DiscordVoice.supportsUserVoice)
                return "unsupported";
            const uid = String(arg?.id ?? "");
            if (uid === "" || uid === DiscordVoice.selfId || typeof arg?.mute !== "boolean")
                return "bad_arg";
            DiscordVoice.setUserLocalMute(uid, arg.mute);
            return "";
        }
        case "video":
            // Official Discord RPC has no video toggle; Vesktop companion does not
            // expose a video feature yet (`canVideo` is false).
            return "unsupported";
        default:
            return "bad_arg";
        }
    }

    // ── The PC's media on the phone ─────────────────────────────────────
    // The shell's active player goes to the phone that asked (`pcMedia` in its caps) as
    // one topic, pushed on change; the position only rides along, and is re-sent when it
    // jumps (a seek), since the phone runs the clock itself. The cover goes as a file,
    // once per image. The phone's own players (the helper's `iitools_` buses) are never
    // sent back to it.

    readonly property string pcMediaDev: root.pcMediaEnabled ? root._capDev("pcMedia") : ""
    readonly property string pcLyricsDev: root.pcMediaEnabled ? root._capDev("pcLyrics") : ""

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

    function _pcTrackId(player): string {
        if (!player)
            return "";
        const len = Math.round(MprisController.trackLengthOf(player) * 1000);
        return Qt.md5(`${player.dbusName ?? ""}\n${player.trackTitle ?? ""}\n${player.trackArtist ?? ""}\n${len}`);
    }

    function _pcMedia(): var {
        const p = root.pcMediaPlayer;
        if (!p)
            return { t: "pcMedia", on: false };
        return {
            t: "pcMedia",
            on: true,
            id: p.dbusName ?? "",
            track: root._pcTrackId(p),
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
            art: root._pcArt,
            // The page being played (browsers, YouTube…): lets the phone continue it.
            url: root.playerUrl(p)
        };
    }

    function playerUrl(player): string {
        const u = String(player?.metadata?.["xesam:url"] ?? "");
        return /^https?:\/\//i.test(u) ? u : "";
    }

    /// [url] at [seconds] where the site takes one: YouTube and Twitch videos `t=`, Vimeo `#t=`;
    /// anything else opens from the start.
    function urlAt(url, seconds): string {
        const s = Math.floor(Number(seconds) || 0);
        const m = /^https?:\/\/(?:www\.|m\.)?([^\/?#]+)(\/[^?#]*)?/i.exec(url);
        if (!m || s < 3)
            return url;
        const host = m[1].toLowerCase();
        const path = m[2] ?? "";
        const hash = url.indexOf("#");
        const frag = hash >= 0 ? url.slice(hash) : "";
        const base = hash >= 0 ? url.slice(0, hash) : url;
        const withParam = value => {
            const clean = base.replace(/([?&])(t|start)=[^&]*&?/g, "$1").replace(/[?&]$/, "");
            return `${clean}${clean.includes("?") ? "&" : "?"}t=${value}${frag}`;
        };
        if (host === "youtube.com" || host === "music.youtube.com" || host === "youtu.be")
            return withParam(`${s}s`);
        if (host.endsWith("twitch.tv") && path.startsWith("/videos/"))
            return withParam(`${Math.floor(s / 3600)}h${Math.floor(s % 3600 / 60)}m${s % 60}s`);
        if (host === "vimeo.com" || host === "player.vimeo.com")
            return `${base}#t=${s}s`;
        return url;
    }

    /// Media handoff, phone to PC: the page the phone plays (its app gave a web URL) opens
    /// in the browser at the same point, and the phone's player is paused. False when the
    /// player has no page.
    function continueOnPc(player): bool {
        const url = root.playerUrl(player);
        if (url === "")
            return false;
        Quickshell.execDetached(["xdg-open", root.urlAt(url, MprisController.trackPositionOf(player))]);
        if (player.isPlaying)
            player.pause();
        return true;
    }

    /// The linked PC media hands off to: the most recently connected one.
    readonly property string handoffPc: {
        if (!root.pcLinkEnabled)
            return "";
        let best = "";
        for (const [fp, c] of Object.entries(root.pcConnections))
            if (best === "" || c.since > root.pcConnections[best].since)
                best = fp;
        return best;
    }

    /// Media handoff, PC to PC: the page opens on [fp] at the same point, and pauses here.
    function continueOnLinkedPc(player, fp): bool {
        const url = root.playerUrl(player);
        if (url === "" || !root.pcConnections[fp])
            return false;
        root.send({ op: "pcSend", pc: fp, m: {
            t: "mediaHandoff", url: url, title: player.trackTitle ?? "", app: player.identity ?? "",
            position: Math.round(MprisController.trackPositionOf(player) * 1000)
        } });
        if (player.isPlaying)
            player.pause();
        return true;
    }

    function _receiveMediaHandoff(fp, m): void {
        const url = String(m.url ?? "");
        if (!/^https?:\/\//.test(url) || !root.pcMediaEnabled)
            return;
        Quickshell.execDetached(["xdg-open", root.urlAt(url, Number(m.position ?? 0) / 1000)]);
        Notifications.publishInternalNotification({
            appName: "ii tools",
            appIcon: "multimedia-player",
            summary: Translation.tr("Continuing from %1").arg(root._pcName(fp)),
            body: String(m.title ?? "")
        });
    }

    // Locking the PC while a web page plays offers the phone to continue it at the same
    // point (a notification there: a background app cannot open a page by itself).
    readonly property string handoffDev: (root.pcMediaEnabled && (root.opts?.handoff?.onLock ?? true)) ? root._capDev("handoff") : ""
    Connections {
        target: root.handoffDev !== "" ? GlobalStates : null
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked)
                return;
            const p = root.pcMediaPlayer;
            const url = root.playerUrl(p);
            if (!p || !p.isPlaying || url === "")
                return;
            root.sendTo(root.handoffDev, {
                t: "handoff",
                url: url,
                title: p.trackTitle ?? "",
                artist: p.trackArtist ?? "",
                app: p.identity ?? "",
                position: Math.round(MprisController.trackPositionOf(p) * 1000)
            });
        }
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
        if (root._phoneHas(root.pcMediaDev, "pcMediaArt", root._pcArt))
            return;
        root.send({ op: "sendFile", dev: root.pcMediaDev, id: 700000 + root._fileSerial++, path: root._pcArtPath,
            name: root._pcArt, purpose: "pcMediaArt" });
    }

    // ── The PC's lyrics on the phone ────────────────────────────────────
    // Sent to the phone that asked (`pcLyrics` in its caps) only while it watches
    // (`cmd pcLyrics {a: "watch", on: true|false}`). Holds LyricsService open via a
    // set of watching devices (cleared when the phone leaves or the link drops) and pushes
    // once per track or lyrics change (150 ms coalesced). LyricsService is only initialised;
    // `mediaModeOpenCount` is not touched (it also arms the shell's recolour from the cover).

    /// dev id -> 1 while that phone watches
    property var _pcLyricsWatchers: ({})
    property bool _pcLyricsClaimed: false
    property bool _pcLyricsForce: false
    readonly property bool _pcLyricsWatching: root.pcMediaEnabled
        && root.pcLyricsDev !== ""
        && (root._pcLyricsWatchers[root.pcLyricsDev] ?? 0) > 0

    function _syncPcLyricsClaim(): void {
        const watching = Object.keys(root._pcLyricsWatchers).length > 0;
        root._pcLyricsClaimed = watching;
        if (watching && !LyricsService.isInitialized)
            LyricsService.initiliazeLyrics();
    }

    function _releasePcLyricsDev(dev): void {
        if (!root._pcLyricsWatchers[dev])
            return;
        const next = Object.assign({}, root._pcLyricsWatchers);
        delete next[dev];
        root._pcLyricsWatchers = next;
        root._syncPcLyricsClaim();
    }

    function _clearPcLyricsWatchers(): void {
        if (Object.keys(root._pcLyricsWatchers).length === 0 && !root._pcLyricsClaimed)
            return;
        root._pcLyricsWatchers = ({});
        root._syncPcLyricsClaim();
    }

    function _pcLyricsSourcePlain(): string {
        if (LyricsService.usingLocalLyrics)
            return "local";
        const provider = LyricsService.lyricsProvider;
        if (provider === "betterlyrics")
            return "BetterLyrics";
        if (provider === "lrclib")
            return "LRCLib";
        if (provider === "lrcmux")
            return "lrcmux";
        if (provider === "netease")
            return "NetEase";
        if (provider === "ytmusic")
            return "YT Music";
        if (provider === "genius")
            return "Genius";
        const states = LyricsService.providerStates ?? [];
        const has = key => states.some(s => s.key === key && s.found);
        if (has("betterlyrics"))
            return "BetterLyrics";
        if (has("lrclib"))
            return "LRCLib";
        if (has("ytmusic"))
            return "YT Music";
        if (has("genius"))
            return "Genius";
        return "";
    }

    function _pcLyrics(): var {
        const p = root.pcMediaPlayer;
        const track = root._pcTrackId(p);
        const offset = Math.round(Config.options?.background?.mediaMode?.lyricsOffsetMs ?? 0);
        if (!p || LyricsService.activePlayer !== p) {
            return {
                t: "pcLyrics",
                track: track,
                state: "none",
                source: "",
                offset: offset
            };
        }

        if (LyricsService.hasSyncedLines) {
            const out = [];
            for (const line of (LyricsService.syncedLines ?? [])) {
                const ms = Math.max(0, Math.round(Number(line?.time ?? 0) * 1000));
                const entry = { ms: ms, text: String(line?.text ?? "").trim() };
                if (line?.endTime !== undefined && isFinite(line.endTime) && line.endTime > (line?.time ?? 0))
                    entry.end = Math.round(Number(line.endTime) * 1000);
                if (Array.isArray(line?.words) && line.words.length > 0) {
                    const words = [];
                    for (const w of line.words) {
                        const b = w?.begin !== undefined ? w.begin : (w?.startTime ?? 0);
                        const e = w?.end !== undefined ? w.end : (w?.endTime ?? b);
                        const wMs = Math.max(0, Math.round(Number(b) * 1000));
                        const wEnd = Math.max(wMs, Math.round(Number(e) * 1000));
                        // The word keeps its trailing space: the phone just joins them.
                        words.push({ ms: wMs, end: wEnd, text: String(w?.text ?? "") + String(w?.trailingSpace ?? "") });
                    }
                    if (words.length > 0)
                        entry.words = words;
                }
                out.push(entry);
            }
            out.sort((a, b) => a.ms - b.ms);
            while (out.length > 0 && out[out.length - 1].text === "")
                out.pop();
            if (out.length > 0) {
                const source = LyricsService.usingCustomLyrics ? "custom"
                    : LyricsService.usingLocalLyrics ? "local"
                    : (LyricsService.syncedSourceName ?? "");
                return {
                    t: "pcLyrics",
                    track: track,
                    state: "synced",
                    source: source,
                    offset: offset,
                    lines: out
                };
            }
        }

        if (LyricsService.hasPlainLyrics) {
            return {
                t: "pcLyrics",
                track: track,
                state: "plain",
                source: root._pcLyricsSourcePlain(),
                offset: offset,
                plain: String(LyricsService.plainLyrics ?? "").trim()
            };
        }

        if (LyricsService.instrumental) {
            return {
                t: "pcLyrics",
                track: track,
                state: "instrumental",
                source: "LRCLib",
                offset: offset
            };
        }

        if (LyricsService.searching) {
            return {
                t: "pcLyrics",
                track: track,
                state: "searching",
                source: "",
                offset: offset
            };
        }

        return {
            t: "pcLyrics",
            track: track,
            state: "none",
            source: "",
            offset: offset
        };
    }

    readonly property string _pcLyricsKey: root._pcLyricsWatching ? JSON.stringify(root._pcLyrics()) : ""

    onPcLyricsDevChanged: {
        root._sentKeys["pcLyrics"] = "";
        if (root._pcLyricsKey !== "" && !pcLyricsPush.running)
            pcLyricsPush.start();
    }
    on_PcLyricsKeyChanged: {
        if (root._pcLyricsKey === "") {
            pcLyricsPush.stop();
            root._pcLyricsForce = false;
            root._sentKeys["pcLyrics"] = "";
        } else if (!pcLyricsPush.running) {
            pcLyricsPush.start();
        }
    }
    Timer {
        id: pcLyricsPush
        interval: 150
        onTriggered: {
            const key = root._pcLyricsKey;
            if (key === "" || (!root._pcLyricsForce && key === (root._sentKeys["pcLyrics"] ?? "")))
                return;
            root._pcLyricsForce = false;
            root._sentKeys["pcLyrics"] = key;
            root.sendTo(root.pcLyricsDev, JSON.parse(key));
        }
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
    on_LookNameChanged: {
        root._makeLook();
        root._makeWallSync();
    }

    function _makeLook(): void {
        if (root.lookDev === "" || root._lookName === "" || root._lookName === root._lookSent || lookProc.running)
            return;
        // The phone kept this one from an earlier connection: only the topic.
        if (root._phoneHas(root.lookDev, "look", root._lookName)) {
            root._lookSent = root._lookName;
            root.sendTo(root.lookDev, { t: "look", wall: root._lookName });
            return;
        }
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

    // ── The PC's wallpaper as the phone's ────────────────────────────────
    // For a phone that opted in (`wallSync`): the desktop wallpaper as a JPEG of at most
    // 3840 px (the phone cuts its portrait crop from it), made once per image, sent when
    // the wallpaper changes or the phone connects. Nothing runs for a phone that does not ask.

    readonly property bool wallSyncEnabled: root.opts?.wallSync?.enable ?? true
    readonly property string wallSyncDev: root.wallSyncEnabled ? root._capDev("wallSync") : ""
    readonly property string wallSyncDir: `${root.stateDir}/wallsync`
    property string _wallSyncSent: ""
    onWallSyncDevChanged: {
        root._wallSyncSent = "";
        root._makeWallSync();
    }

    /// The shell command that makes (once) the wallpaper's 3840 px JPEG at `out`.
    function _wallJpegCommand(out): var {
        const video = /\.(mp4|mkv|webm|mov|avi|gif)$/i.test(root._wallPath);
        const make = video
            ? `ffmpeg -y -loglevel error -i "$2" -frames:v 1 -vf "scale='min(3840,iw)':-2" -q:v 3 "$3"`
            : `magick "$2[0]" -resize '3840x3840>' -quality 88 "$3"`;
        return ["sh", "-c",
            `mkdir -p -m 700 -- "$1" && find "$1" -type f ! -name "$4.jpg" -delete && { [ -s "$3" ] || ${make}; }`,
            "sh", root.wallSyncDir, root._wallPath, out, root._lookName];
    }

    function _makeWallSync(): void {
        if (root.wallSyncDev === "" || root._lookName === "" || root._lookName === root._wallSyncSent || wallSyncProc.running)
            return;
        if (root._phoneHas(root.wallSyncDev, "wallSync", root._lookName)) {
            root._wallSyncSent = root._lookName;
            return;
        }
        const out = `${root.wallSyncDir}/${root._lookName}.jpg`;
        wallSyncProc.out = out;
        wallSyncProc.name = root._lookName;
        wallSyncProc.command = root._wallJpegCommand(out);
        wallSyncProc.running = true;
    }

    /// The phone's "Save the PC's wallpaper" button: the same JPEG, uncropped, as a file the
    /// phone files in its gallery (`purpose: "wallSave"`). Any phone may ask while sharing is on.
    function _sendWallSave(dev): void {
        if (!root.wallSyncEnabled || root._wallPath === "" || wallSaveProc.running) {
            root.sendTo(dev, { t: "err", id: 0, code: "unavailable" });
            return;
        }
        const out = `${root.wallSyncDir}/${root._lookName}.jpg`;
        wallSaveProc.dev = dev;
        wallSaveProc.out = out;
        wallSaveProc.name = root._lookName;
        wallSaveProc.command = root._wallJpegCommand(out);
        wallSaveProc.running = true;
    }
    Process {
        id: wallSaveProc
        property string dev
        property string out
        property string name
        onExited: code => {
            if (code === 0 && root.connections[wallSaveProc.dev] !== undefined) {
                root.send({ op: "sendFile", dev: wallSaveProc.dev, id: 660000 + root._fileSerial++, path: wallSaveProc.out,
                    name: wallSaveProc.name, purpose: "wallSave" });
            } else {
                root.sendTo(wallSaveProc.dev, { t: "err", id: 0, code: "unavailable" });
            }
        }
    }
    Process {
        id: wallSyncProc
        property string out
        property string name
        onExited: code => {
            if (code === 0 && root.wallSyncDev !== "") {
                root._wallSyncSent = wallSyncProc.name;
                root.send({ op: "sendFile", dev: root.wallSyncDev, id: 650000 + root._fileSerial++, path: wallSyncProc.out,
                    name: wallSyncProc.name, purpose: "wallSync" });
            }
            // The wallpaper changed again while this one was being made.
            if (root._lookName !== wallSyncProc.name)
                root._makeWallSync();
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

    /// Media Mode on the phone: {a: "watch", on: bool}.
    function _runPcLyrics(dev, arg): string {
        if (String(arg?.a ?? "") !== "watch" || typeof arg?.on !== "boolean")
            return "bad_arg";
        const next = Object.assign({}, root._pcLyricsWatchers);
        if (arg.on) {
            next[dev] = 1;
            root._pcLyricsWatchers = next;
            root._syncPcLyricsClaim();
            if (dev === root.pcLyricsDev) {
                root._pcLyricsForce = true;
                pcLyricsPush.restart();
            }
        } else {
            delete next[dev];
            root._pcLyricsWatchers = next;
            root._syncPcLyricsClaim();
        }
        return "";
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
    readonly property string _drawKey: {
        if (root._drawDev === "")
            return "";
        if (!root.drawEnabled)
            return JSON.stringify({ t: "draw", err: "disabled" });
        if (!LiveDraw.enabled)
            return JSON.stringify({ t: "draw", err: "liveDraw" });
        return JSON.stringify(root._drawState());
    }
    on_DrawKeyChanged: {
        if (root._drawKey === "")
            root._sentKeys["draw"] = "";
        else if (root._drawDev !== "" && root._drawKey !== (root._sentKeys["draw"] ?? "")) {
            root._sentKeys["draw"] = root._drawKey;
            root.sendTo(root._drawDev, JSON.parse(root._drawKey));
        }
    }

    function _draw(dev, m): void {
        const a = String(m.a ?? "");
        if (a === "stop") {
            // Leaving the pad puts live draw away too (the ink stays, as with the tray).
            if (root._drawDev === dev) {
                root._drawDev = "";
                LiveDraw.close();
            }
            return;
        }
        if (!root.drawEnabled)
            return root.sendTo(dev, { t: "draw", err: "disabled" });
        if (a === "enableLiveDraw") {
            if (Config.ready) {
                if (PanelFamily.isTablet) {
                    if (Config.options?.tablet?.liveDraw)
                        Config.options.tablet.liveDraw.enable = true;
                } else if (Config.options?.liveDraw) {
                    Config.options.liveDraw.enable = true;
                }
            }
            if (!LiveDraw.enabled) {
                root._drawDev = dev;
                return root.sendTo(dev, { t: "draw", err: "liveDraw" });
            }
            root._drawDev = dev;
            LiveDraw.open();
            const st = root._drawState();
            root._sentKeys["draw"] = JSON.stringify(st);
            root.sendTo(dev, st);
            return;
        }
        if (!LiveDraw.enabled) {
            if (a === "start")
                root._drawDev = dev;
            return root.sendTo(dev, { t: "draw", err: "liveDraw" });
        }
        if (m.s !== undefined) {
            if (dev === root._drawDev && LiveDraw.trayOpen)
                LiveDraw.remoteStroke(String(m.s), Array.isArray(m.p) ? m.p : []);
            return;
        }
        switch (a) {
        case "start": {
            root._drawDev = dev;
            LiveDraw.open();
            const st = root._drawState();
            root._sentKeys["draw"] = JSON.stringify(st);
            root.sendTo(dev, st);
            return;
        }
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
            LiveDraw.command(a, null);
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

    function activeLauncherIconDir(): string {
        const dev = root.usageDev || root.launcherIconDev || String(root.peers[0]?.id ?? "");
        return dev !== "" ? root.launcherIconDir(dev) : "";
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
        iconMover.appIcon = Boolean(next.appIcon);
        iconMover.dest = `${next.dir}/${next.pkg}.png`;
        iconMover.command = next.appIcon
            ? ["sh", "-c", 'mkdir -p -m 700 -- "$1" && mv -f -- "$2" "$3"', "sh", next.dir, next.from, iconMover.dest]
            : ["sh", "-c", 'mkdir -p -- "$1" && mv -f -- "$2" "$3"', "sh", next.dir, next.from, iconMover.dest];
        iconMover.running = true;
    }
    Process {
        id: iconMover
        property string pkg: ""
        property bool appIcon: false
        property string dest: ""
        onExited: exitCode => {
            if (exitCode === 0) {
                if (iconMover.appIcon)
                    root.appIconReady(iconMover.pkg, iconMover.dest);
                else
                    root.launcherIconReady(iconMover.pkg, iconMover.dest);
            }
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
            // `power` with MangoHud's own reading when sysfs has none, as the HUD shows it
            cpu: Object.assign({ name: perfSampler.cpuModel }, perfSampler.cpu, { power: perfSampler.cpuPower }),
            ram: perfSampler.ram,
            gpu: Object.assign({ name: perfSampler.selectedGpu?.name ?? "" }, perfSampler.gpu, { power: perfSampler.gpuPower }),
            fps: perfSampler.fps,
            net: perfSampler.net,
            gamemode: perfSampler.gamemode !== null && (perfSampler.gamemode?.length ?? 0) > 0,
            battery: root._perfBattery(),
            game: root._perfGame(),
            hud: root._perfHud
        })
    }

    // The phone draws the game overlay's HUD (Settings › Game overlay › Performance), so it
    // gets the HUD's own choices: which rows, the style, the palette and the thresholds.
    readonly property var _perfHudKeys: ["showFps", "showFpsAverage", "showFpsLow1", "showFpsLow01",
        "showFrametime", "showFrametimeGraph", "showFpsCap", "showStutter", "showCpu", "showCpuUsage",
        "showCpuTemp", "showCpuClock", "showCpuPower", "showRam", "showSwap", "showGpu", "showGpuUsage",
        "showGpuTemp", "showGpuClock", "showGpuMemClock", "showGpuPower", "showGpuFan", "showVram",
        "showBattery", "showBatteryEnergy", "showBatteryPower", "showBatteryTime", "showNetwork",
        "showNetDown", "showNetUp", "showNetJitter", "showNetLoss", "showDetails", "showProcess",
        "showResolution", "showDriver", "showSessionTime", "showPowerProfile", "showGameMode", "showClock"]
    readonly property var _perfHud: {
        const c = Config.options.overlay.perfMonitor;
        const show = {};
        for (const key of root._perfHudKeys)
            show[key] = c[key] === true;
        return {
            style: c.style, palette: c.palette, title: c.title, uppercase: c.uppercase,
            icons: c.showIcons, fpsTarget: c.fpsTarget, colorFps: c.colorCodeFps,
            hotTemp: c.hotTemp, window: c.statsWindow, cpuName: c.cpuName, gpuName: c.gpuName,
            show: show
        };
    }
    function _perfBattery() {
        if (!Battery.available)
            return null;
        return {
            percent: Battery.percentage, charging: Battery.isCharging,
            energy: Battery.device?.energy ?? 0, rate: Battery.energyRate,
            timeLeft: Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty
        };
    }
    // The focused game names itself better than MangoHud's process ("java" for Minecraft).
    function _perfGame() {
        const w = GameDetector.focusedWindow;
        let name = GameDetector.gameFocused && w ? String(w.title || w["class"] || "").trim() : "";
        if (name.length > 32)
            name = name.slice(0, 31) + "…";
        let resolution = "";
        if (w?.size && (perfSampler.fpsActive || GameDetector.gameFocused)) {
            const scale = HyprlandData.monitors.find(m => m.id === w.monitor)?.scale ?? 1;
            resolution = `${Math.round(w.size[0] * scale)}×${Math.round(w.size[1] * scale)}`;
        }
        const info = perfSampler.selectedGpu;
        const profile = PowerProfiles.profile === PowerProfile.PowerSaver ? "saver"
            : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced";
        return {
            name: name, resolution: resolution, running: GameDetector.gameRunning,
            driverVersion: info?.driverVersion ? String(info.driverVersion) : "",
            driver: info?.driver ?? "", profile: profile
        };
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
            peripherals: conn && Array.isArray(st?.peripherals) ? st.peripherals : [],
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

    /// The phone that announced it can be controlled from routines (Modes' phoneControl).
    readonly property string phoneControlDev: root._capDev("ctl")

    /// dev id → true while "find my phone" is ringing.
    property var ringing: ({})

    function isRinging(deviceId): bool {
        const id = root._peerOf(deviceId);
        return id !== "" && root.ringing[id] === true;
    }

    function _setRinging(dev, on): void {
        const id = root._peerOf(dev);
        if (!id)
            return;
        const next = Object.assign({}, root.ringing);
        if (on)
            next[id] = true;
        else
            delete next[id];
        root.ringing = next;
        if (on)
            ringFallbackTimer.restart();
        else if (Object.keys(next).length === 0)
            ringFallbackTimer.stop();
    }

    // Fallback for older phone apps that do not emit `{"t":"act","ringing":false}`.
    Timer {
        id: ringFallbackTimer
        interval: 60000
        repeat: false
        onTriggered: root.ringing = ({})
    }

    /// Something the phone does by itself: `{ kind, ...fields }` (see ModeActions.phoneControlRequest).
    function phoneControl(req): bool {
        if (root.phoneControlDev === "")
            return false;
        root.sendTo(root.phoneControlDev, Object.assign({ t: "act", a: "ctl" }, req));
        if (req?.kind === "ring")
            root._setRinging(root.phoneControlDev, true);
        return true;
    }

    /// An action for the phone (`act`): ring, ping, url, text. False when it is away.
    function phoneAct(deviceId, action, fields): bool {
        const dev = root._peerOf(deviceId);
        if (root.connections[dev] === undefined)
            return false;
        root.sendTo(dev, Object.assign({ t: "act", a: action }, fields ?? {}));
        if (action === "ring")
            root._setRinging(dev, fields?.on !== false);
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

    /// dev → whether the phone takes the PC's screenshots (its `shots` cap, off by
    /// default in the app). Kept across disconnects, unlike `phoneCaps`, so a shot
    /// still waits in the outbox for a phone that wants it, and nothing is converted
    /// or queued for one that does not.
    property var _shotsReceivers: ({})
    readonly property bool phoneTakesShots: Object.keys(root._shotsReceivers)
        .some(id => root._shotsReceivers[id] && root.peers.some(p => p.id === id))

    readonly property bool _watchShots: root.enabled && root.shotsEnabled && root.shotsAutoToPhone && root.hasPeers && root.phoneTakesShots
    /// The screenshot preview's "Save to phone gallery": shown when sending is by hand.
    readonly property bool canSaveShotToPhone: root.enabled && root.shotsEnabled && !root.shotsAutoToPhone && root.hasPeers && root.phoneTakesShots
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
            root._iconMoves.push({ pkg: pkg, dir: root.iconDir, from: path, appIcon: true });
            root._moveIcons();
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

    // ── Deck profiles: the focused window's class ───────────────────────
    // The deck switches to the folder bound to the focused app. The phone subscribes
    // (`sub focus`) only while its deck is on screen and has such a folder (or is
    // editing one: `open` lists the windows' classes to pick from), so nothing is
    // computed or sent otherwise. A window change is held 120 ms: moving focus passes
    // through "no window" and the deck must not bounce to its default page and back.

    property string _focusDev: ""
    readonly property bool _focusLive: root.deckEnabled && root._focusDev !== "" && root.connections[root._focusDev] !== undefined
    property string _focusClass: ""
    property var _focusOpen: []

    function _focusRead(): void {
        const open = [];
        for (const t of ToplevelManager.toplevels.values) {
            const c = String(t.appId ?? "");
            if (c !== "" && !open.includes(c))
                open.push(c);
        }
        open.sort();
        root._focusClass = String(ToplevelManager.activeToplevel?.appId ?? "");
        root._focusOpen = open;
    }
    function _focusMsg(): var {
        return { t: "focus", class: root._focusClass, open: root._focusOpen };
    }
    readonly property string _focusKey: root._focusLive ? JSON.stringify(root._focusMsg()) : ""
    on_FocusKeyChanged: {
        if (root._focusKey !== "")
            root.sendTo(root._focusDev, JSON.parse(root._focusKey));
    }
    Timer {
        id: focusDebounce
        interval: 120
        onTriggered: root._focusRead()
    }
    Connections {
        target: root._focusLive ? ToplevelManager : null
        function onActiveToplevelChanged() {
            focusDebounce.restart();
        }
    }
    Connections {
        target: root._focusLive ? ToplevelManager.toplevels : null
        function onValuesChanged() {
            focusDebounce.restart();
        }
    }
    on_FocusLiveChanged: {
        if (root._focusLive)
            root._focusRead();
    }

    // ── Display: brightness and night light ─────────────────────────────
    // For the remote screen (`sub display`): the focused monitor's brightness and the
    // night light, pushed whole on change (a slider dragged on the PC coalesces to ~16/s).
    // Computed only while a phone has the screen open.

    property string _displayDev: ""
    readonly property bool _displayLive: root.remoteEnabled && root._displayDev !== "" && root.connections[root._displayDev] !== undefined

    function _display(): var {
        const monitor = Brightness.getTargetMonitor();
        return {
            t: "display",
            monitor: monitor?.screen?.name ?? "",
            brightness: monitor?.ready ? monitor.brightness : -1,
            floor: monitor?.floorBrightness ?? 0.01,
            night: Hyprsunset.temperatureActive,
            temp: Hyprsunset.colorTemperature,
            auto: Hyprsunset.automatic
        };
    }
    readonly property string _displayKey: root._displayLive ? JSON.stringify(root._display()) : ""
    on_DisplayKeyChanged: {
        if (root._displayKey === "")
            root._sentKeys["display"] = "";
        else if (!displayPush.running)
            displayPush.start();
    }
    Timer {
        id: displayPush
        interval: 60
        onTriggered: {
            const key = root._displayKey;
            if (key === "" || key === (root._sentKeys["display"] ?? ""))
                return;
            root._sentKeys["display"] = key;
            root.sendTo(root._displayDev, JSON.parse(key));
        }
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
        if (root.pcLiveEnabled && (root.phoneCaps[dev] ?? []).includes("pcLive"))
            root.sendTo(dev, root._pcLive());
        if (root.voiceEnabled)
            root.sendTo(dev, root._voiceSummary());
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
        if (GlobalStates.screenLocked && root._remoteArgActions.includes(action))
            return "locked";
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
        case "brightness": {
            const monitor = Brightness.getTargetMonitor();
            const v = Number(arg);
            if (!monitor?.ready || !isFinite(v))
                return "unavailable";
            monitor.setBrightness(Math.max(monitor.floorBrightness, Math.min(1, v)));
            return "";
        }
        case "night":
            Hyprsunset.toggleTemperature(arg === true);
            return "";
        case "modeAction":
            return root._runModeAction(arg);
        case "nightTemp": {
            const k = Math.round(Number(arg));
            if (!isFinite(k))
                return "bad_arg";
            Config.options.light.night.colorTemperature = Math.max(1200, Math.min(6500, k));
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

    // ── The Modes & Routines actions, for the phone ─────────────────────
    // The phone's routines can do what a mode can: the catalog below is the Modes
    // registry itself (so a new action there shows up on the phone with no change
    // here), minus what would hand the phone a shell: running commands, launching
    // or closing apps, raw Hyprland dispatches, files. Values have the shape the
    // Modes editor stores, so `{ type, value }` is a mode's action verbatim.
    readonly property var _modeActionDeny: ["shell", "launch", "closeApps", "hyprland", "file", "wallpaper",
        "wait", "pingPhone", "playSound", "appVolume", "audioOutput", "audioInput", "easyEffects", "earbudsAnc",
        "barDock", "keyboardBacklight", "notify", "suspend", "dnsOverTls", "phoneControl"]
    readonly property var _modeActionForms: ({
        "switch": "switch", segmented: "choice", dropdown: "choice", none: "none", brightness: "percent",
        level: "percent", temperature: "kelvin", volume: "volume", workspace: "workspace", text: "text",
        mode: "choice", routine: "choice"
    })

    function _modeActionChoices(e): var {
        if (e.editor === "mode")
            return [{ v: "", l: Translation.tr("Turn off the active mode") }]
                .concat(Array.from(Modes.modes ?? []).map(m => ({ v: String(m.id), l: String(m.name ?? m.id) })));
        if (e.editor === "routine")
            return Array.from(Modes.routines ?? []).map(r => ({ v: String(r.id), l: String(r.name ?? r.id) }));
        return Array.from(e.choices ? e.choices() : []).map(c => ({
            v: String(c),
            l: e.choiceLabel ? Translation.tr(String(e.choiceLabel(c))) : String(c)
        }));
    }

    function _modeCatalog(): var {
        const cats = Modes.actions.categories;
        const list = [];
        for (const type of Modes.actions.types()) {
            const e = Modes.actions.get(type);
            const form = root._modeActionForms[e.editor];
            if (!form || root._modeActionDeny.includes(type))
                continue;
            if (!Modes.actions.isAvailable(type) && e.editor !== "mode" && e.editor !== "routine")
                continue;
            const entry = {
                id: type, label: Translation.tr(String(e.label)), icon: String(e.icon ?? ""),
                category: String(e.category ?? ""), categoryLabel: Translation.tr(String(cats[e.category]?.label ?? "")),
                form: form
            };
            if (form === "choice")
                entry.choices = root._modeActionChoices(e);
            list.push(entry);
        }
        return { t: "modeActions", list: list };
    }

    /// Runs one Modes action for the phone; "" when done, or why not.
    function _runModeAction(arg): string {
        const type = String(arg?.type ?? "");
        const e = Modes.actions.get(type);
        if (!e || root._modeActionDeny.includes(type) || !root._modeActionForms[e.editor])
            return "unknown_action";
        let value = arg?.value;
        // A mode or a routine travels as a bare id; the registry wants it wrapped.
        if (type === "mode")
            value = { action: value === "" || value === undefined ? "stop" : "start", id: String(value ?? "") };
        else if (type === "routine")
            value = { action: "run", id: String(value ?? "") };
        const result = Modes.applyActions("phone", [{ type: type, value: value }], null);
        if (result.failed.length > 0) {
            console.warn(`[IiLink] phone action ${type}: ${result.failed[0]}`);
            return /not available/.test(result.failed[0]) ? "unavailable" : "failed";
        }
        return "";
    }

    readonly property var _remoteArgActions: ["workspace", "mode", "preset", "brightness", "night", "nightTemp", "modeAction"]
    readonly property var _audioArgActions: ["volume", "mute", "default", "eePreset", "eeBypass"]

    Timer {
        id: lockAodTimer
        interval: 700
        onTriggered: {
            if (GlobalStates.screenLocked && (Config.options?.oledSaver?.enable ?? true))
                GlobalStates.oledSaverMonitors = Quickshell.screens.map(s => s.name);
        }
    }

    // ── Remote unlock ───────────────────────────────────────────────────
    // Delegates password verification to the active LockScreen's PamContext and
    // replies with ok or err (wrong_password / busy / unavailable / timeout).
    property var _pendingUnlock: null

    Timer {
        id: unlockTimeoutTimer
        interval: 10000
        onTriggered: {
            const req = root._pendingUnlock;
            root._pendingUnlock = null;
            console.warn("[IiLink] unlock timed out");
            if (req)
                root.sendTo(req.dev, { t: "err", id: req.id, code: "timeout" });
        }
    }

    Connections {
        target: GlobalStates
        function onRemoteUnlockFinished(ok, code) {
            unlockTimeoutTimer.stop();
            const req = root._pendingUnlock;
            root._pendingUnlock = null;
            if (!req)
                return;
            if (!ok)
                console.warn("[IiLink] unlock failed:", code);
            root.sendTo(req.dev, ok ? { t: "ok", id: req.id } : { t: "err", id: req.id, code: code || "wrong_password" });
        }
    }

    function _runUnlock(dev, id, arg): void {
        if (!root.remoteEnabled) {
            root.sendTo(dev, { t: "err", id: id, code: "disabled" });
            return;
        }
        if (!GlobalStates.screenLocked) {
            root.sendTo(dev, { t: "ok", id: id });
            return;
        }
        const ctx = GlobalStates.activeLockContext;
        if (!ctx) {
            console.warn("[IiLink] unlock: activeLockContext is null");
            root.sendTo(dev, { t: "err", id: id, code: "unavailable" });
            return;
        }
        if (root._pendingUnlock !== null) {
            root.sendTo(dev, { t: "err", id: id, code: "busy" });
            return;
        }
        if (typeof arg !== "string" || arg.length === 0) {
            console.warn("[IiLink] unlock: bad_arg, type =", typeof arg);
            root.sendTo(dev, { t: "err", id: id, code: "bad_arg" });
            return;
        }
        root._pendingUnlock = { dev: dev, id: id };
        unlockTimeoutTimer.restart();
        ctx.tryRemoteUnlock(arg);
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
        const d = String(dev);
        // "pc:<fp>" or "pc:*": the linked PCs (the clipboard decode queue serves both).
        if (d.startsWith("pc:")) {
            root.send({ op: "pcSend", pc: d.slice(3), m: message });
            return;
        }
        if (root._holdable(message)) {
            if (d === "*") {
                const ids = Object.keys(root.connections);
                if (ids.some(id => root._quietDevs[id])) {
                    for (const id of ids) {
                        if (root._quietDevs[id])
                            root._hold(id, message);
                        else
                            root.send({ op: "send", dev: id, m: message });
                    }
                    return;
                }
            } else if (root._quietDevs[d]) {
                root._hold(d, message);
                return;
            }
        }
        root.send({ op: "send", dev: d, m: message });
    }

    // ── Quiet phones ────────────────────────────────────────────────────
    // A phone whose screen is off (`{"t":"quiet","on":true}`) is not woken for what only
    // its screen shows: the latest of each such topic waits and goes out when it lights
    // up again. Calls, notifications, live activity, the PC media (the lock screen and AOD
    // show it), answers and actions still go at once.
    readonly property var _quietTopics: ["workspaces", "modes", "presets", "audio", "deck", "state", "clip", "look", "display", "focus", "voiceSummary"]
    /// dev id -> true while that phone's screen is off
    property var _quietDevs: ({})
    /// dev id -> { topic: latest message } held for it
    property var _held: ({})

    function _holdable(message): bool {
        // An answer to a request (`clipPull`) is never held: the phone is waiting for it.
        return root._quietTopics.includes(message?.t ?? "") && !(Number(message?.id ?? 0) > 0);
    }

    function _hold(dev, message): void {
        const held = root._held[dev] ?? {};
        delete held[message.t];
        held[message.t] = message;
        root._held[dev] = held;
    }

    function _setQuiet(dev, on): void {
        if (on) {
            root._quietDevs[dev] = true;
            return;
        }
        delete root._quietDevs[dev];
        const held = root._held[dev] ?? {};
        delete root._held[dev];
        for (const t of Object.keys(held))
            root.send({ op: "send", dev: dev, m: held[t] });
    }

    // ── Files a phone already has ───────────────────────────────────────
    // A phone lists in `caps.have` the images it keeps ({look, wallSync, pcMediaArt}: names),
    // so a reconnect does not send them again.
    /// dev id -> { kind: [names] }
    property var phoneHave: ({})

    function _phoneHas(dev, kind, name): bool {
        const list = root.phoneHave[dev]?.[kind];
        return Array.isArray(list) && list.includes(name);
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
            wake: root.wolEnabled ? root.wakeTargets : [],
            routes: root.routes,
            // The PCs this one is linked with, so the phone offers to link only the others.
            pcLinks: root.pcPeers.map(p => p.fp)
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
        // The phone, away or on Tailscale, asks this PC to wake another one on its LAN.
        case "wakeFor": {
            const targets = (Array.isArray(m.targets) ? m.targets : []).slice(0, 8)
                .filter(t => /^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$/.test(String(t?.mac ?? "")))
                .map(t => ({ mac: String(t.mac), broadcast: String(t.broadcast ?? "") }));
            if (targets.length > 0)
                root.send({ op: "wake", targets: targets });
            return;
        }
        // The phone introduces two PCs: this one opens a window, the other joins it.
        case "pcPairOpen":
            root._pcRequest(dev, m, { op: "pcPairOpen" });
            return;
        case "pcPairJoin":
            root._pcRequest(dev, m, { op: "pcPairJoin", fp: String(m.fp ?? ""), hosts: m.hosts ?? [], port: Number(m.port ?? 0), secret: String(m.secret ?? ""), name: String(m.name ?? "") });
            return;
        case "cmd": {
            const id = Number(m.id ?? 0);
            const action = String(m.a ?? "");
            let why;
            if (action === "unlock") {
                root._runUnlock(dev, id, m.arg);
                return;
            }
            if (action === "live")
                why = root.pcLiveEnabled ? root._runLive(m.arg) : "disabled";
            else if (action === "focus")
                why = root.focusEnabled ? root._runFocus(m.arg) : "disabled";
            else if (action === "voice")
                why = root.voiceEnabled ? root._runVoice(m.arg) : "disabled";
            else if (action === "pcMedia")
                why = root.pcMediaEnabled ? root._runPcMedia(m.arg) : "disabled";
            else if (action === "pcLyrics")
                why = root.pcMediaEnabled ? root._runPcLyrics(dev, m.arg) : "disabled";
            else if (action === "clip")
                why = !root.clipEnabled ? "disabled" : (GlobalStates.screenLocked ? "locked" : root._clipFromPhone(dev, m.arg));
            else if (action === "clipPull") {
                root._clipPull(dev, id, m.arg);
                return;
            } else if (action === "clipCopyPc")
                why = root._clipCopyPc(m.arg);
            else if (action === "share")
                why = !root.shareEnabled ? "disabled" : (GlobalStates.screenLocked ? "locked" : root._share(m.arg));
            else if (action === "deck")
                why = root.deckEnabled ? root._runDeck(String(m.arg ?? "")) : "disabled";
            else if (action === "power")
                why = !root.powerEnabled ? "disabled" : (GlobalStates.screenLocked ? "locked" : root._runPower(String(m.arg ?? "")));
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
        case "quiet":
            root._setQuiet(dev, m.on === true);
            return;
        case "sub":
            if (m.what === "perf")
                root._perfDev = m.on === true ? dev : (root._perfDev === dev ? "" : root._perfDev);
            else if (m.what === "display")
                root._displayDev = m.on === true ? dev : (root._displayDev === dev ? "" : root._displayDev);
            else if (m.what === "focus")
                root._focusDev = m.on === true ? dev : (root._focusDev === dev ? "" : root._focusDev);
            else if (m.what === "voice")
                root._voiceDev = (m.on === true && root.voiceEnabled) ? dev : (root._voiceDev === dev ? "" : root._voiceDev);
            else if (m.what === "clipHistory") {
                root._clipHistoryDev = (m.on === true && root.clipHistoryEnabled)
                    ? dev
                    : (root._clipHistoryDev === dev ? "" : root._clipHistoryDev);
                if (root._clipHistoryDev !== dev)
                    root._clipHistoryDirtyWhileLocked = false;
            }
            return;
        case "unsub":
            if (m.what === "perf" && root._perfDev === dev)
                root._perfDev = "";
            else if (m.what === "display" && root._displayDev === dev)
                root._displayDev = "";
            else if (m.what === "focus" && root._focusDev === dev)
                root._focusDev = "";
            else if (m.what === "voice" && root._voiceDev === dev)
                root._voiceDev = "";
            else if (m.what === "clipHistory" && root._clipHistoryDev === dev) {
                root._clipHistoryDev = "";
                root._clipHistoryDirtyWhileLocked = false;
            }
            return;
        case "dnd":
            if (dev === root.dndDev)
                root._phoneDndChanged(m.on === true);
            return;
        case "status":
            if (root.phoneDataEnabled)
                root._status(m);
            return;
        case "phonePerf":
            if (root.phoneDataEnabled && dev === root._phonePerfSubDev)
                root._phonePerfSample(dev, m);
            return;
        case "contacts":
            if (root.phoneDataEnabled && dev === root.dataDev)
                root._contacts(dev, m);
            return;
        case "calendar":
            if (dev === root.calendarDev)
                root._calendar(dev, m);
            return;
        case "calendarResult":
            root._calendarResult(m);
            return;
        case "files":
            root._filesReply(dev, m);
            return;
        case "draw":
            root._draw(dev, m);
            return;
        case "act":
            if (typeof m.ringing === "boolean")
                root._setRinging(dev, m.ringing);
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
        case "camera":
            IiCameraService.handleMessage(dev, m);
            return;
        case "mic":
            IiMicService.handleMessage(dev, m);
            return;
        case "phoneUsage":
            if (root.usageEnabled)
                root._savePhoneUsage(dev, m);
            return;
        case "vitals":
        case "vitalsRoute":
            if (dev === root.vitalsDev)
                VitalsService.handleMessage(m);
            return;
        case "caps": {
            // Before the caps: assigning them wakes the senders that read it.
            const have = Object.assign({}, root.phoneHave);
            have[dev] = (m.have && typeof m.have === "object") ? m.have : {};
            root.phoneHave = have;
            const prevCaps = root.phoneCaps[dev] ?? [];
            const next = Object.assign({}, root.phoneCaps);
            next[dev] = Array.isArray(m.caps) ? m.caps.map(String) : [];
            root.phoneCaps = next;
            if (root.pcLiveEnabled && !prevCaps.includes("pcLive") && next[dev].includes("pcLive") && dev !== root.liveDev)
                root.sendTo(dev, root._pcLive());
            const takes = next[dev].includes("shots");
            if (Boolean(root._shotsReceivers[dev]) !== takes) {
                const shots = Object.assign({}, root._shotsReceivers);
                shots[dev] = takes;
                root._shotsReceivers = shots;
            }
            if (next[dev].includes("mirrorRadio")) {
                if (root.mirrorActive)
                    root.sendTo(dev, { t: "mirror", on: true });
            }
            if (!next[dev].includes("pcLyrics"))
                root._releasePcLyricsDev(dev);
            // A phone that (re)announces itself gets a fresh chance, and an open Stats
            // panel asks it again.
            if (root._phonePerfSilent[dev]) {
                const silent = Object.assign({}, root._phonePerfSilent);
                delete silent[dev];
                root._phonePerfSilent = silent;
            }
            if (dev === root._phonePerfSubDev && next[dev].includes("phonePerf"))
                root.sendTo(dev, { t: "sub", what: "phonePerf", on: true });
            return;
        }
        case "notifs":
            if (dev === root.notifDev)
                root.linkNotifications = Array.isArray(m.list) ? m.list.map(root._notif).filter(n => n.key !== "") : [];
            return;
        case "notifApps":
            if (root.notifsEnabled && (root.notifDev === "" || dev === root.notifDev)) {
                root.notifApps = root._normalizeNotifApps(m.list);
                notifAppsFile.setText(JSON.stringify(root.notifApps));
            }
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
            else if (m.what === "appIcons" && root.deckEnabled)
                root._requestAppIcons(dev, m.icons);
            else if (m.what === "clipHistory")
                root._sendClipHistory(dev, m.offset, m.limit);
            else if (m.what === "clipThumbs")
                root._requestClipThumbs(dev, m.ids);
            else if (m.what === "wallpaper")
                root._sendWallSave(dev);
            else if (m.what === "modeActions" && root.remoteEnabled)
                root.sendTo(dev, root._modeCatalog());
            else if (m.what === "timers" && root.focusEnabled)
                root.sendTo(dev, root._timers());
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
            root.send({ op: "config", media: root.mediaEnabled, touchpad: root.touchpadEnabled, present: root.presentEnabled, pcLink: root.pcLinkEnabled });
            root.discovery = ev.discovery === true;
            if (root.pairingRequested && !root.pairing)
                root.send({ op: "pair" });
            break;
        case "peers":
            root._setPeers(JSON.stringify(ev.list ?? []));
            break;
        case "pcPeers":
        case "pcConnected":
        case "pcDisconnected":
        case "pcPairOpen":
        case "pcPaired":
        case "pcPairFailed":
        case "pcMsg":
        case "pcFileProgress":
        case "pcFileSent":
        case "pcPairClosed":
        case "pcFound":
            root._handlePcEvent(ev);
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
            root._syncTailscale();
            if (root.remoteEnabled)
                root._listPresets();
            break;
        }
        case "disconnected": {
            const next = Object.assign({}, root.connections);
            delete next[ev.dev];
            root.connections = next;
            delete root._quietDevs[ev.dev];
            delete root._held[ev.dev];
            const had = Object.assign({}, root.phoneHave);
            delete had[ev.dev];
            root.phoneHave = had;
            const caps = Object.assign({}, root.phoneCaps);
            delete caps[ev.dev];
            root.phoneCaps = caps;
            if (root._perfDev === ev.dev)
                root._perfDev = "";
            if (root._voiceDev === ev.dev)
                root._voiceDev = "";
            if (root._clipHistoryDev === ev.dev) {
                root._clipHistoryDev = "";
                root._clipHistoryDirtyWhileLocked = false;
            }
            root._unmountFiles(ev.dev, false);
            if (root._drawDev === ev.dev) {
                root._drawDev = "";
                LiveDraw.close();
            }
            if (root._presentDev === ev.dev)
                root._presentDev = "";
            root._releasePcLyricsDev(String(ev.dev));
            root._setRinging(String(ev.dev), false);
            IiCameraService.handleDisconnect(String(ev.dev));
            IiMicService.handleDisconnect(String(ev.dev));
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
        case "screenRate":
        case "screenAudio":
        case "screenLive":
        case "screenEnd":
            PhoneScreenService.handleEvent(ev);
            break;
        case "camera":
        case "cameraLive":
        case "cameraEnd":
            IiCameraService.handleEvent(ev);
            break;
        case "mic":
        case "micLive":
        case "micEnd":
            IiMicService.handleEvent(ev);
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
        /// Sends files to a linked PC (`pc`: a fingerprint, a name, or "" for the only one
        /// connected). Paths separated by newlines, for a file manager's "Send to" action.
        function sendToPc(paths: string, pc: string): string {
            const ids = Object.keys(root.pcConnections);
            const want = String(pc ?? "").trim().toLowerCase();
            const fp = want === "" ? (ids.length === 1 ? ids[0] : "")
                : ids.find(id => id.startsWith(want) || String(root.pcConnections[id]?.name ?? "").toLowerCase() === want) ?? "";
            if (fp === "")
                return ids.length === 0 ? "no_pc" : "which_pc";
            const list = String(paths ?? "").split("\n").map(p => p.trim()).filter(p => p !== "");
            root.sendToPc(fp, list);
            return `sent ${list.length} to ${root._pcName(fp)}`;
        }
        /// Continues what plays here (a web page) on the linked PC most recently connected.
        function continueOnPc(): string {
            const p = root.pcMediaPlayer ?? MprisController.activePlayer;
            return p && root.continueOnLinkedPc(p, root.handoffPc) ? "ok" : "unavailable";
        }
        /// A notification on the connected phone, for scripts: "ok" once handed to the link (no
        /// receipt comes back), "no_phone" when none is connected.
        function ping(text: string): string {
            const dev = Object.keys(root.connections)[0] ?? "";
            return dev !== "" && root.phoneAct(dev, "ping", { text: text }) ? "ok" : "no_phone";
        }
        /// The linked PCs: name, fingerprint and whether each is connected.
        function pcs(): string {
            return JSON.stringify(root.pcPeers.map(p => ({ name: p.name, fp: p.fp, connected: root.pcConnections[p.fp] !== undefined })));
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
        /// Watches the phone's load from the terminal ("on" / "off"), as the Stats panel does.
        function phonePerf(on: string): string {
            root.watchPhonePerf(on === "on");
            return root.phonePerfDev === "" ? "no phone reports its load" : `watching ${root.phonePerfDev}: ${root._phonePerfWatchers}`;
        }

        function focusState(): string {
            return JSON.stringify({
                caps: root.capabilities,
                timers: root._timers(),
                pcLive: root._pcLive()
            });
        }

        function focusRun(argJson: string): string {
            let arg = {};
            try {
                arg = JSON.parse(argJson || "{}");
            } catch (e) {
                return "bad_json";
            }
            const why = root.focusEnabled ? root._runFocus(arg) : "disabled";
            return why === "" ? "ok" : why;
        }

        function voiceState(): string {
            return JSON.stringify({
                caps: root.capabilities,
                summary: root._voiceSummary(),
                voice: root._voiceState(),
                speaking: root._voiceSpeakingIds,
                subscribed: root._voiceDev
            });
        }

        function voiceRun(argJson: string): string {
            let arg = {};
            try {
                arg = JSON.parse(argJson || "{}");
            } catch (e) {
                return "bad_json";
            }
            const why = root.voiceEnabled ? root._runVoice(arg) : "disabled";
            return why === "" ? "ok" : why;
        }

        function status(): string {
            const held = {};
            for (const d of Object.keys(root._held))
                held[d] = Object.keys(root._held[d]);
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
                phonePerf: { dev: root.phonePerfDev, watchers: root._phonePerfWatchers, last: root.phonePerf },
                // Phones with the screen off, and the topics held for each until it comes on.
                quiet: Object.keys(root._quietDevs),
                held: held,
                have: root.phoneHave,
                error: root.lastError
            });
        }
    }

    // ── Process ─────────────────────────────────────────────────────────
    readonly property bool wanted: root.enabled && (root.hasPeers || (root.pcLinkEnabled && root.hasPcPeers) || root.pairingRequested || root._linger)

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

    // Held until the old helper exits: cleared on the next tick, the exit came after it and
    // read as a crash (code 15), so every restart also waited out a crash backoff.
    property bool _restartPending: false

    function restart(): void {
        if (!helper.running)
            return;
        root._restartPending = true;
        root._restarting = true;
        // A helper that never exits still comes back.
        backoff.interval = 5000;
        backoff.restart();
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
        onTriggered: {
            root._restartPending = false;
            root._restarting = false;
        }
    }

    Process {
        id: helper
        running: root.wanted && root.probed && root.binaryPresent && !root._restarting
        stdinEnabled: true
        command: [root.binaryPath, "--state-dir", root.stateDir, "--port", String(root.port)]

        onStarted: root._runningStamp = root._stampRead ? root._stamp : "pending"

        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("[IiLink]", data)
        }

        onExited: (code, status) => {
            root.running = false;
            root.connections = ({});
            root.ringing = ({});
            ringFallbackTimer.stop();
            root.pairing = null;
            root._clearPcLyricsWatchers();
            if (root._restartPending) {
                root._restartPending = false;
                backoff.stop();
                root._restarting = false;
                return;
            }
            if (root._restarting || !root.wanted)
                return;
            if (code !== 0) {
                console.warn(`[IiLink] helper exited with code ${code}`);
                // A binary that is gone (deleted, an update without it) shows the Build card
                // instead of being restarted forever.
                root.checkBinary();
                root._failures += 1;
                root._restarting = true;
                backoff.interval = Math.min(300000, 2000 * Math.pow(2, Math.min(7, root._failures)));
                backoff.restart();
            }
        }
    }
}
