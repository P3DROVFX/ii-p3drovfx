import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar.registry
import QtQuick
import Quickshell

/**
 * One bar's worth of Edit Mode: the horizontal and the vertical content trees
 * instantiate the same coordinator, so both run one reorder logic.
 *
 * The drawn widgets register themselves (BarEditSlot) with their stored list
 * and index, so a drop is answered directly in stored indices; a list with
 * nothing drawn gets a stand-in anchor so it stays a valid target. The
 * placeholder and the ghost are positioned imperatively rather than bound,
 * because their positions are maps of OTHER items' geometry, which a binding
 * would not re-read when an ancestor moves.
 *
 * The row previews the drop while the gesture is still running: the widget
 * being carried collapses out of its place and the same room opens where it
 * would land (BarComponent reads `gapBefore`/`gapAfter`/`isLifted`). A row
 * dragged out of Edit Mode's catalogue arrives through `externalDragMoved`
 * and gets the same preview, because the drawer lives on another surface and
 * can only hand this one a point.
 *
 * Every write here is one history entry, closed over copies of the touched
 * lists and reaching only the Config singleton - the stack outlives the
 * overlays the mode tears down.
 */
Item {
    id: root

    property bool vertical: false
    readonly property string axis: root.vertical ? "y" : "x"
    readonly property string screenName: root.QsWindow.window?.screen?.name ?? ""

    property var slots: []
    property var dragSlot: null
    readonly property bool dragActive: root.dragSlot !== null
    property var dropTarget: null
    // The frozen candidate table and the gesture's own decision state. Built
    // once when the press commits, from the RESTING row, and every pointer
    // sample resolves against that - never against the geometry the preview
    // itself is moving. Re-asking `barDropTarget` per sample let the preview
    // decide the next preview: the hole opened, a neighbour's live centre
    // slid past the pointer, the answer flipped, the row re-animated - the
    // flicker on every swap. See edit_mode.js, "The reorder target, decided
    // on frozen cells". The hold window is the bar's own resize clock.
    property var dragCells: null
    property var dragState: null
    readonly property real settleWindow: Appearance.animation.barResize.duration + 140

    // The window this bar is drawn in, published for the chrome: a catalogue
    // row dragged over here arrives in screen coordinates and has to be
    // brought into this window's before any of the arithmetic below means
    // anything.
    readonly property var barWindow: root.QsWindow.window
    readonly property real windowWidth: root.barWindow ? root.barWindow.width : 0
    readonly property real windowHeight: root.barWindow ? root.barWindow.height : 0
    // Both orientations declare a controller, and the plain bar window and
    // Connect Mode's panel can hold one each at the same time. Only the one
    // that is actually drawn answers for its screen.
    readonly property bool usable: root.vertical === (Config.options?.bar?.vertical ?? false)
        && root.windowWidth > 0 && root.width > 0 && root.height > 0

    onScreenNameChanged: GlobalStates.registerBarEditController(root.screenName, root)
    Component.onCompleted: GlobalStates.registerBarEditController(root.screenName, root)
    Component.onDestruction: GlobalStates.unregisterBarEditController(root)

    function registerSlot(slot) {
        root.slots = root.slots.concat([slot]);
    }

    function unregisterSlot(slot) {
        root.slots = root.slots.filter(s => s !== slot);
        if (root.dragSlot === slot)
            root.endDrag();
    }

    // ── Store access: literal paths, so every write stays greppable ─────────
    function storedList(bucket) {
        if (bucket === 0) return Config.options.bar.layouts.left;
        if (bucket === 1) return Config.options.bar.layouts.center;
        return Config.options.bar.layouts.right;
    }

    function writeList(bucket, list) {
        if (bucket === 0) Config.options.bar.layouts.left = list;
        else if (bucket === 1) Config.options.bar.layouts.center = list;
        else Config.options.bar.layouts.right = list;
    }

    function plainEntry(entry) {
        const out = Object.assign({}, entry);
        out.id = entry.id;
        out.visible = entry.visible !== false;
        out.centered = !!entry.centered;
        return out;
    }

    function snapshot(bucket) {
        return EditModeLogic.listCopy(root.storedList(bucket)).map(root.plainEntry);
    }

    function commit(before, after, buckets) {
        for (const b of buckets)
            root.writeList(b, after[b]);
        GlobalStates.editHistoryPush({
            "undo": () => { for (const b of buckets) root.writeList(b, before[b]); },
            "redo": () => { for (const b of buckets) root.writeList(b, after[b]); }
        });
    }

    // ── The centre, when there is no centre ──────────────────────────────────
    // With the Dynamic Island centred in the bar, BarLayout hands the centre
    // section an empty list whatever the store holds: the island is drawn over
    // that stretch of bar and the widgets underneath it are not rendered at
    // all. A drop into the centre list therefore LOOKED like the widget
    // vanishing - it was still stored, still counted by the catalogue, and
    // nowhere on screen. So while the island owns the centre, the centre is
    // not a drop target at all: it is dropped from the anchors, its slots are
    // dropped from the candidates, and a commit that somehow still names it is
    // refused. EditModeChromeSurface's `evictBarCentre()` is the other half -
    // it takes whatever is already stored there out, once, on the way in.
    readonly property bool centreBlocked: ShellModePolicy.barCenterActive

    // ── The gesture ──────────────────────────────────────────────────────────
    function anchorFor(bucket) {
        if (bucket === 1 && root.centreBlocked)
            return null;
        const f = [0.1, 0.5, 0.9][bucket];
        return root.vertical
            ? root.mapToItem(null, root.width / 2, root.height * f)
            : root.mapToItem(null, root.width * f, root.height / 2);
    }

    // The frozen candidate table, measured off the RESTING row. Call this
    // before anything arms the preview: setting `dragSlot` is what lifts the
    // carried widget and opens the first hole, and a table built after that
    // would freeze the row mid-parting.
    function restingCells(excludeSlot) {
        const groups = [];
        const empties = [];
        for (let b = 0; b < 3; b++) {
            if (b === 1 && root.centreBlocked)
                continue;
            const list = root.slots
                .filter(s => s !== excludeSlot && s.bucket === b && s.width > 0 && s.height > 0)
                .map(s => {
                    const at = s.mapToItem(root, s.width / 2, s.height / 2);
                    return {
                        "index": s.storedIndex,
                        "at": root.vertical ? at.y : at.x,
                        "extent": root.vertical ? s.height : s.width
                    };
                });
            if (list.length === 0) {
                const a = root.anchorFor(b);
                if (a) {
                    const la = root.mapFromItem(null, a.x, a.y);
                    empties.push({ "bucket": b, "at": root.vertical ? la.y : la.x });
                }
                continue;
            }
            groups.push({ "bucket": b, "slots": list });
        }
        return EditModeLogic.buildBarGapCells(groups, empties);
    }

    function beginDrag(slot) {
        if (!GlobalStates.editMode)
            return;
        root.dragCells = root.restingCells(slot);
        root.dragState = EditModeLogic.createBarDragState();
        root.dragSlot = slot;
        root.dropTarget = null;
        // What the row has to make room for, measured off the widget itself
        // plus the layout's own spacing, so the gap that opens is the size of
        // the hole the widget left.
        root.dragExtent = (root.vertical ? slot.height : slot.width) + 4;
        GlobalStates.clearEditBarHover(null);
        GlobalStates.editBarDragActive = true;
    }

    function endDrag() {
        root.dragSlot = null;
        root.externalId = "";
        root.dropTarget = null;
        root.dragCells = null;
        root.dragState = null;
        GlobalStates.editBarDragActive = false;
        ghost.shown = false;
        indicator.shown = false;
    }

    // The drawn widgets other than the one being carried, in the shape
    // barDropTarget wants them. The fallback path for a row too degenerate to
    // freeze a table from (no candidates at all); a live-geometry answer is
    // fine there precisely because nothing moves - there is no preview to
    // feed back into the decision.
    function otherSlots() {
        return root.slots
            .filter(s => s !== root.dragSlot && !(root.centreBlocked && s.bucket === 1))
            .map(s => ({
                "bucket": s.bucket, "index": s.storedIndex, "centre": s.sceneCentre()
            }));
    }

    function targetAt(scenePoint) {
        // The frozen table answers while a gesture runs. A drag from the
        // catalogue gets one built on its first sample: the carried ROW item
        // lifts on press for a reorder, and an external preview opens a hole
        // too - both move the live centres, so both must resolve off the
        // resting geometry, not the moving one.
        if (!root.dragCells)
            root.dragCells = root.restingCells(root.dragSlot);
        if (!root.dragState)
            root.dragState = EditModeLogic.createBarDragState();
        if (root.dragCells.length > 0) {
            const local = root.mapFromItem(null, scenePoint.x, scenePoint.y);
            const r = EditModeLogic.resolveBarGap(root.dragCells,
                root.vertical ? local.y : local.x, root.dragState,
                { "now": Date.now(), "hysteresis": 0.25, "settleMs": root.settleWindow });
            if (r)
                return (r.cell.bucket === 1 && root.centreBlocked) ? null
                    : { "bucket": r.cell.bucket, "index": r.cell.index };
        }
        const target = EditModeLogic.barDropTarget(root.otherSlots(), [0, 1, 2].map(root.anchorFor), scenePoint, root.axis);
        return (target && target.bucket === 1 && root.centreBlocked) ? null : target;
    }

    // The answer at release: a candidate held by the accommodation window is
    // what the pointer last asked for, so letting go inside the hold still
    // lands on the gap the user was aiming at.
    function settledTarget() {
        if (EditModeLogic.flushBarGap(root.dragState) && root.dragState && root.dragState.chosen) {
            const c = root.dragState.chosen;
            if (c.bucket === 1 && root.centreBlocked)
                return null;
            root.dropTarget = { "bucket": c.bucket, "index": c.index };
        }
        return root.dropTarget;
    }

    function dragMoved(scenePoint) {
        if (!root.dragActive)
            return;
        root.rearmPreview();
        root.dropTarget = root.targetAt(scenePoint);
        const local = root.mapFromItem(null, scenePoint.x, scenePoint.y);
        ghost.x = local.x - ghost.width / 2;
        ghost.y = local.y - ghost.height / 2;
        ghost.shown = true;
        root.placeIndicator(root.dropTarget);
    }

    // ── A catalogue row carried over the bar ─────────────────────────────────
    // The drawer is on the chrome's surface and cannot see this window, so the
    // chrome brings the pointer into these coordinates and hands it over. The
    // preview from here on is the same one a reorder gets.
    property string externalId: ""
    readonly property bool externalActive: root.externalId !== ""

    function externalDragMoved(componentId, sceneX, sceneY) {
        if (!GlobalStates.editMode || root.dragActive) {
            root.externalDragEnd();
            return;
        }
        if (!root.externalActive)
            root.dragExtent = root.vertical ? 44 : 76;
        root.externalId = componentId;
        root.rearmPreview();
        GlobalStates.clearEditBarHover(null);
        GlobalStates.editBarDragActive = true;
        root.dropTarget = root.targetAt(Qt.point(sceneX, sceneY));
        root.placeIndicator(root.dropTarget);
    }

    function externalDragEnd() {
        if (!root.externalActive)
            return;
        root.externalId = "";
        root.dropTarget = null;
        // The table is frozen PER GESTURE: the row may have changed between
        // two visits from the catalogue, and a stale hold would answer the
        // next drag with the last one's decision.
        root.dragCells = null;
        root.dragState = null;
        GlobalStates.editBarDragActive = false;
        indicator.shown = false;
    }

    function externalDrop(componentId, sceneX, sceneY) {
        root.externalDragMoved(componentId, sceneX, sceneY);
        const target = root.settledTarget();
        root.externalDragEnd();
        if (!GlobalStates.editMode || !target || !componentId)
            return;
        if (target.bucket === 1 && root.centreBlocked)
            return;
        const before = [root.snapshot(0), root.snapshot(1), root.snapshot(2)];
        const after = before.map(l => l.map(e => Object.assign({}, e)));
        // A component belongs to one list at a time; the catalogue only offers
        // unused ones, but a stale offer must not double it.
        const touched = [target.bucket];
        for (let b = 0; b < 3; b++) {
            const at = after[b].findIndex(e => e && e.id === componentId);
            if (at === -1)
                continue;
            after[b].splice(at, 1);
            if (touched.indexOf(b) === -1)
                touched.push(b);
        }
        after[target.bucket].splice(Math.min(target.index, after[target.bucket].length), 0,
            { "id": componentId, "centered": false, "visible": true });
        root.commit(before, after, touched);
    }

    // ── The live preview ────────────────────────────────────────────────────
    // The row parts around the drop: the widget being carried collapses out of
    // its place and the same amount of room opens where it would land, so the
    // bar keeps its width and the gap under the pointer IS the answer. Every
    // drawn widget asks the two functions below for its own share of it.
    property real dragExtent: 0
    readonly property bool previewActive: root.dragActive || root.externalActive

    // Which drawn widget carries the gap, and on which side of it: the first
    // one at or past the insertion index, or after the last one when the drop
    // lands at the end. Null while nothing is being carried, and for a list
    // with nothing drawn in it - there the placeholder alone marks the spot.
    readonly property var gapAnchor: {
        if (!root.previewActive || !root.dropTarget)
            return null;
        const inBucket = root.slots.filter(s => s !== root.dragSlot && s.bucket === root.dropTarget.bucket)
            .sort((a, b) => a.storedIndex - b.storedIndex);
        if (inBucket.length === 0)
            return null;
        const at = inBucket.find(s => s.storedIndex >= root.dropTarget.index);
        const ref = at ?? inBucket[inBucket.length - 1];
        return { "bucket": ref.bucket, "index": ref.storedIndex, "after": at === undefined };
    }

    function gapBefore(bucket, storedIndex) {
        const a = root.gapAnchor;
        return (a && !a.after && a.bucket === bucket && a.index === storedIndex) ? root.dragExtent : 0;
    }

    function gapAfter(bucket, storedIndex) {
        const a = root.gapAnchor;
        return (a && a.after && a.bucket === bucket && a.index === storedIndex) ? root.dragExtent : 0;
    }

    // The placeholder that fills that gap. Re-placed on a tick rather than on
    // pointer events alone: the room it sits in opens over an animation, and
    // between two moves of the pointer the layout is still catching up. The
    // tick stops once the geometry it computes stops changing, so a pointer
    // held still over one spot costs nothing; anything that can move the
    // placeholder rearms it.
    //
    // The still-count must outlast the row's own clock. The hole opens on
    // `barResize` (280ms); the old fixed budget of 8 ticks (~128ms) stopped
    // re-placing the placeholder MID-animation, freezing it over the
    // neighbour it was meant to avoid - the "despositioned preview" of a
    // held pointer. A few ticks of margin over the resize settles it.
    property int settledTicks: 0
    readonly property int settleAfter: Math.ceil(
        (Appearance.animation.barResize.duration + 140) / 16)
    function rearmPreview() {
        root.settledTicks = 0;
    }
    onDropTargetChanged: root.rearmPreview()
    onPreviewActiveChanged: root.rearmPreview()

    Timer {
        running: root.previewActive && root.settledTicks < root.settleAfter
        interval: 16
        repeat: true
        onTriggered: root.placeIndicator(root.dropTarget)
    }

    function placeIndicator(target) {
        if (!target) {
            indicator.shown = false;
            root.settledTicks = root.settledTicks + 1;
            return;
        }
        const inBucket = root.slots.filter(s => s !== root.dragSlot && s.bucket === target.bucket)
            .sort((a, b) => a.storedIndex - b.storedIndex);
        let along, extent, crossCentre, crossSize;
        if (inBucket.length === 0) {
            // Nothing drawn in this list, so there is no margin animating and
            // nothing to measure: the anchor and the drag's own extent are all
            // there is.
            extent = Math.max(12, root.dragExtent - 4);
            const a = root.mapFromItem(null, root.anchorFor(target.bucket).x, root.anchorFor(target.bucket).y);
            along = (root.vertical ? a.y : a.x) - extent / 2;
            crossCentre = root.vertical ? a.x : a.y;
            crossSize = root.vertical ? root.width * 0.6 : root.height * 0.6;
        } else {
            let ref = inBucket.find(s => s.storedIndex >= target.index);
            const after = ref === undefined;
            if (after)
                ref = inBucket[inBucket.length - 1];
            const tl = ref.mapToItem(root, 0, 0);
            const size = root.vertical ? ref.height : ref.width;
            const start = root.vertical ? tl.y : tl.x;
            // The room as it IS, not as it will be. `ref` animates its own
            // margin open on the bar's clock, and an indicator drawn at the
            // drop's final extent covered the neighbour for the whole of that
            // - so it is measured off the live margin instead, and grows with
            // the hole it marks.
            const hole = Math.max(0, after ? ref.gapAfter : ref.gapBefore);
            extent = Math.max(0, hole - 4);
            along = after ? start + size + 2 : start - hole + 2;
            crossCentre = root.vertical ? tl.x + ref.width / 2 : tl.y + ref.height / 2;
            crossSize = root.vertical ? ref.width : ref.height;
        }
        const width = root.vertical ? crossSize : extent;
        const height = root.vertical ? extent : crossSize;
        const x = root.vertical ? crossCentre - crossSize / 2 : along;
        const y = root.vertical ? along : crossCentre - crossSize / 2;
        // A tick that computed the same rectangle as the last one is the
        // layout having settled; a few of those in a row stop the timer.
        const still = indicator.width === width && indicator.height === height
            && indicator.x === x && indicator.y === y && indicator.shown;
        root.settledTicks = still ? root.settledTicks + 1 : 0;
        indicator.width = width;
        indicator.height = height;
        indicator.x = x;
        indicator.y = y;
        indicator.shown = true;
    }

    // ── The commits, guarded on the mode: a drag can outlive it ─────────────
    function drop() {
        const slot = root.dragSlot;
        // The decision AT release, not the last sample: a candidate still
        // held by the accommodation window is applied first, so letting go
        // moments after crossing a boundary lands where the pointer aimed.
        // (Read before `endDrag`, which clears the state it flushes into.)
        const target = root.settledTarget();
        root.endDrag();
        if (!GlobalStates.editMode || !slot || !target)
            return;
        if (target.bucket === 1 && root.centreBlocked)
            return;
        const from = slot.bucket;
        const fromIndex = slot.storedIndex;
        const before = [root.snapshot(0), root.snapshot(1), root.snapshot(2)];
        const after = before.map(l => l.map(e => Object.assign({}, e)));
        const entry = after[from][fromIndex];
        if (!entry)
            return;
        if (target.bucket === from) {
            const dest = EditModeLogic.moveTargetForInsertion(fromIndex, target.index);
            if (dest === fromIndex)
                return;
            after[from].splice(fromIndex, 1);
            after[from].splice(dest, 0, entry);
            root.commit(before, after, [from]);
            return;
        }
        after[from].splice(fromIndex, 1);
        // The centre split belongs to the centre list alone.
        if (from === 1)
            entry.centered = false;
        after[target.bucket].splice(Math.min(target.index, after[target.bucket].length), 0, entry);
        root.commit(before, after, [from, target.bucket]);
    }

    function removeSlot(slot) {
        root.removeAt(slot.bucket, slot.storedIndex);
    }

    function removeAt(bucket, index) {
        if (!GlobalStates.editMode)
            return;
        const before = [root.snapshot(0), root.snapshot(1), root.snapshot(2)];
        const after = before.map(l => l.map(e => Object.assign({}, e)));
        if (!after[bucket][index])
            return;
        after[bucket].splice(index, 1);
        root.commit(before, after, [bucket]);
    }

    // "Center this": one centred entry at most, and the same row again
    // clears it.
    function toggleCenter(bucket, index) {
        if (!GlobalStates.editMode || bucket !== 1 || root.centreBlocked)
            return;
        const before = [root.snapshot(0), root.snapshot(1), root.snapshot(2)];
        const after = before.map(l => l.map(e => Object.assign({}, e)));
        const entry = after[1][index];
        if (!entry)
            return;
        const wasCentered = !!before[1][index].centered;
        after[1].forEach((e, i) => e.centered = (i === index && !wasCentered));
        root.commit(before, after, [1]);
    }

    function openMenu(slot, scenePoint) {
        const window = root.QsWindow.window;
        const entry = root.storedList(slot.bucket)[slot.storedIndex];
        GlobalStates.openEditBarMenu(root.screenName, root, slot.bucket, slot.storedIndex,
            !!(entry && entry.centered), scenePoint.x, scenePoint.y,
            window ? window.width : 0, window ? window.height : 0);
    }

    // The hovered widget's name, handed to the chrome the same way the menu's
    // anchor is: in this window's coordinates, for it to translate. It is drawn
    // over there because Edit Mode's toolbar sits on top of the bar's own
    // surface, so a label drawn here would end up underneath it.
    function showHoverName(slot) {
        const window = root.QsWindow.window;
        const at = slot.sceneCentre();
        GlobalStates.showEditBarHover(slot, root.screenName, root.widgetName(slot.widgetId), at.x, at.y,
            window ? window.width : 0, window ? window.height : 0);
    }

    function clearHoverName(slot) {
        GlobalStates.clearEditBarHover(slot);
    }

    function widgetName(widgetId) {
        const match = BarComponentRegistry.allComponents.find(c => c.id === widgetId);
        return match ? match.title : widgetId;
    }

    Connections {
        target: GlobalStates
        function onEditModeChanged() {
            if (!GlobalStates.editMode)
                root.endDrag();
        }
        function onEditBarDragCancel() {
            root.endDrag();
        }
    }

    // The room the drop reserves, drawn as the widget-shaped hole it is.
    Rectangle {
        id: indicator
        property bool shown: false
        visible: root.previewActive && shown
        radius: Appearance.rounding.small
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.4)
    }

    // The chip riding the pointer: a drag between distant lists carries its
    // name with it.
    Rectangle {
        id: ghost
        property bool shown: false
        visible: root.dragActive && shown
        z: 1
        width: ghostLabel.implicitWidth + 20
        height: 26
        radius: 13
        color: Appearance.colors.colSecondaryContainer

        StyledText {
            id: ghostLabel
            anchors.centerIn: parent
            text: root.dragSlot ? root.widgetName(root.dragSlot.widgetId) : ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
}
