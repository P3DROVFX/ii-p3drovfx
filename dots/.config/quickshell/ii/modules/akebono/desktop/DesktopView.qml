pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.akebono
import qs.modules.akebono.desktop
import qs.modules.akebono.desktop.widgets
import qs.modules.akebono.menu

Item {
    id: view

    property string screenName: ""
    property var screen: null
    readonly property var cfg: Config.options.akebono.desktop
    readonly property bool showIcons: ScreenOverrides.resolve(view.screenName, "showIcons", view.cfg.showIcons)
    readonly property bool showWidgets: ScreenOverrides.resolve(view.screenName, "showWidgets", view.cfg.showWidgets ?? true)
    readonly property var keymap: view.cfg.shortcuts
    readonly property string desktopDir: FileUtils.trimFileProtocol(Directories.desktop)

    readonly property int iconSize: view.cfg.iconSize
    readonly property int labelH: 34
    readonly property int cellW: view.iconSize + view.cfg.iconSpacingX
    readonly property int cellH: view.iconSize + view.labelH + view.cfg.iconSpacingY
    readonly property bool shelfOnTop: Config.options.akebono.shelf.position === "top"
    readonly property int shelfReserve: Config.options.akebono.shelf.height + 28
    readonly property bool dockPinned: (Config.options.akebono?.standaloneDock ?? false) && (Config.options.dock.pinnedOnStartup ?? false)
    readonly property int dockReserve: (Config.options.dock.height ?? 70) + 28
    readonly property int edgePadX: 16
    readonly property int marginLeft: edgePadX
    readonly property int marginTop: shelfOnTop ? shelfReserve : 12
    readonly property int marginBottom: shelfOnTop
        ? (dockPinned ? dockReserve : 12)
        : Math.max(shelfReserve, dockPinned ? dockReserve : 0)
    readonly property int cols: Math.max(1, Math.floor((width - edgePadX * 2) / cellW))
    readonly property real pitchX: cols > 1 ? (width - edgePadX * 2 - cellW) / (cols - 1) : cellW
    readonly property int rows: Math.max(1, Math.floor((height - marginTop - marginBottom) / cellH))
    readonly property real pitchY: rows > 1 ? (height - marginTop - marginBottom - cellH) / (rows - 1) : cellH
    readonly property var gridGeometry: [cols, rows, marginLeft, marginTop, pitchX]

    property var cellAssignments: ({})
    property var fileEntries: []
    property bool dragActive: false
    onDragActiveChanged: GlobalStates.desktopIconDragActive = view.dragActive
    property var selectedFiles: []
    property string renamingFile: ""

    property bool banding: false
    property real bandStartX: 0
    property real bandStartY: 0
    property real bandX: 0
    property real bandY: 0
    property real bandW: 0
    property real bandH: 0

    property bool groupSnapping: false
    property int settleTick: 0
    property var clipFiles: []
    property string clipMode: "copy"
    readonly property var hiddenList: view.cfg.hiddenIcons
    property var menuItems: []
    property string openWithTarget: ""
    property int iconRefresh: 0
    property string dragStackLeader: ""
    readonly property var dragStackEntries: {
        let names = view.selectedFiles;
        const lead = view.dragStackLeader;
        if (lead !== "" && names.indexOf(lead) >= 0)
            names = [lead].concat(names.filter(n => n !== lead));
        return names.slice(0, 4).map(n => view.dragStackEntryFor(n)).filter(Boolean);
    }

    property var dropPaths: []
    property real dropX: 0
    property real dropY: 0
    property real createX: 0
    property real createY: 0
    property var pendingCreateCell: null
    property string pendingCreateName: ""
    readonly property string dropOpScript: 'mode="$0"; src="$1"; dd="$2"; base=$(basename "$src"); dst="$dd/$base"; if [ "$mode" = move ] && [ "$src" = "$dst" ]; then exit 0; fi; stem="${base%.*}"; ext="${base##*.}"; if [ "$stem" = "$ext" ]; then ext=""; else ext=".$ext"; fi; i=2; while [ -e "$dst" ]; do dst="$dd/$stem ($i)$ext"; i=$((i+1)); done; case "$mode" in copy) cp -r "$src" "$dst";; move) mv "$src" "$dst";; link) ln -s "$src" "$dst";; esac'

    onGridGeometryChanged: layoutTimer.restart()
    onHiddenListChanged: {
        view.rebuildEntries();
        view.scheduleLayout();
    }
    onRenamingFileChanged: GlobalStates.desktopIconRenaming = (view.renamingFile.length > 0)
    Component.onDestruction: if (view.renamingFile.length > 0)
        GlobalStates.desktopIconRenaming = false

    property bool clicked: false
    readonly property bool pointerOver: deskHover.hovered
    readonly property bool desktopEngaged: (view.clicked && view.pointerOver) || view.renamingFile.length > 0 || DesktopWidgets.textEditing || DesktopWidgets.editMode
    onPointerOverChanged: if (!view.pointerOver) view.clicked = false

    HoverHandler { id: deskHover }

    function scheduleLayout() {
        layoutTimer.restart();
    }

    property var entryCache: ({})

    function rebuildEntries() {
        const arr = [];
        const cache = view.entryCache;
        const live = new Set();
        const hidden = view.cfg.hiddenIcons ?? [];
        for (let i = 0; i < folderModel.count; i++) {
            const n = folderModel.get(i, "fileName");
            if (hidden.indexOf(n) >= 0)
                continue;
            const path = folderModel.get(i, "filePath");
            let entry = cache[n];
            if (!entry || entry.filePath !== path) {
                entry = {
                    "fileName": n,
                    "filePath": path,
                    "fileIsDir": folderModel.get(i, "fileIsDir"),
                    "fileUrl": "" + folderModel.get(i, "fileUrl")
                };
                cache[n] = entry;
            }
            live.add(n);
            arr.push(entry);
        }
        for (const k of Object.keys(cache))
            if (!live.has(k))
                delete cache[k];
        view.fileEntries = arr;
    }

    function computeLayout() {
        if (view.dragActive)
            return;
        if (view.cols < 1 || view.rows < 1 || view.width < 300 || view.height < 300)
            return;
        const result = ({});
        const occupied = ({});
        const toSave = ({});
        const hidden = view.cfg.hiddenIcons ?? [];
        const names = [];
        const listed = [];
        for (let i = 0; i < folderModel.count; i++) {
            const n = folderModel.get(i, "fileName");
            listed.push(n);
            if (hidden.indexOf(n) < 0)
                names.push(n);
        }
        if (folderModel.status === FolderListModel.Ready)
            DesktopLayout.prune(view.screenName, listed);
        for (const n of names) {
            const c = DesktopLayout.cellOf(view.screenName, n);
            if (c && c.col >= 0 && c.col < view.cols && c.row >= 0 && c.row < view.rows) {
                const key = c.col + "," + c.row;
                if (!occupied[key]) {
                    occupied[key] = true;
                    result[n] = { "col": c.col, "row": c.row };
                }
            }
        }
        let idx = 0;
        for (const n of names) {
            if (result[n])
                continue;
            let col, row, key;
            do {
                col = Math.floor(idx / view.rows);
                row = idx % view.rows;
                key = col + "," + row;
                idx++;
            } while (occupied[key]);
            occupied[key] = true;
            result[n] = { "col": col, "row": row };
            if (col < view.cols && row < view.rows)
                toSave[n] = { "col": col, "row": row };
        }
        view.cellAssignments = result;
        for (const k in toSave) {
            DesktopLayout.setCells(view.screenName, toSave);
            break;
        }
    }

    function occupiedBy(c, r, exceptName) {
        const a = view.cellAssignments;
        for (const k in a) {
            if (k === exceptName)
                continue;
            if (a[k].col === c && a[k].row === r)
                return true;
        }
        return false;
    }

    function nearestFreeCell(col, row, name) {
        let best = null;
        let bestD = Infinity;
        for (let c = 0; c < view.cols; c++) {
            for (let r = 0; r < view.rows; r++) {
                if (view.occupiedBy(c, r, name))
                    continue;
                const d = (c - col) * (c - col) + (r - row) * (r - row);
                if (d < bestD) {
                    bestD = d;
                    best = { "col": c, "row": r };
                }
            }
        }
        return best ?? { "col": col, "row": row };
    }

    function cellAt(x, y) {
        let col = Math.round((x - view.marginLeft) / view.pitchX);
        let row = Math.round((y - view.marginTop) / view.pitchY);
        col = Math.max(0, Math.min(view.cols - 1, col));
        row = Math.max(0, Math.min(view.rows - 1, row));
        return { "col": col, "row": row };
    }

    function cursorCell() {
        const b = view.cellAt(view.createX, view.createY);
        return view.nearestFreeCell(b.col, b.row, "");
    }

    function selectFile(name) {
        DesktopWidgets.releaseEditing();
        view.selectedFiles = (name === "" || name === undefined) ? [] : [name];
    }

    function selectAll() {
        const all = [];
        for (const k in view.cellAssignments)
            all.push(k);
        view.selectedFiles = all;
    }

    function selectedPaths() {
        return view.selectedFiles.map(n => view.desktopDir + "/" + n);
    }

    function openSelected() {
        for (const n of view.selectedFiles)
            view.openFile(view.desktopDir + "/" + n, false);
    }

    function shortcutEnabled(seq, extra) {
        return view.renamingFile.length === 0 && seq !== "" && extra;
    }

    function selectInRect(left, top, right, bottom) {
        const sel = [];
        const a = view.cellAssignments;
        for (const name in a) {
            const c = a[name];
            const ix = view.marginLeft + c.col * view.pitchX;
            const iy = view.marginTop + c.row * view.pitchY;
            if (ix + 8 < right && ix + view.cellW - 8 > left && iy + 6 < bottom && iy + view.cellH - 6 > top)
                sel.push(name);
        }
        view.selectedFiles = sel;
    }

    function updateBand(curX, curY) {
        view.bandX = Math.min(view.bandStartX, curX);
        view.bandY = Math.min(view.bandStartY, curY);
        view.bandW = Math.abs(curX - view.bandStartX);
        view.bandH = Math.abs(curY - view.bandStartY);
        view.selectInRect(view.bandX, view.bandY, view.bandX + view.bandW, view.bandY + view.bandH);
    }

    function openFile(path, isDir) {
        if (path.endsWith(".desktop"))
            Quickshell.execDetached(["gio", "launch", path]);
        else
            Quickshell.execDetached(["xdg-open", path]);
        view.selectFile("");
    }

    function resolveAppId(fileName) {
        if (!fileName.endsWith(".desktop"))
            return null;
        const id = fileName.slice(0, -8);
        const entry = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
        return entry ? entry.id : null;
    }

    function buildDragMime(names, leader, hotX, hotY) {
        const appIds = [];
        for (const n of names) {
            const id = view.resolveAppId(n);
            if (id)
                appIds.push(id);
        }
        const uriList = names.map(n => view.pathToUri(view.desktopDir + "/" + n)).join("\r\n") + "\r\n";
        return {
            "text/uri-list": uriList,
            "application/x-desktop-icon": JSON.stringify({
                "screen": view.screenName,
                "names": names,
                "leader": leader,
                "appIds": appIds,
                "hotSpotX": hotX,
                "hotSpotY": hotY
            })
        };
    }

    function repositionFromMarker(json, dropX, dropY) {
        let m;
        try {
            m = JSON.parse(json);
        } catch (e) {
            return;
        }
        if (!m || !m.leader)
            return;
        const x = dropX - (m.hotSpotX ?? 0);
        const y = dropY - (m.hotSpotY ?? 0);
        const names = (m.names && m.names.length > 0) ? m.names : [m.leader];
        const cell = view.cellAt(x, y);
        const target = view.fileAtCell(cell.col, cell.row);
        if (target && names.indexOf(target) < 0 && view.isDirEntry(target)) {
            view.moveInto(target, names);
            return;
        }
        if (names.length > 1)
            view.commitGroupDrag(m.leader, x, y);
        else
            view.commitDrag(m.leader, x, y);
    }

    function fileAtCell(col, row) {
        const a = view.cellAssignments;
        for (const name in a)
            if (a[name].col === col && a[name].row === row)
                return name;
        return null;
    }

    function isDirEntry(name) {
        const e = view.dragStackEntryFor(name);
        return e ? e.fileIsDir : false;
    }

    function moveInto(folderName, names) {
        const dest = view.desktopDir + "/" + folderName;
        for (const n of names) {
            if (n === folderName)
                continue;
            Quickshell.execDetached(["bash", "-c", view.dropOpScript, "move", view.desktopDir + "/" + n, dest]);
            DesktopLayout.forget(view.screenName, n);
        }
    }

    function dragStackEntryFor(name) {
        return view.fileEntries.find(e => e.fileName === name) ?? null;
    }

    function grabDragStack(callback) {
        Qt.callLater(() => dragStack.grabToImage(callback));
    }

    function commitDrag(name, x, y) {
        let col = Math.round((x - view.marginLeft) / view.pitchX);
        let row = Math.round((y - view.marginTop) / view.pitchY);
        col = Math.max(0, Math.min(view.cols - 1, col));
        row = Math.max(0, Math.min(view.rows - 1, row));
        if (view.occupiedBy(col, row, name)) {
            const free = view.nearestFreeCell(col, row, name);
            col = free.col;
            row = free.row;
        }
        const next = Object.assign({}, view.cellAssignments);
        next[name] = { "col": col, "row": row };
        view.cellAssignments = next;
        DesktopLayout.setCell(view.screenName, name, col, row);
    }

    function commitGroupDrag(leaderName, leaderX, leaderY) {
        const lead = view.cellAssignments[leaderName];
        if (!lead) {
            view.dragActive = false;
            return;
        }
        const lcol = Math.round((leaderX - view.marginLeft) / view.pitchX);
        const lrow = Math.round((leaderY - view.marginTop) / view.pitchY);
        const dCol = lcol - lead.col;
        const dRow = lrow - lead.row;
        const next = ({});
        for (const name of view.selectedFiles) {
            const c = view.cellAssignments[name];
            if (!c)
                continue;
            next[name] = {
                "col": Math.max(0, Math.min(view.cols - 1, c.col + dCol)),
                "row": Math.max(0, Math.min(view.rows - 1, c.row + dRow))
            };
        }
        view.groupSnapping = true;
        view.dragActive = false;
        const merged = Object.assign({}, view.cellAssignments);
        for (const k in next)
            merged[k] = next[k];
        view.cellAssignments = merged;
        DesktopLayout.setCells(view.screenName, next);
        view.settleTick++;
        view.groupSnapping = false;
    }

    function beginRename(name) {
        view.renamingFile = name;
    }
    function cancelRename() {
        view.renamingFile = "";
    }
    function commitRename(oldName, newName) {
        view.renamingFile = "";
        if (newName.length === 0 || newName === oldName)
            return;
        const src = view.desktopDir + "/" + oldName;
        const dst = view.desktopDir + "/" + newName;
        const c = DesktopLayout.cellOf(view.screenName, oldName);
        Quickshell.execDetached(["bash", "-c", 'mv -n "$0" "$1"', src, dst]);
        if (c) {
            DesktopLayout.setCell(view.screenName, newName, c.col, c.row);
            DesktopLayout.forget(view.screenName, oldName);
        }
    }

    function trash(paths) {
        if (paths.length === 0)
            return;
        Quickshell.execDetached(["gio", "trash"].concat(paths));
        for (const p of paths)
            DesktopLayout.forget(view.screenName, FileUtils.fileNameForPath(p));
    }
    function pathToUri(p) {
        return "file://" + p.split("/").map(s => encodeURIComponent(s)).join("/");
    }

    function clip(files, mode) {
        view.clipFiles = files;
        view.clipMode = mode;
        const uriList = files.map(p => view.pathToUri(p)).join("\r\n") + "\r\n";
        if (mode === "cut")
            Quickshell.execDetached([Quickshell.shellPath("scripts/desktop/clipboard/fileclip"), "cut", uriList]);
        else
            Quickshell.execDetached(["bash", "-c", 'printf "%s" "$0" | wl-copy --type text/uri-list', uriList]);
    }

    function paste() {
        pasteProc.running = true;
    }

    function onClipboardRead(text) {
        const lines = text.split(/\r?\n/);
        let isCut = false;
        const uris = [];
        for (const line of lines) {
            const t = line.trim();
            if (t.startsWith("CUT:"))
                isCut = (t.slice(4) === "1");
            else if (t.startsWith("file://"))
                uris.push(t);
        }
        let paths, mode;
        if (uris.length > 0) {
            paths = uris.map(u => view.urlToLocalPath(u));
            const ourCut = view.clipMode === "cut" && view.clipFiles.length > 0 && paths.some(p => view.clipFiles.indexOf(p) >= 0);
            mode = (isCut || ourCut) ? "move" : "copy";
        } else if (view.clipFiles.length > 0) {
            paths = view.clipFiles.slice();
            mode = view.clipMode === "cut" ? "move" : "copy";
        } else {
            return;
        }
        view.dropPaths = paths;
        view.dropX = view.createX;
        view.dropY = view.createY;
        view.performDrop(mode);
        if (mode === "move") {
            view.clipFiles = [];
            view.clipMode = "copy";
        }
    }

    function urlToLocalPath(u) {
        let s = "" + u;
        if (s.startsWith("file://"))
            s = s.slice(7);
        try {
            return decodeURIComponent(s);
        } catch (e) {
            return s;
        }
    }

    function beginDrop(paths, x, y) {
        view.dropPaths = paths;
        view.dropX = x;
        view.dropY = y;
        const n = paths.length;
        const multi = n > 1;
        const items = [
            { "icon": "drive_file_move", "label": multi ? `Move ${n} items here` : "Move here", "action": () => view.performDrop("move") },
            { "icon": "content_copy", "label": multi ? `Copy ${n} items here` : "Copy here", "action": () => view.performDrop("copy") },
            { "icon": "link", "label": multi ? `Link ${n} items here` : "Link here", "action": () => view.performDrop("link") },
            { "separator": true },
            { "icon": "close", "label": "Cancel" }
        ];
        menu.show(items, x, y);
    }

    function performDrop(mode) {
        const paths = view.dropPaths;
        if (!paths || paths.length === 0)
            return;
        const origin = view.cellAt(view.dropX, view.dropY);
        const first = view.nearestFreeCell(origin.col, origin.row, "");
        let idx = 0;
        for (const src of paths) {
            const base = src.split("/").pop();
            let c = first.col;
            let r = first.row + idx;
            while (r > view.rows - 1) {
                r -= view.rows;
                c = Math.min(view.cols - 1, c + 1);
            }
            DesktopLayout.setCell(view.screenName, base, c, r);
            Quickshell.execDetached(["bash", "-c", view.dropOpScript, mode, src, view.desktopDir]);
            idx++;
        }
        view.dropPaths = [];
        view.scheduleLayout();
    }

    function createEntry(kind) {
        const nm = (kind === "folder") ? "New Folder" : "New File";
        const mk = (kind === "folder") ? 'mkdir -p "$t"' : 'touch "$t"';
        const c = view.cursorCell();
        view.pendingCreateCell = c;
        view.pendingCreateName = nm;
        DesktopLayout.setCell(view.screenName, nm, c.col, c.row);
        createProc.command = ["bash", "-c", `d="$0"; n="${nm}"; t="$d/$n"; i=2; while [ -e "$t" ]; do t="$d/$n ($i)"; i=$((i+1)); done; ${mk}; basename "$t"`, view.desktopDir];
        createProc.running = true;
    }

    function hideIcons(names) {
        const h = (view.cfg.hiddenIcons ?? []).slice();
        for (const n of names)
            if (h.indexOf(n) < 0)
                h.push(n);
        Config.options.akebono.desktop.hiddenIcons = h;
    }
    function unhideAll() {
        Config.options.akebono.desktop.hiddenIcons = [];
    }
    function toggleShowIcons() {
        ScreenOverrides.setEffective(view.screenName, "showIcons", !view.showIcons, view.cfg.showIcons);
    }
    function toggleShowWidgets() {
        ScreenOverrides.setEffective(view.screenName, "showWidgets", !view.showWidgets, view.cfg.showWidgets ?? true);
    }
    function setIconSize(v) {
        Config.options.akebono.desktop.iconSize = v;
    }
    function sortBy(v) {
        Config.options.akebono.desktop.sortBy = v;
        view.tidy();
    }
    function tidy() {
        DesktopLayout.clearScreen(view.screenName);
    }

    function openIconMenu(it, mx, my) {
        if (view.selectedFiles.indexOf(it.fileName) < 0)
            view.selectedFiles = [it.fileName];
        const targets = view.selectedFiles.slice();
        const multi = targets.length > 1;
        const paths = targets.map(n => view.desktopDir + "/" + n);
        view.openWithTarget = it.filePath;
        const items = [
            { "icon": "open_in_new", "label": "Open", "action": () => view.openFile(it.filePath, it.fileIsDir) }
        ];
        if (!it.fileIsDir && !multi)
            items.push({ "icon": "apps", "label": "Open with…", "submenu": [{ "label": "Loading…", "enabled": false }] });
        items.push({ "separator": true });
        items.push({ "icon": "content_cut", "label": multi ? `Cut ${targets.length} items` : "Cut", "action": () => view.clip(paths, "cut") });
        items.push({ "icon": "content_copy", "label": multi ? `Copy ${targets.length} items` : "Copy", "action": () => view.clip(paths, "copy") });
        if (!multi)
            items.push({ "icon": "edit", "label": "Rename", "action": () => view.beginRename(it.fileName) });
        items.push({ "separator": true });
        items.push({ "icon": "visibility_off", "label": multi ? `Hide ${targets.length} icons` : "Hide this icon", "action": () => view.hideIcons(targets) });
        items.push({ "icon": "delete", "label": multi ? `Move ${targets.length} to Trash` : "Move to Trash", "danger": true, "action": () => view.trash(paths) });
        view.menuItems = items;
        menu.show(items, it.x + mx, it.y + my);
        if (!it.fileIsDir && !multi) {
            openWithProc.targetPath = it.filePath;
            openWithProc.running = true;
        }
    }

    function populateOpenWith(text) {
        if (!menu.showing)
            return;
        const ids = [];
        for (const line of text.split("\n")) {
            const t = line.trim();
            if (t.endsWith(".desktop") && ids.indexOf(t) < 0)
                ids.push(t);
        }
        const sub = [];
        for (const id of ids) {
            const entry = DesktopEntries.byId(id.slice(0, -8)) ?? DesktopEntries.heuristicLookup(id.slice(0, -8));
            sub.push({
                "iconSource": Quickshell.iconPath(entry?.icon ?? "application-x-executable", "application-x-executable"),
                "label": entry?.name ?? id,
                "action": () => Quickshell.execDetached(["gtk-launch", id, view.openWithTarget])
            });
        }
        if (sub.length === 0)
            sub.push({ "label": "No apps found", "enabled": false });
        for (const item of view.menuItems) {
            if (item.label === "Open with…")
                item.submenu = sub;
        }
        menu.items = view.menuItems.slice();
    }

    function openEmptyMenu(mx, my) {
        view.createX = mx;
        view.createY = my;
        view.selectFile("");
        if (DesktopWidgets.editMode) {
            const we = [
                { "icon": "add_photo_alternate", "label": "Add image widget", "action": () => DesktopWidgets.add(view.screenName, "image", mx, my) },
                { "icon": "sticky_note_2", "label": "Add notes widget", "action": () => DesktopWidgets.add(view.screenName, "notes", mx, my) },
                { "icon": "calendar_month", "label": "Add calendar widget", "action": () => DesktopWidgets.add(view.screenName, "calendar", mx, my) },
                { "icon": "partly_cloudy_day", "label": "Add weather widget", "action": () => DesktopWidgets.add(view.screenName, "weather", mx, my) },
                { "icon": "music_note", "label": "Add media widget", "action": () => DesktopWidgets.add(view.screenName, "media", mx, my) },
                { "separator": true },
                { "icon": "check", "label": "Done editing", "action": () => DesktopWidgets.editMode = false }
            ];
            view.menuItems = we;
            menu.show(we, mx, my);
            return;
        }
        const sizes = [{ "label": "Small", "v": 48 }, { "label": "Medium", "v": 64 }, { "label": "Large", "v": 96 }];
        const sorts = [{ "label": "Name", "v": "name" }, { "label": "Date", "v": "date" }, { "label": "Size", "v": "size" }, { "label": "Type", "v": "type" }];
        const items = [
            { "icon": "create_new_folder", "label": "New Folder", "action": () => view.createEntry("folder") },
            { "icon": "note_add", "label": "New File", "action": () => view.createEntry("file") },
            { "icon": "content_paste", "label": "Paste", "action": () => view.paste() },
            { "separator": true },
            { "icon": "sort", "label": "Sort by", "submenu": sorts.map(s => ({ "label": s.label, "action": () => view.sortBy(s.v) })) },
            { "icon": "photo_size_select_large", "label": "Icon size", "submenu": sizes.map(s => ({ "label": s.label, "action": () => view.setIconSize(s.v) })) },
            { "icon": view.showIcons ? "visibility_off" : "visibility", "label": view.showIcons ? "Hide all icons" : "Show icons", "action": () => view.toggleShowIcons() }
        ];
        if ((view.cfg.hiddenIcons ?? []).length > 0)
            items.push({ "icon": "visibility", "label": "Show hidden icons (" + view.cfg.hiddenIcons.length + ")", "action": () => view.unhideAll() });
        items.push({ "separator": true });
        items.push({ "icon": view.showWidgets ? "visibility_off" : "visibility", "label": view.showWidgets ? "Hide widgets" : "Show widgets", "action": () => view.toggleShowWidgets() });
        items.push({ "icon": "dashboard_customize", "label": "Edit widgets", "action": () => DesktopWidgets.editMode = true });
        items.push({ "separator": true });
        items.push({ "icon": "wallpaper", "label": "Change wallpaper", "action": () => GlobalStates.wallpaperSelectorOpen = true });
        view.menuItems = items;
        menu.show(items, mx, my);
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", view.desktopDir]);
        view.scheduleLayout();
    }

    Timer {
        id: layoutTimer
        interval: 16
        onTriggered: view.computeLayout()
    }

    FileView {
        id: kdeglobalsWatcher
        path: FileUtils.trimFileProtocol(Directories.config) + "/kdeglobals"
        watchChanges: true
        onFileChanged: themeSettleTimer.restart()
    }
    Timer {
        id: themeSettleTimer
        interval: 1000
        onTriggered: view.iconRefresh++
    }

    Connections {
        target: DesktopLayout
        function onRevisionChanged() {
            view.scheduleLayout();
        }
    }

    Shortcut {
        sequence: view.keymap?.trash ?? ""
        enabled: view.shortcutEnabled(sequence, view.selectedFiles.length > 0)
        onActivated: view.trash(view.selectedPaths())
    }
    Shortcut {
        sequence: view.keymap?.rename ?? ""
        enabled: view.shortcutEnabled(sequence, view.selectedFiles.length === 1)
        onActivated: view.beginRename(view.selectedFiles[0])
    }
    Shortcut {
        sequence: view.keymap?.copy ?? ""
        enabled: view.shortcutEnabled(sequence, view.selectedFiles.length > 0)
        onActivated: view.clip(view.selectedPaths(), "copy")
    }
    Shortcut {
        sequence: view.keymap?.cut ?? ""
        enabled: view.shortcutEnabled(sequence, view.selectedFiles.length > 0)
        onActivated: view.clip(view.selectedPaths(), "cut")
    }
    Shortcut {
        sequence: view.keymap?.paste ?? ""
        enabled: view.shortcutEnabled(sequence, true)
        onActivated: view.paste()
    }
    Shortcut {
        sequence: view.keymap?.selectAll ?? ""
        enabled: view.shortcutEnabled(sequence, true)
        onActivated: view.selectAll()
    }
    Shortcut {
        sequence: view.keymap?.open ?? ""
        enabled: view.shortcutEnabled(sequence, view.selectedFiles.length > 0)
        onActivated: view.openSelected()
    }
    Shortcut {
        sequence: view.keymap?.deselect ?? ""
        enabled: view.shortcutEnabled(sequence, view.selectedFiles.length > 0)
        onActivated: view.selectFile("")
    }

    FolderListModel {
        id: folderModel
        folder: Directories.desktop
        showDirs: true
        showFiles: true
        showDotAndDotDot: false
        showHidden: view.cfg.showHidden
        sortField: {
            switch (view.cfg.sortBy) {
            case "date":
                return FolderListModel.Time;
            case "size":
                return FolderListModel.Size;
            case "type":
                return FolderListModel.Type;
            default:
                return FolderListModel.Name;
            }
        }
        onCountChanged: {
            view.rebuildEntries();
            view.scheduleLayout();
        }
        onStatusChanged: if (status === FolderListModel.Ready) {
            view.rebuildEntries();
            view.scheduleLayout();
        }
    }

    ScriptModel {
        id: iconModel
        objectProp: "fileName"
        values: view.fileEntries
    }

    Process {
        id: createProc
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name.length === 0)
                    return;
                const c = view.pendingCreateCell;
                if (c) {
                    if (name !== view.pendingCreateName)
                        DesktopLayout.forget(view.screenName, view.pendingCreateName);
                    DesktopLayout.setCell(view.screenName, name, c.col, c.row);
                }
                view.pendingCreateCell = null;
                view.pendingCreateName = "";
                view.renamingFile = name;
            }
        }
    }

    Process {
        id: pasteProc
        command: ["bash", "-c", 'c=$(wl-paste --no-newline --type application/x-kde-cutselection 2>/dev/null); printf "CUT:%s\\n" "$c"; wl-paste --no-newline --type text/uri-list 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: view.onClipboardRead(text)
        }
    }

    Process {
        id: openWithProc
        property string targetPath: ""
        command: ["bash", "-c", 'mime=$(xdg-mime query filetype "$0"); case "$mime" in inode/x-empty|application/x-zerosize) mime=$(python3 -c "import sys, gi; from gi.repository import Gio; print(Gio.content_type_guess(sys.argv[1], None)[0])" "$0");; esac; gio mime "$mime" 2>/dev/null', openWithProc.targetPath]
        stdout: StdioCollector {
            onStreamFinished: view.populateOpenWith(text)
        }
    }

    MouseArea {
        id: bgMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            view.clicked = true;
            DesktopWidgets.releaseEditing();
            if (mouse.button === Qt.RightButton) {
                view.openEmptyMenu(mouse.x, mouse.y);
            } else {
                view.bandStartX = mouse.x;
                view.bandStartY = mouse.y;
                view.banding = false;
                if (view.renamingFile.length > 0)
                    view.cancelRename();
            }
        }
        onPositionChanged: mouse => {
            if (!pressed || !(mouse.buttons & Qt.LeftButton))
                return;
            if (!view.banding && (Math.abs(mouse.x - view.bandStartX) > 4 || Math.abs(mouse.y - view.bandStartY) > 4)) {
                view.banding = true;
                view.selectedFiles = [];
            }
            if (view.banding)
                view.updateBand(mouse.x, mouse.y);
        }
        onReleased: mouse => {
            if (view.banding)
                view.banding = false;
            else if (mouse.button === Qt.LeftButton)
                view.selectFile("");
        }
    }

    ScriptModel {
        id: widgetModel
        objectProp: "id"
        values: {
            DesktopWidgets.revision;
            return DesktopWidgets.widgetsFor(view.screenName);
        }
    }

    Item {
        id: widgetsLayer
        anchors.fill: parent
        visible: view.showWidgets || DesktopWidgets.editMode

        Repeater {
            model: widgetModel
            delegate: DesktopWidgetChooser {}
        }
    }

    Item {
        id: iconsLayer
        anchors.fill: parent
        visible: view.showIcons

        Repeater {
            id: iconRepeater
            model: iconModel
            delegate: DesktopIcon {
                desktop: view
            }
        }

        Connections {
            target: view
            function onIconRefreshChanged() {
                iconRepeater.model = null;
                Qt.callLater(() => iconRepeater.model = iconModel);
            }
        }
    }

    Rectangle {
        visible: view.banding
        x: view.bandX
        y: view.bandY
        width: view.bandW
        height: view.bandH
        z: 50
        radius: 4
        color: Qt.alpha(Appearance.colors.colPrimary, 0.18)
        border.width: 1
        border.color: Qt.alpha(Appearance.colors.colPrimary, 0.7)
    }

    PanelWindow {
        id: menuWindow
        screen: view.screen
        visible: menu.showing
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:akebonoDesktopMenu"
        WlrLayershell.layer: WlrLayer.Overlay

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        SdfContextMenu {
            id: menu
            anchors.fill: parent
            boundsWidth: view.width
            boundsHeight: view.height
        }
    }

    Item {
        id: dragStack
        x: -10000
        readonly property int fan: 9
        readonly property int shown: view.dragStackEntries.length
        width: view.cellW + Math.max(0, shown - 1) * fan
        height: view.cellH + Math.max(0, shown - 1) * fan

        Repeater {
            model: dragStack.shown
            delegate: Item {
                id: card
                required property int index
                readonly property int ei: dragStack.shown - 1 - index
                x: card.ei * dragStack.fan
                y: card.ei * dragStack.fan
                width: view.cellW
                height: view.cellH

                DirectoryIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    width: view.iconSize
                    height: view.iconSize
                    fileModelData: view.dragStackEntries[card.ei]
                }
            }
        }

        Rectangle {
            visible: view.selectedFiles.length > 1
            z: 100
            width: 22
            height: 22
            radius: height / 2
            color: Appearance.colors.colPrimary
            x: (view.cellW + view.iconSize) / 2 - width / 2
            y: 2

            StyledText {
                anchors.centerIn: parent
                text: view.selectedFiles.length
                color: Appearance.colors.colOnPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    function widgetAt(px, py) {
        const ws = DesktopWidgets.widgetsFor(view.screenName);
        for (let i = ws.length - 1; i >= 0; i--) {
            const w = ws[i];
            const ww = w.w ?? 190;
            const wh = w.h ?? 190;
            if (px >= w.x && px <= w.x + ww && py >= w.y && py <= w.y + wh)
                return w.id;
        }
        return null;
    }

    DropArea {
        anchors.fill: parent
        z: 9999
        onDropped: drop => {
            if (drop.formats.indexOf("application/x-desktop-icon") >= 0) {
                view.repositionFromMarker(drop.getDataAsString("application/x-desktop-icon"), drop.x, drop.y);
                drop.accept();
                return;
            }
            if (!drop.hasUrls)
                return;
            const wid = view.widgetAt(drop.x, drop.y);
            if (wid) {
                const w = DesktopWidgets.get(wid);
                if (w && w.type === "image") {
                    DesktopWidgets.setProp(wid, "source", drop.urls[0].toString());
                    drop.accept();
                    return;
                }
            }
            const paths = drop.urls.map(u => view.urlToLocalPath(u)).filter(p => p.length > 0);
            if (paths.length === 0)
                return;
            drop.acceptProposedAction();
            view.beginDrop(paths, drop.x, drop.y);
        }
    }
}
