pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    readonly property real plateRadius: Appearance.rounding.large
    readonly property real plateInset: -4
    readonly property color colSelected: Appearance.colors.colSecondaryContainer
    readonly property real selectedAlpha: 0.82
    readonly property real focusedAlpha: 0.96
    readonly property color colHover: Appearance.m3colors.m3surfaceContainerHighest
    readonly property real hoverAlpha: 0.42
    readonly property color colGhost: Appearance.colors.colSecondaryContainer
    readonly property real ghostAlpha: 0.5
    readonly property var labelAxes: ({ "wght": 650, "wdth": 92, "ROND": 100 })
    readonly property real labelSize: Math.round(Appearance.font.pixelSize.smaller * Math.max(1, Math.min(1.25, root.iconScale)))
    readonly property real labelLineHeight: 0.92
    readonly property real labelGap: 4
    readonly property int labelLines: (root.options.labelLines ?? 1) === 2 ? 2 : 1
    // The label's slot is reserved for its full line count, so a row of icons
    // stays level whatever each name wraps to, and icon + label sit centred.
    readonly property real labelHeight: Math.ceil(labelMetrics.height * root.labelLineHeight * root.labelLines)
    FontMetrics {
        id: labelMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: root.labelSize
    }
    readonly property real labelShadowOffset: 1
    readonly property real systemDragEdge: 96
    readonly property string dragMimeType: "application/x-ii-desktop-item"

    required property string screenName
    // The grid is the store's (DesktopShortcuts.cellWidth/cellHeight): the
    // spacing preset scaled by the icon size, so a bigger icon takes a
    // bigger cell. Positions keep the 10px snap; every hit-test reads the
    // same two numbers.
    readonly property real cellWidth: DesktopShortcuts.cellWidth
    readonly property real cellHeight: DesktopShortcuts.cellHeight
    readonly property real iconScale: DesktopShortcuts.iconScale
    readonly property real iconSize: DesktopShortcuts.iconSize
    readonly property var options: Config.options.background.desktopIcons
    readonly property bool autoArrange: root.options.autoArrange ?? false
    // A clean desktop: the icons fade out and stop taking input; the store
    // is untouched. Coming back replays the entrance wave.
    readonly property bool iconsHidden: DesktopShortcuts.hidden
    opacity: root.iconsHidden ? 0 : 1
    visible: root.opacity > 0.01
    enabled: !root.iconsHidden
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    onIconsHiddenChanged: {
        if (root.iconsHidden)
            root.clearSelection();
        else {
            root.introWave = true;
            ++root.introEpoch;
        }
    }
    // Bumped to replay the entrance: every tile restarts its own delayed
    // rise, the delay growing with its distance from the top-left, so the
    // desktop fills in as one diagonal wave - the widgets' stagger, per icon.
    property int introEpoch: 0
    // The wave is for arrivals of the whole desktop (the layer's first
    // frame, an unhide); one icon added later rises without waiting its turn.
    property bool introWave: true
    onIntroEpochChanged: {
        root.introWave = true;
        introWaveTimer.restart();
    }
    Timer {
        id: introWaveTimer
        interval: 1000
        running: true
        onTriggered: root.introWave = false
    }
    readonly property var items: DesktopShortcuts.itemsFor(root.screenName)
    readonly property bool dialogOpen: contextDialog.active || groupPopup.active
    property string dropTargetId: ""
    property string contextId: ""
    property point contextPosition: Qt.point(0, 0)
    readonly property var contextEntry: root.items.find(item => item.id === root.contextId) ?? null
    onContextEntryChanged: {
        if (!contextEntry)
            closeContext();
    }
    // ── Multi-selection ────────────────────────────────────────────────────
    // Mirrors the widget canvas's system: the same marquee band (the canvas
    // owns the press on empty desktop and announces the settled rect — a
    // MouseArea of this layer's own would swallow the widgets' marquee),
    // Shift/Ctrl+click to add or drop one icon, a rigid group drag, Delete
    // to take the lot off. Session state only, never persisted, and pruned
    // with the items themselves so a removed icon cannot haunt a halo.
    property var canvas: null
    property var selectedIds: []
    readonly property bool hasSelection: root.selectedIds.length > 0
    // Edit Mode shrinks this whole layer with the desktop, and the
    // background overview scales it too (camera-push holds 1.09 permanently
    // when the overview is always-on). The modal cards — context menu and
    // folder popup — undo the window's NET content scale (the
    // align bar's counter-scale pattern): they are laid out and rasterized
    // in SCREEN pixels, so their text, symbols and icons stay on their
    // native grid and the menu stays readable at any combined scale.
    // Cancelling only the edit shrink left the menu off-grid by the
    // overview's factor — the residual jaggies of the second screenshot.
    // Handed in by the host window; 1 when nothing is applied.
    property real surfaceScale: 1
    readonly property real counterScale: 1 / Math.max(0.2, Math.min(5, root.surfaceScale))
    // Wallpaper brightness, without sampling: matugen picks the scheme FROM
    // the wallpaper's luminance, so the palette itself is the signal. One
    // scalar for the whole layer, re-evaluated only when the theme changes.
    // Rec.709 luma over the color's rgb floats — the same reading the
    // ColorPickerPopup makes; QML colors expose no .hsl in this Qt.
    readonly property bool wallpaperLight: (0.2126 * Appearance.m3colors.m3background.r
        + 0.7152 * Appearance.m3colors.m3background.g
        + 0.0722 * Appearance.m3colors.m3background.b) > 0.55
    // ── Click-to-open ──────────────────────────────────────────────────────
    // Windows/KDE semantics: the first click SELECTS and arms, the second
    // click of the pair opens. One timer for the whole layer (never one per
    // icon), keyed by the armed id — clicking a different icon just
    // re-arms. Qt.styleHints is absent in this runtime, so the window is
    // the conventional 400 ms.
    property string armedId: ""
    readonly property bool iconsLocked: Config.options.background.desktopIconsLocked ?? false
    Timer {
        id: clickTimer
        interval: 400
        onTriggered: root.armedId = ""
    }
    // Which page the next context menu opens on ("" = the action list).
    // F2 sets "rename"; the dialog is built with it, so no page motion
    // plays over what is already the menu's first frame.
    property string contextInitialPage: ""

    function isSelected(id) {
        return root.selectedIds.indexOf(id) !== -1;
    }
    function toggleSelected(id) {
        const next = root.selectedIds.slice();
        const at = next.indexOf(id);
        if (at === -1)
            next.push(id);
        else
            next.splice(at, 1);
        root.selectedIds = next;
    }
    function clearSelection() {
        if (root.selectedIds.length > 0)
            root.selectedIds = [];
    }
    function removeSelection() {
        if (root.selectedIds.length === 0)
            return;
        const ids = root.selectedIds;
        root.clearSelection();
        Qt.callLater(() => DesktopShortcuts.removeMany(root.screenName, ids));
    }

    // Rigid cluster travel: the selection stops where its tightest member
    // would leave the desktop, the widget canvas's own rule. The inputs are
    // settled (grid-snapped) positions, so every bound is a multiple of 10
    // and the clamped delta lands on the lattice without a second snap.
    function groupDelta(ids, dx, dy) {
        let minX = -Infinity, maxX = Infinity, minY = -Infinity, maxY = Infinity;
        for (let i = 0; i < iconModel.count; ++i) {
            const entry = iconModel.get(i).entry;
            if (ids.indexOf(entry.id) === -1)
                continue;
            const s = root.positionAt(entry.x, entry.y);
            minX = Math.max(minX, -s.x);
            maxX = Math.min(maxX, root.width - root.cellWidth - s.x);
            minY = Math.max(minY, -s.y);
            maxY = Math.min(maxY, root.height - root.cellHeight - s.y);
        }
        return Qt.point(Math.max(minX, Math.min(maxX, dx)), Math.max(minY, Math.min(maxY, dy)));
    }

    // Notify-backed so followers re-render from one property write per frame
    // instead of a fresh object per pointer event.
    QtObject {
        id: groupDrag
        property string leaderId: ""
        property var ids: []
        property real dx: 0
        property real dy: 0
        readonly property bool active: leaderId !== ""
    }

    Connections {
        target: root.canvas
        enabled: root.canvas !== null
        function onMarqueeFinished(band) {
            const picked = [];
            for (let i = 0; i < iconModel.count; ++i) {
                const entry = iconModel.get(i).entry;
                const s = root.positionAt(entry.x, entry.y);
                if (s.x < band.x + band.width && s.x + root.cellWidth > band.x
                    && s.y < band.y + band.height && s.y + root.cellHeight > band.y)
                    picked.push(entry.id);
            }
            root.selectedIds = picked;
        }
    }

    // The keys ride the window's OnDemand keyboard (the host holds it while
    // hasSelection is true). When the band picked widgets as well, the canvas
    // holds the focus and Delete stays the widgets' — the context menu's
    // Remove still takes the whole icon selection either way.
    focus: root.hasSelection
    onHasSelectionChanged: {
        if (root.hasSelection)
            root.forceActiveFocus();
    }
    Keys.onEscapePressed: event => {
        if (!root.hasSelection)
            return;
        event.accepted = true;
        root.clearSelection();
    }
    Keys.onPressed: event => {
        // Keys has no Backspace signal, so both delete keys ride the generic
        // one; auto-repeat dropped — a held key is one removal, not a queue.
        if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
            && !event.isAutoRepeat) {
            event.accepted = true;
            root.removeSelection();
        } else if (event.key === Qt.Key_F2 && !event.isAutoRepeat
            && root.selectedIds.length === 1) {
            // Rename the selection: the menu opens straight on its page,
            // at the tile's own centre.
            event.accepted = true;
            const entry = root.items.find(item => item.id === root.selectedIds[0]);
            if (entry) {
                const s = root.positionAt(entry.x, entry.y);
                root.openContext(entry.id, s.x + root.cellWidth / 2,
                    s.y + root.cellHeight / 2, "rename");
            }
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            event.accepted = true;
            root.selectedIds = root.items.map(item => item.id);
        } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
            event.accepted = true;
            if (!event.isAutoRepeat)
                DesktopShortcuts.undo();
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
            || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            // The arrows walk the desktop; Shift keeps what was picked.
            event.accepted = true;
            const dx = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : 0;
            const dy = event.key === Qt.Key_Up ? -1 : event.key === Qt.Key_Down ? 1 : 0;
            const next = root.neighbour(root.focusId, dx, dy);
            if (next === "")
                return;
            if (event.modifiers & Qt.ShiftModifier) {
                if (!root.isSelected(next))
                    root.selectedIds = root.selectedIds.concat([next]);
            } else {
                root.selectedIds = [next];
            }
            root.focusId = next;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
            event.accepted = true;
            const entry = root.items.find(item => item.id === root.focusId);
            if (entry)
                root.openEntry(entry);
        } else if (event.key === Qt.Key_Menu) {
            event.accepted = true;
            const tile = root.tileFor(root.focusId);
            if (tile)
                root.openContext(root.focusId, tile.x + tile.width / 2, tile.y + tile.height / 2);
        } else if (event.text.length === 1 && event.text.trim() !== ""
            && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            event.accepted = true;
            root.typeAhead += event.text.toLocaleLowerCase();
            typeAheadTimer.restart();
            const found = root.findByPrefix(root.typeAhead);
            if (found !== "") {
                root.selectedIds = [found];
                root.focusId = found;
            }
        }
    }

    function openContext(itemId, x, y, initialPage = "") {
        root.closePopup();
        root.contextId = itemId;
        root.contextPosition = Qt.point(x, y);
        root.contextInitialPage = initialPage;
        contextDialog.active = root.contextEntry !== null;
    }

    function closeContext() {
        contextDialog.active = false;
        root.contextId = "";
        root.contextInitialPage = "";
    }

    // ── Group popup ────────────────────────────────────────────────────────
    // A folder's contents on left-click (DesktopShortcutGroupPopup); the
    // context menu keeps right-click. Mutually exclusive with the menu,
    // and closed by the layer itself when the group is gone.
    property string popupId: ""
    property rect popupRect: Qt.rect(0, 0, 0, 0)
    readonly property var popupEntry: root.items.find(item => item.id === root.popupId && item.type === "group") ?? null
    onPopupEntryChanged: {
        if (!popupEntry)
            closePopup();
    }
    function openPopup(itemId, x, y, w, h) {
        root.closeContext();
        root.popupId = itemId;
        root.popupRect = Qt.rect(x, y, w, h);
        groupPopup.active = root.popupEntry !== null;
    }
    function closePopup() {
        groupPopup.active = false;
        root.popupId = "";
    }

    function positionAt(x, y) {
        return Qt.point(Math.max(0, Math.min(width - cellWidth, Math.round(x / 10) * 10)),
                        Math.max(0, Math.min(height - cellHeight, Math.round(y / 10) * 10)));
    }

    // The merge target under (x, y). With autoArrange only the middle of a
    // tile merges: its edges are where a drop pushes the icon aside instead.
    function targetAt(x, y, exceptId) {
        const insetX = root.autoArrange ? root.cellWidth * 0.22 : 0;
        const insetY = root.autoArrange ? root.cellHeight * 0.22 : 0;
        for (let i = 0; i < iconModel.count; ++i) {
            const item = iconModel.get(i).entry;
            const s = root.positionAt(item.x, item.y);
            if (item.id !== exceptId && DesktopShortcuts.isGroupable(item)
                && x >= s.x + insetX && x < s.x + root.cellWidth - insetX
                && y >= s.y + insetY && y < s.y + root.cellHeight - insetY)
                return item.id;
        }
        return "";
    }

    // ── Drag preview ───────────────────────────────────────────────────────
    // With autoArrange a single drag shows where it will land - a cell
    // outline - and the icon holding that cell steps into the one it will
    // be pushed to. Both come from DesktopShortcuts.planDrop, the same
    // function the release commits through.
    property var dragPlan: null
    property string dragId: ""
    onDragPlanChanged: {
        if (!root.dragPlan)
            return;
        dropGhost.snapping = dropGhost.opacity < 0.05;
        dropGhost.x = root.dragPlan.x;
        dropGhost.y = root.dragPlan.y;
        dropGhost.snapping = false;
    }

    // Off the snap grid, a drop onto another icon is answered by the
    // nearest clear spot; the ghost shows it only when that differs.
    function freePlan(tile, pending) {
        const plan = DesktopShortcuts.planFreeDrop(root.screenName, [tile.entry.id], pending.x, pending.y);
        return plan.x !== pending.x || plan.y !== pending.y ? plan : null;
    }

    // ── System drag ────────────────────────────────────────────────────────
    // On the desktop the tile itself follows the pointer. Once the pointer
    // reaches a window or the screen-edge band where the bar, dock and island
    // live, the tile hands over to a real drag (text/uri-list) carrying its
    // own snapshot, so file managers, browsers, the dock and the island take
    // it; the tile hides, so one icon is on screen throughout. Dropped back on
    // a desktop, the DropArea finds the private type and makes it a move.
    function leavesDesktop(p) {
        if (GlobalStates.editMode)
            return false;
        const window = root.Window.window;
        if (!window)
            return false;
        const w = root.mapToItem(null, p.x, p.y);
        const edge = root.systemDragEdge;
        if (w.x < edge || w.y < edge || w.x > window.width - edge || w.y > window.height - edge)
            return true;
        const monitor = (HyprlandData.monitors ?? []).find(m => m.name === root.screenName);
        if (!monitor)
            return false;
        const gx = monitor.x + w.x;
        const gy = monitor.y + w.y;
        const shown = [monitor.activeWorkspace?.id, monitor.specialWorkspace?.id].filter(id => id);
        return (HyprlandData.windowList ?? []).some(c => c.mapped !== false && !c.hidden
            && shown.indexOf(c.workspace?.id) !== -1
            && gx >= c.at[0] && gx < c.at[0] + c.size[0]
            && gy >= c.at[1] && gy < c.at[1] + c.size[1]);
    }
    property Item systemDragTile: null
    property var systemDragIds: []
    property bool systemDropHandled: false
    readonly property bool systemDragging: root.systemDragTile !== null

    function beginSystemDrag(tile) {
        if (tile.systemDrag)
            return;
        const ids = groupDrag.leaderId === tile.entry.id ? groupDrag.ids : [tile.entry.id];
        const urls = [];
        for (const id of ids) {
            const member = root.tileFor(id);
            if (member && member.fileUrl !== "")
                urls.push(member.fileUrl);
        }
        if (tile.fileUrl === "" || urls.length === 0)
            return;
        tile.Drag.mimeData = {
            "text/uri-list": urls.join("\r\n") + "\r\n",
            [root.dragMimeType]: JSON.stringify({ "screen": root.screenName, "ids": ids, "leader": tile.entry.id })
        };
        root.systemDropHandled = false;
        root.systemDragIds = ids;
        root.systemDragTile = tile;
        tile.systemDrag = true;
        tile.Drag.active = true;
    }

    function systemDragMove(p) {
        if (root.systemDragTile)
            root.systemDragTile.dragTo(p);
    }

    // A drop on this screen's desktop: the pointer's last point, then the
    // same commit a release makes.
    function systemDragDrop(p) {
        const tile = root.systemDragTile;
        if (!tile)
            return false;
        tile.dragTo(p);
        tile.finishDrag();
        root.systemDropHandled = true;
        return true;
    }

    function endSystemDrag(tile, dropAction) {
        if (!root.systemDropHandled)
            tile.cancelDrag();
        tile.systemDrag = false;
        tile.Drag.active = false;
        root.systemDragTile = null;
        root.systemDragIds = [];
        root.systemDropHandled = false;
    }

    // New folder / New document land straight in their rename, at the tile.
    property string renameWhenPlaced: ""
    function openPendingRename() {
        const entry = root.items.find(item => item.id === root.renameWhenPlaced);
        if (!entry)
            return;
        root.renameWhenPlaced = "";
        const s = root.positionAt(entry.x, entry.y);
        root.selectedIds = [entry.id];
        root.openContext(entry.id, s.x + root.cellWidth / 2, s.y + root.cellHeight / 2, "rename");
    }
    Connections {
        target: DesktopShortcuts
        function onCreatedForRename(screenName, itemId) {
            if (screenName !== root.screenName)
                return;
            root.renameWhenPlaced = itemId;
            Qt.callLater(root.openPendingRename);
        }
    }

    // ── Plates on the wallpaper ────────────────────────────────────────────
    // Hover, selection and the landing ghost are drawn by DesktopIconPlates on
    // the wallpaper surface, which is never blurred, whenever this layer sits
    // 1:1 on the screen; Edit Mode and a scaled overview keep them here.
    readonly property bool platesOnWallpaper: !GlobalStates.editMode
        && Math.abs(root.surfaceScale - 1) < 0.001 && root.visible
    readonly property var plateEntries: {
        if (!root.platesOnWallpaper)
            return [];
        const out = [];
        const inset = root.plateInset;
        const push = (id, x, y, kind) => {
            const p = root.mapToItem(null, x + inset, y + inset);
            out.push({ "id": id, "x": p.x, "y": p.y, "w": root.cellWidth - inset * 2, "h": root.cellHeight - inset * 2, "kind": kind });
        };
        for (let i = 0; i < iconRepeater.count; ++i) {
            const tile = iconRepeater.itemAt(i);
            if (!tile || root.systemDragIds.indexOf(tile.entry.id) !== -1 || tile.intro < 1)
                continue;
            const follow = tile.dragging ? Qt.point(tile.pending.x - tile.x, tile.pending.y - tile.y)
                : tile.groupMember ? Qt.point(groupDrag.dx, groupDrag.dy) : Qt.point(0, 0);
            if (tile.selected)
                push(tile.entry.id, tile.x + follow.x, tile.y + follow.y,
                    root.focusId === tile.entry.id && root.selectedIds.length > 1 ? "focus" : "selected");
            else if (tile.hovered && !tile.dragging && root.dropTargetId !== tile.entry.id)
                push(tile.entry.id, tile.x, tile.y, "hover");
        }
        if (dropGhost.shown)
            push("__ghost__", dropGhost.x, dropGhost.y, "ghost");
        return out;
    }
    onPlateEntriesChanged: DesktopShortcuts.setPlates(root.screenName, root.plateEntries)
    Component.onDestruction: DesktopShortcuts.setPlates(root.screenName, [])

    // ── Keyboard ───────────────────────────────────────────────────────────
    // The icon the arrows walk from: the last one clicked or reached.
    property string focusId: ""
    onSelectedIdsChanged: {
        if (root.selectedIds.length === 0)
            root.focusId = "";
        else if (root.selectedIds.indexOf(root.focusId) === -1)
            root.focusId = root.selectedIds[root.selectedIds.length - 1];
    }
    // The nearest icon in a direction, weighting the sideways distance
    // double so the walk keeps to its row or column.
    function neighbour(fromId, dx, dy) {
        const from = root.items.find(item => item.id === fromId);
        if (!from)
            return root.items.length > 0 ? root.items[0].id : "";
        const a = root.positionAt(from.x, from.y);
        let best = "", bestScore = Infinity;
        for (const item of root.items) {
            if (item.id === fromId)
                continue;
            const b = root.positionAt(item.x, item.y);
            const along = dx !== 0 ? (b.x - a.x) * dx : (b.y - a.y) * dy;
            const across = dx !== 0 ? Math.abs(b.y - a.y) : Math.abs(b.x - a.x);
            if (along <= 0)
                continue;
            const score = along + across * 2;
            if (score < bestScore) {
                bestScore = score;
                best = item.id;
            }
        }
        return best;
    }
    function openEntry(entry) {
        const tile = root.tileFor(entry.id);
        if (entry.type === "group" && tile)
            root.openPopup(entry.id, tile.x, tile.y, tile.width, tile.height);
        else
            DesktopShortcuts.launch(entry);
    }
    function tileFor(id) {
        for (let i = 0; i < iconRepeater.count; ++i) {
            const tile = iconRepeater.itemAt(i);
            if (tile && tile.entry.id === id)
                return tile;
        }
        return null;
    }
    // Type to find: letters typed within a beat of each other build one
    // prefix; a repeated single letter cycles through the icons it starts.
    property string typeAhead: ""
    Timer {
        id: typeAheadTimer
        interval: 900
        onTriggered: root.typeAhead = ""
    }
    function findByPrefix(text) {
        const label = item => String(item.name || item.id).toLocaleLowerCase();
        const ordered = root.items.slice().sort((a, b) => (a.y - b.y) || (a.x - b.x));
        const matches = ordered.filter(item => label(item).startsWith(text));
        if (matches.length === 0)
            return "";
        const repeat = text.length > 1 && text.split("").every(c => c === text[0]);
        if (repeat) {
            const single = ordered.filter(item => label(item).startsWith(text[0]));
            const at = single.findIndex(item => item.id === root.focusId);
            return single[(at + 1) % single.length].id;
        }
        return matches[0].id;
    }

    // ── Quick size ─────────────────────────────────────────────────────────
    // Ctrl + wheel anywhere on the desktop steps the icon size, one notch
    // per step; a touchpad's small deltas are summed into notches.
    property real wheelAccum: 0
    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            root.wheelAccum += event.angleDelta.y;
            while (Math.abs(root.wheelAccum) >= 120) {
                DesktopShortcuts.stepIconScale(root.wheelAccum > 0 ? 1 : -1);
                root.wheelAccum -= root.wheelAccum > 0 ? 120 : -120;
            }
        }
    }

    // Preserve delegates on rename/move/member edits; never rebuild the whole desktop.
    function sync() {
        const wanted = new Set(root.items.map(item => item.id));
        if (root.selectedIds.some(id => !wanted.has(id)))
            root.selectedIds = root.selectedIds.filter(id => wanted.has(id));
        for (let i = iconModel.count - 1; i >= 0; --i) {
            if (!wanted.has(iconModel.get(i).entry.id))
                iconModel.remove(i);
        }
        for (let i = 0; i < root.items.length; ++i) {
            const entry = root.items[i];
            let found = -1;
            for (let j = i; j < iconModel.count; ++j) {
                if (iconModel.get(j).entry.id === entry.id) {
                    found = j;
                    break;
                }
            }
            const encoded = JSON.stringify(entry);
            if (found < 0)
                iconModel.insert(i, { entry: entry, encoded: encoded, mergePulse: 0 });
            else {
                if (found !== i)
                    iconModel.move(found, i, 1);
                if (iconModel.get(i).encoded !== encoded) {
                    const prev = iconModel.get(i).entry;
                    iconModel.setProperty(i, "entry", entry);
                    iconModel.setProperty(i, "encoded", encoded);
                    // The swallow landed here: the group grew. One pulse
                    // drives the target's pop — a role write, not a signal
                    // hunt, so the delegate animates exactly once per merge.
                    if (entry.type === "group"
                        && entry.apps.length > (prev.type === "group" ? prev.apps.length : 1))
                        iconModel.setProperty(i, "mergePulse", iconModel.get(i).mergePulse + 1);
                }
            }
        }
    }
    onItemsChanged: sync()
    Component.onCompleted: sync()
    ListModel { id: iconModel; dynamicRoles: true }

    onVisibleChanged: {
        if (!visible) {
            closeContext();
            closePopup();
            root.clearSelection();
        }
    }

    // The landing spot of a single autoArrange drag.
    Rectangle {
        id: dropGhost
        readonly property bool shown: root.dragPlan !== null
        // Placed by onDragPlanChanged: it keeps its last cell while fading
        // out, and jumps (rather than slides) to the first one of a drag.
        property bool snapping: false
        width: root.cellWidth
        height: root.cellHeight
        radius: root.plateRadius
        color: Qt.alpha(root.colGhost, root.ghostAlpha)
        opacity: dropGhost.shown && !root.platesOnWallpaper ? 1 : 0
        visible: opacity > 0.001
        scale: dropGhost.shown ? 1 : 0.9
        Behavior on x {
            enabled: !dropGhost.snapping && !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dropGhost)
        }
        Behavior on y {
            enabled: !dropGhost.snapping && !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dropGhost)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dropGhost)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dropGhost)
        }
    }

    Repeater {
        id: iconRepeater
        model: iconModel
        delegate: Item {
            id: tile
            required property var entry
            required property int mergePulse
            readonly property point settled: root.positionAt(entry.x, entry.y)
            property bool dragging: false
            property bool suppressClick: false
            property point pressPoint: Qt.point(0, 0)
            property point origin: Qt.point(0, 0)
            property point pending: Qt.point(0, 0)
            // The swallow: while the absorbed tile animates into its target
            // the store write is still pending — merging gates the gesture
            // and mergeData carries the commit.
            property bool merging: false
            property var mergeData: null
            readonly property bool selected: root.isSelected(entry.id)
            readonly property bool groupMember: groupDrag.active && !tile.dragging
                && entry.id !== groupDrag.leaderId && groupDrag.ids.indexOf(entry.id) !== -1
            readonly property bool hovered: tileHover.hovered

            // ── Motion ─────────────────────────────────────────────────────
            // The tile is drawn at its stored cell plus an offset that glides
            // to rest. Whenever the cell changes - a sort, an align, a drop,
            // a reflow - the offset is re-based so the tile starts from where
            // it was on screen and travels to the new cell instead of
            // teleporting. The rest is 0, or the bump preview's step aside.
            property real offX: 0
            property real offY: 0
            property point prevSettled: Qt.point(0, 0)
            property bool placed: false
            readonly property bool bumped: root.dragPlan !== null && root.dragPlan.bumpId === tile.entry.id
            readonly property real restX: tile.bumped ? root.dragPlan.bumpX - tile.settled.x : 0
            readonly property real restY: tile.bumped ? root.dragPlan.bumpY - tile.settled.y : 0
            function glide() {
                glideMotion.stop();
                if (Appearance.reducedMotion || (tile.offX === tile.restX && tile.offY === tile.restY)) {
                    tile.offX = tile.restX;
                    tile.offY = tile.restY;
                    return;
                }
                glideX.to = tile.restX;
                glideY.to = tile.restY;
                glideMotion.start();
            }
            // Hold the tile where it is now (screen position), then glide.
            function holdAt(screenX, screenY) {
                glideMotion.stop();
                tile.offX = screenX - tile.settled.x;
                tile.offY = screenY - tile.settled.y;
                tile.glide();
            }
            onSettledChanged: {
                if (!tile.placed)
                    return;
                const fromX = tile.prevSettled.x + tile.offX;
                const fromY = tile.prevSettled.y + tile.offY;
                tile.prevSettled = tile.settled;
                tile.holdAt(fromX, fromY);
            }
            onRestXChanged: tile.glide()
            onRestYChanged: tile.glide()
            ParallelAnimation {
                id: glideMotion
                NumberAnimation {
                    id: glideX
                    target: tile; property: "offX"
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
                NumberAnimation {
                    id: glideY
                    target: tile; property: "offY"
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            x: settled.x + offX
            y: settled.y + offY
            width: root.cellWidth
            height: root.cellHeight
            z: dragging || merging ? 2 : (glideMotion.running ? 1 : 0)

            // ── Entrance ───────────────────────────────────────────────────
            // A rise and fade, delayed by the tile's distance from the
            // top-left in cells: the whole desktop arrives as one wave.
            property real intro: Appearance.reducedMotion ? 1 : 0
            function replayIntro() {
                if (Appearance.reducedMotion) {
                    tile.intro = 1;
                    return;
                }
                introMotion.stop();
                tile.intro = 0;
                introDelay.duration = !root.introWave ? 0 : Math.min(700, 30 * (tile.settled.x / root.cellWidth + tile.settled.y / root.cellHeight));
                introMotion.start();
            }
            Component.onCompleted: {
                tile.prevSettled = tile.settled;
                tile.placed = true;
                tile.replayIntro();
            }
            Connections {
                target: root
                function onIntroEpochChanged() {
                    tile.replayIntro();
                }
            }
            SequentialAnimation {
                id: introMotion
                PauseAnimation { id: introDelay; duration: 0 }
                NumberAnimation {
                    target: tile; property: "intro"; to: 1
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            // The merge physics, one-shot: the leader pops as it swallows
            // (scale 1.1→1 on the eased tail), the absorbed tile shrinks and
            // fades into it (mergeMotion). Both animate tileContent's scale
            // imperatively — the press-dip binding is shadowed while they
            // run and resumes the instant they stop, so hover/press and the
            // merge cannot fight over the property.
            onMergePulseChanged: {
                if (mergePulse > 0)
                    targetPop.restart();
            }
            SequentialAnimation {
                id: targetPop
                NumberAnimation {
                    target: tileContent; property: "scale"; to: 1.1
                    duration: 90; easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: tileContent; property: "scale"; to: 1.0
                    duration: 170; easing.type: Easing.OutCubic
                }
            }
            ParallelAnimation {
                id: mergeMotion
                NumberAnimation {
                    target: tileContent; property: "opacity"; to: 0
                    duration: 150
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                }
                NumberAnimation {
                    target: tileContent; property: "scale"; to: 0.3
                    duration: 150
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                }
                onFinished: {
                    const m = tile.mergeData;
                    tile.merging = false;
                    tile.mergeData = null;
                    if (m)
                        DesktopShortcuts.move(root.screenName, m.id, m.x, m.y, m.target);
                }
            }

            // ── The drag ───────────────────────────────────────────────────
            // One path for the pointer and for a system drag the desktop's
            // own DropArea reports back: `dragTo` follows, `finishDrag`
            // commits, `cancelDrag` puts everything back.
            property bool systemDrag: false
            property url dragImage: ""
            readonly property string fileUrl: DesktopShortcuts.isLocalPath(tile.entry.path) ? DesktopShortcuts.fileUrl(tile.entry.path) : ""

            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
            Drag.proposedAction: Qt.CopyAction
            Drag.imageSource: tile.dragImage
            Drag.hotSpot.x: tile.pressPoint.x - tile.origin.x
            Drag.hotSpot.y: tile.pressPoint.y - tile.origin.y
            Drag.onDragFinished: dropAction => root.endSystemDrag(tile, dropAction)

            function dragTo(p) {
                const dx = p.x - tile.pressPoint.x;
                const dy = p.y - tile.pressPoint.y;
                if (!tile.dragging) {
                    tile.dragging = true;
                    root.dragId = tile.entry.id;
                    if (root.selectedIds.length > 1 && root.isSelected(tile.entry.id)) {
                        // Grabbing a selected tile drags the whole set.
                        groupDrag.leaderId = tile.entry.id;
                        groupDrag.ids = root.selectedIds;
                        groupDrag.dx = 0;
                        groupDrag.dy = 0;
                    } else if (root.hasSelection) {
                        // Grabbing outside the selection is a click-away
                        // (the widget canvas's rule): single drag.
                        root.clearSelection();
                    }
                }
                tile.suppressClick = true;
                tile.pending = root.positionAt(tile.origin.x + dx, tile.origin.y + dy);
                if (groupDrag.leaderId === tile.entry.id) {
                    // Re-clamp the leader's own snapped position to what
                    // the cluster's tightest member allows, so the whole
                    // selection stops at the first wall.
                    const travel = root.groupDelta(groupDrag.ids,
                        tile.pending.x - tile.origin.x, tile.pending.y - tile.origin.y);
                    tile.pending = Qt.point(tile.origin.x + travel.x, tile.origin.y + travel.y);
                    groupDrag.dx = travel.x;
                    groupDrag.dy = travel.y;
                    root.dragPlan = null;
                } else {
                    root.dropTargetId = DesktopShortcuts.isGroupable(tile.entry) ? root.targetAt(p.x, p.y, tile.entry.id) : "";
                    root.dragPlan = root.dropTargetId !== "" ? null
                        : root.autoArrange ? DesktopShortcuts.planDrop(root.screenName, tile.entry.id, tile.pending.x, tile.pending.y)
                        : tile.systemDrag ? null : root.freePlan(tile, tile.pending);
                }
            }

            function finishDrag() {
                if (!tile.dragging)
                    return;
                const itemId = tile.entry.id;
                const targetId = root.dropTargetId;
                const p = tile.pending;
                tile.dragging = false;
                root.dragId = "";
                root.dropTargetId = "";
                root.dragPlan = null;
                if (groupDrag.leaderId === itemId) {
                    // One write for the cluster; merging is a single-drag
                    // gesture, so the group just travels. Every member is
                    // held where it was dropped and glides from there.
                    const ids = groupDrag.ids;
                    const ddx = groupDrag.dx;
                    const ddy = groupDrag.dy;
                    for (const id of ids) {
                        const member = root.tileFor(id);
                        if (member)
                            member.holdAt(member.settled.x + ddx, member.settled.y + ddy);
                    }
                    groupDrag.leaderId = "";
                    groupDrag.ids = [];
                    groupDrag.dx = 0;
                    groupDrag.dy = 0;
                    if (ddx !== 0 || ddy !== 0) {
                        const moves = [];
                        for (const entry of root.items) {
                            if (ids.indexOf(entry.id) === -1)
                                continue;
                            const s = root.positionAt(entry.x, entry.y);
                            moves.push({ id: entry.id, x: s.x + ddx, y: s.y + ddy });
                        }
                        Qt.callLater(() => DesktopShortcuts.moveMany(root.screenName, moves));
                    }
                    return;
                }
                if (targetId !== "" && DesktopShortcuts.isGroupable(tile.entry)) {
                    // Play the swallow first, commit on its last frame:
                    // the store write destroying an invisible delegate
                    // is what made the old merge read as a teleport.
                    tile.holdAt(p.x, p.y);
                    tile.merging = true;
                    tile.mergeData = { id: itemId, x: p.x, y: p.y, target: targetId };
                    mergeMotion.start();
                    return;
                }
                // Held at the drop point; the store write moves the cell
                // and the tile glides into it.
                tile.holdAt(p.x, p.y);
                Qt.callLater(() => DesktopShortcuts.move(root.screenName, itemId, p.x, p.y, targetId));
            }

            function cancelDrag() {
                if (groupDrag.leaderId === tile.entry.id) {
                    groupDrag.leaderId = "";
                    groupDrag.ids = [];
                    groupDrag.dx = 0;
                    groupDrag.dy = 0;
                }
                tile.dragging = false;
                tile.suppressClick = true;
                root.dragId = "";
                root.dropTargetId = "";
                root.dragPlan = null;
            }

            HoverHandler {
                id: tileHover
            }

            Item {
                id: tileContent
                anchors.fill: parent
                opacity: tile.intro * (root.systemDragIds.indexOf(tile.entry.id) !== -1 ? 0 : 1)
                // Press feedback mirrors RippleButton's interactionScale (dip
                // while held, spring back on release), but at 0.9: a 100px
                // tile at 0.96 moves the icon barely 2px. Suppressed during a
                // drag (the Translate already moves the tile).
                scale: (gesture.pressedButtons & Qt.LeftButton) !== 0
                    && !tile.dragging ? 0.9 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                }
                transform: [
                    Translate {
                        x: root.systemDragging ? 0 : tile.dragging ? tile.pending.x - tile.x : (tile.groupMember ? groupDrag.dx : 0)
                        y: root.systemDragging ? 0 : tile.dragging ? tile.pending.y - tile.y : (tile.groupMember ? groupDrag.dy : 0)
                    },
                    // The entrance's rise.
                    Translate {
                        y: (1 - tile.intro) * 14
                    }
                ]
                // Selection: a filled tonal plate, no outline.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.plateInset
                    radius: root.plateRadius
                    color: Qt.alpha(root.colSelected, root.focusId === tile.entry.id && root.selectedIds.length > 1
                        ? root.focusedAlpha : root.selectedAlpha)
                    opacity: tile.selected && !root.platesOnWallpaper ? 1 : 0
                    visible: opacity > 0.001
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
                // Hover and merge-target plates.
                Rectangle {
                    anchors.fill: parent
                    radius: root.plateRadius
                    color: root.dropTargetId === tile.entry.id ? Appearance.colors.colPrimaryContainer
                        : Qt.alpha(root.colHover, root.hoverAlpha)
                    opacity: root.dropTargetId === tile.entry.id
                        || (tile.hovered && !tile.selected && !tile.dragging && !root.platesOnWallpaper) ? 1 : 0
                    visible: opacity > 0.001
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 4
                    spacing: root.labelGap
                    Item {
                        id: plate
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: root.iconSize
                        Layout.preferredHeight: root.iconSize
                        readonly property string style: root.options.iconBackground ?? "none"
                        readonly property bool shaped: plate.style === "circle" || plate.style === "squircle"
                        // The icon backdrop: a translucent card, or a
                        // palette-tinted circle or squircle the glyph sits in.
                        Rectangle {
                            anchors.fill: parent
                            visible: plate.style !== "none" && tile.entry.type !== "group"
                            radius: plate.style === "circle" ? width / 2
                                : plate.style === "squircle" ? width * 0.3 : Appearance.rounding.normal
                            color: plate.shaped ? Appearance.colors.colPrimaryContainer
                                : Qt.alpha(Appearance.m3colors.m3surfaceContainer, 0.55)
                            border.width: plate.style === "translucent" ? 1 : 0
                            border.color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.5)
                        }
                        Loader {
                            anchors.centerIn: parent
                            readonly property real glyph: tile.entry.type === "group" ? root.iconSize
                                : plate.shaped ? root.iconSize * 0.64
                                : plate.style === "translucent" ? root.iconSize * 0.78 : root.iconSize
                            width: glyph
                            height: glyph
                            sourceComponent: tile.entry.type === "group" ? groupIcon : singleIcon
                        }
                        // Running: the dock's own dot, under the icon.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: -2
                            readonly property bool shown: (root.options.runningBadges ?? true) && DesktopShortcuts.isRunning(tile.entry)
                            width: shown ? 12 * Math.max(0.75, root.iconScale) : 4
                            height: 4
                            radius: 2
                            color: Appearance.colors.colPrimary
                            opacity: shown ? 1 : 0
                            visible: opacity > 0.001
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on width {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                        // Unread notifications from the app.
                        Rectangle {
                            id: unreadBadge
                            readonly property int count: (root.options.notificationBadges ?? true) ? DesktopShortcuts.unreadCount(tile.entry) : 0
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -4
                            anchors.topMargin: -4
                            height: 18
                            width: Math.max(height, unreadText.implicitWidth + 10)
                            radius: height / 2
                            color: Appearance.m3colors.m3error
                            scale: unreadBadge.count > 0 ? 1 : 0
                            visible: scale > 0.01
                            Behavior on scale {
                                NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
                            }
                            StyledText {
                                id: unreadText
                                anchors.centerIn: parent
                                text: unreadBadge.count > 99 ? "99+" : String(unreadBadge.count)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.m3colors.m3onError
                            }
                        }
                    }
                    Item {
                        id: labelBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.labelHeight
                        readonly property string mode: root.options.labels ?? "always"
                        readonly property string style: root.options.labelStyle ?? "auto"
                        // "auto" and "shadow" draw light text in a soft dark
                        // halo, readable on any wallpaper: the palette only
                        // knows the wallpaper's overall brightness, never the
                        // patch behind one label. "pill" draws the M3
                        // inverse pair's scrim instead.
                        readonly property bool pill: labelBox.style === "pill"
                        visible: labelBox.mode !== "never"
                        opacity: labelBox.mode === "hover" ? (tile.hovered || tile.selected ? 1 : 0) : 1
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            width: Math.min(parent.width, tileLabel.contentWidth + 12)
                            height: tileLabel.contentHeight + 5
                            radius: Appearance.rounding.small
                            color: Appearance.m3colors.m3inverseSurface
                            opacity: 0.7
                            visible: labelBox.pill
                        }
                        StyledText {
                            id: tileLabel
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            text: tile.entry.name || tile.entry.id
                            font.family: Appearance.font.family.main
                            font.variableAxes: root.labelAxes
                            font.pixelSize: root.labelSize
                            lineHeight: root.labelLineHeight
                            color: labelBox.pill ? Appearance.m3colors.m3inverseOnSurface
                                : (root.wallpaperLight ? Appearance.m3colors.m3inverseOnSurface : Appearance.m3colors.m3onSurface)
                            elide: Text.ElideRight
                            wrapMode: (root.options.labelLines ?? 1) === 2 ? Text.Wrap : Text.NoWrap
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: (root.options.labelLines ?? 1) === 2 ? 2 : 1
                            // The halo: a wide, spread shadow rather than a
                            // 1 px offset, so a white patch of wallpaper behind
                            // white text still leaves a dark rim to read.
                            layer.enabled: !labelBox.pill
                            layer.effect: GE.DropShadow {
                                radius: Math.max(4, Math.round(root.labelSize * 0.45))
                                samples: radius * 2 + 1
                                spread: 0.3
                                verticalOffset: 1
                                color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.35)
                                transparentBorder: true
                            }
                        }
                    }
                }
                Component {
                    id: singleIcon
                    IconImage {
                        implicitSize: root.iconSize
                        // The tiles ARE minified in Edit Mode (the mode's
                        // shrink has no counter for them — they are the
                        // desktop). Mipmapping keeps their edges clean.
                        mipmap: true
                        source: DesktopShortcuts.iconSource(tile.entry.icon, tile.entry.type === "file" ? "text-x-generic" : "folder")
                    }
                }
                Component {
                    id: groupIcon
                    Rectangle {
                        id: groupPlate
                        readonly property string style: root.options.iconBackground ?? "none"
                        radius: style === "circle" ? width / 2 : style === "squircle" ? width * 0.3 : Appearance.rounding.normal
                        color: style === "circle" || style === "squircle" ? Appearance.colors.colPrimaryContainer
                            : Appearance.m3colors.m3surfaceContainerHigh
                        Grid {
                            anchors.centerIn: parent
                            columns: 2
                            spacing: 4 * root.iconScale
                            Repeater {
                                model: tile.entry.apps.slice(0, 4)
                                delegate: IconImage {
                                    required property var modelData
                                    implicitSize: (groupPlate.style === "circle" ? 18 : 22) * root.iconScale
                                    mipmap: true
                                    source: DesktopShortcuts.iconSource(modelData.icon, "image-missing")
                                }
                            }
                        }
                    }
                }
            }
            MouseArea {
                id: gesture
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                enabled: !tile.merging
                onPressed: mouse => {
                    tile.suppressClick = false;
                    tile.pressPoint = root.mapFromItem(gesture, mouse.x, mouse.y);
                    tile.origin = Qt.point(tile.settled.x, tile.settled.y);
                    if (mouse.button === Qt.LeftButton && tile.fileUrl !== "" && !root.iconsLocked)
                        tileContent.grabToImage(result => tile.dragImage = result.url);
                }
                onPositionChanged: mouse => {
                    if (!(pressedButtons & Qt.LeftButton) || tile.systemDrag)
                        return;
                    // The lock gates only the drag START — press feedback,
                    // selection and the menu keep working.
                    if (!tile.dragging && root.iconsLocked)
                        return;
                    const p = root.mapFromItem(gesture, mouse.x, mouse.y);
                    const dx = p.x - tile.pressPoint.x;
                    const dy = p.y - tile.pressPoint.y;
                    if (!tile.dragging && dx * dx + dy * dy < 100)
                        return;
                    tile.dragTo(p);
                    if (tile.dragging && root.leavesDesktop(p))
                        root.beginSystemDrag(tile);
                }
                onReleased: {
                    if (!tile.systemDrag)
                        tile.finishDrag();
                }
                onCanceled: {
                    if (!tile.systemDrag)
                        tile.cancelDrag();
                }
                onClicked: mouse => {
                    if (tile.suppressClick)
                        return;
                    root.focusId = tile.entry.id;
                    if (mouse.button === Qt.LeftButton
                        && (mouse.modifiers & (Qt.ShiftModifier | Qt.ControlModifier))) {
                        root.toggleSelected(tile.entry.id);
                        return;
                    }
                    if (mouse.button === Qt.RightButton) {
                        // Right-clicking outside the selection retargets it,
                        // like everywhere else: the menu then speaks of the
                        // clicked icon alone.
                        if (!root.isSelected(tile.entry.id))
                            root.clearSelection();
                        const p = root.mapFromItem(gesture, mouse.x, mouse.y);
                        root.openContext(tile.entry.id, p.x, p.y);
                    } else if (Config.options.interactions.desktopDoubleClick
                        && root.armedId !== tile.entry.id) {
                        // First beat of the pair: select it, arm, wait. The
                        // halo is the feedback that the icon is loaded.
                        root.selectedIds = [tile.entry.id];
                        root.armedId = tile.entry.id;
                        clickTimer.restart();
                    } else {
                        // The second beat — or the whole gesture when the
                        // option is off: open what is under the pointer.
                        root.armedId = "";
                        clickTimer.stop();
                        root.openEntry(tile.entry);
                    }
                }
            }
        }
    }

    // The two modal cards counter-scale the mode's shrink (see
    // `counterScale`): the dialog undoes it inside its own cards, the
    // popup on the popup itself.
    Loader {
        id: contextDialog
        anchors.fill: parent
        z: 3
        active: false
        sourceComponent: DesktopShortcutContextDialog {
            entry: root.contextEntry ?? ({})
            anchorPoint: root.contextPosition
            screenName: root.screenName
            selectionCount: root.isSelected(root.contextId) ? root.selectedIds.length : 1
            selectedIds: root.isSelected(root.contextId) ? root.selectedIds : [root.contextId]
            counterScale: root.counterScale
            page: root.contextInitialPage
            onSelectAllRequested: root.selectedIds = root.items.map(item => item.id)
            onCloseRequested: {
                const remove = pendingAction === "remove";
                const itemId = root.contextId;
                const screenName = root.screenName;
                const bulk = remove && root.isSelected(itemId) && root.selectedIds.length > 1;
                const ids = root.selectedIds.slice();
                root.closeContext();
                if (bulk) {
                    root.clearSelection();
                    Qt.callLater(() => DesktopShortcuts.removeMany(screenName, ids));
                } else if (remove)
                    Qt.callLater(() => DesktopShortcuts.remove(screenName, itemId));
            }
        }
    }

    Loader {
        id: groupPopup
        anchors.fill: parent
        z: 4
        active: false
        sourceComponent: DesktopShortcutGroupPopup {
            entry: root.popupEntry ?? ({ apps: [] })
            tileRect: root.popupRect
            onCloseRequested: root.closePopup()
            counterScale: root.counterScale
            // The header's two operations: rename retargets the context
            // menu onto the same tile's rename page, ungroup dissolves the
            // members back onto the desktop. Both close the popup first —
            // it is the one surface that must not survive its own subject.
            onRenameRequested: {
                const id = root.popupId;
                const r = root.popupRect;
                root.closePopup();
                root.openContext(id, r.x + r.width / 2, r.y + r.height / 2, "rename");
            }
            onUngroupRequested: {
                const id = root.popupId;
                root.closePopup();
                Qt.callLater(() => DesktopShortcuts.ungroup(root.screenName, id));
            }
        }
    }
}
