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

    function beginDrag(slot) {
        if (!GlobalStates.editMode)
            return;
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
        GlobalStates.editBarDragActive = false;
        ghost.shown = false;
        indicator.shown = false;
    }

    // The drawn widgets other than the one being carried, in the shape
    // barDropTarget wants them.
    function otherSlots() {
        return root.slots
            .filter(s => s !== root.dragSlot && !(root.centreBlocked && s.bucket === 1))
            .map(s => ({
                "bucket": s.bucket, "index": s.storedIndex, "centre": s.sceneCentre()
            }));
    }

    function targetAt(scenePoint) {
        const target = EditModeLogic.barDropTarget(root.otherSlots(), [0, 1, 2].map(root.anchorFor), scenePoint, root.axis);
        return (target && target.bucket === 1 && root.centreBlocked) ? null : target;
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
        GlobalStates.editBarDragActive = false;
        indicator.shown = false;
    }

    function externalDrop(componentId, sceneX, sceneY) {
        root.externalDragMoved(componentId, sceneX, sceneY);
        const target = root.dropTarget;
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

    function isLifted(bucket, storedIndex) {
        const s = root.dragSlot;
        return s !== null && s.bucket === bucket && s.storedIndex === storedIndex;
    }

    // The placeholder that fills that gap. Re-placed on a tick rather than on
    // pointer events alone: the room it sits in opens over an animation, and
    // between two moves of the pointer the layout is still catching up. The
    // tick stops once the geometry it computes stops changing, so a pointer
    // held still over one spot costs nothing; anything that can move the
    // placeholder rearms it.
    property int settledTicks: 0
    readonly property int settleAfter: 8
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
        const extent = Math.max(12, root.dragExtent - 4);
        const inBucket = root.slots.filter(s => s !== root.dragSlot && s.bucket === target.bucket)
            .sort((a, b) => a.storedIndex - b.storedIndex);
        let along, crossCentre, crossSize;
        if (inBucket.length === 0) {
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
            // The room has already been opened on the far side of `ref`, so
            // the placeholder sits in it rather than on the seam.
            along = after ? start + size + 2 : start - root.dragExtent + 2;
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
        const target = root.dropTarget;
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
