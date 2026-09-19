pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    required property string screenName
    readonly property real cellSize: 100
    // Icon scale from Edit Mode's panel (Config.options.background.
    // desktopIconScale). The footprint stays exactly 100 — positions, the
    // 10px snap and every hit-test keep their old geometry — only the
    // plate inside it grows, so a scale change is one property write and a
    // handful of binding re-evaluations, never a rebuild. The whitelist
    // means a hand-edited config can't render an unoffered size: any value
    // outside 1 / 1.25 / 1.5 draws at 1.
    readonly property real iconScale: [1, 1.25, 1.5].includes(Config.options.background.desktopIconScale)
        ? Config.options.background.desktopIconScale : 1
    readonly property real iconSize: 56 * root.iconScale
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
            maxX = Math.min(maxX, root.width - root.cellSize - s.x);
            minY = Math.max(minY, -s.y);
            maxY = Math.min(maxY, root.height - root.cellSize - s.y);
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
                if (s.x < band.x + band.width && s.x + root.cellSize > band.x
                    && s.y < band.y + band.height && s.y + root.cellSize > band.y)
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
                root.openContext(entry.id, s.x + root.cellSize / 2,
                    s.y + root.cellSize / 2, "rename");
            }
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            event.accepted = true;
            root.selectedIds = root.items.map(item => item.id);
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
        return Qt.point(Math.max(0, Math.min(width - cellSize, Math.round(x / 10) * 10)),
                        Math.max(0, Math.min(height - cellSize, Math.round(y / 10) * 10)));
    }

    function targetAt(x, y, exceptId) {
        for (let i = 0; i < iconModel.count; ++i) {
            const item = iconModel.get(i).entry;
            if (item.id !== exceptId && DesktopShortcuts.isGroupable(item)
                && x >= item.x && x < item.x + cellSize && y >= item.y && y < item.y + cellSize)
                return item.id;
        }
        return "";
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

    Repeater {
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
            x: settled.x
            y: settled.y
            width: root.cellSize
            height: root.cellSize
            z: dragging || merging ? 1 : 0

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

            Item {
                id: tileContent
                anchors.fill: parent
                // Press feedback mirrors RippleButton's interactionScale (dip
                // while held, spring back on release), but at 0.9: a row swells
                // across ~350px so 0.96 reads strongly, while a 100px tile at
                // 0.96 moves the icon barely 2px — imperceptible. Suppressed
                // during a drag (the Translate already moves the tile) and for
                // the right button (that press opens the context menu).
                // `pressedButtons`, not `pressButton` — MouseArea has no such
                // property, and reading a missing one yields undefined, so the
                // old `pressButton === Qt.LeftButton` test was dead and this
                // dip had NEVER fired since the day it was written.
                scale: (gesture.pressedButtons & Qt.LeftButton) !== 0
                    && !tile.dragging ? 0.9 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                }
                transform: Translate {
                    x: tile.dragging ? tile.pending.x - tile.x : (tile.groupMember ? groupDrag.dx : 0)
                    y: tile.dragging ? tile.pending.y - tile.y : (tile.groupMember ? groupDrag.dy : 0)
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colPrimaryContainer
                    visible: root.dropTargetId === tile.entry.id
                }
                ColumnLayout {
                    anchors.fill: parent
                    // The gutter pays for the plate: at 1.5 the icon needs
                    // the whole cell (84 + label inside 100), so the margin
                    // thins to zero; at 1 it is the original 4.
                    anchors.margins: Math.max(0, 4 - 8 * (root.iconScale - 1))
                    // Negative on purpose: the label's line box carries a few
                    // px of transparent leading above the glyphs, so a "0"
                    // spacing already reads as a visible gap. -2 pulls the
                    // text up into that dead space, icon-to-cap height ≈ 2px.
                    Loader {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: root.iconSize
                        Layout.preferredHeight: root.iconSize
                        sourceComponent: tile.entry.type === "group" ? groupIcon : singleIcon
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: tileLabel.implicitHeight
                        // A bright wallpaper swallows the raised shadow — the
                        // old treatment was tuned for dark schemes. Then, and
                        // only then, the M3 inverse pair (guaranteed contrast
                        // against each other in EITHER scheme) draws a small
                        // scrim under the label; elsewhere the plate is
                        // visible:false — no node, no cost.
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, tileLabel.implicitWidth + 12)
                            height: tileLabel.implicitHeight + 5
                            radius: Appearance.rounding.small
                            color: Appearance.m3colors.m3inverseSurface
                            opacity: 0.7
                            visible: root.wallpaperLight
                        }
                        StyledText {
                            id: tileLabel
                            anchors.fill: parent
                            text: tile.entry.name || tile.entry.id
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.wallpaperLight
                                ? Appearance.m3colors.m3inverseOnSurface
                                : Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 1
                            style: root.wallpaperLight ? Text.Normal : Text.Raised
                            styleColor: Appearance.colors.colShadow
                        }
                    }
                }
                // Selection halo: the widget canvas's own, scaled to a tile —
                // same colour, fill and border, so one language says "picked"
                // whether it is a clock or a shortcut.
                Rectangle {
                    visible: opacity > 0.001
                    opacity: tile.selected ? 1 : 0
                    anchors.fill: parent
                    anchors.margins: -6
                    radius: Appearance.rounding.large
                    color: Qt.alpha(Appearance.colors.colPrimary, 0.08)
                    border.color: Appearance.colors.colPrimary
                    border.width: 2
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
                Component {
                    id: singleIcon
                    IconImage {
                        implicitSize: root.iconSize
                        // The tiles ARE minified in Edit Mode (the mode's
                        // shrink has no counter for them — they are the
                        // desktop). Mipmapping the icon texture is what
                        // keeps their edges from stair-stepping, and it
                        // costs +33% of a 56px RGBA blit, nothing per frame.
                        mipmap: true
                        source: Quickshell.iconPath(tile.entry.icon || (tile.entry.type === "file" ? "text-x-generic" : "folder"), "image-missing")
                    }
                }
                Component {
                    id: groupIcon
                    Rectangle {
                        radius: Appearance.rounding.normal
                        color: Appearance.m3colors.m3surfaceContainerHigh
                        Grid {
                            anchors.centerIn: parent
                            columns: 2
                            spacing: 4 * root.iconScale
                            Repeater {
                                model: tile.entry.apps.slice(0, 4)
                                delegate: IconImage {
                                    required property var modelData
                                    implicitSize: 22 * root.iconScale
                                    mipmap: true
                                    source: Quickshell.iconPath(modelData.icon, "image-missing")
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
                    tile.origin = Qt.point(tile.x, tile.y);
                }
                onPositionChanged: mouse => {
                    if (!(pressedButtons & Qt.LeftButton))
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
                    if (!tile.dragging) {
                        tile.dragging = true;
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
                    } else {
                        root.dropTargetId = DesktopShortcuts.isGroupable(tile.entry) ? root.targetAt(p.x, p.y, tile.entry.id) : "";
                    }
                }
                onReleased: {
                    if (!tile.dragging)
                        return;
                    const itemId = tile.entry.id;
                    const targetId = root.dropTargetId;
                    const p = tile.pending;
                    tile.dragging = false;
                    root.dropTargetId = "";
                    if (groupDrag.leaderId === itemId) {
                        // One write for the cluster; merging is a single-drag
                        // gesture, so the group just travels.
                        const ids = groupDrag.ids;
                        const ddx = groupDrag.dx;
                        const ddy = groupDrag.dy;
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
                        tile.merging = true;
                        tile.mergeData = { id: itemId, x: p.x, y: p.y, target: targetId };
                        mergeMotion.start();
                        return;
                    }
                    // A plain move may still destroy nothing, but the write
                    // must wait for this release to be dispatched.
                    Qt.callLater(() => DesktopShortcuts.move(root.screenName, itemId, p.x, p.y, targetId));
                }
                onCanceled: {
                    if (groupDrag.leaderId === tile.entry.id) {
                        groupDrag.leaderId = "";
                        groupDrag.ids = [];
                        groupDrag.dx = 0;
                        groupDrag.dy = 0;
                    }
                    tile.dragging = false;
                    tile.suppressClick = true;
                    root.dropTargetId = "";
                }
                onClicked: mouse => {
                    if (tile.suppressClick)
                        return;
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
                        if (tile.entry.type === "group")
                            // A folder opens its contents, not its menu: the
                            // grid popup anchored to the tile. The menu is one
                            // right-click away, as for everything else.
                            root.openPopup(tile.entry.id, tile.x, tile.y, tile.width, tile.height);
                        else
                            DesktopShortcuts.launch(tile.entry);
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
