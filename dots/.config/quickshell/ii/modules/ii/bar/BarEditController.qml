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
 * indicator and the ghost are positioned per pointer event rather than bound,
 * because their positions are maps of OTHER items' geometry, which a binding
 * would not re-read when an ancestor moves.
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

    // ── The gesture ──────────────────────────────────────────────────────────
    function anchorFor(bucket) {
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
        GlobalStates.clearEditBarHover(null);
        GlobalStates.editBarDragActive = true;
    }

    function endDrag() {
        root.dragSlot = null;
        root.dropTarget = null;
        GlobalStates.editBarDragActive = false;
        ghost.shown = false;
        indicator.shown = false;
    }

    function dragMoved(scenePoint) {
        if (!root.dragActive)
            return;
        const others = root.slots.filter(s => s !== root.dragSlot).map(s => ({
            "bucket": s.bucket, "index": s.storedIndex, "centre": s.sceneCentre()
        }));
        root.dropTarget = EditModeLogic.barDropTarget(others, [0, 1, 2].map(root.anchorFor), scenePoint, root.axis);
        const local = root.mapFromItem(null, scenePoint.x, scenePoint.y);
        ghost.x = local.x - ghost.width / 2;
        ghost.y = local.y - ghost.height / 2;
        ghost.shown = true;
        root.placeIndicator(others, root.dropTarget);
    }

    // The indicator marks the GAP the insertion names: before the first drawn
    // slot at or past the index, after the last one otherwise, and the
    // stand-in for an empty list.
    function placeIndicator(others, target) {
        if (!target) {
            indicator.shown = false;
            return;
        }
        const inBucket = root.slots.filter(s => s !== root.dragSlot && s.bucket === target.bucket)
            .sort((a, b) => a.storedIndex - b.storedIndex);
        let along, crossCentre, crossSize;
        if (inBucket.length === 0) {
            const a = root.mapFromItem(null, root.anchorFor(target.bucket).x, root.anchorFor(target.bucket).y);
            along = root.vertical ? a.y : a.x;
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
            along = after ? start + size : start;
            crossCentre = root.vertical ? tl.x + ref.width / 2 : tl.y + ref.height / 2;
            crossSize = root.vertical ? ref.width : ref.height;
        }
        if (root.vertical) {
            indicator.width = crossSize;
            indicator.height = 3;
            indicator.x = crossCentre - crossSize / 2;
            indicator.y = along - 1.5;
        } else {
            indicator.width = 3;
            indicator.height = crossSize;
            indicator.x = along - 1.5;
            indicator.y = crossCentre - crossSize / 2;
        }
        indicator.shown = true;
    }

    // ── The commits, guarded on the mode: a drag can outlive it ─────────────
    function drop() {
        const slot = root.dragSlot;
        const target = root.dropTarget;
        root.endDrag();
        if (!GlobalStates.editMode || !slot || !target)
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
        if (!GlobalStates.editMode || bucket !== 1)
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

    Rectangle {
        id: indicator
        property bool shown: false
        visible: root.dragActive && shown
        radius: Appearance.rounding.unsharpen
        color: Appearance.colors.colPrimary
    }

    // The chip riding the pointer: a drag between distant lists carries its
    // name with it.
    Rectangle {
        id: ghost
        property bool shown: false
        visible: root.dragActive && shown
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
