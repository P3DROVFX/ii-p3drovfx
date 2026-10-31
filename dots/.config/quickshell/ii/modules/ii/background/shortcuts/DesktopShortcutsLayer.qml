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
import qs.modules.common.dock
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
    // The screen-edge bands where panels sit (the bar's edge, the dock's),
    // a thin one elsewhere: reaching one hands a drag over to the system.
    // A fixed 96 px band on every edge started the hand-over at once for the
    // icons near the screen's edges, which then hid and showed no landing.
    readonly property var systemDragEdges: {
        const thin = 6;
        const bands = { "top": thin, "right": thin, "bottom": thin, "left": thin };
        if (Config.options.bar.vertical)
            bands[Config.options.bar.bottom ? "right" : "left"] = Appearance.sizes.verticalBarWidth;
        else
            bands[Config.options.bar.bottom ? "bottom" : "top"] = Appearance.sizes.barHeight;
        if (Config.options.dock?.enable)
            bands.bottom = Math.max(bands.bottom, (Config.options.dock.height ?? 60) + 10);
        return bands;
    }
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
    readonly property var groups: root.options.groups ?? []
    readonly property bool shelf: root.options.shelf ?? false
    readonly property bool iconShadow: root.options.iconShadow ?? false

    // ── Launch pad: sections, captions, cards ──────────────────────────────
    // A section (config `groups`: {title, items, x, y, width, height}) names
    // its members by entry name or path and owns a glass card - the widgets'
    // card surface - at its stored rectangle, with its caption in a band on
    // top. Inside, the members take as many columns as fit the card's width,
    // spread evenly across it, in rows from the top; a card is never shorter
    // than its rows need. A section with no rectangle yet (an older config,
    // one just created) gets one under the lowest card and keeps it. Icons in
    // no section draw bare.
    //
    // The cards move and resize like the widgets: drag the glass, pull the
    // corner grip (free width and height). Membership follows the hand: a
    // tile dropped on a card joins that section, one dropped off every card
    // leaves it. Every change - a drop, the menu's Section page, a card moved
    // or resized, an edit of the config - lays the members out again.
    readonly property real captionSize: Math.round(root.labelSize * 0.85)
    readonly property real captionBand: root.captionSize + 16
    readonly property real shelfPad: 12
    // A new card's width, in cells.
    readonly property int sectionColumns: Math.max(1, root.options.groupColumns ?? 3)
    // Inside a card rows sit 10 px apart; a new card keeps 16 px from the
    // one above it.
    readonly property real sectionRowGap: 10
    readonly property real sectionGap: 16
    readonly property real cardMinWidth: root.cellWidth + root.shelfPad * 2
    function bandOf(title) {
        return title !== "" ? root.captionBand : 0;
    }
    function columnsFor(width) {
        return Math.max(1, Math.floor((width - root.shelfPad * 2) / root.cellWidth));
    }
    function cardHeightFor(count, width, title) {
        const rows = Math.max(1, Math.ceil(count / root.columnsFor(width)));
        return root.shelfPad * 2 + root.bandOf(title) + rows * root.cellHeight + (rows - 1) * root.sectionRowGap;
    }
    function hasRect(g) {
        return Number(g?.width ?? 0) > 0 && Number(g?.height ?? 0) > 0;
    }
    // Where the k-th member sits in `card`: its column's centre, its row
    // from the top, on the 10 px snap.
    function slotIn(card, title, k) {
        const cols = root.columnsFor(card.width);
        const colW = (card.width - root.shelfPad * 2) / cols;
        const snap = v => Math.round(v / 10) * 10;
        return Qt.point(snap(card.x + root.shelfPad + (k % cols) * colW + (colW - root.cellWidth) / 2),
            snap(card.y + root.shelfPad + root.bandOf(title) + Math.floor(k / cols) * (root.cellHeight + root.sectionRowGap)));
    }
    // A section's members in reading order of where they are (or, for the
    // `landed` ones, where they were dropped), so a layout keeps the order
    // and a drop ranks the tile where it landed.
    function orderedMembers(list, landed) {
        const pos = e => landed[e.id] ?? root.positionAt(e.x, e.y);
        const stayed = list.filter(e => landed[e.id] === undefined);
        const top = Math.min(...(stayed.length > 0 ? stayed : list).map(e => pos(e).y));
        const rowStep = root.cellHeight + root.sectionRowGap;
        const rowOf = e => Math.floor((pos(e).y + root.cellHeight / 2 - top) / rowStep);
        return list.slice().sort((a, b) => (rowOf(a) - rowOf(b)) || (pos(a).x - pos(b).x));
    }

    // ── Card gestures ──────────────────────────────────────────────────────
    // While a card is dragged or resized it is drawn at `cardPreview`
    // ({index, rect}) and its members at `sectionPreview` (id -> point);
    // nothing is written until the release.
    property var cardPreview: null
    property var sectionPreview: ({})
    // A drag (not a resize): the members follow the pointer directly.
    property bool cardMoving: false
    // The section under the pointer, through its glass or one of its tiles
    // (kept apart: their enter and leave arrive in either order): what
    // shows the card's grip.
    property int cardHoverSection: -1
    property int tileHoverSection: -1
    // The section whose caption is being renamed in place, -1 when none.
    // The window takes the keyboard while it is (BackgroundWidgetsWindow).
    property int editingSection: -1
    readonly property bool captionEditing: root.editingSection >= 0
    // Counted with the icon dialogs (GlobalStates.desktopDialogCount): no
    // window has focus on an empty desktop, so type-to-search would bind
    // every letter and open the launcher with what was meant for the name.
    property bool _captionCounted: false
    onCaptionEditingChanged: {
        if (root.captionEditing === root._captionCounted)
            return;
        root._captionCounted = root.captionEditing;
        GlobalStates.desktopDialogCount = Math.max(0, GlobalStates.desktopDialogCount + (root.captionEditing ? 1 : -1));
    }
    // A press anywhere on the bare desktop ends a rename too (it saves).
    Connections {
        target: root.canvas
        enabled: root.captionEditing
        function onPressed() {
            root.forceActiveFocus();
        }
    }
    function finishCaptionEdit(text, save) {
        const index = root.editingSection;
        if (index < 0)
            return;
        root.editingSection = -1;
        if (save)
            root.renameSection(String(root.groups[index]?.title ?? ""), text);
    }
    function previewCard(index, rect) {
        const g = root.groups[index];
        const title = String(g?.title ?? "");
        const list = root.items.filter(e => root.memberOf(g, e));
        const card = Qt.rect(rect.x, rect.y, rect.width,
            Math.max(rect.height, root.cardHeightFor(list.length, rect.width, title)));
        root.cardPreview = { "index": index, "rect": card };
        const slots = {};
        root.orderedMembers(list, {}).forEach((e, k) => slots[e.id] = root.slotIn(card, title, k));
        root.sectionPreview = slots;
    }
    function commitCard() {
        const preview = root.cardPreview;
        if (!preview)
            return;
        const sections = root.sectionsCopy();
        const s = sections[preview.index];
        if (s) {
            s.x = preview.rect.x;
            s.y = preview.rect.y;
            s.width = preview.rect.width;
            s.height = preview.rect.height;
            root.reflowSections(sections, {});
        }
        root.cancelCard();
    }
    function cancelCard() {
        root.cardPreview = null;
        root.sectionPreview = ({});
    }
    // The widgets' drag feedback: the wallpaper dims and the depth subject
    // steps back while something is being placed.
    function setCanvasDragging(active) {
        if (root.canvas)
            root.canvas.draggingActive = active;
    }
    // A list out of the config arrives as a QML sequence, not an Array:
    // Array.from gives it includes().
    function memberOf(group, entry) {
        const names = Array.from(group?.items ?? []);
        return names.includes(entry.name) || names.includes(entry.path) || names.includes(entry.fileName);
    }
    function sectionIndexOf(entry) {
        for (let i = 0; i < root.groups.length; ++i) {
            if (root.memberOf(root.groups[i], entry))
                return i;
        }
        return -1;
    }
    // Each section's card and the box inside it (under the caption band):
    // the gesture's preview, else the stored rectangle (grown to its rows),
    // else - a section not laid out yet - around its members' cells, leaving
    // out `exceptIds` (a Set, or null).
    function boxesFor(exceptIds) {
        const out = [];
        for (let i = 0; i < root.groups.length; ++i) {
            const g = root.groups[i];
            const title = String(g?.title ?? "");
            const band = root.bandOf(title);
            const members = root.items.filter(entry => root.memberOf(g, entry));
            if (members.length === 0)
                continue;
            let card = null;
            if (root.cardPreview && root.cardPreview.index === i) {
                card = root.cardPreview.rect;
            } else if (root.hasRect(g)) {
                card = Qt.rect(Number(g.x), Number(g.y), Number(g.width),
                    Math.max(Number(g.height), root.cardHeightFor(members.length, Number(g.width), title)));
            } else {
                let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
                for (const entry of members) {
                    if (exceptIds && exceptIds.has(entry.id))
                        continue;
                    const p = root.positionAt(entry.x, entry.y);
                    x0 = Math.min(x0, p.x);
                    y0 = Math.min(y0, p.y);
                    x1 = Math.max(x1, p.x + root.cellWidth);
                    y1 = Math.max(y1, p.y + root.cellHeight);
                }
                if (x0 === Infinity)
                    continue;
                card = Qt.rect(x0 - root.shelfPad, y0 - root.shelfPad - band,
                    x1 - x0 + root.shelfPad * 2, y1 - y0 + root.shelfPad * 2 + band);
            }
            out.push({ "index": i, "title": title, "card": card,
                "x": card.x + root.shelfPad, "y": card.y + root.shelfPad + band,
                "width": card.width - root.shelfPad * 2, "height": card.height - root.shelfPad * 2 - band });
        }
        return out;
    }
    readonly property var groupBoxes: root.boxesFor(null)
    function sectionAt(x, y, exceptIds) {
        const hit = root.boxesFor(exceptIds).find(b => x >= b.card.x && x < b.card.x + b.card.width
            && y >= b.card.y && y < b.card.y + b.card.height);
        return hit ? hit.index : -1;
    }
    // The card a dragged tile would join, lit while it is over it.
    property int dropSection: -1

    // Plain copies of the config's sections, safe to edit and write back;
    // the rectangle only when there is one, keys always in this order (the
    // reflow compares copies as JSON).
    function sectionsCopy() {
        return Array.from(root.groups).map(g => {
            const s = { "title": String(g?.title ?? ""), "items": Array.from(g?.items ?? []).map(String) };
            if (root.hasRect(g)) {
                s.x = Number(g.x);
                s.y = Number(g.y);
                s.width = Number(g.width);
                s.height = Number(g.height);
            }
            return s;
        });
    }
    function dropMember(sections, entry) {
        for (const s of sections)
            s.items = s.items.filter(n => n !== entry.name && n !== entry.path && n !== entry.fileName);
    }

    // Tiles just dropped (`landed`: id -> {x, y}): membership by the card
    // under each tile's centre, then the reflow. False when nothing about
    // the sections is touched - the caller then writes the plain move.
    function settleSections(landed) {
        if (root.groups.length === 0)
            return false;
        const moved = new Set(Object.keys(landed));
        const staying = root.boxesFor(moved);
        const sections = root.sectionsCopy();
        let touched = false;
        for (const entry of root.items) {
            if (!moved.has(entry.id))
                continue;
            const p = landed[entry.id];
            const cx = p.x + root.cellWidth / 2;
            const cy = p.y + root.cellHeight / 2;
            const hit = staying.find(b => cx >= b.card.x && cx < b.card.x + b.card.width
                && cy >= b.card.y && cy < b.card.y + b.card.height);
            const current = root.sectionIndexOf(entry);
            const sectionMoved = current >= 0 && !staying.some(b => b.index === current);
            const target = hit ? hit.index : (sectionMoved ? current : -1);
            if (current >= 0 || target >= 0)
                touched = true;
            if (target === current)
                continue;
            root.dropMember(sections, entry);
            if (target >= 0)
                sections[target].items.push(entry.name || entry.fileName || entry.path);
        }
        if (!touched)
            return false;
        root.reflowSections(sections.filter(s => s.items.length > 0), landed);
        return true;
    }

    // The menu's Section page: `title` "" takes the tiles out of every
    // section; an unknown title starts a new one at the bottom of the stack.
    function moveToSection(ids, title) {
        const sections = root.sectionsCopy();
        const wanted = String(title ?? "").trim();
        let target = wanted === "" ? null : sections.find(s => s.title === wanted);
        if (wanted !== "" && !target) {
            target = { "title": wanted, "items": [] };
            sections.push(target);
        }
        for (const entry of root.items) {
            if (ids.indexOf(entry.id) === -1)
                continue;
            root.dropMember(sections, entry);
            if (target)
                target.items.push(entry.name || entry.fileName || entry.path);
        }
        root.reflowSections(sections.filter(s => s.items.length > 0), {});
    }
    function renameSection(from, to) {
        const title = String(to ?? "").trim();
        if (title === "" || title === from)
            return;
        Config.options.background.desktopIcons.groups = root.sectionsCopy().map(s => s.title === from
            ? Object.assign(s, { "title": title }) : s);
    }

    // Lays every section out in its card and writes what changed: the config
    // when a membership or a rectangle did, the positions of every tile that
    // moves (the dropped ones included, section or not). A section without a
    // rectangle gets one: under the lowest card, or - the first one, from an
    // older config - around where its members already are.
    function reflowSections(sections, landed) {
        const has = (s, e) => s.items.includes(e.name) || s.items.includes(e.path) || s.items.includes(e.fileName);
        const pos = e => landed[e.id] ?? root.positionAt(e.x, e.y);
        const snap = v => Math.round(v / 10) * 10;
        const members = sections.map(s => root.items.filter(e => has(s, e)));
        const moves = [];
        let low = null;
        sections.forEach((s, i) => {
            if (!root.hasRect(s) || members[i].length === 0)
                return;
            const bottom = s.y + Math.max(s.height, root.cardHeightFor(members[i].length, s.width, s.title));
            if (!low || bottom > low.bottom)
                low = { "x": s.x, "bottom": bottom };
        });
        sections.forEach((s, i) => {
            const list = members[i];
            if (list.length === 0)
                return;
            if (!root.hasRect(s)) {
                const stayed = list.filter(e => landed[e.id] === undefined);
                const ref = stayed.length > 0 ? stayed : list;
                s.x = low ? low.x : snap(Math.min(...ref.map(e => pos(e).x)) - root.shelfPad);
                s.y = low ? snap(low.bottom + root.sectionGap)
                    : snap(Math.min(...ref.map(e => pos(e).y)) - root.shelfPad - root.bandOf(s.title));
                s.width = root.shelfPad * 2 + Math.min(list.length, root.sectionColumns) * root.cellWidth;
                s.height = 0;
            }
            s.height = Math.max(s.height, root.cardHeightFor(list.length, s.width, s.title));
            if (!low || s.y + s.height > low.bottom)
                low = { "x": low ? low.x : s.x, "bottom": s.y + s.height };
            const card = Qt.rect(s.x, s.y, s.width, s.height);
            root.orderedMembers(list, landed).forEach((e, k) => {
                const p = root.slotIn(card, s.title, k);
                moves.push({ "id": e.id, "x": p.x, "y": p.y });
            });
        });
        for (const id of Object.keys(landed)) {
            if (!moves.some(m => m.id === id))
                moves.push({ "id": id, "x": landed[id].x, "y": landed[id].y, "free": true });
        }
        const before = JSON.stringify(root.sectionsCopy());
        if (JSON.stringify(sections) !== before)
            Config.options.background.desktopIcons.groups = sections;
        const changed = moves.filter(m => {
            const e = root.items.find(item => item.id === m.id);
            const p = e ? root.positionAt(e.x, e.y) : null;
            return p && (p.x !== m.x || p.y !== m.y);
        });
        if (changed.length > 0)
            DesktopShortcuts.placeMany(root.screenName, changed);
    }
    // Any other change to who is in a section - the config edited by hand,
    // a member arriving or leaving the desktop - reflows the stack too, a
    // beat later. Positions alone never trigger it, and an unchanged stack
    // writes nothing, so its own write ends the loop.
    readonly property string sectionSignature: JSON.stringify(root.sectionsCopy()) + "|"
        + root.items.filter(e => root.sectionIndexOf(e) >= 0).map(e => e.id).sort().join(",")
    onSectionSignatureChanged: sectionReflowTimer.restart()
    Timer {
        id: sectionReflowTimer
        interval: 250
        onTriggered: {
            const busy = root.dragId !== "" || root.cardPreview !== null;
            if (busy || root.items.length === 0 || root.groups.length === 0) {
                if (busy)
                    sectionReflowTimer.restart();
                return;
            }
            root.reflowSections(root.sectionsCopy(), {});
        }
    }
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
    // The open modal surface, for the depth cutout to leave uncovered.
    readonly property Item modalItem: groupPopup.active ? groupPopup : contextDialog.active ? contextDialog : null
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
            const span = DesktopShortcuts.spanOf(entry);
            const s = root.positionAt(entry.x, entry.y, span);
            minX = Math.max(minX, -s.x);
            maxX = Math.min(maxX, root.width - root.cellWidth * span - s.x);
            minY = Math.max(minY, -s.y);
            maxY = Math.min(maxY, root.height - root.cellHeight * span - s.y);
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
        // A caption being renamed keeps its keys: what its field leaves
        // (Backspace at the start) must not reach the icons.
        if (root.captionEditing) {
            event.accepted = true;
            return;
        }
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

    // An app group's look: its own override, else the Edit Mode default,
    // else (auto) what the icon background does for every other icon.
    function groupShapeOf(entry) {
        const v = entry.shape || (root.options.groupShape ?? "auto");
        if (v !== "auto")
            return v;
        const bg = root.options.iconBackground ?? "none";
        return bg === "circle" ? "circle" : bg === "squircle" ? "squircle" : "rounded";
    }
    function groupColorOf(entry) {
        return entry.color || (root.options.groupColor ?? "auto");
    }
    // Glass: the neutral surface at the glass alpha, which the compositor
    // blurs (Appearance.desktopGlassScreens).
    function groupFillOf(entry) {
        const v = root.groupColorOf(entry);
        const bg = root.options.iconBackground ?? "none";
        if (v === "glass")
            return Qt.alpha(Appearance.m3colors.m3surfaceContainer, Appearance.desktopGlassAlpha);
        if (v === "primary" || (v === "auto" && (bg === "circle" || bg === "squircle")))
            return Appearance.colors.colPrimaryContainer;
        if (v === "secondary")
            return Appearance.colors.colSecondaryContainer;
        if (v === "tertiary")
            return Appearance.colors.colTertiaryContainer;
        return Appearance.m3colors.m3surfaceContainerHigh;
    }
    function groupOnFillOf(entry) {
        const v = root.groupColorOf(entry);
        const bg = root.options.iconBackground ?? "none";
        if (v === "primary" || (v === "auto" && (bg === "circle" || bg === "squircle")))
            return Appearance.colors.colOnPrimaryContainer;
        if (v === "secondary")
            return Appearance.colors.colOnSecondaryContainer;
        if (v === "tertiary")
            return Appearance.colors.colOnTertiaryContainer;
        return Appearance.m3colors.m3onSurface;
    }
    // The glass's hairline rim: a light edge, like light catching a pane.
    readonly property color groupRim: Qt.alpha(Appearance.m3colors.m3onSurface, 0.16)
    // How a group clips its members' icons. Auto follows the group's shape,
    // so square icons never poke out of a round group.
    function groupMaskOf(entry) {
        const v = entry.mask || (root.options.groupIconMask ?? "auto");
        if (v !== "auto")
            return v;
        const shape = root.groupShapeOf(entry);
        return shape === "rounded" ? "rounded" : shape === "squircle" ? "squircle" : "circle";
    }
    // A glass group on this screen turns the compositor blur on behind the
    // layer even when the widgets are opaque.
    readonly property bool hasGlassGroup: root.visible
        && root.items.some(item => item.type === "group" && root.groupColorOf(item) === "glass")
    onHasGlassGroupChanged: Appearance.setDesktopGlass(root.screenName, root.hasGlassGroup)
    function positionAt(x, y, span = 1) {
        return Qt.point(Math.max(0, Math.min(width - cellWidth * span, Math.round(x / 10) * 10)),
                        Math.max(0, Math.min(height - cellHeight * span, Math.round(y / 10) * 10)));
    }

    // The merge target under (x, y). With autoArrange only the middle of a
    // tile merges: its edges are where a drop pushes the icon aside instead.
    function targetAt(x, y, exceptId) {
        const insetX = root.autoArrange ? root.cellWidth * 0.22 : 0;
        const insetY = root.autoArrange ? root.cellHeight * 0.22 : 0;
        for (let i = 0; i < iconModel.count; ++i) {
            const item = iconModel.get(i).entry;
            const span = DesktopShortcuts.spanOf(item);
            const s = root.positionAt(item.x, item.y, span);
            if (item.id !== exceptId && DesktopShortcuts.isGroupable(item)
                && x >= s.x + insetX && x < s.x + root.cellWidth * span - insetX
                && y >= s.y + insetY && y < s.y + root.cellHeight * span - insetY)
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

    // Off the snap grid the ghost marks where the icon lands: under the
    // pointer, or the nearest clear spot when another icon is there. A system
    // drag hides the tile, so the ghost is its only mark on the desktop.
    function freePlan(tile, pending) {
        return DesktopShortcuts.planFreeDrop(root.screenName, [tile.entry.id], pending.x, pending.y);
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
        const edge = root.systemDragEdges;
        if (w.x < edge.left || w.y < edge.top || w.x > window.width - edge.right || w.y > window.height - edge.bottom)
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

    // Off the desktop (over a window or a panel) a system drag lands
    // elsewhere: the ghost goes until the pointer comes back.
    function systemDragLeave() {
        if (root.systemDragTile) {
            root.dragPlan = null;
            root.dropTargetId = "";
        }
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
        // Opened - by double-click, Enter, the menu or a group: the
        // selection goes, or its plate stays lit under the window.
        function onLaunched(itemId) {
            root.armedId = "";
            root.clearSelection();
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
        const push = (id, x, y, kind, span = 1) => {
            const p = root.mapToItem(null, x + inset, y + inset);
            out.push({ "id": id, "x": p.x, "y": p.y, "w": root.cellWidth * span - inset * 2, "h": root.cellHeight * span - inset * 2, "kind": kind });
        };
        for (let i = 0; i < iconRepeater.count; ++i) {
            const tile = iconRepeater.itemAt(i);
            if (!tile || tile.intro < 1)
                continue;
            const follow = tile.dragging ? Qt.point(tile.pending.x - tile.x, tile.pending.y - tile.y)
                : tile.groupMember ? Qt.point(groupDrag.dx, groupDrag.dy) : Qt.point(0, 0);
            if (root.systemDragIds.indexOf(tile.entry.id) !== -1) {
                // A selection handed to the system is hidden: each member's
                // landing spot stands in for it (a single drag has the ghost).
                if (groupDrag.active)
                    push(tile.entry.id, tile.x + follow.x, tile.y + follow.y, "ghost", tile.span);
                continue;
            }
            if (tile.selected)
                push(tile.entry.id, tile.x + follow.x, tile.y + follow.y,
                    root.focusId === tile.entry.id && root.selectedIds.length > 1 ? "focus" : "selected", tile.span);
            else if (tile.hovered && !tile.dragging && root.dropTargetId !== tile.entry.id)
                push(tile.entry.id, tile.x, tile.y, "hover", tile.span);
        }
        if (dropGhost.shown)
            push("__ghost__", dropGhost.x, dropGhost.y, "ghost", dropGhost.span);
        return out;
    }
    onPlateEntriesChanged: DesktopShortcuts.setPlates(root.screenName, root.plateEntries)
    Component.onDestruction: {
        DesktopShortcuts.setPlates(root.screenName, []);
        Appearance.setDesktopGlass(root.screenName, false);
        // A rename cut short by the layer going away gives its count back.
        if (root._captionCounted)
            GlobalStates.desktopDialogCount = Math.max(0, GlobalStates.desktopDialogCount - 1);
    }

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
    // A click on an extended group at (x, y) in its tile: a spot with an
    // app launches it; the mini group, an empty spot, the rim or the label
    // open the popup.
    function openGroupSpot(tile, x, y) {
        const view = tile.largeView;
        const p = view ? view.mapFromItem(tile, x, y) : Qt.point(x, y);
        const spot = view ? view.spotAt(p.x, p.y) : -1;
        const apps = tile.entry.apps ?? [];
        const app = spot >= 0 && (spot < 3 || apps.length === 4) ? apps[spot] : null;
        if (app) {
            root.selectedIds = [];
            DesktopShortcuts.launch(app);
        } else {
            root.openEntry(tile.entry);
        }
    }
    function openEntry(entry) {
        const tile = root.tileFor(entry.id);
        const view = tile ? tile.largeView : null;
        if (entry.type === "group" && view) {
            // From the mini group: the popup holds the members it gathers.
            const r = view.spotRect(3);
            const p = view.mapToItem(root, r.x, r.y);
            root.openPopup(entry.id, p.x, p.y, r.width, r.height);
        } else if (entry.type === "group" && tile && tile.span > 1)
            root.openPopup(entry.id, tile.x + tile.width / 2, tile.y + tile.height / 2, tile.width / 2, tile.height / 2);
        else if (entry.type === "group" && tile)
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
    Component.onCompleted: {
        sync();
        Appearance.setDesktopGlass(root.screenName, root.hasGlassGroup);
    }
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
        readonly property int span: root.dragId !== "" ? DesktopShortcuts.spanOf(root.items.find(e => e.id === root.dragId)) : 1
        width: root.cellWidth * span
        height: root.cellHeight * span
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

    // One card per section: the widgets' card surface, so the launch pad and
    // the widgets read as one family; the compositor blurs behind it as
    // behind them. Counted by section, not by box, so a reflow glides the
    // cards instead of rebuilding them. The one a dragged tile would join
    // takes a primary outline.
    //
    // Dragging the glass moves the card like a widget: past the widgets'
    // 4 px threshold, on the 10 px snap, kept on screen, with the widgets'
    // drag feedback; the members ride along and land on release.
    Repeater {
        model: root.shelf ? root.groups.length : 0
        delegate: Item {
            id: sectionCard
            required property int index
            readonly property var box: root.groupBoxes.find(b => b.index === sectionCard.index) ?? null
            // Under the pointer: follow it, no glide.
            readonly property bool live: root.cardPreview !== null && root.cardPreview.index === sectionCard.index
            visible: sectionCard.box !== null
            x: sectionCard.box ? sectionCard.box.card.x : 0
            y: sectionCard.box ? sectionCard.box.card.y : 0
            width: sectionCard.box ? sectionCard.box.card.width : 0
            height: sectionCard.box ? sectionCard.box.card.height : 0

            Behavior on x {
                enabled: !sectionCard.live
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on y {
                enabled: !sectionCard.live
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on width {
                enabled: !sectionCard.live
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on height {
                enabled: !sectionCard.live
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            HoverHandler {
                onHoveredChanged: {
                    if (hovered)
                        root.cardHoverSection = sectionCard.index;
                    else if (root.cardHoverSection === sectionCard.index)
                        root.cardHoverSection = -1;
                }
            }
            MouseArea {
                id: cardMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                enabled: !root.iconsLocked
                preventStealing: true
                // The glass reads as a handle: an open hand over it, closed
                // while the card is carried.
                hoverEnabled: true
                cursorShape: cardMouse.moving ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property point pressAt: Qt.point(0, 0)
                property rect startRect: Qt.rect(0, 0, 0, 0)
                property bool moving: false
                function end() {
                    if (cardMouse.moving) {
                        root.cardMoving = false;
                        root.setCanvasDragging(false);
                    }
                    cardMouse.moving = false;
                }
                onPressed: mouse => {
                    // Clicking the glass ends a rename (the field saves on
                    // losing focus).
                    if (root.captionEditing)
                        root.forceActiveFocus();
                    cardMouse.pressAt = cardMouse.mapToItem(root, mouse.x, mouse.y);
                    cardMouse.startRect = sectionCard.box ? sectionCard.box.card : Qt.rect(0, 0, 0, 0);
                    cardMouse.moving = false;
                    // A press on the glass is a click-away, as on the bare desktop.
                    root.clearSelection();
                }
                onPositionChanged: mouse => {
                    // Hover reports positions too (hoverEnabled, for the
                    // cursor): only a held button carries the card.
                    if (!cardMouse.pressed)
                        return;
                    const p = cardMouse.mapToItem(root, mouse.x, mouse.y);
                    const dx = p.x - cardMouse.pressAt.x;
                    const dy = p.y - cardMouse.pressAt.y;
                    if (!cardMouse.moving) {
                        if (dx * dx + dy * dy < 16)
                            return;
                        cardMouse.moving = true;
                        root.cardMoving = true;
                        root.setCanvasDragging(true);
                    }
                    const r = cardMouse.startRect;
                    const snap = v => Math.round(v / 10) * 10;
                    root.previewCard(sectionCard.index, Qt.rect(
                        Math.max(0, Math.min(root.width - r.width, snap(r.x + dx))),
                        Math.max(0, Math.min(root.height - r.height, snap(r.y + dy))),
                        r.width, r.height));
                }
                onReleased: {
                    if (cardMouse.moving)
                        root.commitCard();
                    cardMouse.end();
                }
                onCanceled: {
                    root.cancelCard();
                    cardMouse.end();
                }
                // A double-click on the caption band renames the section in place.
                onDoubleClicked: mouse => {
                    const title = sectionCard.box ? sectionCard.box.title : "";
                    if (title !== "" && mouse.y < root.shelfPad + root.bandOf(title))
                        root.editingSection = sectionCard.index;
                }
            }

            StyledRectangularShadow {
                target: sectionPlate
                visible: Config.options.background.widgets.enableShadows ?? true
            }
            Rectangle {
                id: sectionPlate
                anchors.fill: parent
                radius: Appearance.rounding.windowRounding
                color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
                border.width: 2
                border.color: root.dropSection === sectionCard.index
                    ? Appearance.colors.colPrimary : "transparent"
                Behavior on border.color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
    }
    // Captions: each section's title in small caps on the primary, a
    // hairline running on to the section's far edge.
    Repeater {
        model: root.groups.length
        delegate: Item {
            id: caption
            required property int index
            readonly property var modelData: root.groupBoxes.find(b => b.index === caption.index)
                ?? ({ "title": "", "x": 0, "y": 0, "width": 0, "height": 0 })
            readonly property bool live: root.cardPreview !== null && root.cardPreview.index === caption.index
            visible: caption.modelData.title !== ""
            x: caption.modelData.x + 10
            y: caption.modelData.y - root.captionBand + 6
            width: Math.max(0, caption.modelData.width - 20)
            height: root.captionSize + 4

            Behavior on x {
                enabled: !caption.live
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on y {
                enabled: !caption.live
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            StyledText {
                id: captionText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: caption.modelData.title
                font.family: Appearance.font.family.title
                font.pixelSize: root.captionSize
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: root.captionSize * 0.14
                color: Appearance.colors.colPrimary
                visible: !caption.editing
                // Off the shelf, the same halo the labels read by.
                layer.enabled: !root.shelf
                layer.effect: GE.DropShadow {
                    radius: Math.max(4, Math.round(root.captionSize * 0.45))
                    samples: radius * 2 + 1
                    spread: 0.3
                    verticalOffset: 1
                    color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.35)
                    transparentBorder: true
                }
            }
            Rectangle {
                visible: !caption.editing
                anchors.left: captionText.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: captionText.verticalCenter
                height: 1
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
            }

            // In-place rename (a double-click on the caption band): the
            // caption's own type, the whole name selected. Return saves,
            // Escape keeps the old name, clicking away saves. Return is taken
            // here, before the field ignores it and the layer's keys see it.
            readonly property bool editing: root.editingSection === caption.index
            StyledTextInput {
                id: captionEdit
                visible: caption.editing
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                font.family: Appearance.font.family.title
                font.pixelSize: root.captionSize
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: root.captionSize * 0.14
                color: Appearance.colors.colPrimary
                selectByMouse: true
                clip: true
                onVisibleChanged: {
                    if (!captionEdit.visible)
                        return;
                    captionEdit.text = caption.modelData.title;
                    captionEdit.forceActiveFocus();
                    captionEdit.selectAll();
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        event.accepted = true;
                        root.finishCaptionEdit(captionEdit.text, true);
                    } else if (event.key === Qt.Key_Escape) {
                        event.accepted = true;
                        root.finishCaptionEdit("", false);
                    }
                }
                // The item's own focus, not activeFocus: the window drops the
                // keyboard for a moment when its focus seed hands over to
                // OnDemand, which cleared activeFocus after the first key.
                onFocusChanged: {
                    if (!captionEdit.focus && caption.editing)
                        root.finishCaptionEdit(captionEdit.text, true);
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.bottom
                    anchors.topMargin: 2
                    height: 2
                    radius: 1
                    color: Appearance.colors.colPrimary
                }
            }
        }
    }
    // Each card's resize grip - the widgets' own (ResizeGrip.qml) - over the
    // tiles, so the last row cannot cover it. Free width and height: the
    // columns follow the width, the height never drops below the rows. A
    // double-click puts the card back to its first size.
    Repeater {
        model: root.shelf ? root.groups.length : 0
        delegate: Item {
            id: gripHost
            required property int index
            readonly property var box: root.groupBoxes.find(b => b.index === gripHost.index) ?? null
            z: 2
            visible: gripHost.box !== null
            x: gripHost.box ? gripHost.box.card.x : 0
            y: gripHost.box ? gripHost.box.card.y : 0
            width: gripHost.box ? gripHost.box.card.width : 0
            height: gripHost.box ? gripHost.box.card.height : 0

            ResizeGrip {
                id: cardGrip
                property point pressAt: Qt.point(0, 0)
                property rect startRect: Qt.rect(0, 0, 0, 0)
                shown: !root.iconsLocked && !root.cardMoving && root.dragId === ""
                    && (root.cardHoverSection === gripHost.index || root.tileHoverSection === gripHost.index
                        || cardGrip.hovered)
                onPressed: mouse => {
                    cardGrip.pressAt = cardGrip.mapToItem(root, mouse.x, mouse.y);
                    cardGrip.startRect = gripHost.box ? gripHost.box.card : Qt.rect(0, 0, 0, 0);
                }
                onPositionChanged: mouse => {
                    if (!cardGrip.active)
                        return;
                    const p = cardGrip.mapToItem(root, mouse.x, mouse.y);
                    const r = cardGrip.startRect;
                    const snap = v => Math.round(v / 10) * 10;
                    root.previewCard(gripHost.index, Qt.rect(r.x, r.y,
                        Math.max(root.cardMinWidth, Math.min(root.width - r.x, snap(r.width + p.x - cardGrip.pressAt.x))),
                        Math.max(0, Math.min(root.height - r.y, snap(r.height + p.y - cardGrip.pressAt.y)))));
                }
                onReleased: root.commitCard()
                onCanceled: root.cancelCard()
                onDoubleClicked: {
                    const g = root.groups[gripHost.index];
                    const count = root.items.filter(e => root.memberOf(g, e)).length;
                    const r = gripHost.box ? gripHost.box.card : null;
                    if (!r)
                        return;
                    root.previewCard(gripHost.index, Qt.rect(r.x, r.y,
                        root.shelfPad * 2 + Math.min(count, root.sectionColumns) * root.cellWidth, 0));
                    root.commitCard();
                }
            }
        }
    }

    Repeater {
        id: iconRepeater
        model: iconModel
        delegate: Item {
            id: tile
            required property var entry
            required property int mergePulse
            readonly property int span: DesktopShortcuts.spanOf(entry)
            // An extended group's plate, for its spots' geometry.
            readonly property var largeView: tile.span > 1 ? glyphLoader.item : null
            readonly property point settled: root.positionAt(entry.x, entry.y, tile.span)
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
            // A tile over its card counts as the card for the grip.
            onHoveredChanged: {
                const section = root.sectionIndexOf(tile.entry);
                if (tile.hovered && section >= 0)
                    root.tileHoverSection = section;
                else if (!tile.hovered && root.tileHoverSection === section)
                    root.tileHoverSection = -1;
            }
            // The hover's lift, with the shadow on: 4 px up, back on leave.
            property real lift: root.iconShadow && tile.hovered && !tile.dragging ? 4 : 0
            Behavior on lift {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tile)
            }

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
            // Its card being moved or resized: the slot it will land in.
            readonly property var previewSlot: root.sectionPreview[tile.entry.id] ?? null
            readonly property real restX: tile.previewSlot ? tile.previewSlot.x - tile.settled.x
                : tile.bumped ? root.dragPlan.bumpX - tile.settled.x : 0
            readonly property real restY: tile.previewSlot ? tile.previewSlot.y - tile.settled.y
                : tile.bumped ? root.dragPlan.bumpY - tile.settled.y : 0
            function glide() {
                glideMotion.stop();
                // A card drag carries its tiles with the pointer, no glide.
                if (Appearance.reducedMotion || (root.cardMoving && tile.previewSlot)
                    || (tile.offX === tile.restX && tile.offY === tile.restY)) {
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
            width: root.cellWidth * tile.span
            height: root.cellHeight * tile.span
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
            // No hot spot: the snapshot hangs from the pointer's tip. Qt sends
            // the hot spot as the icon's offset on its first buffer only, and
            // Hyprland (0.56) takes each commit's offset as absolute, so the
            // next buffer's 0,0 threw the icon a hot spot away from the
            // pointer. With 0,0 every compositor draws it in the same place.
            Drag.hotSpot.x: 0
            Drag.hotSpot.y: 0
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
                tile.pending = root.positionAt(tile.origin.x + dx, tile.origin.y + dy, tile.span);
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
                    root.dropSection = root.sectionAt(tile.pending.x + root.cellWidth / 2,
                        tile.pending.y + root.cellHeight / 2, new Set(groupDrag.ids));
                } else {
                    root.dropTargetId = DesktopShortcuts.isGroupable(tile.entry) ? root.targetAt(p.x, p.y, tile.entry.id) : "";
                    root.dragPlan = root.dropTargetId !== "" ? null
                        : root.autoArrange ? DesktopShortcuts.planDrop(root.screenName, tile.entry.id, tile.pending.x, tile.pending.y)
                        : root.freePlan(tile, tile.pending);
                    root.dropSection = root.dropTargetId !== "" ? -1
                        : root.sectionAt(tile.pending.x + root.cellWidth / 2, tile.pending.y + root.cellHeight / 2, new Set([tile.entry.id]));
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
                root.dropSection = -1;
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
                        const landed = {};
                        for (const entry of root.items) {
                            if (ids.indexOf(entry.id) === -1)
                                continue;
                            const s = root.positionAt(entry.x, entry.y);
                            moves.push({ id: entry.id, x: s.x + ddx, y: s.y + ddy });
                            landed[entry.id] = { x: s.x + ddx, y: s.y + ddy };
                        }
                        Qt.callLater(() => {
                            if (!root.settleSections(landed))
                                DesktopShortcuts.moveMany(root.screenName, moves);
                        });
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
                Qt.callLater(() => {
                    const landed = {};
                    landed[itemId] = { x: p.x, y: p.y };
                    if (!root.settleSections(landed))
                        DesktopShortcuts.move(root.screenName, itemId, p.x, p.y, targetId);
                });
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
                root.dropSection = -1;
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
                    && !tile.dragging ? (tile.span > 1 ? 0.97 : 0.9) : 1.0
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
                    // The entrance's rise, and the hover's lift.
                    Translate {
                        y: (1 - tile.intro) * 14 - tile.lift
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
                        // An extended group's plate is the folder itself: as
                        // big as the block leaves after its label.
                        readonly property real size: tile.span > 1
                            ? Math.min(tile.width - 24, tile.height - 24 - (labelBox.visible ? root.labelHeight + root.labelGap : 0))
                            : root.iconSize
                        Layout.preferredWidth: plate.size
                        Layout.preferredHeight: plate.size
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
                            id: glyphLoader
                            anchors.centerIn: parent
                            readonly property real glyph: tile.entry.type === "group" ? plate.size
                                : plate.shaped ? root.iconSize * 0.64
                                : plate.style === "translucent" ? root.iconSize * 0.78 : root.iconSize
                            width: glyph
                            height: glyph
                            sourceComponent: tile.span > 1 ? largeGroupIcon
                                : tile.entry.type === "group" ? groupIcon : singleIcon
                        }
                        // Running: the dock's own indicator, under the icon.
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: -2
                            width: parent.width
                            height: runningIndicator.height
                            DockRunningIndicator {
                                id: runningIndicator
                                toplevels: (root.options.runningBadges ?? true) ? DesktopShortcuts.toplevelsFor(tile.entry) : []
                                edge: "top"
                                edgeExtent: plate.size * 0.8
                                scaleFactor: Math.max(0.75, root.iconScale)
                                margin: 0
                            }
                        }
                        // A link (every dropped file or folder): the shortcut
                        // arrow, so it never reads as a copy of the original.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: -2
                            anchors.bottomMargin: -2
                            visible: (root.options.linkBadges ?? true)
                                && tile.entry.type !== "group" && !!tile.entry.path
                                && DesktopShortcuts.linkedPaths[tile.entry.path] === true
                            width: Math.round(18 * Math.max(0.75, root.iconScale))
                            height: width
                            radius: width / 2
                            color: Appearance.m3colors.m3surfaceContainerHighest
                            border.width: 1
                            border.color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.6)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_outward"
                                iconSize: parent.width * 0.72
                                color: Appearance.m3colors.m3onSurface
                            }
                        }
                        // Unread notifications from the app.
                        AppNotificationBadge {
                            count: (root.options.notificationBadges ?? true) ? DesktopShortcuts.unreadCount(tile.entry) : 0
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
                        id: glyphIcon
                        implicitSize: root.iconSize
                        // The tiles ARE minified in Edit Mode (the mode's
                        // shrink has no counter for them — they are the
                        // desktop). Mipmapping keeps their edges clean.
                        mipmap: true
                        // A file with a thumbnail (a photo, a PDF's first
                        // page, a video frame) shows it, as a file manager
                        // does; the type icon holds until the picture loads.
                        readonly property string thumbnail: tile.entry.type === "file" && !tile.entry.customIcon
                            ? (DesktopShortcuts.fileThumbnails[tile.entry.path] ?? "") : ""
                        readonly property bool thumbnailShown: thumbnailImage.status === Image.Ready
                        source: glyphIcon.thumbnailShown ? ""
                            : DesktopShortcuts.iconSource(tile.entry.icon, tile.entry.type === "file" ? "text-x-generic" : "folder")
                        Image {
                            id: thumbnailImage
                            anchors.fill: parent
                            visible: glyphIcon.thumbnailShown
                            source: glyphIcon.thumbnail !== ""
                                ? DesktopShortcuts.fileUrl(glyphIcon.thumbnail) + "?" + (tile.entry.modified ?? 0) : ""
                            sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            mipmap: true
                            smooth: true
                            // A hairline frame on the picture itself, so a
                            // white page reads on a light wallpaper.
                            Rectangle {
                                anchors.centerIn: parent
                                width: thumbnailImage.paintedWidth
                                height: thumbnailImage.paintedHeight
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.7)
                            }
                        }

                        // A soft shadow under the picture; hovering warms it
                        // into a glow of the primary while the tile lifts.
                        readonly property bool lit: root.iconShadow && tile.hovered && !tile.dragging
                        layer.enabled: root.iconShadow
                        layer.effect: GE.DropShadow {
                            radius: glyphIcon.lit ? 20 : 12
                            samples: 41
                            spread: glyphIcon.lit ? 0.3 : 0.12
                            verticalOffset: glyphIcon.lit ? 0 : 3
                            color: glyphIcon.lit ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.3)
                                : ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.5)
                            transparentBorder: true

                            Behavior on radius {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on spread {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on verticalOffset {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }

                        // A folder shows what is in it, as Dolphin does: up
                        // to four pictures on the folder's front, one alone
                        // drawn large. The face is the part of a folder icon
                        // below the tab, kept clear of its rim. A folder with
                        // a picture of its own keeps its face: the previews
                        // would sit on what the person chose.
                        readonly property var previews: tile.entry.type === "directory" && !tile.entry.customIcon
                            ? (DesktopShortcuts.folderPreviews[tile.entry.path] ?? []) : []
                        Grid {
                            visible: glyphIcon.previews.length > 0
                            x: glyphIcon.width * 0.2
                            y: glyphIcon.height * 0.32
                            width: glyphIcon.width * 0.6
                            height: glyphIcon.height * 0.52
                            columns: glyphIcon.previews.length > 1 ? 2 : 1
                            spacing: glyphIcon.width * 0.04
                            readonly property real cell: glyphIcon.previews.length > 1 ? (width - spacing) / 2 : width
                            readonly property real cellHeight: glyphIcon.previews.length > 1 ? (height - spacing) / 2 : height
                            Repeater {
                                model: glyphIcon.previews
                                delegate: Image {
                                    required property string modelData
                                    width: parent.cell
                                    height: parent.cellHeight
                                    source: "file://" + modelData
                                    sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    mipmap: true
                                    smooth: true
                                }
                            }
                        }
                    }
                }
                Component {
                    id: groupIcon
                    DesktopGroupFace {
                        apps: tile.entry.apps
                        shape: root.groupShapeOf(tile.entry)
                        fill: root.groupFillOf(tile.entry)
                        mask: root.groupMaskOf(tile.entry)
                        glass: root.groupColorOf(tile.entry) === "glass"
                        rim: root.groupRim
                    }
                }
                Component {
                    id: largeGroupIcon
                    DesktopGroupLarge {
                        id: largeView
                        entry: tile.entry
                        shape: root.groupShapeOf(tile.entry)
                        fill: root.groupFillOf(tile.entry)
                        onFill: root.groupOnFillOf(tile.entry)
                        mask: root.groupMaskOf(tile.entry)
                        glass: root.groupColorOf(tile.entry) === "glass"
                        rim: root.groupRim
                        hovering: tile.hovered
                        hoverPoint: largeView.mapFromItem(tile, tileHover.point.position.x, tileHover.point.position.y)
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
                        tileContent.grabToImage(result => tile.dragImage = result.url,
                            Qt.size(Math.round(tileContent.width * 0.75), Math.round(tileContent.height * 0.75)));
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
                    } else if (tile.span > 1) {
                        // An extended group: the spot under the pointer opens
                        // its own app, the mini group opens the popup.
                        root.armedId = "";
                        clickTimer.stop();
                        root.openGroupSpot(tile, mouse.x, mouse.y);
                    } else if (Config.options.interactions.desktopDoubleClick
                        && tile.entry.type !== "group"
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
            sections: Array.from(root.groups).map(g => String(g?.title ?? ""))
            currentSection: {
                const entry = root.contextEntry;
                const i = entry ? root.sectionIndexOf(entry) : -1;
                return i >= 0 ? String(root.groups[i]?.title ?? "") : "";
            }
            onSectionRequested: (ids, title) => Qt.callLater(() => root.moveToSection(ids, title))
            onSectionRenameRequested: (from, to) => root.renameSection(from, to)
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
            insets: root.counterScale === 1 ? DesktopShortcuts.panelInsets(root.screenName) : ({ left: 8, top: 8, right: 8, bottom: 8 })
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
            onExtendRequested: {
                const id = root.popupId;
                const screenName = root.screenName;
                const large = !(root.popupEntry?.large ?? false);
                root.closePopup();
                Qt.callLater(() => DesktopShortcuts.setGroupLarge(screenName, id, large));
            }
            onUngroupRequested: {
                const id = root.popupId;
                const screenName = root.screenName;
                root.closePopup();
                Qt.callLater(() => DesktopShortcuts.ungroup(screenName, id));
            }
        }
    }
}
