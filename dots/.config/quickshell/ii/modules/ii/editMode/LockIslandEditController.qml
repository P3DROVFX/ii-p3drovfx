import qs
import qs.modules.common
import qs.modules.common.functions
import "../../common/functions/lock_islands.js" as LockIslands
import QtQuick

/**
 * The lock islands' Edit Mode reorder, loaded by LockSurface over the
 * Lockscreen tab's preview. It spawns one LockIslandEditItem per reorderable
 * slot, owns the drag's bookkeeping and the drop indicator, and commits the
 * move through Config. One bucket per drag: an item reorders within its own
 * island, since each island's vocabulary is its own defaults.
 *
 * Indices are RENDERED indices (the resolver's answer), so a hidden slot is a
 * hole among the centres rather than a shift in the indexing.
 */
Item {
    id: root

    property Item surface: null

    property var slots: []
    property var dragSlot: null
    readonly property bool dragActive: root.dragSlot !== null
    property var dropTarget: null

    readonly property var slotModel: {
        const out = [];
        if (!root.surface)
            return out;
        for (const island of ["main", "left", "right"]) {
            const order = root.surface.islandOrder(island);
            const items = root.surface.islandItems[island];
            order.forEach((id, index) => {
                if (LockIslands.reorderable(island, id) && items[id])
                    out.push({ "island": island, "index": index, "item": items[id] });
            });
        }
        return out;
    }

    function registerSlot(slot) {
        root.slots = root.slots.concat([slot]);
    }

    function unregisterSlot(slot) {
        root.slots = root.slots.filter(s => s !== slot);
        if (root.dragSlot === slot)
            root.endDrag();
    }

    function storedList(island) {
        if (island === "main") return Config.options.lock.islands.main;
        if (island === "left") return Config.options.lock.islands.left;
        return Config.options.lock.islands.right;
    }

    function othersOf(slot) {
        return root.slots.filter(s => s !== slot && s.island === slot.island && s.slotVisible());
    }

    // ── The gesture ──────────────────────────────────────────────────────────
    function beginDrag(slot) {
        if (!GlobalStates.editMode)
            return;
        root.dragSlot = slot;
        root.dropTarget = null;
        GlobalStates.editBarDragActive = true;
    }

    function endDrag() {
        root.dragSlot = null;
        root.dropTarget = null;
        GlobalStates.editBarDragActive = false;
        indicator.shown = false;
    }

    function dragMoved(scenePoint) {
        if (!root.dragActive)
            return;
        const slot = root.dragSlot;
        const others = root.othersOf(slot).map(s => ({
            "bucket": 0, "index": s.renderedIndex, "centre": s.sceneCentre()
        }));
        const toolbar = root.surface.islandToolbars[slot.island];
        const anchor = toolbar.mapToItem(null, toolbar.width / 2, toolbar.height / 2);
        root.dropTarget = EditModeLogic.barDropTarget(others, [anchor], scenePoint, "x");
        root.placeIndicator(root.dropTarget);
    }

    // The indicator marks the GAP the insertion names: before the first drawn
    // slot at or past the index, after the last one otherwise.
    function placeIndicator(target) {
        if (!target) {
            indicator.shown = false;
            return;
        }
        const inIsland = root.othersOf(root.dragSlot).sort((a, b) => a.renderedIndex - b.renderedIndex);
        if (inIsland.length === 0) {
            indicator.shown = false;
            return;
        }
        let ref = inIsland.find(s => s.renderedIndex >= target.index);
        const after = ref === undefined;
        if (after)
            ref = inIsland[inIsland.length - 1];
        const tl = ref.mapToItem(root, 0, 0);
        indicator.width = 3;
        indicator.height = ref.height;
        indicator.x = (after ? tl.x + ref.width : tl.x) - 1.5;
        indicator.y = tl.y;
        indicator.shown = true;
    }

    // Guarded on the mode: a drag can outlive it.
    function drop() {
        const slot = root.dragSlot;
        const target = root.dropTarget;
        root.endDrag();
        if (!GlobalStates.editMode || !slot || !target)
            return;
        const order = EditModeLogic.listCopy(root.surface.islandOrder(slot.island));
        const from = slot.renderedIndex;
        const dest = EditModeLogic.moveTargetForInsertion(from, target.index);
        if (dest === from || !order[from])
            return;
        const moved = order.slice();
        moved.splice(from, 1);
        moved.splice(dest, 0, order[from]);
        Config.setLockIslandOrder(slot.island,
            LockIslands.storedOrder(moved, root.storedList(slot.island), LockIslands.defaultsFor(slot.island)));
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

    Instantiator {
        model: root.slotModel
        delegate: LockIslandEditItem {
            required property var modelData
            controller: root
            island: modelData.island
            renderedIndex: modelData.index
            target: modelData.item
        }
    }

    Rectangle {
        id: indicator
        property bool shown: false
        visible: root.dragActive && shown
        radius: Appearance.rounding.unsharpen
        color: Appearance.colors.colPrimary
    }
}
