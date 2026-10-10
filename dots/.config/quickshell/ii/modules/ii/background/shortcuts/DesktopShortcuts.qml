pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Qt.labs.folderlistmodel
import qs.services
import qs.modules.common

Singleton {
    id: root

    readonly property string desktopFolder: Directories.desktopPath
    property var pendingPlacements: ({})
    // Set by the menu's New folder / New document: the item the scan places
    // next is announced so the layer opens its rename at once.
    property var renameOnCreate: null
    signal createdForRename(string screenName, string itemId)
    // Something on the desktop was opened: the layers drop their selection,
    // so the opened icon is not left highlighted under the new window.
    signal launched(string itemId)
    // The icons' hover and selection plates, per screen, in screen pixels.
    // The layer publishes them and the wallpaper surface draws them: the
    // widgets surface is compositor-blurred behind anything translucent.
    property var plates: ({})
    function setPlates(screenName, list) {
        const next = Object.assign({}, root.plates);
        next[screenName] = list;
        root.plates = next;
    }
    property var actionQueue: []

    // Decode only when persisted state changes, not on pointer movement or per icon.
    readonly property var screens: {
        try {
            const value = JSON.parse(Persistent.states.desktopShortcutsJson);
            return value && typeof value === "object" && !Array.isArray(value) ? value : {};
        } catch (error) {
            console.warn("[DesktopShortcuts] Invalid persisted data:", error);
            return {};
        }
    }
    property string error: ""
    property var importQueue: []
    property var currentImport: null
    // Folder path → up to four images drawn on its icon (Dolphin's folder
    // thumbnails), from the last scan. Not persisted.
    property var folderPreviews: ({})

    // ── Desktop Folder Watcher & Scanner ───────────────────────────────────
    FolderListModel {
        id: desktopWatcher
        folder: root.desktopFolder ? ("file://" + root.desktopFolder) : ""
        showDirs: true
        showFiles: true
        showHidden: false
        showDotAndDotDot: false
        onCountChanged: scanDebounce.restart()
        onRowsInserted: scanDebounce.restart()
        onRowsRemoved: scanDebounce.restart()
        onDataChanged: scanDebounce.restart()
    }

    Timer {
        id: scanDebounce
        interval: 150
        onTriggered: root.scanDesktop()
    }

    function scanDesktop() {
        if (!Persistent.ready)
            return;
        if (scanner.running)
            return;
        scanner.command = ["/usr/bin/python3", Directories.scriptPath + "/desktop_shortcuts.py",
            "scan", root.desktopFolder];
        scanner.running = true;
    }

    Process {
        id: scanner
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (Array.isArray(result.items))
                        root.syncFromDisk(result.items);
                } catch (error) {
                    console.warn("[DesktopShortcuts] Scan parse error:", error);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            scanner.command = [];
        }
    }

    // ── Action Queue & Worker ──────────────────────────────────────────────
    Item {
        id: actionRunner
        function run(cmd) {
            root.actionQueue.push(cmd);
            actionRunner.processNext();
        }
        function processNext() {
            if (actionProc.running || !root.actionQueue.length)
                return;
            const nextCmd = root.actionQueue.shift();
            actionProc.command = nextCmd;
            actionProc.running = true;
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text);
                    if (res && res.oldPath && res.newPath) {
                        const curScreens = Object.assign({}, root.screens);
                        let changed = false;
                        for (const s of Object.keys(curScreens)) {
                            const list = (curScreens[s] || []).map(it => {
                                if (it.path === res.oldPath || it.id === res.oldPath || (it.id && it.id.endsWith(res.oldPath))) {
                                    changed = true;
                                    return Object.assign({}, it, {
                                        id: res.item ? res.item.id : ("file:" + res.newPath),
                                        path: res.newPath,
                                        fileName: res.item ? res.item.fileName : res.newPath.substring(res.newPath.lastIndexOf("/") + 1),
                                        name: res.item ? res.item.name : it.name
                                    });
                                }
                                return it;
                            });
                            if (changed)
                                curScreens[s] = list;
                        }
                        if (changed)
                            root.writeAll(curScreens);
                    } else if (res && res.item && res.item.path) {
                        const fallback = root.pendingPlacements["__new_item__"];
                        if (res.item.name && root.pendingPlacements[res.item.name]) {
                            root.registerPlacement(res.item.path,
                                root.pendingPlacements[res.item.name].screen,
                                root.pendingPlacements[res.item.name].x,
                                root.pendingPlacements[res.item.name].y);
                        } else if (fallback) {
                            root.registerPlacement(res.item.path,
                                fallback.screen,
                                fallback.x,
                                fallback.y);
                        }
                    }
                } catch (e) {}
            }
        }
        onExited: (exitCode, exitStatus) => {
            actionProc.command = [];
            Qt.callLater(() => {
                root.scanDesktop();
                actionRunner.processNext();
            });
        }
    }

    // ── Grid ───────────────────────────────────────────────────────────────
    // One lattice for everything that places an icon. The cell is the
    // spacing preset scaled by the icon size, so a bigger icon takes a
    // bigger cell instead of crowding its neighbours; a second label line
    // adds a row of text to the cell's height. Every coordinate the grid
    // hands out is a multiple of 10, the layer's own snap.
    readonly property var options: Config.options.background.desktopIcons
    readonly property var iconSteps: [0.75, 1, 1.25, 1.5, 1.75, 2]
    readonly property real iconScale: root.iconSteps.includes(Config.options.background.desktopIconScale)
        ? Config.options.background.desktopIconScale : 1
    readonly property real iconSize: Math.round(56 * root.iconScale)
    readonly property real baseCell: root.options.spacing === "compact" ? 80
        : root.options.spacing === "wide" ? 120 : 100
    readonly property real cellWidth: Math.round(root.baseCell * root.iconScale / 10) * 10
    readonly property real cellHeight: root.cellWidth
        + (root.options.labelLines === 2 && root.options.labels !== "never" ? 20 : 0)
    readonly property bool hidden: root.options.hidden ?? false

    function stepIconScale(direction) {
        const steps = root.iconSteps;
        const at = Math.max(0, steps.indexOf(root.iconScale));
        const next = steps[Math.max(0, Math.min(steps.length - 1, at + direction))];
        if (next !== root.iconScale)
            Config.options.background.desktopIconScale = next;
    }
    function setHidden(value) {
        Config.options.background.desktopIcons.hidden = value;
    }

    // ── Icons ──────────────────────────────────────────────────────────────
    // An `icon` field is either a themed icon name or a path to an image file
    // (a person's pick, or a .desktop entry that named one). Only the names
    // go through the icon theme.
    function isIconPath(icon) {
        const value = String(icon ?? "").trim();
        return value.startsWith("/") || value.startsWith("file://") || value.startsWith("~/");
    }
    // What an `icon` draws as, on the tile, the plate and the rows alike. A
    // name that finds nothing takes the caller's `fallback`.
    function iconSource(icon, fallback) {
        const value = String(icon ?? "").trim();
        if (root.isIconPath(value)) {
            if (value.startsWith("file://"))
                return value;
            if (value.startsWith("~/"))
                return "file://" + Directories.home + value.slice(1);
            return "file://" + value;
        }
        return Quickshell.iconPath(value !== "" ? value : fallback, "image-missing");
    }

    // The part of the screen icons are placed in: the margin on every edge,
    // plus the bar's and the dock's edges when `avoidPanels` is on.
    function workArea(screenName) {
        const screen = Quickshell.screens.find(s => s.name === screenName);
        const w = screen?.width ?? 1920;
        const h = screen?.height ?? 1080;
        const m = Math.max(0, root.options.margin ?? 0);
        let top = m, right = m, bottom = m, left = m;
        if (root.options.avoidPanels) {
            if (Config.options.bar.vertical) {
                if (Config.options.bar.bottom)
                    right += Appearance.sizes.verticalBarWidth;
                else
                    left += Appearance.sizes.verticalBarWidth;
            } else if (Config.options.bar.bottom) {
                bottom += Appearance.sizes.barHeight;
            } else {
                top += Appearance.sizes.barHeight;
            }
            if (Config.options.dock?.enable)
                bottom += (Config.options.dock.height ?? 60) + 10;
        }
        const x = Math.ceil(left / 10) * 10;
        const y = Math.ceil(top / 10) * 10;
        const x2 = Math.floor((w - right) / 10) * 10;
        const y2 = Math.floor((h - bottom) / 10) * 10;
        return { x: x, y: y, width: Math.max(root.cellWidth, x2 - x), height: Math.max(root.cellHeight, y2 - y),
            screenWidth: w, screenHeight: h };
    }

    function grid(screenName) {
        const area = root.workArea(screenName);
        const origin = root.options.origin ?? "topLeft";
        return {
            area: area,
            cw: root.cellWidth,
            ch: root.cellHeight,
            cols: Math.max(1, Math.floor(area.width / root.cellWidth)),
            rows: Math.max(1, Math.floor(area.height / root.cellHeight)),
            right: origin === "topRight" || origin === "bottomRight",
            bottom: origin === "bottomLeft" || origin === "bottomRight",
            byColumns: (root.options.flow ?? "columns") !== "rows"
        };
    }
    function cellPos(g, col, row) {
        const x = g.right ? g.area.x + g.area.width - (col + 1) * g.cw : g.area.x + col * g.cw;
        const y = g.bottom ? g.area.y + g.area.height - (row + 1) * g.ch : g.area.y + row * g.ch;
        return {
            x: Math.max(0, Math.min(g.area.screenWidth - g.cw, x)),
            y: Math.max(0, Math.min(g.area.screenHeight - g.ch, y))
        };
    }
    function cellOf(g, x, y) {
        const col = Math.round((g.right ? g.area.x + g.area.width - g.cw - x : x - g.area.x) / g.cw);
        const row = Math.round((g.bottom ? g.area.y + g.area.height - g.ch - y : y - g.area.y) / g.ch);
        return { col: Math.max(0, Math.min(g.cols - 1, col)), row: Math.max(0, Math.min(g.rows - 1, row)) };
    }
    // The i-th cell in fill order: down the first column (or across the
    // first row) from the origin corner. Past the last cell the fill keeps
    // going off the area, where the layer's clamp stacks the overflow.
    function slotCell(g, index) {
        if (g.byColumns)
            return { col: Math.floor(index / g.rows), row: index % g.rows };
        return { col: index % g.cols, row: Math.floor(index / g.cols) };
    }
    function key(cell) {
        return cell.col + ":" + cell.row;
    }
    // The free cell closest to (col, row), by distance; the cell itself
    // when the whole area is taken.
    function nearestFree(g, taken, col, row) {
        let best = null, bestDistance = Infinity;
        for (let c = 0; c < g.cols; ++c) {
            for (let r = 0; r < g.rows; ++r) {
                if (taken.has(c + ":" + r))
                    continue;
                const d = (c - col) * (c - col) * g.cw * g.cw + (r - row) * (r - row) * g.ch * g.ch;
                if (d < bestDistance) {
                    bestDistance = d;
                    best = { col: c, row: r };
                }
            }
        }
        return best ?? { col: col, row: row };
    }
    function firstFree(g, taken) {
        for (let i = 0; i < g.cols * g.rows; ++i) {
            const cell = root.slotCell(g, i);
            if (!taken.has(root.key(cell)))
                return cell;
        }
        return null;
    }
    // The spot nearest (x, y) where a tile overlaps no other: the point
    // itself when it is clear, else the closest edge-to-edge neighbour of
    // whatever blocks it, else the nearest free grid cell.
    function isLocalPath(path) {
        return typeof path === "string" && path.startsWith("/");
    }
    function fileUrl(path) {
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }
    function fits(g, others, x, y) {
        return !others.some(other => Math.abs(x - other.x) < g.cw && Math.abs(y - other.y) < g.ch);
    }
    function freeSpot(g, others, x, y) {
        const clampX = v => Math.max(0, Math.min(g.area.screenWidth - g.cw, Math.round(v)));
        const clampY = v => Math.max(0, Math.min(g.area.screenHeight - g.ch, Math.round(v)));
        const ox = clampX(x), oy = clampY(y);
        if (root.fits(g, others, ox, oy))
            return { x: ox, y: oy };
        let best = null, bestDistance = Infinity;
        const consider = (px, py) => {
            px = clampX(px);
            py = clampY(py);
            const d = (px - ox) * (px - ox) + (py - oy) * (py - oy);
            if (d < bestDistance && root.fits(g, others, px, py)) {
                bestDistance = d;
                best = { x: px, y: py };
            }
        };
        for (const other of others) {
            if (Math.abs(ox - other.x) >= g.cw * 2 || Math.abs(oy - other.y) >= g.ch * 2)
                continue;
            for (const dx of [-1, 0, 1]) {
                for (const dy of [-1, 0, 1]) {
                    if (dx === 0 && dy === 0)
                        continue;
                    consider(dx === 0 ? ox : other.x + dx * g.cw, dy === 0 ? oy : other.y + dy * g.ch);
                }
            }
        }
        if (best)
            return best;
        const want = root.cellOf(g, ox, oy);
        const cell = root.nearestFree(g, root.takenCells(g, others), want.col, want.row);
        return root.cellPos(g, cell.col, cell.row);
    }
    // Moved items resolved one after another against what stays and what
    // has already landed, so a group keeps its shape where it fits.
    function resolveMoved(g, items, movedIds) {
        const moving = new Set(movedIds);
        const placed = items.filter(item => !moving.has(item.id));
        const landed = new Map();
        for (const item of items) {
            if (!moving.has(item.id))
                continue;
            const spot = root.freeSpot(g, placed, item.x, item.y);
            const moved = Object.assign({}, item, spot);
            placed.push(moved);
            landed.set(item.id, moved);
        }
        return items.map(item => landed.get(item.id) ?? item);
    }
    // Where a free-form drop at (x, y) lands, for the layer's ghost.
    function planFreeDrop(screenName, ids, x, y) {
        const g = root.grid(screenName);
        const skip = new Set(ids);
        const spot = root.freeSpot(g, root.itemsFor(screenName).filter(item => !skip.has(item.id)), x, y);
        return { x: spot.x, y: spot.y, bumpId: "", bumpX: 0, bumpY: 0 };
    }

    function takenCells(g, items, exceptIds) {
        const taken = new Set();
        for (const item of items) {
            if (!exceptIds || !exceptIds.has(item.id))
                taken.add(root.key(root.cellOf(g, item.x, item.y)));
        }
        return taken;
    }
    // Put each listed item (in order) on the nearest free cell to where it
    // stands. The rest of the desktop keeps its cells.
    function settle(g, items, ids) {
        const moving = new Set(ids);
        const taken = root.takenCells(g, items, moving);
        const landed = new Map();
        for (const item of items) {
            if (!moving.has(item.id))
                continue;
            const want = root.cellOf(g, item.x, item.y);
            const cell = root.nearestFree(g, taken, want.col, want.row);
            taken.add(root.key(cell));
            landed.set(item.id, root.cellPos(g, cell.col, cell.row));
        }
        return items.map(item => landed.has(item.id) ? Object.assign({}, item, landed.get(item.id)) : item);
    }
    // Lay the items out in the given order, one cell each, from the origin.
    function arrangeList(g, ordered) {
        return ordered.map((item, i) => {
            const cell = root.slotCell(g, i);
            return Object.assign({}, item, root.cellPos(g, cell.col, cell.row));
        });
    }

    // ── Order ──────────────────────────────────────────────────────────────
    readonly property var typeRank: ({ "app": 0, "group": 1, "directory": 2, "file": 3 })
    function useCount(item) {
        if (item.type === "group")
            return (item.apps ?? []).reduce((sum, app) => sum + (app.launchCount ?? 0), item.launchCount ?? 0);
        return item.launchCount ?? 0;
    }
    function extension(item) {
        const name = String(item.path || "");
        const dot = name.lastIndexOf(".");
        return dot > name.lastIndexOf("/") ? name.slice(dot + 1).toLowerCase() : "";
    }
    function sorted(items, by, descending) {
        const label = item => String(item.name || item.id).toLocaleLowerCase();
        const indexed = items.map((item, index) => ({ item: item, index: index }));
        indexed.sort((a, b) => {
            let d = 0;
            if (by === "type") {
                d = (root.typeRank[a.item.type] ?? 0) - (root.typeRank[b.item.type] ?? 0);
                if (d === 0)
                    d = root.extension(a.item).localeCompare(root.extension(b.item));
            } else if (by === "added") {
                d = (a.item.addedAt ?? 0) - (b.item.addedAt ?? 0);
                if (d === 0)
                    d = a.index - b.index;
            } else if (by === "used") {
                // Most used first: the natural reading of the list.
                d = root.useCount(b.item) - root.useCount(a.item);
            }
            if (d === 0)
                d = label(a.item).localeCompare(label(b.item));
            return descending ? -d : d;
        });
        return indexed.map(entry => entry.item);
    }
    // Sort now. Choosing the order already in use flips its direction, the
    // way a column header does.
    function sortBy(screenName, by) {
        if (by === root.options.sortBy)
            Config.options.background.desktopIcons.sortDescending = !root.options.sortDescending;
        else {
            Config.options.background.desktopIcons.sortBy = by;
            Config.options.background.desktopIcons.sortDescending = false;
        }
        const g = root.grid(screenName);
        root.save(screenName, root.arrangeList(g, root.sorted(root.itemsFor(screenName),
            root.options.sortBy, root.options.sortDescending)));
    }
    function setKeepSorted(value) {
        Config.options.background.desktopIcons.keepSorted = value;
        if (value)
            root.renormalizeAll();
    }
    function setAutoArrange(value) {
        Config.options.background.desktopIcons.autoArrange = value;
        if (value)
            root.renormalizeAll();
    }

    // ── Stacks ─────────────────────────────────────────────────────────────
    // With stacks on, every loose app, folder and file lives in its kind's
    // stack: a group entry marked `stack`, opened by the same popup as any
    // app group. User-made groups stay as they are. Turning stacks off
    // hands the members back to the desktop around their stack.
    function stackName(kind) {
        return kind === "directory" ? Translation.tr("Folders")
            : kind === "file" ? Translation.tr("Files") : Translation.tr("Apps");
    }
    function stackIcon(kind) {
        return kind === "directory" ? "folder" : kind === "file" ? "text-x-generic" : "folder-applications";
    }
    function stackify(items) {
        const stacks = new Map();
        const out = [];
        for (const item of items) {
            if (item.type === "group" && item.stack) {
                const copy = Object.assign({}, item, { apps: (item.apps ?? []).slice() });
                stacks.set(item.stack, copy);
                out.push(copy);
            }
        }
        for (const item of items) {
            if (item.type === "group")
                continue;
            const kind = item.type === "directory" || item.type === "file" ? item.type : "app";
            let stack = stacks.get(kind);
            if (!stack) {
                stack = { id: "stack:" + kind, type: "group", stack: kind, name: root.stackName(kind),
                    icon: root.stackIcon(kind), apps: [], x: item.x, y: item.y, addedAt: Date.now() };
                stacks.set(kind, stack);
                out.push(stack);
            }
            if (!stack.apps.some(app => app.id === item.id))
                stack.apps.push(item);
        }
        return out.filter(item => !(item.type === "group" && item.stack) || item.apps.length > 0)
            .concat(items.filter(item => item.type === "group" && !item.stack));
    }
    function unstack(g, items) {
        let out = items.filter(item => !(item.type === "group" && item.stack));
        for (const stack of items.filter(item => item.type === "group" && item.stack)) {
            const taken = root.takenCells(g, out);
            const home = root.cellOf(g, stack.x, stack.y);
            for (const member of stack.apps ?? []) {
                const cell = root.nearestFree(g, taken, home.col, home.row);
                taken.add(root.key(cell));
                out.push(Object.assign({}, member, root.cellPos(g, cell.col, cell.row)));
            }
        }
        return out;
    }
    function setStacks(value) {
        if ((root.options.stacks ?? false) === value)
            return;
        root.pushUndo();
        Config.options.background.desktopIcons.stacks = value;
        const next = Object.assign({}, root.screens);
        for (const name of Object.keys(next)) {
            const items = root.itemsFor(name);
            next[name] = root.normalize(name, value ? items : root.unstack(root.grid(name), items));
        }
        root.writeAll(next);
    }

    // What every save goes through: stacks absorb their kind, and a kept
    // order is re-applied, so neither has to be remembered by the callers.
    function normalize(screenName, items) {
        let out = items;
        if (root.options.stacks)
            out = root.stackify(out);
        const g = root.grid(screenName);
        if (root.options.keepSorted)
            out = root.arrangeList(g, root.sorted(out, root.options.sortBy, root.options.sortDescending));
        return out;
    }
    function renormalizeAll() {
        const next = Object.assign({}, root.screens);
        for (const name of Object.keys(next)) {
            const items = root.itemsFor(name);
            next[name] = root.options.keepSorted ? root.normalize(name, items)
                : root.settle(root.grid(name), items, items.map(item => item.id));
        }
        root.pushUndo();
        root.writeAll(next);
    }

    // ── Undo ───────────────────────────────────────────────────────────────
    // Snapshots of the whole store, taken before every change a person
    // makes (drags, sorts, arranges, removals); launches and reflows are
    // bookkeeping and never recorded. Session only.
    property var undoStack: []
    readonly property bool canUndo: root.undoStack.length > 0
    function pushUndo() {
        const json = Persistent.states.desktopShortcutsJson;
        if (root.undoStack.length > 0 && root.undoStack[root.undoStack.length - 1] === json)
            return;
        root.undoStack = root.undoStack.concat([json]).slice(-30);
    }
    function undo() {
        if (!root.canUndo || !Persistent.ready || Persistent.blockWrites)
            return;
        const json = root.undoStack[root.undoStack.length - 1];
        root.undoStack = root.undoStack.slice(0, -1);
        Persistent.states.desktopShortcutsJson = json;
    }

    // ── Reflow ─────────────────────────────────────────────────────────────
    // A new cell size scales every layout about its origin corner, then
    // settles whatever the scaling pushed together, so a size change keeps
    // the arrangement the person made instead of piling it up.
    property real lastCellWidth: 0
    property real lastCellHeight: 0
    onCellWidthChanged: Qt.callLater(root.reflow)
    onCellHeightChanged: Qt.callLater(root.reflow)
    // A hot reload builds this singleton with the config already loaded:
    // no ready edge will come, so the size in force is the baseline now.
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.desktopFolder]);
        if (Config.ready) {
            root.lastCellWidth = root.cellWidth;
            root.lastCellHeight = root.cellHeight;
        }
        if (Persistent.ready)
            Qt.callLater(root.scanDesktop);
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.lastCellWidth = 0;
            Qt.callLater(root.reflow);
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready)
                Qt.callLater(root.scanDesktop);
        }
    }
    function reflow() {
        if (!Config.ready || !Persistent.ready)
            return;
        const ow = root.lastCellWidth, oh = root.lastCellHeight;
        root.lastCellWidth = root.cellWidth;
        root.lastCellHeight = root.cellHeight;
        if (ow <= 0 || (ow === root.cellWidth && oh === root.cellHeight))
            return;
        const next = Object.assign({}, root.screens);
        for (const name of Object.keys(next)) {
            const items = root.itemsFor(name);
            if (items.length === 0)
                continue;
            const g = root.grid(name);
            const sx = root.cellWidth / ow, sy = root.cellHeight / oh;
            const ax = g.right ? g.area.x + g.area.width : g.area.x;
            const ay = g.bottom ? g.area.y + g.area.height : g.area.y;
            const scaled = items.map(item => {
                // Measured from the corner's own side of the icon, so the
                // icons nearest the corner stay put.
                const ex = g.right ? item.x + ow : item.x;
                const ey = g.bottom ? item.y + oh : item.y;
                const nx = ax + (ex - ax) * sx - (g.right ? root.cellWidth : 0);
                const ny = ay + (ey - ay) * sy - (g.bottom ? root.cellHeight : 0);
                return Object.assign({}, item, { x: Math.round(nx / 10) * 10, y: Math.round(ny / 10) * 10 });
            });
            next[name] = root.options.keepSorted ? root.normalize(name, scaled)
                : root.settle(g, scaled, scaled.map(item => item.id));
        }
        root.writeAll(next);
    }

    // ── Store ──────────────────────────────────────────────────────────────
    function syncFromDisk(diskItems) {
        if (!Persistent.ready || Persistent.blockWrites)
            return;
        // Kept beside the store, never in it: a folder's contents changing
        // must not rewrite the saved layout.
        const previews = {};
        for (const d of diskItems) {
            if (d.type === "directory" && Array.isArray(d.previews) && d.previews.length > 0)
                previews[d.path] = d.previews;
        }
        if (JSON.stringify(previews) !== JSON.stringify(root.folderPreviews))
            root.folderPreviews = previews;
        const currentScreens = Object.assign({}, root.screens);
        let changed = false;

        const matchedDiskPaths = new Set();
        const nextScreens = {};

        const activeScreenNames = Quickshell.screens.length > 0
            ? Quickshell.screens.map(s => s.name)
            : (Object.keys(currentScreens).length > 0 ? Object.keys(currentScreens) : ["eDP-1"]);

        const allScreenNames = Array.from(new Set(activeScreenNames.concat(Object.keys(currentScreens))));

        for (const sName of allScreenNames) {
            const existing = Array.isArray(currentScreens[sName]) ? currentScreens[sName] : [];
            const kept = [];

            for (const item of existing) {
                if (item.type === "group" && Array.isArray(item.apps)) {
                    const survivingApps = item.apps.filter(app => {
                        const m = diskItems.find(d =>
                            (app.path && d.path && app.path === d.path) ||
                            (app.id && d.id && app.id === d.id) ||
                            (app.fileName && d.fileName && app.fileName === d.fileName) ||
                            (app.path && d.fileName && app.path.endsWith("/" + d.fileName))
                        );
                        if (m)
                            matchedDiskPaths.add(m.path);
                        return !!m;
                    });
                    if (survivingApps.length > 0) {
                        if (survivingApps.length !== item.apps.length)
                            changed = true;
                        kept.push(Object.assign({}, item, { apps: survivingApps }));
                    } else {
                        changed = true;
                    }
                    continue;
                }

                const diskMatch = diskItems.find(d =>
                    (item.path && d.path && item.path === d.path) ||
                    (item.id && d.id && item.id === d.id) ||
                    (item.fileName && d.fileName && item.fileName === d.fileName) ||
                    (item.path && d.fileName && item.path.endsWith("/" + d.fileName))
                );

                if (diskMatch) {
                    matchedDiskPaths.add(diskMatch.path);
                    const updated = Object.assign({}, item, {
                        id: diskMatch.id,
                        name: diskMatch.name,
                        icon: diskMatch.icon,
                        type: diskMatch.type,
                        path: diskMatch.path,
                        fileName: diskMatch.fileName
                    });
                    if (JSON.stringify(updated) !== JSON.stringify(item))
                        changed = true;
                    kept.push(updated);
                } else {
                    changed = true;
                }
            }
            nextScreens[sName] = kept;
        }

        const newItems = diskItems.filter(d => !matchedDiskPaths.has(d.path));
        let created = null;
        if (newItems.length > 0) {
            changed = true;
            const primaryScreen = (Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)?.name)
                || Quickshell.screens[0]?.name
                || allScreenNames[0]
                || "eDP-1";

            for (const newItem of newItems) {
                let px = -1, py = -1;
                let targetScreen = primaryScreen;

                const pendingKey = newItem.path || newItem.fileName;
                const foundPending = root.pendingPlacements[pendingKey]
                    || root.pendingPlacements[newItem.fileName]
                    || (newItem.name ? root.pendingPlacements[newItem.name] : null)
                    || root.pendingPlacements["__new_item__"];
                if (foundPending) {
                    targetScreen = foundPending.screen || primaryScreen;
                    px = foundPending.x;
                    py = foundPending.y;
                    const nextPending = Object.assign({}, root.pendingPlacements);
                    delete nextPending[pendingKey];
                    delete nextPending[newItem.fileName];
                    if (newItem.name)
                        delete nextPending[newItem.name];
                    delete nextPending["__new_item__"];
                    root.pendingPlacements = nextPending;
                }

                if (!nextScreens[targetScreen])
                    nextScreens[targetScreen] = [];

                const targetG = root.grid(targetScreen);
                const taken = root.takenCells(targetG, nextScreens[targetScreen]);

                if (px < 0 || py < 0) {
                    const cell = root.firstFree(targetG, taken) || root.slotCell(targetG, nextScreens[targetScreen].length);
                    const pos = root.cellPos(targetG, cell.col, cell.row);
                    px = pos.x;
                    py = pos.y;
                } else {
                    px = Math.round(px / 10) * 10;
                    py = Math.round(py / 10) * 10;
                    if (root.options.autoArrange) {
                        const want = root.cellOf(targetG, px, py);
                        const cell = root.nearestFree(targetG, taken, want.col, want.row);
                        const pos = root.cellPos(targetG, cell.col, cell.row);
                        px = pos.x;
                        py = pos.y;
                    } else {
                        const spot = root.freeSpot(targetG, nextScreens[targetScreen], px, py);
                        px = spot.x;
                        py = spot.y;
                    }
                }

                const placed = Object.assign({}, newItem, {
                    x: px,
                    y: py,
                    addedAt: Date.now(),
                    launchCount: 0
                });
                nextScreens[targetScreen].push(placed);
                if (foundPending && root.renameOnCreate) {
                    created = { screen: targetScreen, id: placed.id };
                    root.renameOnCreate = null;
                }
            }
        }

        if (changed) {
            for (const sName of Object.keys(nextScreens)) {
                if (root.options.keepSorted)
                    nextScreens[sName] = root.normalize(sName, nextScreens[sName]);
            }
            root.writeAll(nextScreens);
        }
        if (created)
            root.createdForRename(created.screen, created.id);
    }

    function createFolder(screenName, x, y, name = "") {
        Quickshell.execDetached(["mkdir", "-p", root.desktopFolder]);
        root.registerPlacement(name || "New Folder", screenName, x, y);
        root.registerPlacement("__new_item__", screenName, x, y);
        root.renameOnCreate = { screen: screenName };
        actionRunner.run(["/usr/bin/python3", Directories.scriptPath + "/desktop_shortcuts.py",
            "create-folder", root.desktopFolder, name]);
    }

    function createFile(screenName, x, y, name = "") {
        Quickshell.execDetached(["mkdir", "-p", root.desktopFolder]);
        root.registerPlacement(name || "New Document.txt", screenName, x, y);
        root.registerPlacement("__new_item__", screenName, x, y);
        root.renameOnCreate = { screen: screenName };
        actionRunner.run(["/usr/bin/python3", Directories.scriptPath + "/desktop_shortcuts.py",
            "create-file", root.desktopFolder, name]);
    }

    function addDockApps(screenName, appIds, x, y) {
        if (!appIds || !appIds.length)
            return false;
        Quickshell.execDetached(["mkdir", "-p", root.desktopFolder]);
        let curX = Math.round(x / 10) * 10;
        let curY = Math.round(y / 10) * 10;
        for (const appId of appIds) {
            root.registerPlacement(appId, screenName, curX, curY);
            actionRunner.run(["/usr/bin/python3", Directories.scriptPath + "/desktop_shortcuts.py",
                "create-app", root.desktopFolder, appId]);
            curY += root.cellHeight;
        }
        return true;
    }

    function registerPlacement(key, screenName, x, y) {
        const next = Object.assign({}, root.pendingPlacements);
        next[key] = { screen: screenName, x: x, y: y };
        root.pendingPlacements = next;
    }

    function openDesktopFolder() {
        Quickshell.execDetached(["mkdir", "-p", root.desktopFolder]);
        Quickshell.execDetached(["xdg-open", root.desktopFolder]);
    }

    // Dropped and pasted files and folders are linked, never copied: the
    // desktop shows them where they live (a dropped project folder was once
    // copied whole, 196 GB, in the background). "copy" and "move" remain
    // for a caller that means them.
    function importUrls(screenName, urls, x, y, targetId, width, height, mode = "link") {
        if (!Persistent.ready || !urls.length)
            return false;
        Quickshell.execDetached(["mkdir", "-p", root.desktopFolder]);
        root.importQueue.push({ screen: screenName, urls: urls, x: x, y: y,
            target: targetId, width: width, height: height, mode: mode });
        root.startImport();
        return true;
    }

    function startImport() {
        if (root.currentImport || !root.importQueue.length)
            return;
        root.error = "";
        root.currentImport = root.importQueue.shift();
        resolver.command = ["/usr/bin/python3", Directories.scriptPath + "/desktop_shortcuts.py",
            "copy-to-desktop", root.desktopFolder, JSON.stringify(root.currentImport.urls),
            root.currentImport.mode ?? "link"];
        resolver.running = true;
    }

    Process {
        id: resolver
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    const request = root.currentImport;
                    root.error = (result.errors || []).join("\n");
                    if (Array.isArray(result.items) && result.items.length > 0) {
                        let curX = request.x;
                        let curY = request.y;
                        for (const it of result.items) {
                            root.registerPlacement(it.path, request.screen, curX, curY);
                            root.registerPlacement(it.fileName, request.screen, curX, curY);
                            curY += root.cellHeight;
                        }
                        root.scanDesktop();
                    }
                } catch (error) {
                    root.error = Translation.tr("Could not import desktop shortcut");
                    console.warn("[DesktopShortcuts]", error);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.error = Translation.tr("Could not import desktop shortcut");
            root.currentImport = null;
            resolver.command = [];
            Qt.callLater(root.startImport);
        }
    }

    function itemsFor(screenName) {
        const items = root.screens[screenName];
        return Array.isArray(items) ? items : [];
    }
    // Screens that hold icons, connected or not, other than this one: the
    // sources "Move icons here" offers after a monitor change.
    function otherScreens(screenName) {
        return Object.keys(root.screens).filter(name => name !== screenName && root.itemsFor(name).length > 0);
    }
    function isConnected(screenName) {
        return Quickshell.screens.some(s => s.name === screenName);
    }

    function writeAll(next) {
        if (!Persistent.ready || Persistent.blockWrites)
            return false;
        Persistent.states.desktopShortcutsJson = JSON.stringify(next);
        return true;
    }
    // `record` false for bookkeeping writes (launch counts), which must not
    // cost the person an undo step.
    function save(screenName, items, record = true) {
        if (!Persistent.ready || Persistent.blockWrites)
            return false;
        if (record)
            root.pushUndo();
        const next = Object.assign({}, root.screens);
        next[screenName] = root.normalize(screenName, items);
        return root.writeAll(next);
    }

    function add(screenName, entries, x, y, targetId, width, height) {
        if (!entries || !entries.length)
            return false;
        const appEntries = entries.filter(e => e.type === "app" && !e.path);
        if (appEntries.length > 0)
            return root.addDockApps(screenName, appEntries.map(e => e.id), x, y);

        const outsideEntries = entries.filter(e => e.path && !e.path.startsWith(root.desktopFolder));
        if (outsideEntries.length > 0)
            return root.importUrls(screenName, outsideEntries.map(e => e.path), x, y, targetId, width, height);

        const items = root.itemsFor(screenName).slice();
        const targetIndex = targetId && entries.every(entry => root.isGroupable(entry))
            ? items.findIndex(item => item.id === targetId && root.isGroupable(item)) : -1;
        if (targetIndex >= 0) {
            const target = items[targetIndex];
            const apps = target.type === "group" ? target.apps.slice() : [target];
            for (const entry of entries) {
                if (!root.isGroupable(entry))
                    continue;
                for (const app of entry.type === "group" ? entry.apps : [entry]) {
                    if (!apps.some(existing => existing.id === app.id))
                        apps.push(app);
                }
            }
            items[targetIndex] = { id: target.type === "group" ? target.id : "group:" + Date.now(),
                type: "group", name: target.type === "group" ? target.name : Translation.tr("App group"),
                apps: apps, x: target.x, y: target.y, addedAt: target.addedAt ?? Date.now() };
        } else {
            const g = root.grid(screenName);
            const cw = g.cw, ch = g.ch;
            const maxX = Math.max(0, (width || g.area.screenWidth) - cw);
            const maxY = Math.max(0, (height || g.area.screenHeight) - ch);
            const now = Date.now();
            for (const entry of entries) {
                if (items.some(item => item.id === entry.id))
                    continue;
                let px = Math.max(0, Math.min(maxX, Math.round(x / 10) * 10));
                let py = Math.max(0, Math.min(maxY, Math.round(y / 10) * 10));
                const taken = root.takenCells(g, items);
                if (root.options.autoArrange) {
                    const want = root.cellOf(g, px, py);
                    const cell = root.nearestFree(g, taken, want.col, want.row);
                    const p = root.cellPos(g, cell.col, cell.row);
                    px = p.x;
                    py = p.y;
                } else if (items.some(item => Math.abs(item.x - px) < cw && Math.abs(item.y - py) < ch)) {
                    const cell = root.firstFree(g, taken);
                    if (!cell) {
                        root.error = Translation.tr("No free space for desktop shortcuts");
                        break;
                    }
                    const p = root.cellPos(g, cell.col, cell.row);
                    px = p.x;
                    py = p.y;
                }
                items.push(Object.assign({}, entry, { x: px, y: py, addedAt: entry.addedAt ?? now }));
            }
        }
        return root.save(screenName, items);
    }

    // A person's drag. It says where this icon goes, so a kept order steps
    // aside for it; with autoArrange the icon lands on the nearest free
    // cell (planDrop has already chosen it and the neighbour it bumps).
    function releaseKeptOrder() {
        if (root.options.keepSorted)
            Config.options.background.desktopIcons.keepSorted = false;
    }
    function move(screenName, itemId, x, y, targetId) {
        const items = root.itemsFor(screenName);
        const source = items.find(item => item.id === itemId);
        if (!source)
            return;
        const target = items.find(item => item.id === targetId && item.id !== itemId && root.isGroupable(item));
        if (target && root.isGroupable(source)) {
            const apps = target.type === "group" ? target.apps.slice() : [target];
            for (const app of source.type === "group" ? source.apps : [source]) {
                if (!apps.some(existing => existing.id === app.id))
                    apps.push(app);
            }
            root.save(screenName, items.filter(item => item.id !== itemId).map(item => item.id === target.id
                ? { id: target.type === "group" ? target.id : "group:" + Date.now(), type: "group",
                    name: target.type === "group" ? target.name : Translation.tr("App group"),
                    apps: apps, x: target.x, y: target.y, addedAt: target.addedAt ?? Date.now() } : item));
        } else {
            root.releaseKeptOrder();
            let next = items.map(item => item.id === itemId
                ? Object.assign({}, item, { x: Math.round(x), y: Math.round(y) }) : item);
            if (!root.options.autoArrange)
                next = root.resolveMoved(root.grid(screenName), next, [itemId]);
            else {
                const plan = root.planDrop(screenName, itemId, x, y);
                next = items.map(item => item.id === itemId ? Object.assign({}, item, { x: plan.x, y: plan.y })
                    : item.id === plan.bumpId ? Object.assign({}, item, { x: plan.bumpX, y: plan.bumpY }) : item);
            }
            root.save(screenName, next);
        }
    }
    // Where a drop at (x, y) lands with autoArrange: the cell under the
    // icon, and when that cell is taken, the neighbour's way out - the
    // nearest free cell, where the dragged icon's old cell counts as free.
    function planDrop(screenName, itemId, x, y) {
        const g = root.grid(screenName);
        const items = root.itemsFor(screenName);
        const cell = root.cellOf(g, x, y);
        const p = root.cellPos(g, cell.col, cell.row);
        const plan = { x: p.x, y: p.y, bumpId: "", bumpX: 0, bumpY: 0 };
        const occupant = items.find(item => item.id !== itemId
            && root.key(root.cellOf(g, item.x, item.y)) === root.key(cell));
        if (occupant) {
            const taken = root.takenCells(g, items, new Set([itemId, occupant.id]));
            taken.add(root.key(cell));
            const out = root.nearestFree(g, taken, cell.col, cell.row);
            const q = root.cellPos(g, out.col, out.row);
            plan.bumpId = occupant.id;
            plan.bumpX = q.x;
            plan.bumpY = q.y;
        }
        return plan;
    }

    function remove(screenName, itemId) {
        const item = root.itemsFor(screenName).find(i => i.id === itemId);
        const path = item ? (item.path || item.id) : itemId;
        root.save(screenName, root.itemsFor(screenName).filter(item => item.id !== itemId));
        actionRunner.run(["/usr/bin/python3", Directories.scriptPath + "/desktop_shortcuts.py",
            "trash", path]);
    }
    // Bulk forms of the two gestures a multi-selection produces. One save
    // for the whole set: a group move must not write the store per icon.
    function moveMany(screenName, moves) {
        root.releaseKeptOrder();
        const landed = new Map(moves.map(move => [move.id, move]));
        let next = root.itemsFor(screenName).map(item => landed.has(item.id)
            ? Object.assign({}, item, { x: Math.round(landed.get(item.id).x), y: Math.round(landed.get(item.id).y) })
            : item);
        if (root.options.autoArrange)
            next = root.settle(root.grid(screenName), next, moves.map(move => move.id));
        else
            next = root.resolveMoved(root.grid(screenName), next, moves.map(move => move.id));
        root.save(screenName, next);
    }

    function removeMany(screenName, ids) {
        const gone = new Set(ids);
        const items = root.itemsFor(screenName);
        const toTrash = items.filter(i => gone.has(i.id)).map(i => i.path || i.id);
        root.save(screenName, root.itemsFor(screenName).filter(item => !gone.has(item.id)));
        for (const p of toTrash) {
            actionRunner.run(["/usr/bin/python3", Directories.scriptPath + "/desktop_shortcuts.py",
                "trash", p]);
        }
    }
    // "Align to grid": every icon onto the nearest free cell of the grid,
    // in reading order from the origin, so the set keeps its shape and
    // collisions go to the nearest room rather than a corner.
    function alignToGrid(screenName) {
        const g = root.grid(screenName);
        const items = root.itemsFor(screenName).slice()
            .sort((a, b) => (a.y - b.y) || (a.x - b.x));
        if (items.length === 0)
            return;
        root.releaseKeptOrder();
        root.save(screenName, root.settle(g, items, items.map(item => item.id)));
    }

    // ── Selection ──────────────────────────────────────────────────────────
    // Align: onto one line, along the chosen edge or centre. Icons the line
    // would pile up step along it, one cell at a time, to the next free spot.
    function alignSelection(screenName, ids, mode) {
        root.releaseKeptOrder();
        const g = root.grid(screenName);
        const items = root.itemsFor(screenName);
        const picked = new Set(ids);
        const chosen = items.filter(item => picked.has(item.id));
        if (chosen.length < 2)
            return;
        const minX = Math.min(...chosen.map(i => i.x)), maxX = Math.max(...chosen.map(i => i.x));
        const minY = Math.min(...chosen.map(i => i.y)), maxY = Math.max(...chosen.map(i => i.y));
        const vertical = mode === "left" || mode === "hcenter" || mode === "right";
        const line = mode === "left" ? minX : mode === "right" ? maxX
            : mode === "hcenter" ? Math.round((minX + maxX) / 20) * 10
            : mode === "top" ? minY : mode === "bottom" ? maxY : Math.round((minY + maxY) / 20) * 10;
        const order = chosen.slice().sort((a, b) => vertical ? (a.y - b.y) || (a.x - b.x) : (a.x - b.x) || (a.y - b.y));
        const others = items.filter(item => !picked.has(item.id));
        const placed = [];
        const clash = (x, y) => others.concat(placed).some(o => Math.abs(o.x - x) < g.cw && Math.abs(o.y - y) < g.ch);
        const landed = new Map();
        for (const item of order) {
            let x = vertical ? line : item.x;
            let y = vertical ? item.y : line;
            let guard = 0;
            while (clash(x, y) && guard++ < 200) {
                if (vertical)
                    y += g.ch;
                else
                    x += g.cw;
            }
            placed.push({ x: x, y: y });
            landed.set(item.id, { x: x, y: y });
        }
        root.save(screenName, items.map(item => landed.has(item.id) ? Object.assign({}, item, landed.get(item.id)) : item));
    }
    // Distribute: the two outermost stay, the rest spread evenly between
    // them - at least a cell apart, so a tight cluster opens up instead.
    function distributeSelection(screenName, ids, axis) {
        root.releaseKeptOrder();
        const items = root.itemsFor(screenName);
        const picked = new Set(ids);
        const chosen = items.filter(item => picked.has(item.id))
            .sort((a, b) => axis === "horizontal" ? (a.x - b.x) : (a.y - b.y));
        if (chosen.length < 2)
            return;
        const first = chosen[0], last = chosen[chosen.length - 1];
        const span = axis === "horizontal" ? last.x - first.x : last.y - first.y;
        const cell = axis === "horizontal" ? root.cellWidth : root.cellHeight;
        const step = Math.max(cell, span / (chosen.length - 1));
        const landed = new Map();
        chosen.forEach((item, i) => {
            const v = Math.round(((axis === "horizontal" ? first.x : first.y) + i * step) / 10) * 10;
            landed.set(item.id, axis === "horizontal" ? { x: v, y: item.y } : { x: item.x, y: v });
        });
        root.save(screenName, items.map(item => landed.has(item.id) ? Object.assign({}, item, landed.get(item.id)) : item));
    }
    // Stack: one column (or row) from the selection's first icon, in
    // reading order, stepping over cells other icons hold.
    function stackSelection(screenName, ids, axis) {
        root.releaseKeptOrder();
        const g = root.grid(screenName);
        const items = root.itemsFor(screenName);
        const picked = new Set(ids);
        const chosen = items.filter(item => picked.has(item.id))
            .sort((a, b) => axis === "column" ? (a.x - b.x) || (a.y - b.y) : (a.y - b.y) || (a.x - b.x));
        if (chosen.length < 2)
            return;
        const anchor = chosen.reduce((best, item) => (item.y < best.y || (item.y === best.y && item.x < best.x)) ? item : best, chosen[0]);
        const others = items.filter(item => !picked.has(item.id));
        const clash = (x, y) => others.some(o => Math.abs(o.x - x) < g.cw && Math.abs(o.y - y) < g.ch);
        const landed = new Map();
        let x = anchor.x, y = anchor.y;
        for (const item of chosen) {
            let guard = 0;
            while (clash(x, y) && guard++ < 200) {
                if (axis === "column")
                    y += g.ch;
                else
                    x += g.cw;
            }
            landed.set(item.id, { x: x, y: y });
            if (axis === "column")
                y += g.ch;
            else
                x += g.cw;
        }
        root.save(screenName, items.map(item => landed.has(item.id) ? Object.assign({}, item, landed.get(item.id)) : item));
    }
    // Fold the selection's apps (and app groups) into one new group, where
    // the first of them stood. Folders and files are left where they are.
    function groupSelection(screenName, ids) {
        const items = root.itemsFor(screenName);
        const picked = new Set(ids);
        const chosen = items.filter(item => picked.has(item.id) && root.isGroupable(item))
            .sort((a, b) => (a.y - b.y) || (a.x - b.x));
        if (chosen.length < 2)
            return;
        const apps = [];
        for (const item of chosen) {
            for (const app of item.type === "group" ? item.apps : [item]) {
                if (!apps.some(existing => existing.id === app.id))
                    apps.push(app);
            }
        }
        const gone = new Set(chosen.map(item => item.id));
        const group = { id: "group:" + Date.now(), type: "group", name: Translation.tr("App group"),
            apps: apps, x: chosen[0].x, y: chosen[0].y, addedAt: Date.now() };
        root.save(screenName, items.filter(item => !gone.has(item.id)).concat([group]));
    }
    function canGroup(screenName, ids) {
        const picked = new Set(ids);
        return root.itemsFor(screenName).filter(item => picked.has(item.id) && root.isGroupable(item)).length >= 2;
    }

    // ── Screens ────────────────────────────────────────────────────────────
    // Icons are stored per output name; these move them between outputs -
    // onto the first free cells of the target, in their old reading order.
    function moveToScreen(fromScreen, toScreen, ids) {
        if (fromScreen === toScreen)
            return;
        const source = root.itemsFor(fromScreen);
        const moving = new Set(ids ?? source.map(item => item.id));
        const leaving = source.filter(item => moving.has(item.id)).sort((a, b) => (a.y - b.y) || (a.x - b.x));
        if (leaving.length === 0)
            return;
        const g = root.grid(toScreen);
        const target = root.itemsFor(toScreen).filter(item => !moving.has(item.id));
        const taken = root.takenCells(g, target);
        const arrived = [];
        for (const item of leaving) {
            const cell = root.firstFree(g, taken) ?? root.slotCell(g, target.length + arrived.length);
            taken.add(root.key(cell));
            arrived.push(Object.assign({}, item, root.cellPos(g, cell.col, cell.row)));
        }
        root.pushUndo();
        const next = Object.assign({}, root.screens);
        next[fromScreen] = source.filter(item => !moving.has(item.id));
        next[toScreen] = root.normalize(toScreen, target.concat(arrived));
        root.writeAll(next);
    }

    function rename(screenName, itemId, name) {
        if (!name.trim())
            return;
        const newName = name.trim();
        const item = root.itemsFor(screenName).find(i => i.id === itemId);
        const targetId = item ? (item.path || item.id) : itemId;
        if (item)
            root.registerPlacement(newName, screenName, item.x, item.y);
        root.save(screenName, root.itemsFor(screenName).map(i => i.id === itemId
            ? Object.assign({}, i, { name: newName }) : i));
        actionRunner.run(["/usr/bin/python3", Directories.scriptPath + "/desktop_shortcuts.py",
            "rename", root.desktopFolder, targetId, newName]);
    }

    // A person's picture for one item, as the path of an image file; "" puts
    // it back on whatever its kind draws (the store drops the field rather
    // than keeping an empty one). How it becomes an image is iconSource().
    function setIcon(screenName, itemId, icon) {
        const value = String(icon ?? "").trim();
        root.save(screenName, root.itemsFor(screenName).map(item => {
            if (item.id !== itemId)
                return item;
            const next = Object.assign({}, item);
            if (value === "")
                delete next.icon;
            else
                next.icon = value;
            return next;
        }));
    }

    function removeMember(screenName, groupId, appId) {
        root.save(screenName, root.itemsFor(screenName).map(item => item.id === groupId
            ? Object.assign({}, item, { apps: item.apps.filter(app => app.id !== appId) }) : item));
    }

    // Dissolve a group: its members return to the desktop as individual
    // tiles, fanning out from the group's own cell.
    function ungroup(screenName, groupId) {
        const g = root.grid(screenName);
        const items = root.itemsFor(screenName);
        const group = items.find(item => item.id === groupId && item.type === "group");
        if (!group)
            return;
        const rest = items.filter(item => item.id !== groupId);
        const taken = root.takenCells(g, rest);
        const home = root.cellOf(g, group.x, group.y);
        const members = (group.apps ?? []).map(app => {
            const cell = root.nearestFree(g, taken, home.col, home.row);
            taken.add(root.key(cell));
            return Object.assign({}, app, root.cellPos(g, cell.col, cell.row));
        });
        root.save(screenName, rest.concat(members));
    }

    function application(appId) {
        const entry = TaskbarApps.getCachedDesktopEntry(appId);
        return entry ? { id: entry.id, type: "app", name: entry.name, icon: entry.icon, path: "" } : null;
    }

    function launch(entry) {
        // Folders and plain files go to the default handler; only .desktop
        // paths are launchable through gio directly. An AppImage has no
        // handler (xdg-open drops it silently), so one marked executable runs
        // itself, as in a file manager; an unmarked one still goes to xdg-open.
        if (entry.type === "file" && /\.appimage$/i.test(entry.path ?? ""))
            Quickshell.execDetached(["sh", "-c", '[ -x "$1" ] && exec "$1"; exec xdg-open "$1"', "sh", entry.path]);
        else if ((entry.type === "directory" || entry.type === "file") && entry.path)
            // Through a link's target, so a linked folder opens where it
            // lives rather than under Desktop/.
            Quickshell.execDetached(["sh", "-c", 'exec xdg-open "$(readlink -f -- "$1")"', "sh", entry.path]);
        else if (entry.path)
            Quickshell.execDetached(["gio", "launch", entry.path]);
        else
            TaskbarApps.getCachedDesktopEntry(entry.id)?.execute();
        root.launched(entry.id);
        Qt.callLater(() => root.countLaunch(entry.id));
    }
    // "Most used" is fed here: the entry, wherever it lives - loose on any
    // screen or inside a group - gets one more launch.
    function countLaunch(itemId) {
        if (!Persistent.ready || Persistent.blockWrites)
            return;
        const bump = item => Object.assign({}, item, { launchCount: (item.launchCount ?? 0) + 1, lastUsed: Date.now() });
        let changed = false;
        const next = {};
        for (const name of Object.keys(root.screens)) {
            next[name] = root.itemsFor(name).map(item => {
                if (item.id === itemId) {
                    changed = true;
                    return bump(item);
                }
                if (item.type === "group" && (item.apps ?? []).some(app => app.id === itemId)) {
                    changed = true;
                    return Object.assign({}, item, { apps: item.apps.map(app => app.id === itemId ? bump(app) : app) });
                }
                return item;
            });
            if (root.options.keepSorted && root.options.sortBy === "used")
                next[name] = root.normalize(name, next[name]);
        }
        if (changed)
            root.writeAll(next);
    }

    // Only apps and groups fold into a group: a folder or a file on the
    // desktop is its own thing, never merge fuel, and a stack takes its
    // members from the stacks rule alone. The layer's targetAt and the
    // guards above share this one rule.
    function isGroupable(item) {
        return item.type !== "directory" && item.type !== "file" && !item.stack;
    }

    // ── Badges ─────────────────────────────────────────────────────────────
    // Running apps, by the dock's own normalized id, and unread counts by
    // app name. Built once per change of the sources, looked up per icon.
    readonly property var runningIds: {
        const ids = new Set();
        for (const app of TaskbarApps.apps) {
            if (app.toplevels.length > 0)
                ids.add(TaskbarApps.normalizeAppId(app.appId));
        }
        return ids;
    }
    readonly property var notificationCounts: {
        const counts = {};
        const groups = Notifications.groupsByAppName ?? {};
        for (const name of Object.keys(groups))
            counts[String(name).toLowerCase()] = groups[name].notifications.length;
        return counts;
    }
    function appKey(item) {
        if (item.type !== "app")
            return "";
        if (item.path)
            return TaskbarApps.normalizeAppId(item.path.substring(item.path.lastIndexOf("/") + 1));
        return TaskbarApps.normalizeAppId(item.id);
    }
    function isRunning(item) {
        if (item.type === "group")
            return (item.apps ?? []).some(app => root.runningIds.has(root.appKey(app)));
        const k = root.appKey(item);
        return k !== "" && root.runningIds.has(k);
    }
    function unreadCount(item) {
        if (item.type === "group")
            return (item.apps ?? []).reduce((sum, app) => sum + root.unreadCount(app), 0);
        if (item.type !== "app")
            return 0;
        const byName = root.notificationCounts[String(item.name ?? "").toLowerCase()] ?? 0;
        if (byName > 0)
            return byName;
        const k = root.appKey(item);
        const tail = k.substring(k.lastIndexOf(".") + 1);
        return root.notificationCounts[k] ?? root.notificationCounts[tail] ?? 0;
    }

    // ── IPC ────────────────────────────────────────────────────────────────
    // For keybinds: `qs -c ii ipc call desktopIcons toggleHidden`.
    IpcHandler {
        target: "desktopIcons"
        function toggleHidden(): void {
            root.setHidden(!root.hidden);
        }
        function refresh(): void {
            root.scanDesktop();
        }
        function newFolder(): void {
            const screen = Hyprland.focusedMonitor?.name ?? (Quickshell.screens[0]?.name ?? "eDP-1");
            root.createFolder(screen, 100, 100);
        }
        function newFile(): void {
            const screen = Hyprland.focusedMonitor?.name ?? (Quickshell.screens[0]?.name ?? "eDP-1");
            root.createFile(screen, 100, 100);
        }
        function openFolder(): void {
            root.openDesktopFolder();
        }
        function sort(by: string): void {
            const screen = Hyprland.focusedMonitor?.name ?? "";
            if (screen !== "")
                root.sortBy(screen, by);
        }
        function align(): void {
            const screen = Hyprland.focusedMonitor?.name ?? "";
            if (screen !== "")
                root.alignToGrid(screen);
        }
        function undo(): void {
            root.undo();
        }
        function biggerIcons(): void {
            root.stepIconScale(1);
        }
        function smallerIcons(): void {
            root.stepIconScale(-1);
        }
    }
}
