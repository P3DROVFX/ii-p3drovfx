pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Central state & persistence for the standalone Gallery app.
 * Persists user preferences to `${Directories.appsState}/gallery.json`
 * (never to the shell's config.json) and scans folders via a one-shot Python
 * helper so zero background daemons stay alive when idle.
 */
QtObject {
    id: store

    // ── Persisted preferences ───────────────────────────────────────────
    property string gridSize: "M"          // "P" (7), "M" (5), "G" (3)
    property string sortOrder: "desc"      // "desc" | "asc"
    property bool showVideos: true
    property bool autoplay: true
    property bool startMuted: false
    property real videoVolume: 1.0
    property bool includeSub: true
    property var folders: [
        { name: "Pictures", path: "~/Pictures", on: true, base: true },
        { name: "Downloads", path: "~/Downloads", on: true, base: true },
        { name: "Videos", path: "~/Videos", on: false, base: true }
    ]
    property var favs: []                  // array of file paths

    readonly property int gridColumns: gridSize === "P" ? 7 : (gridSize === "G" ? 3 : 5)
    readonly property string stateFilePath: `${Directories.appsState}/gallery.json`
    readonly property string scanScriptPath: `${Directories.scriptPath}/gallery/scan_gallery.py`
    readonly property string helperBinPath: `${Directories.scriptPath}/gallery/gallery_helper`

    // ── Library data ────────────────────────────────────────────────────
    property var items: []
    property var folderCounts: ({})
    property var videoMeta: ({})           // path -> { thumb, dur, w, h }
    property var photoThumbs: ({})         // path -> cached 256px jpg path
    property int videoMetaRev: 0
    property bool scanning: false
    property bool loadedOnce: false

    // ── Navigation & UI state ───────────────────────────────────────────
    property string activeTab: "home"      // "home" | "albums" | "phone" | "settings"
    property string filter: "all"          // "all" | "photo" | "video" | "fav"
    property string query: ""
    property string activeAlbum: ""        // "" = albums overview; otherwise relative folder path
    property bool addSheetOpen: false

    // ── Shared variable font presets (4 fixed faces -> avoids FreeType mmap bloat) ─
    readonly property var axesDigitsBold: ({ "wght": 760, "wdth": 36, "ROND": 100 })
    readonly property var axesDigitsLight: ({ "wght": 320, "wdth": 34, "ROND": 100 })
    readonly property var axesTitle: ({ "wght": 660, "wdth": 110, "ROND": 100 })
    readonly property var axesBody: ({ "wght": 540, "wdth": 100, "ROND": 100 })

    // ── Multi-selection state (click, long-press, and swipe/drag-to-select) ─
    property var selectedPaths: []
    property bool dragSelecting: false
    property bool dragSelectTarget: true
    readonly property bool selectionMode: selectedPaths.length > 0
    readonly property int selectedCount: selectedPaths.length
    readonly property var _selectedSet: {
        const s = {};
        for (const p of (store.selectedPaths ?? []))
            s[String(p)] = true;
        return s;
    }

    function isSelected(path): bool {
        return !!store._selectedSet[String(path ?? "")];
    }

    function setSelected(path, want): void {
        const p = String(path ?? "");
        if (!p)
            return;
        const already = !!store._selectedSet[p];
        if (already === want)
            return;
        const cur = (store.selectedPaths ?? []).slice();
        if (want) {
            cur.push(p);
        } else {
            const idx = cur.indexOf(p);
            if (idx >= 0)
                cur.splice(idx, 1);
        }
        store.selectedPaths = cur;
    }

    function startDragSelect(path): void {
        const p = String(path ?? "");
        if (!p)
            return;
        store.dragSelectTarget = !store.isSelected(p);
        store.dragSelecting = true;
        store.setSelected(p, store.dragSelectTarget);
    }

    function applyDragSelect(path): void {
        if (!store.dragSelecting)
            return;
        store.setSelected(path, store.dragSelectTarget);
    }

    function endDragSelect(): void {
        store.dragSelecting = false;
    }

    function toggleSelect(path): void {
        const p = String(path ?? "");
        if (!p)
            return;
        store.setSelected(p, !store.isSelected(p));
    }

    function selectAllFrom(list): void {
        const arr = Array.isArray(list) ? list : [];
        const next = [];
        for (const it of arr) {
            if (it && it.path)
                next.push(String(it.path));
        }
        store.selectedPaths = next;
    }

    function clearSelection(): void {
        store.selectedPaths = [];
    }

    function setVideoVolume(vol): void {
        const clamped = Math.max(0.0, Math.min(1.0, Math.round(Number(vol) * 100) / 100));
        if (Math.abs(clamped - store.videoVolume) < 0.005)
            return;
        store.videoVolume = clamped;
        volSaveDebounce.restart();
    }

    function favoriteSelected(): void {
        const sel = store.selectedPaths ?? [];
        if (sel.length === 0)
            return;
        const allFav = sel.every(p => store.isFav(p));
        let cur = (store.favs ?? []).slice();
        if (allFav) {
            const drop = {};
            for (const p of sel) drop[p] = true;
            cur = cur.filter(p => !drop[p]);
            store.showSnack(Translation.tr("Removed %1 items from favorites").arg(sel.length), "", null);
        } else {
            for (const p of sel) {
                if (!store.isFav(p))
                    cur.push(p);
            }
            store.showSnack(Translation.tr("Added %1 items to favorites").arg(sel.length), "", null);
        }
        store.favs = cur;
        store.savePrefs();
        store.clearSelection();
    }

    function trashSelected(): void {
        const sel = (store.selectedPaths ?? []).slice();
        if (sel.length === 0 || batchTrashProc.running)
            return;
        batchTrashProc.command = ["python3", store.scanScriptPath, "trash-batch", "--paths-json", JSON.stringify(sel)];
        batchTrashProc.running = true;
    }

    function moveSelectedTo(destFolder): void {
        const sel = (store.selectedPaths ?? []).slice();
        const dest = String(destFolder ?? "").trim();
        if (sel.length === 0 || !dest || batchMoveProc.running)
            return;
        batchMoveProc.command = ["python3", store.scanScriptPath, "move-batch", "--paths-json", JSON.stringify(sel), "--dest", dest];
        batchMoveProc.running = true;
    }

    // ── Viewer state ────────────────────────────────────────────────────
    property bool viewerOpen: false
    property string viewerSource: "local"  // "local" | "phone"
    property var viewerList: []
    property int viewerIndex: -1
    // Origin rect (in window coords) & preview URL for hero expand animation
    property var viewerOrigin: null        // { x, y, w, h, thumb } or null

    // ── Snackbar state ──────────────────────────────────────────────────
    property bool snackVisible: false
    property string snackText: ""
    property string snackActionLabel: ""
    property var _snackCallback: null

    // ── Derived library lists ───────────────────────────────────────────
    readonly property var _favSet: {
        const s = {};
        for (const p of (store.favs ?? []))
            s[String(p)] = true;
        return s;
    }

    function isFav(path): bool {
        return !!store._favSet[String(path ?? "")];
    }

    function _norm(s): string {
        return String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
    }

    function inTimeline(it): bool {
        if (!it)
            return false;
        const f = store.folders.find(x => x.name === it.root);
        if (!f || !f.on)
            return false;
        if (!store.includeSub && it.isSub)
            return false;
        return true;
    }

    function matchesQuery(it, normQ): bool {
        if (!normQ)
            return true;
        const d = new Date(it.mtime);
        const hay = store._norm([
            it.title, it.folder, it.file,
            store.monthFullName(d.getMonth()),
            store.monthShortName(d.getMonth()),
            store.weekdayName(d.getDay()),
            String(d.getDate()),
            String(d.getFullYear()),
            it.type === "video" ? "video vídeo" : "foto photo imagem"
        ].join(" "));
        const words = normQ.split(/\s+/).filter(Boolean);
        for (const w of words) {
            if (!hay.includes(w))
                return false;
        }
        return true;
    }

    readonly property var timelineAllItems: {
        const out = [];
        for (const it of store.items) {
            if (!store.inTimeline(it))
                continue;
            if (!store.showVideos && it.type === "video")
                continue;
            out.push(it);
        }
        return out;
    }

    readonly property int timelineTotalCount: timelineAllItems.length
    readonly property int timelinePhotoCount: timelineAllItems.filter(i => i.type === "photo").length
    readonly property int timelineVideoCount: timelineAllItems.filter(i => i.type === "video").length
    readonly property int todayCount: {
        const todayKey = store.dayKey(Date.now());
        let n = 0;
        for (const it of store.timelineAllItems) {
            if (store.dayKey(it.mtime) === todayKey)
                n++;
        }
        return n;
    }

    readonly property var homeItems: {
        const q = store._norm(store.query.trim());
        const filtered = store.timelineAllItems.filter(it => {
            if (store.filter === "fav" && !store.isFav(it.path))
                return false;
            if (store.filter === "photo" && it.type !== "photo")
                return false;
            if (store.filter === "video" && it.type !== "video")
                return false;
            return store.matchesQuery(it, q);
        });
        if (store.sortOrder === "asc")
            return filtered.slice().reverse();
        return filtered;
    }

    readonly property var libraryItems: {
        const rootNames = {};
        for (const f of store.folders)
            rootNames[f.name] = true;
        const out = store.items.filter(it => rootNames[it.root] && (store.showVideos || it.type !== "video"));
        return store.sortOrder === "asc" ? out.slice().reverse() : out;
    }

    readonly property var albumsData: {
        const lib = store.libraryItems;
        const byPath = {};
        for (const f of store.folders) {
            byPath[f.name] = {
                path: f.name,
                name: f.name,
                displayPath: f.path,
                depth: 1,
                items: []
            };
        }
        for (const it of lib) {
            const segs = String(it.folder ?? it.root).split("/");
            for (let i = 1; i <= segs.length; i++) {
                const p = segs.slice(0, i).join("/");
                if (!byPath[p]) {
                    const rootFolder = store.folders.find(f => f.name === segs[0]);
                    const disp = rootFolder ? (rootFolder.path + p.slice(segs[0].length)) : p;
                    byPath[p] = {
                        path: p,
                        name: segs[i - 1],
                        displayPath: disp,
                        depth: i,
                        items: []
                    };
                }
                byPath[p].items.push(it);
            }
        }
        return Object.values(byPath);
    }

    function albumItems(folderPath): var {
        const target = String(folderPath ?? "");
        if (!target)
            return [];
        const prefix = target + "/";
        return store.libraryItems.filter(it => it.folder === target || String(it.folder).startsWith(prefix));
    }

    function subfoldersOf(folderPath): var {
        const target = String(folderPath ?? "");
        if (!target)
            return [];
        const targetDepth = target.split("/").length;
        const prefix = target + "/";
        return store.albumsData
            .filter(a => a.depth === targetDepth + 1 && a.path.startsWith(prefix))
            .sort((a, b) => b.items.length - a.items.length);
    }

    // ── Date & formatting helpers ───────────────────────────────────────
    function pad2(n): string {
        return n < 10 ? ("0" + n) : String(n);
    }

    function dayKey(ms): string {
        const d = new Date(Number(ms || 0));
        return d.getFullYear() + "-" + store.pad2(d.getMonth() + 1) + "-" + store.pad2(d.getDate());
    }

    function monthShortName(m): string {
        const arr = [
            Translation.tr("JAN"), Translation.tr("FEB"), Translation.tr("MAR"),
            Translation.tr("APR"), Translation.tr("MAY"), Translation.tr("JUN"),
            Translation.tr("JUL"), Translation.tr("AUG"), Translation.tr("SEP"),
            Translation.tr("OCT"), Translation.tr("NOV"), Translation.tr("DEC")
        ];
        return arr[m] ?? "";
    }

    function monthFullName(m): string {
        const arr = [
            Translation.tr("January"), Translation.tr("February"), Translation.tr("March"),
            Translation.tr("April"), Translation.tr("May"), Translation.tr("June"),
            Translation.tr("July"), Translation.tr("August"), Translation.tr("September"),
            Translation.tr("October"), Translation.tr("November"), Translation.tr("December")
        ];
        return arr[m] ?? "";
    }

    function weekdayName(w): string {
        const arr = [
            Translation.tr("Sunday"), Translation.tr("Monday"), Translation.tr("Tuesday"),
            Translation.tr("Wednesday"), Translation.tr("Thursday"), Translation.tr("Friday"),
            Translation.tr("Saturday")
        ];
        return arr[w] ?? "";
    }

    function relDayLabel(ms): string {
        const now = new Date();
        const d = new Date(Number(ms || 0));
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const itemStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const diff = Math.round((todayStart - itemStart) / 86400000);
        if (diff === 0)
            return Translation.tr("Today");
        if (diff === 1)
            return Translation.tr("Yesterday");
        return store.weekdayName(d.getDay());
    }

    function todayCaption(): string {
        const d = new Date();
        return `${store.weekdayName(d.getDay())}, ${d.getDate()} ${store.monthFullName(d.getMonth())}`;
    }

    function formatTime(sec): string {
        const s = Math.max(0, Math.floor(Number(sec || 0)));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const r = s % 60;
        if (h > 0)
            return `${h}:${store.pad2(m)}:${store.pad2(r)}`;
        return `${m}:${store.pad2(r)}`;
    }

    function formatBytes(bytes): string {
        const n = Number(bytes || 0);
        if (n <= 0)
            return "";
        if (n < 1024)
            return `${n} B`;
        if (n < 1048576)
            return `${(n / 1024).toFixed(1)} KB`;
        if (n < 1073741824)
            return `${(n / 1048576).toFixed(1)} MB`;
        return `${(n / 1073741824).toFixed(2)} GB`;
    }

    function folderIcon(name): string {
        const n = String(name ?? "").toLowerCase();
        if (n === "pictures" || n === "imagens" || n === "photos")
            return "image";
        if (n === "downloads")
            return "download";
        if (n === "videos" || n === "vídeos")
            return "movie";
        if (n === "desktop" || n === "área de trabalho")
            return "desktop_windows";
        if (n === "screenshots" || n === "capturas")
            return "screenshot";
        if (n === "wallpapers")
            return "wallpaper";
        if (n === "phone" || n === "celular")
            return "smartphone";
        return "folder";
    }

    function thumbUrlFor(it): string {
        if (!it)
            return "";
        if (it.type === "photo") {
            const cached = store.photoThumbs[it.path];
            if (cached)
                return "file://" + cached;
            if (it.thumb)
                return "file://" + it.thumb;
            return "file://" + it.path;
        }
        // Video thumbnail from cache or lazy meta map
        const meta = store.videoMeta[it.path];
        if (meta && meta.thumb)
            return "file://" + meta.thumb;
        if (it.thumb)
            return "file://" + it.thumb;
        return "";
    }

    function durationFor(it): int {
        if (!it)
            return 0;
        const meta = store.videoMeta[it.path];
        if (meta && meta.dur > 0)
            return meta.dur;
        return Number(it.dur || 0);
    }

    // ── Snackbar ────────────────────────────────────────────────────────
    function showSnack(text, actionLabel, callback): void {
        store.snackText = String(text ?? "");
        store.snackActionLabel = String(actionLabel ?? "");
        store._snackCallback = callback ?? null;
        store.snackVisible = true;
        snackTimer.interval = store.snackActionLabel.length > 0 ? 5500 : 3200;
        snackTimer.restart();
    }

    function triggerSnackAction(): void {
        const cb = store._snackCallback;
        store.hideSnack();
        if (typeof cb === "function")
            cb();
    }

    function hideSnack(): void {
        snackTimer.stop();
        store.snackVisible = false;
        store._snackCallback = null;
    }

    // ── Mutations ───────────────────────────────────────────────────────
    function setGridSize(sz): void {
        if (sz !== "P" && sz !== "M" && sz !== "G")
            return;
        store.gridSize = sz;
        store.savePrefs();
    }

    function setSortOrder(ord): void {
        if (ord !== "desc" && ord !== "asc")
            return;
        store.sortOrder = ord;
        store.savePrefs();
    }

    function togglePref(key): void {
        if (key === "showVideos") {
            store.showVideos = !store.showVideos;
            if (!store.showVideos && store.filter === "video")
                store.filter = "all";
            store.savePrefs();
            store.rescan();
        } else if (key === "autoplay") {
            store.autoplay = !store.autoplay;
            store.savePrefs();
        } else if (key === "startMuted") {
            store.startMuted = !store.startMuted;
            store.savePrefs();
        } else if (key === "includeSub") {
            store.includeSub = !store.includeSub;
            store.savePrefs();
        }
    }

    function toggleFolder(name): void {
        const next = store.folders.map(f => f.name === name ? Object.assign({}, f, { on: !f.on }) : f);
        store.folders = next;
        store.savePrefs();
    }

    function addFolder(name, path): void {
        const cleanPath = String(path ?? "").trim();
        if (!cleanPath)
            return;
        if (store.folders.some(f => f.path === cleanPath)) {
            store.showSnack(Translation.tr("Folder is already in library"), "", null);
            return;
        }
        let cleanName = String(name ?? "").trim();
        if (!cleanName) {
            const parts = cleanPath.replace(/\/+$/, "").split("/");
            cleanName = parts[parts.length - 1] || cleanPath;
        }
        if (store.folders.some(f => f.name === cleanName))
            cleanName = `${cleanName} (2)`;
        store.folders = store.folders.concat([{ name: cleanName, path: cleanPath, on: true, base: false }]);
        store.savePrefs();
        store.rescan();
        store.showSnack(Translation.tr("Added \"%1\"").arg(cleanName), "", null);
    }

    function removeFolder(name): void {
        const idx = store.folders.findIndex(f => f.name === name);
        if (idx < 0)
            return;
        const removed = store.folders[idx];
        const next = store.folders.slice();
        next.splice(idx, 1);
        store.folders = next;
        if (store.activeAlbum === name || store.activeAlbum.startsWith(name + "/"))
            store.activeAlbum = "";
        store.savePrefs();
        store.rescan();
        store.showSnack(Translation.tr("Removed \"%1\"").arg(removed.name), Translation.tr("Undo"), () => {
            const restored = store.folders.slice();
            restored.splice(Math.min(idx, restored.length), 0, removed);
            store.folders = restored;
            store.savePrefs();
            store.rescan();
        });
    }

    function toggleFav(path): void {
        const p = String(path ?? "");
        if (!p)
            return;
        const cur = (store.favs ?? []).slice();
        const idx = cur.indexOf(p);
        if (idx >= 0) {
            cur.splice(idx, 1);
            store.favs = cur;
            store.showSnack(Translation.tr("Removed from favorites"), "", null);
        } else {
            cur.push(p);
            store.favs = cur;
            store.showSnack(Translation.tr("Added to favorites"), "", null);
        }
        store.savePrefs();
    }

    // ── Viewer control ──────────────────────────────────────────────────
    function openLocalViewer(itemPath, list, originRect): void {
        const arr = Array.isArray(list) ? list : store.homeItems;
        const idx = arr.findIndex(x => x.path === itemPath);
        if (idx < 0)
            return;
        store.viewerOrigin = originRect ?? null;
        store.viewerSource = "local";
        store.viewerList = arr;
        store.viewerIndex = idx;
        store.viewerOpen = true;
    }

    function openPhoneViewer(itemId, list, originRect): void {
        const arr = Array.isArray(list) ? list : [];
        const sid = String(itemId ?? "");
        const idx = arr.findIndex(x => String(x.id) === sid);
        if (idx < 0)
            return;
        store.viewerOrigin = originRect ?? null;
        store.viewerSource = "phone";
        store.viewerList = arr;
        store.viewerIndex = idx;
        store.viewerOpen = true;
    }

    function closeViewer(): void {
        store.viewerOpen = false;
        store.viewerIndex = -1;
        store.viewerOrigin = null;
    }

    // ── Shell actions (Wallpaper, Avatar, Clipboard, Trash) ─────────────
    function setWallpaper(path, lockscreen): void {
        const p = String(path ?? "").trim();
        if (!p)
            return;
        const fn = lockscreen ? "applyLockscreen" : "apply";
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpapers", fn, p]);
        store.showSnack(
            lockscreen
                ? Translation.tr("Lockscreen wallpaper updated")
                : Translation.tr("Desktop wallpaper updated"),
            "", null
        );
    }

    function setAvatar(path): void {
        const p = String(path ?? "").trim();
        if (!p)
            return;
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "gallery", "setAvatar", p]);
        store.showSnack(Translation.tr("Profile avatar updated"), "", null);
    }

    function copyPath(path): void {
        const p = String(path ?? "").trim();
        if (!p)
            return;
        Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", p]);
        store.showSnack(Translation.tr("Path copied to clipboard"), "", null);
    }

    function trashLocalItem(path): void {
        const p = String(path ?? "").trim();
        if (!p || trashProc.running)
            return;
        trashProc.targetPath = p;
        trashProc.command = ["python3", store.scanScriptPath, "trash", "--path", p];
        trashProc.running = true;
    }

    // ── Photo thumbnail warm-up queue (batched Pillow worker) ───────────
    property var _photoThumbPending: []

    function _startPhotoThumbWarmup(): void {
        const missing = [];
        for (const it of (store.items ?? [])) {
            if (it && it.type === "photo" && !it.thumb && !store.photoThumbs[it.path])
                missing.push(it.path);
        }
        store._photoThumbPending = missing;
        store._pumpPhotoThumbBatch();
    }

    function _pumpPhotoThumbBatch(): void {
        if (photoThumbProc.running || store._photoThumbPending.length === 0)
            return;
        const batch = store._photoThumbPending.slice(0, 80);
        store._photoThumbPending = store._photoThumbPending.slice(80);
        photoThumbProc.command = [
            "sh", "-c",
            'bin="$1"; py="$2"; shift 2; [ -x "$bin" ] && exec "$bin" "$@" || exec python3 "$py" "$@"',
            "sh", store.helperBinPath, store.scanScriptPath,
            "thumbs-batch",
            "--paths-json", JSON.stringify(batch),
            "--size", "480"
        ];
        photoThumbProc.running = true;
    }

    // ── Video thumbnail lazy queue (1 process at a time) ────────────────
    property var _thumbQueue: []
    property var _thumbQueuedSet: ({})

    function requestVideoThumb(path): void {
        const p = String(path ?? "");
        if (!p)
            return;
        if (store.videoMeta[p] || store._thumbQueuedSet[p])
            return;
        store._thumbQueuedSet[p] = true;
        store._thumbQueue.push(p);
        store._pumpThumbQueue();
    }

    function _pumpThumbQueue(): void {
        if (thumbProc.running || store._thumbQueue.length === 0)
            return;
        const next = store._thumbQueue.shift();
        thumbProc.targetPath = next;
        thumbProc.command = ["python3", store.scanScriptPath, "thumb", "--path", next];
        thumbProc.running = true;
    }

    // ── Scan & persistence ──────────────────────────────────────────────
    function rescan(): void {
        if (scanProc.running) {
            store._rescanPending = true;
            return;
        }
        store._rescanPending = false;
        store.scanning = true;
        scanProc.command = [
            "sh", "-c",
            'bin="$1"; py="$2"; shift 2; [ -x "$bin" ] && exec "$bin" "$@" || exec python3 "$py" "$@"',
            "sh", store.helperBinPath, store.scanScriptPath,
            "scan",
            "--folders-json", JSON.stringify(store.folders),
            "--show-videos", store.showVideos ? "1" : "0"
        ];
        scanProc.running = true;
    }

    property bool _rescanPending: false
    property bool _prefsLoaded: false

    function loadPrefs(content): void {
        try {
            const parsed = JSON.parse(content || "{}");
            if (parsed.gridSize === "P" || parsed.gridSize === "M" || parsed.gridSize === "G")
                store.gridSize = parsed.gridSize;
            if (parsed.sortOrder === "asc" || parsed.sortOrder === "desc")
                store.sortOrder = parsed.sortOrder;
            if (typeof parsed.showVideos === "boolean")
                store.showVideos = parsed.showVideos;
            if (typeof parsed.autoplay === "boolean")
                store.autoplay = parsed.autoplay;
            if (typeof parsed.startMuted === "boolean")
                store.startMuted = parsed.startMuted;
            if (typeof parsed.videoVolume === "number" && parsed.videoVolume >= 0 && parsed.videoVolume <= 1)
                store.videoVolume = parsed.videoVolume;
            if (typeof parsed.includeSub === "boolean")
                store.includeSub = parsed.includeSub;
            if (Array.isArray(parsed.folders) && parsed.folders.length > 0) {
                const loaded = parsed.folders.slice();
                // Ensure the system Videos folder is always available in Albums (off on Home by default)
                if (!loaded.some(f => f.path === "~/Videos" || String(f.name).toLowerCase() === "videos")) {
                    loaded.push({ name: "Videos", path: "~/Videos", on: false, base: true });
                }
                store.folders = loaded;
            }
            if (Array.isArray(parsed.favs))
                store.favs = parsed.favs;
        } catch (e) {
            // First run or unreadable file: keep defaults
        }
        store._prefsLoaded = true;
    }

    function savePrefs(): void {
        const payload = JSON.stringify({
            gridSize: store.gridSize,
            sortOrder: store.sortOrder,
            showVideos: store.showVideos,
            autoplay: store.autoplay,
            startMuted: store.startMuted,
            videoVolume: store.videoVolume,
            includeSub: store.includeSub,
            folders: store.folders,
            favs: store.favs
        }, null, 2);
        Quickshell.execDetached([
            "sh", "-c",
            'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"',
            "sh", store.stateFilePath, payload
        ]);
    }

    // ── Child objects ───────────────────────────────────────────────────
    property Timer _snackTimer: Timer {
        id: snackTimer
        interval: 3200
        repeat: false
        onTriggered: store.hideSnack()
    }

    property Timer _volSaveDebounce: Timer {
        id: volSaveDebounce
        interval: 400
        repeat: false
        onTriggered: store.savePrefs()
    }

    property Process _batchTrashProc: Process {
        id: batchTrashProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(this.text || "{}");
                    if (res.ok && Array.isArray(res.trashed) && res.trashed.length > 0) {
                        const gone = {};
                        for (const p of res.trashed) gone[p] = true;
                        store.items = store.items.filter(it => !gone[it.path]);
                        store.clearSelection();
                        store.showSnack(Translation.tr("Moved %1 items to trash").arg(res.trashed.length), "", null);
                        return;
                    }
                } catch (e) {}
                store.showSnack(Translation.tr("Could not move items to trash"), "", null);
            }
        }
    }

    property Process _batchMoveProc: Process {
        id: batchMoveProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(this.text || "{}");
                    if (res.ok && res.moved > 0) {
                        store.clearSelection();
                        store.rescan();
                        const destName = String(res.dest || "").split("/").pop();
                        store.showSnack(Translation.tr("Moved %1 items to %2").arg(res.moved).arg(destName), "", null);
                        return;
                    }
                } catch (e) {}
                store.showSnack(Translation.tr("Could not move items"), "", null);
            }
        }
    }

    property FileView _prefsFile: FileView {
        id: prefsFile
        path: store.stateFilePath
        blockLoading: true
        printErrors: false
        onLoaded: {
            store.loadPrefs(text());
            if (!store.loadedOnce)
                store.rescan();
        }
        onLoadFailed: {
            store._prefsLoaded = true;
            if (!store.loadedOnce)
                store.rescan();
        }
    }

    property Process _scanProc: Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                store.scanning = false;
                store.loadedOnce = true;
                try {
                    const data = JSON.parse(this.text || "{}");
                    if (Array.isArray(data.items))
                        store.items = data.items;
                    if (data.folderCounts && typeof data.folderCounts === "object")
                        store.folderCounts = data.folderCounts;
                    Qt.callLater(store._startPhotoThumbWarmup);
                } catch (e) {
                    console.warn("[Gallery] Failed to parse scan output:", e);
                }
                if (store._rescanPending)
                    Qt.callLater(store.rescan);
            }
        }
        onExited: code => {
            if (code !== 0) {
                store.scanning = false;
                store.loadedOnce = true;
            }
        }
    }

    property Process _photoThumbProc: Process {
        id: photoThumbProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text || "{}");
                    const map = data.thumbs;
                    if (map && typeof map === "object") {
                        const keys = Object.keys(map);
                        if (keys.length > 0) {
                            const next = Object.assign({}, store.photoThumbs);
                            for (const k of keys)
                                next[k] = map[k];
                            store.photoThumbs = next;
                        }
                    }
                } catch (e) {}
                if (store._photoThumbPending.length > 0)
                    Qt.callLater(store._pumpPhotoThumbBatch);
            }
        }
        onExited: code => {
            if (code !== 0 && store._photoThumbPending.length > 0)
                Qt.callLater(store._pumpPhotoThumbBatch);
        }
    }

    property Process _thumbProc: Process {
        id: thumbProc
        property string targetPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text || "{}");
                    const p = String(data.path || thumbProc.targetPath);
                    if (p) {
                        const next = Object.assign({}, store.videoMeta);
                        next[p] = {
                            thumb: String(data.thumb || ""),
                            dur: Number(data.dur || 0),
                            w: Number(data.w || 0),
                            h: Number(data.h || 0)
                        };
                        store.videoMeta = next;
                        store.videoMetaRev += 1;
                    }
                } catch (e) {}
                Qt.callLater(store._pumpThumbQueue);
            }
        }
        onExited: code => {
            if (code !== 0)
                Qt.callLater(store._pumpThumbQueue);
        }
    }

    property Process _trashProc: Process {
        id: trashProc
        property string targetPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let ok = false;
                try {
                    ok = JSON.parse(this.text || "{}").ok === true;
                } catch (e) {}
                if (ok) {
                    const removedPath = trashProc.targetPath;
                    store.items = store.items.filter(it => it.path !== removedPath);
                    if (store.viewerOpen && store.viewerSource === "local") {
                        const nextList = store.viewerList.filter(it => it.path !== removedPath);
                        if (nextList.length === 0) {
                            store.closeViewer();
                        } else {
                            store.viewerList = nextList;
                            store.viewerIndex = Math.min(store.viewerIndex, nextList.length - 1);
                        }
                    }
                    store.showSnack(Translation.tr("Moved to trash"), "", null);
                } else {
                    store.showSnack(Translation.tr("Could not move file to trash"), "", null);
                }
            }
        }
    }

    Component.onCompleted: {
        // Fallback in case FileView neither emits onLoaded nor onLoadFailed synchronously
        if (!store._prefsLoaded) {
            const raw = prefsFile.text();
            if (raw && raw.length > 0)
                store.loadPrefs(raw);
            if (!store.loadedOnce && !store.scanning)
                store.rescan();
        }
    }
}
