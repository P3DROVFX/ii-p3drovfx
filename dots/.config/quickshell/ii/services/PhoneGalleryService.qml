pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Phone gallery over ii link: lists albums and media items for the active
 * ii tools phone, caches thumbnails and full images under
 * $XDG_CACHE_HOME/quickshell/phone_gallery/<dev>/, and drives the viewer.
 *
 * Nothing is requested while the gallery page is closed.
 */
Singleton {
    id: root

    // ── Active device & capabilities ────────────────────────────────────
    readonly property bool cardVisible: KdeConnectService.activeIsIi && IiLinkService.galleryEnabled
    readonly property string activeDev: {
        if (!root.cardVisible)
            return "";
        const active = String(KdeConnectService.activeDeviceId ?? "");
        if (active.startsWith("iitools:"))
            return active.slice(8);
        return String(IiLinkService.peers[0]?.id ?? "");
    }
    readonly property bool connected: root.activeDev !== ""
        && IiLinkService.connections[root.activeDev] !== undefined
    readonly property bool hasGalleryCap: root.connected
        && (IiLinkService.phoneCaps[root.activeDev] ?? []).includes("gallery")
    readonly property bool hasFilesCap: root.connected
        && IiLinkService.filesEnabled
        && (IiLinkService.phoneCaps[root.activeDev] ?? []).includes("files")
    readonly property string setupState: {
        if (!root.connected)
            return "offline";
        if (!root.hasGalleryCap || root.error === "disabled" || root.error === "permission")
            return "setup";
        return "ready";
    }
    readonly property bool available: root.setupState === "ready"

    readonly property string _xdgCache: Quickshell.env("XDG_CACHE_HOME")
        || `${FileUtils.trimFileProtocol(Directories.home)}/.cache`
    readonly property string _cacheBase: root.activeDev !== ""
        ? `${root._xdgCache}/quickshell/phone_gallery/${root.activeDev}`
        : ""
    readonly property string thumbDir: root._cacheBase !== "" ? `${root._cacheBase}/thumbs` : ""
    readonly property string fullDir: root._cacheBase !== "" ? `${root._cacheBase}/full` : ""
    readonly property string saveDir: `${FileUtils.trimFileProtocol(Directories.pictures)}/Phone`

    // ── Gallery state ───────────────────────────────────────────────────
    property var items: []
    property var albums: []
    property string album: ""
    property bool loading: false
    property bool more: false
    property string error: ""
    property bool isOpen: false
    property bool loadedOnce: false
    property int thumbRevision: 0

    readonly property int totalCount: {
        if (root.albums.length > 0) {
            let sum = 0;
            for (const a of root.albums)
                sum += Number(a?.count ?? 0);
            return sum;
        }
        if (root.loadedOnce && root.album === "" && !root.more)
            return root.items.length;
        return -1;
    }

    // ── Viewer & transfer state ─────────────────────────────────────────
    property bool viewerOpen: false
    property int viewerIndex: -1
    readonly property var viewerItem: (root.viewerOpen && root.viewerIndex >= 0 && root.viewerIndex < root.items.length)
        ? root.items[root.viewerIndex]
        : null

    /// item id (string) → local path under fullDir.
    property var fullPaths: ({})
    /// item id (string) → { received, size }.
    property var fullProgress: ({})
    /// item id (string) → error code.
    property var fullErrors: ({})
    /// item id (string) → saved path in ~/Pictures/Phone.
    property var savedPaths: ({})
    property bool videoMounting: false

    // ── Internal state ──────────────────────────────────────────────────
    property string _lastDev: ""
    property var _thumbsOnDisk: new Set()
    property bool _thumbsScanned: false
    property int _listReq: 0
    property bool _listAppend: false
    property var _pendingThumbIds: []

    Timer {
        id: listTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            if (!root.loading)
                return;
            root.loading = false;
            root.error = "timeout";
        }
    }

    onActiveDevChanged: {
        if (root.activeDev === root._lastDev)
            return;
        root._lastDev = root.activeDev;
        root._resetState();
        if (root.isOpen && root.setupState === "ready")
            root._startSession();
    }

    onHasGalleryCapChanged: {
        if (!root.hasGalleryCap) {
            root._clearSession();
            return;
        }
        if (root.error === "disabled" || root.error === "permission")
            root.error = "";
        if (root.isOpen && !root.loadedOnce && !root.loading && root.setupState === "ready")
            root._startSession();
    }

    onSetupStateChanged: {
        if (root.setupState !== "ready") {
            listTimeout.stop();
            thumbDebounce.stop();
            root.loading = false;
            root._pendingThumbIds = [];
            root.viewerOpen = false;
            root.viewerIndex = -1;
            return;
        }
        if (root.isOpen && !root.loadedOnce && !root.loading)
            root._startSession();
    }

    Connections {
        target: IiLinkService
        function onPhoneCapsChanged(): void {
            // Re-try if the phone re-advertised "gallery" after an earlier disabled/permission error.
            if (root.hasGalleryCap && (root.error === "disabled" || root.error === "permission")) {
                root.error = "";
                if (root.isOpen && !root.loadedOnce && !root.loading)
                    root._startSession();
            }
        }
    }

    function _clearSession(): void {
        thumbDebounce.stop();
        listTimeout.stop();
        root.items = [];
        root.albums = [];
        root.album = "";
        root.loading = false;
        root.more = false;
        root.error = "";
        root.loadedOnce = false;
        root._thumbsScanned = false;
        root._pendingThumbIds = [];
        root.viewerOpen = false;
        root.viewerIndex = -1;
    }

    function _resetState(): void {
        root._clearSession();
        root._thumbsOnDisk = new Set();
        root.thumbRevision += 1;
        root.fullPaths = ({});
        root.fullProgress = ({});
        root.fullErrors = ({});
        root.savedPaths = ({});
        root.videoMounting = false;
    }

    // ── Lifecycle & queries ─────────────────────────────────────────────
    function open(): void {
        root.isOpen = true;
        if (root.hasGalleryCap && (root.error === "disabled" || root.error === "permission"))
            root.error = "";
        if (root.setupState === "ready")
            root._startSession();
    }

    function close(): void {
        root.isOpen = false;
        thumbDebounce.stop();
        listTimeout.stop();
        root.loading = false;
        root._pendingThumbIds = [];
        root.viewerOpen = false;
        root.viewerIndex = -1;
    }

    function _startSession(): void {
        if (root.setupState !== "ready")
            return;
        root.error = "";
        root._thumbsScanned = false;
        thumbScanProc.running = false;
        thumbScanProc.running = true;
        fullPruneProc.running = false;
        fullPruneProc.running = true;
        root._requestAlbums();
        root._requestList(false);
    }

    function refresh(): void {
        if (root.setupState !== "ready")
            return;
        root.error = "";
        root._requestAlbums();
        root._requestList(false);
    }

    function setAlbum(bucketId): void {
        if (root.setupState !== "ready")
            return;
        const next = String(bucketId ?? "");
        if (next === root.album && root.loadedOnce && root.error === "")
            return;
        root.album = next;
        root.items = [];
        root.more = false;
        root.error = "";
        root.viewerOpen = false;
        root.viewerIndex = -1;
        root._requestList(false);
    }

    function loadMore(): void {
        if (root.setupState !== "ready" || root.loading || !root.more || root.items.length === 0)
            return;
        root._requestList(true);
    }

    function _requestAlbums(): void {
        if (root.setupState !== "ready")
            return;
        IiLinkService.sendTo(root.activeDev, { t: "gallery", a: "albums" });
    }

    function _requestList(append: bool): void {
        if (root.setupState !== "ready")
            return;
        const req = ++root._listReq;
        root._listAppend = append;
        root.error = "";
        root.loading = true;
        listTimeout.restart();
        let before = null;
        if (append && root.items.length > 0) {
            const last = root.items[root.items.length - 1];
            before = { taken: Number(last.taken ?? 0), id: Number(last.id ?? 0) };
        }
        IiLinkService.sendTo(root.activeDev, {
            t: "gallery",
            a: "list",
            req: req,
            album: root.album,
            before: before,
            n: 200
        });
    }

    // ── Thumbnails ──────────────────────────────────────────────────────
    function hasThumb(id): bool {
        return root._thumbsOnDisk.has(String(id));
    }

    function thumbPath(id): string {
        const sid = String(id ?? "");
        if (root.thumbDir === "" || sid === "" || !root._thumbsOnDisk.has(sid))
            return "";
        return `file://${root.thumbDir}/${sid}.jpg`;
    }

    function wantThumbs(ids): void {
        root._pendingThumbIds = Array.from(ids ?? []).map(x => String(x)).filter(s => s !== "");
        if (!root.isOpen || root.setupState !== "ready" || root._pendingThumbIds.length === 0)
            return;
        thumbDebounce.restart();
    }

    Timer {
        id: thumbDebounce
        interval: 60
        repeat: false
        onTriggered: root._flushThumbRequest()
    }

    function _flushThumbRequest(): void {
        if (!root.isOpen || root.setupState !== "ready" || !root._thumbsScanned)
            return;
        const seen = new Set();
        const wanted = [];
        for (const sid of root._pendingThumbIds) {
            if (seen.has(sid) || root._thumbsOnDisk.has(sid))
                continue;
            seen.add(sid);
            const num = Number(sid);
            if (!Number.isFinite(num) || num < 0)
                continue;
            wanted.push(num);
            if (wanted.length >= 128)
                break;
        }
        if (wanted.length === 0)
            return;
        IiLinkService.sendTo(root.activeDev, { t: "gallery", a: "thumbs", ids: wanted });
    }

    // Seed on-disk thumbnail set with a single `ls` process.
    Process {
        id: thumbScanProc
        command: ["sh", "-c", 'ls -1 -- "$1" 2>/dev/null || true', "sh", root.thumbDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const set = new Set();
                for (const line of this.text.split("\n")) {
                    const m = /^([0-9]{1,19})\.jpg$/.exec(line.trim());
                    if (m)
                        set.add(m[1]);
                }
                root._thumbsOnDisk = set;
                root._thumbsScanned = true;
                root.thumbRevision += 1;
                if (root._pendingThumbIds.length > 0)
                    thumbDebounce.restart();
            }
        }
    }

    // Prune full cache to 512 MiB oldest-first and seed fullPaths from surviving files.
    Process {
        id: fullPruneProc
        command: ["sh", "-c", `
            d="$1"
            [ -d "$d" ] || exit 0
            find "$d" -maxdepth 1 -type f -printf '%T@ %s %p\\n' | sort -n | awk '
                { sizes[NR]=$2; paths[NR]=$3; total+=$2 }
                END {
                    limit = 536870912
                    for (i = 1; i <= NR && total > limit; i++) {
                        print paths[i]
                        total -= sizes[i]
                    }
                }' | xargs -r -d '\\n' rm -f --
            ls -1 -- "$d" 2>/dev/null || true`, "sh", root.fullDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = root.fullDir;
                if (dir === "")
                    return;
                const next = {};
                for (const line of this.text.split("\n")) {
                    const f = line.trim();
                    const m = /^([0-9]{1,19})\.(jpg|jpeg|png|webp|gif)$/.exec(f);
                    if (m)
                        next[m[1]] = `${dir}/${f}`;
                }
                root.fullPaths = next;
            }
        }
    }

    // ── Full images & viewer ────────────────────────────────────────────
    function fullPathFor(id): string {
        return root.fullPaths[String(id ?? "")] ?? "";
    }

    function get(id): void {
        const sid = String(id ?? "");
        if (root.setupState !== "ready" || sid === "")
            return;
        if (root.fullPaths[sid])
            return;
        const item = root.items.find(it => String(it.id) === sid) ?? null;
        if (item?.kind === "video")
            return;
        if (root.fullProgress[sid])
            return;

        const nextErr = Object.assign({}, root.fullErrors);
        delete nextErr[sid];
        root.fullErrors = nextErr;

        const nextProg = Object.assign({}, root.fullProgress);
        nextProg[sid] = { received: 0, size: Number(item?.size ?? 0) };
        root.fullProgress = nextProg;

        IiLinkService.sendTo(root.activeDev, { t: "gallery", a: "get", id: Number(sid) });
    }

    function _prepareViewerIndex(index: int): void {
        if (index >= root.items.length - 5 && root.more && !root.loading)
            root.loadMore();
        const item = root.items[index];
        if (item && item.kind !== "video")
            root.get(item.id);
    }

    function openViewer(index: int): void {
        if (index < 0 || index >= root.items.length)
            return;
        root.viewerIndex = index;
        root.viewerOpen = true;
        root._prepareViewerIndex(index);
    }

    function closeViewer(): void {
        root.viewerOpen = false;
        root.viewerIndex = -1;
    }

    function stepViewer(delta: int): void {
        const next = root.viewerIndex + delta;
        if (next < 0 || next >= root.items.length)
            return;
        root.viewerIndex = next;
        root._prepareViewerIndex(next);
    }

    // ── Formatting & Viewer actions (Save / Copy / Open / Show in folder) ─
    function formatDuration(ms): string {
        const total = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        const ss = s < 10 ? "0" + s : String(s);
        if (h > 0) {
            const mm = m < 10 ? "0" + m : String(m);
            return h + ":" + mm + ":" + ss;
        }
        return m + ":" + ss;
    }

    function _mimeForFile(path: string, fallbackMime: string): string {
        const lower = path.toLowerCase();
        if (lower.endsWith(".png"))
            return "image/png";
        if (lower.endsWith(".webp"))
            return "image/webp";
        if (lower.endsWith(".gif"))
            return "image/gif";
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg"))
            return "image/jpeg";
        return fallbackMime || "image/jpeg";
    }

    function _uriForPath(path: string): string {
        return "file://" + encodeURI(String(path || "")).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    // Resolve an item's SFTP-mounted path on the phone, mounting if needed.
    function _withPhonePath(item, callback): void {
        if (!item || !item.path || !root.hasFilesCap)
            return;
        const dev = root.activeDev;
        const existing = IiLinkService.filesMounts[dev];
        if (existing) {
            const rel = String(item.path);
            callback(`${existing.dir}${rel.startsWith("/") ? "" : "/"}${rel}`);
            return;
        }
        root.videoMounting = true;
        IiLinkService.mountPhoneFiles(dev, (mountDir, _openPath, err) => {
            root.videoMounting = false;
            if (mountDir === "" || err !== "") {
                KdeConnectService.dispatchActionFeedback(
                    err !== "" ? err : Translation.tr("Couldn't access phone files"),
                    false
                );
                return;
            }
            const rel = String(item.path);
            callback(`${mountDir}${rel.startsWith("/") ? "" : "/"}${rel}`);
        });
    }

    function copyItem(item): void {
        if (!item)
            return;
        if (item.kind === "video") {
            root._withPhonePath(item, mountedPath => {
                Cliphist.markInternalCopy();
                Quickshell.execDetached(["wl-copy", "--type", "text/uri-list", `${root._uriForPath(mountedPath)}\r\n`]);
                KdeConnectService.dispatchActionFeedback(Translation.tr("Copied to clipboard"), true);
            });
            return;
        }
        const path = root.fullPathFor(item.id);
        if (path === "")
            return;
        const mime = root._mimeForFile(path, String(item.mime ?? ""));
        Cliphist.markInternalCopy();
        Quickshell.execDetached(["sh", "-c", 'wl-copy --type "$1" < "$2"', "sh", mime, path]);
        KdeConnectService.dispatchActionFeedback(Translation.tr("Copied to clipboard"), true);
    }

    function openItem(item): void {
        if (!item)
            return;
        if (item.kind === "video") {
            root._withPhonePath(item, mountedPath => {
                Quickshell.execDetached(["gio", "open", mountedPath]);
            });
            return;
        }
        const path = root.fullPathFor(item.id);
        if (path === "")
            return;
        Quickshell.execDetached(["gio", "open", path]);
    }

    function showInFolder(item): void {
        if (!item)
            return;
        const sid = String(item.id);
        const saved = root.savedPaths[sid] ?? "";
        if (saved !== "") {
            Quickshell.execDetached(["gio", "open", FileUtils.parentDirectory(saved)]);
            return;
        }
        if (root.hasFilesCap && String(item.path ?? "") !== "") {
            root._withPhonePath(item, mountedPath => {
                Quickshell.execDetached(["gio", "open", FileUtils.parentDirectory(mountedPath)]);
            });
        }
    }

    property var _saveQueue: []
    function saveItem(item): void {
        if (!item)
            return;
        const sid = String(item.id);
        const name = String(item.name || `${sid}.jpg`).replace(/[\/\0]/g, "_");
        if (item.kind === "video") {
            root._withPhonePath(item, mountedPath => {
                root._saveQueue.push({ id: sid, src: mountedPath, name: name });
                root._runNextSave();
            });
            return;
        }
        const path = root.fullPathFor(sid);
        if (path === "")
            return;
        root._saveQueue.push({ id: sid, src: path, name: name });
        root._runNextSave();
    }

    function _runNextSave(): void {
        if (saveProc.running || root._saveQueue.length === 0)
            return;
        const next = root._saveQueue.shift();
        saveProc.itemId = next.id;
        // Same non-overwriting name (1).ext scheme as IiLinkService's share flow.
        saveProc.command = ["sh", "-c", `
            dir="$1"; src="$2"; name="$3"
            mkdir -p -- "$dir" || exit 1
            case "$name" in ?*.*) base="\${name%.*}"; ext=".\${name##*.}" ;; *) base="$name"; ext="" ;; esac
            dest="$dir/$name"; n=1
            while [ -e "$dest" ]; do dest="$dir/$base ($n)$ext"; n=$((n + 1)); done
            cp -f -- "$src" "$dest" && chmod 644 -- "$dest" && printf %s "$dest"`,
            "sh", root.saveDir, next.src, next.name];
        saveProc.running = true;
    }

    Process {
        id: saveProc
        property string itemId: ""
        stdout: StdioCollector { id: saveDest }
        onExited: code => {
            const dest = String(saveDest.text ?? "").trim();
            const sid = saveProc.itemId;
            if (code === 0 && dest !== "") {
                const nextSaved = Object.assign({}, root.savedPaths);
                nextSaved[sid] = dest;
                root.savedPaths = nextSaved;

                const nid = Notifications.publishInternalNotification({
                    appName: "ii tools",
                    appIcon: "image-x-generic",
                    summary: Translation.tr("Saved to Pictures/Phone"),
                    body: dest.split("/").pop(),
                    actions: [
                        { identifier: "__qs_open_file", text: Translation.tr("Open"), icon: "open_in_new", iconOnly: true },
                        { identifier: "__qs_open_folder", text: Translation.tr("Show in folder"), icon: "folder_open" }
                    ]
                });
                const notif = nid ? Notifications.findTrackedNotification(nid) : null;
                if (notif)
                    notif._qsFilePath = dest;
                KdeConnectService.dispatchActionFeedback(Translation.tr("Saved to Pictures/Phone"), true);
            } else {
                KdeConnectService.dispatchActionFeedback(Translation.tr("Couldn't save file"), false);
            }
            Qt.callLater(root._runNextSave);
        }
    }

    // ── Wire message & event handlers (called by IiLinkService) ─────────
    function handleMessage(dev: string, m: var): void {
        if (dev !== root.activeDev || !IiLinkService.galleryEnabled)
            return;

        if (m.err !== undefined && m.a === undefined) {
            listTimeout.stop();
            root.error = String(m.err);
            root.loading = false;
            return;
        }

        switch (String(m.a ?? "")) {
        case "albums":
            if (m.err !== undefined) {
                listTimeout.stop();
                root.error = String(m.err);
                root.loading = false;
                return;
            }
            root.albums = Array.isArray(m.list) ? m.list : [];
            return;

        case "list": {
            if (Number(m.req ?? 0) !== root._listReq || String(m.album ?? "") !== root.album)
                return;
            listTimeout.stop();
            root.loading = false;
            if (m.err !== undefined) {
                root.error = String(m.err);
                return;
            }
            root.error = "";
            const pageItems = Array.isArray(m.items) ? m.items : [];
            if (root._listAppend) {
                const existing = new Set(root.items.map(it => String(it.id)));
                const appended = pageItems.filter(it => !existing.has(String(it.id)));
                root.items = root.items.concat(appended);
            } else {
                root.items = pageItems;
            }
            root.more = m.more === true;
            root.loadedOnce = true;
            return;
        }

        case "get": {
            if (m.err !== undefined) {
                const sid = String(m.id ?? "");
                if (sid === "")
                    return;
                const nextProg = Object.assign({}, root.fullProgress);
                delete nextProg[sid];
                root.fullProgress = nextProg;

                const nextErr = Object.assign({}, root.fullErrors);
                nextErr[sid] = String(m.err);
                root.fullErrors = nextErr;
            }
            return;
        }

        case "new": {
            if (!root.isOpen && !root.viewerOpen)
                return;
            const incoming = (Array.isArray(m.items) ? m.items : [])
                .filter(it => root.album === "" || String(it?.album ?? "") === root.album);
            if (incoming.length === 0)
                return;
            const existing = new Set(root.items.map(it => String(it.id)));
            const fresh = incoming.filter(it => !existing.has(String(it.id)));
            if (fresh.length === 0)
                return;
            root.items = fresh.concat(root.items);
            if (root.viewerOpen && root.viewerIndex >= 0)
                root.viewerIndex += fresh.length;
            if (root.isOpen)
                root._requestAlbums();
            return;
        }

        case "gone": {
            const ids = Array.isArray(m.ids) ? m.ids.map(x => String(x)) : [];
            if (ids.length === 0)
                return;
            const goneSet = new Set(ids);
            const currentViewedId = root.viewerItem ? String(root.viewerItem.id) : "";
            root.items = root.items.filter(it => !goneSet.has(String(it.id)));

            let thumbChanged = false;
            for (const sid of ids) {
                if (root._thumbsOnDisk.delete(sid))
                    thumbChanged = true;
            }
            if (thumbChanged)
                root.thumbRevision += 1;

            const nextFull = Object.assign({}, root.fullPaths);
            let fullChanged = false;
            for (const sid of ids) {
                if (sid in nextFull) {
                    delete nextFull[sid];
                    fullChanged = true;
                }
            }
            if (fullChanged)
                root.fullPaths = nextFull;

            if (root.viewerOpen) {
                if (root.items.length === 0) {
                    root.viewerOpen = false;
                    root.viewerIndex = -1;
                } else if (currentViewedId !== "") {
                    const idx = root.items.findIndex(it => String(it.id) === currentViewedId);
                    if (idx >= 0) {
                        root.viewerIndex = idx;
                    } else {
                        root.viewerIndex = Math.min(root.viewerIndex, root.items.length - 1);
                        const replacement = root.items[root.viewerIndex];
                        if (replacement && replacement.kind !== "video")
                            root.get(replacement.id);
                    }
                }
            }
            if (root.isOpen)
                root._requestAlbums();
            return;
        }

        case "changed":
            if (root.isOpen) {
                root._requestAlbums();
                root._requestList(false);
            }
            return;
        }
    }

    function handleEvent(ev: var): void {
        if (String(ev?.dev ?? "") !== root.activeDev)
            return;

        switch (String(ev.ev ?? "")) {
        case "galleryThumbs": {
            const ids = Array.isArray(ev.ids) ? ev.ids : [];
            let added = false;
            for (const id of ids) {
                const sid = String(id);
                if (!root._thumbsOnDisk.has(sid)) {
                    root._thumbsOnDisk.add(sid);
                    added = true;
                }
            }
            if (added)
                root.thumbRevision += 1;
            return;
        }

        case "galleryProgress": {
            const sid = String(ev.id ?? "");
            if (sid === "")
                return;
            const nextProg = Object.assign({}, root.fullProgress);
            nextProg[sid] = {
                received: Number(ev.received ?? 0),
                size: Number(ev.size ?? 0)
            };
            root.fullProgress = nextProg;
            return;
        }

        case "galleryFile": {
            const sid = String(ev.id ?? "");
            const path = String(ev.path ?? "");
            if (sid === "" || path === "")
                return;
            const nextProg = Object.assign({}, root.fullProgress);
            delete nextProg[sid];
            root.fullProgress = nextProg;

            const nextErr = Object.assign({}, root.fullErrors);
            delete nextErr[sid];
            root.fullErrors = nextErr;

            const nextFull = Object.assign({}, root.fullPaths);
            nextFull[sid] = path;
            root.fullPaths = nextFull;
            return;
        }

        case "galleryAbort": {
            const sid = String(ev.id ?? "");
            if (sid === "")
                return;
            const nextProg = Object.assign({}, root.fullProgress);
            delete nextProg[sid];
            root.fullProgress = nextProg;

            const nextErr = Object.assign({}, root.fullErrors);
            nextErr[sid] = "abort";
            root.fullErrors = nextErr;
            return;
        }
        }
    }
}
