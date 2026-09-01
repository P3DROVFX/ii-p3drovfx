import QtQuick
import QtTest
import "../../modules/ii/dock/DockReorder.js" as DockReorder

TestCase {
    name: "DockReorder"

    // Four 60px icons, no spacing: slots [0,60] [60,120] [120,180] [180,240].
    function evenSlots() {
        return [
            { start: 0, end: 60 },
            { start: 60, end: 120 },
            { start: 120, end: 180 },
            { start: 180, end: 240 }
        ];
    }

    // An icon, a three-slot widget, an icon.
    function mixedSlots() {
        return [
            { start: 0, end: 60 },
            { start: 60, end: 240 },
            { start: 240, end: 300 }
        ];
    }

    function ids(items) {
        return items.map(function (item) { return item.orderKey; });
    }

    function item(orderKey) {
        return { orderKey: orderKey, type: "app", appId: orderKey };
    }

    // ── Drop index ────────────────────────────────────────────────────────

    function test_drop_target_follows_the_pointer_not_the_travelled_distance() {
        const slots = evenSlots();
        const state = DockReorder.createDragState();
        state.targetIndex = 0;
        // Straight to the far end: the answer is where the pointer is, not the
        // sum of the thresholds it crossed on the way.
        compare(DockReorder.resolveDropIndex(slots, 210, 0, state, {}).index, 3);
        compare(DockReorder.resolveDropIndex(slots, 30, 0, state, {}).index, 0);
    }

    function test_taking_a_neighbour_needs_real_penetration() {
        const slots = evenSlots();
        const state = DockReorder.createDragState();
        state.targetIndex = 0;
        const options = { hysteresis: 0.25 };

        // Just past the seam is not enough.
        compare(DockReorder.resolveDropIndex(slots, 62, 0, state, options).index, 0);
        compare(DockReorder.resolveDropIndex(slots, 74, 0, state, options).index, 0);
        // A quarter into the neighbour hands it over.
        compare(DockReorder.resolveDropIndex(slots, 76, 0, state, options).index, 1);
        // And the same margin protects the way back.
        compare(DockReorder.resolveDropIndex(slots, 58, 0, state, options).index, 1);
        compare(DockReorder.resolveDropIndex(slots, 44, 0, state, options).index, 0);
    }

    function test_pointer_resting_on_a_seam_never_oscillates() {
        const slots = evenSlots();
        const state = DockReorder.createDragState();
        state.targetIndex = 0;
        const options = { hysteresis: 0.25 };

        var seen = {};
        for (var i = 0; i < 40; i++) {
            const jitter = 60 + ((i % 2 === 0) ? -2 : 2);
            seen[DockReorder.resolveDropIndex(slots, jitter, 0, state, options).index] = true;
        }
        compare(Object.keys(seen).length, 1);
        compare(DockReorder.resolveDropIndex(slots, 60, 0, state, options).index, 0);
    }

    function test_pointer_in_the_gap_between_icons_keeps_reordering() {
        // Spacing pushes the slots apart; the pointer travelling through the
        // gap must resolve to a neighbour rather than falling back to nothing.
        const slots = [
            { start: 0, end: 60 },
            { start: 70, end: 130 }
        ];
        const state = DockReorder.createDragState();
        state.targetIndex = 0;
        // Equidistant keeps the slot it already has; past the middle of the gap
        // the next icon takes over.
        compare(DockReorder.resolveDropIndex(slots, 65, 0, state, { hysteresis: 0 }).index, 0);
        compare(DockReorder.resolveDropIndex(slots, 68, 0, state, { hysteresis: 0 }).index, 1);
    }

    function test_hysteresis_scales_with_the_target_not_a_fixed_width() {
        // The three-slot widget owns a much wider dead zone than the icon next
        // to it, which is the whole point of measuring against its own extent.
        const slots = mixedSlots();
        const state = DockReorder.createDragState();
        state.targetIndex = 0;
        const options = { hysteresis: 0.25 };
        // 25% of 180px means the pointer must reach 105 to claim the widget.
        compare(DockReorder.resolveDropIndex(slots, 100, 0, state, options).index, 0);
        compare(DockReorder.resolveDropIndex(slots, 110, 0, state, options).index, 1);
    }

    function test_zero_extent_slots_are_never_targets() {
        // An item collapsing out of the dock keeps its index but no width.
        const slots = [
            { start: 0, end: 60 },
            { start: 60, end: 60 },
            { start: 60, end: 120 }
        ];
        const state = DockReorder.createDragState();
        state.targetIndex = 0;
        compare(DockReorder.resolveDropIndex(slots, 60, 0, state, { hysteresis: 0.25 }).index, 0);
    }

    // ── Preview shift ─────────────────────────────────────────────────────

    function test_preview_shift_uses_the_dragged_item_footprint() {
        const slots = mixedSlots();
        // Dragging the 180px widget (index 1) onto index 2: only index 2 moves,
        // and it moves by the widget's own footprint.
        compare(DockReorder.previewShift(slots, 1, 2, 2, 0), -180);
        compare(DockReorder.previewShift(slots, 1, 2, 0, 0), 0);
        compare(DockReorder.previewShift(slots, 1, 2, 1, 0), 0);

        // Dragging the last icon to the front pushes both items right by 60.
        compare(DockReorder.previewShift(slots, 2, 0, 0, 0), 60);
        compare(DockReorder.previewShift(slots, 2, 0, 1, 0), 60);
    }

    function test_preview_shift_includes_spacing_and_honours_negative_spacing() {
        const slots = evenSlots();
        compare(DockReorder.previewShift(slots, 0, 2, 1, 6), -66);
        compare(DockReorder.previewShift(slots, 0, 2, 1, -1), -59);
        compare(DockReorder.previewShift(slots, 0, 0, 1, 6), 0);
    }

    // ── Grouping intent ───────────────────────────────────────────────────

    function groupable(count, exceptIndex) {
        var flags = [];
        for (var i = 0; i < count; i++)
            flags.push(i !== exceptIndex);
        return flags;
    }

    function test_grouping_requires_the_middle_of_the_icon() {
        const slots = evenSlots();
        const state = DockReorder.createDragState();
        const options = { enabled: true, centerZone: 0.5, dwellMs: 0, now: 0 };
        // Slot 1 spans 60..120, so its centre zone is 75..105.
        compare(DockReorder.resolveGroupIntent(slots, 65, 0, groupable(4, 0), state, options).candidate, -1);
        compare(DockReorder.resolveGroupIntent(slots, 90, 0, groupable(4, 0), state, options).candidate, 1);
        compare(DockReorder.resolveGroupIntent(slots, 115, 0, groupable(4, 0), state, options).candidate, -1);
    }

    function test_grouping_needs_a_hold_and_never_fires_on_a_pass_through() {
        const slots = evenSlots();
        const state = DockReorder.createDragState();
        const flags = groupable(4, 0);

        function sample(pointer, now) {
            return DockReorder.resolveGroupIntent(slots, pointer, 0, flags, state, {
                enabled: true, centerZone: 0.5, dwellMs: 200, now: now
            });
        }

        // Entering the centre only starts the hold.
        var first = sample(90, 1000);
        compare(first.candidate, 1);
        verify(!first.armed);
        compare(first.index, -1);

        // Still holding, but not long enough.
        verify(!sample(92, 1150).armed);
        // Sliding on through resets it: a drag that crosses the icon on its way
        // somewhere else must stay a reorder. 125 is inside slot 2 but off its
        // centre, which is exactly what passing over an icon looks like.
        compare(sample(125, 1200).candidate, -1);
        verify(!sample(90, 1260).armed);

        // A real hold arms it.
        verify(!sample(90, 1300).armed);
        var armed = sample(91, 1560);
        verify(armed.armed);
        compare(armed.index, 1);
    }

    function test_group_progress_reports_the_hold_building() {
        const slots = evenSlots();
        const state = DockReorder.createDragState();
        const flags = groupable(4, 0);

        DockReorder.resolveGroupIntent(slots, 90, 0, flags, state, { enabled: true, centerZone: 0.5, dwellMs: 200, now: 0 });
        compare(DockReorder.resolveGroupIntent(slots, 90, 0, flags, state, { enabled: true, centerZone: 0.5, dwellMs: 200, now: 100 }).progress, 0.5);
        compare(DockReorder.resolveGroupIntent(slots, 150, 0, flags, state, { enabled: true, centerZone: 0.5, dwellMs: 200, now: 120 }).progress, 0);
    }

    function test_ungroupable_items_and_the_source_are_ignored() {
        const slots = evenSlots();
        const state = DockReorder.createDragState();
        const flags = [true, false, true, true];
        const options = { enabled: true, centerZone: 0.5, dwellMs: 0, now: 0 };
        // Index 1 is not groupable (a widget, or the same app).
        compare(DockReorder.resolveGroupIntent(slots, 90, 0, flags, state, options).candidate, -1);
        // The dragged item itself is never its own group target.
        compare(DockReorder.resolveGroupIntent(slots, 30, 0, flags, state, options).candidate, -1);
        // A groupable neighbour still arms.
        compare(DockReorder.resolveGroupIntent(slots, 150, 0, flags, state, options).candidate, 2);
    }

    function test_grouping_disabled_clears_the_state() {
        const slots = evenSlots();
        const state = DockReorder.createDragState();
        DockReorder.resolveGroupIntent(slots, 90, 0, groupable(4, 0), state, {
            enabled: true, centerZone: 0.5, dwellMs: 0, now: 0
        });
        const off = DockReorder.resolveGroupIntent(slots, 90, 0, groupable(4, 0), state, {
            enabled: false, centerZone: 0.5, dwellMs: 0, now: 0
        });
        compare(off.index, -1);
        compare(state.groupIndex, -1);
    }

    // ── Smart grouping ────────────────────────────────────────────────────

    function test_smart_grouping_sorts_by_category() {
        const items = [item("app:editor"), item("app:browser"), item("app:term")];
        const sorted = DockReorder.applySmartGrouping(items, [30, 10, 20], []);
        compare(ids(sorted), ["app:browser", "app:term", "app:editor"]);
    }

    function test_smart_grouping_is_stable_inside_a_category() {
        const items = [item("a"), item("b"), item("c"), item("d")];
        const sorted = DockReorder.applySmartGrouping(items, [10, 20, 10, 20], []);
        compare(ids(sorted), ["a", "c", "b", "d"]);
    }

    // The regression this whole mechanism exists for: a widget is alone in its
    // category, so the category sort put it straight back and dragging it was
    // silently impossible.
    function test_a_hand_placed_item_keeps_its_slot() {
        const items = [item("weather"), item("app:browser"), item("app:term")];
        const categories = [3, 10, 20];
        compare(ids(DockReorder.applySmartGrouping(items, categories, [])),
                ["weather", "app:browser", "app:term"]);

        // The user drags the weather widget to the end: order becomes
        // browser, term, weather — and the anchor keeps it there.
        const moved = [item("app:browser"), item("app:term"), item("weather")];
        const movedCategories = [10, 20, 3];
        compare(ids(DockReorder.applySmartGrouping(moved, movedCategories, [])),
                ["weather", "app:browser", "app:term"]);
        compare(ids(DockReorder.applySmartGrouping(moved, movedCategories, ["weather"])),
                ["app:browser", "app:term", "weather"]);
    }

    function test_anchors_hold_their_slot_while_the_rest_auto_arranges() {
        const items = [item("a"), item("pinned"), item("b"), item("c")];
        const categories = [30, 50, 20, 10];
        // "pinned" stays at index 1; everything else fills the free slots in
        // category order.
        compare(ids(DockReorder.applySmartGrouping(items, categories, ["pinned"])),
                ["c", "pinned", "b", "a"]);
    }

    function test_manual_keys_are_added_once_and_pruned_when_the_item_leaves() {
        var keys = DockReorder.withManualKey([], "media");
        compare(keys, ["media"]);
        compare(DockReorder.withManualKey(keys, "media"), ["media"]);
        compare(DockReorder.withManualKey(keys, "app:kitty"), ["media", "app:kitty"]);
        compare(DockReorder.pruneManualKeys(["media", "app:gone"], ["media", "app:kitty"]), ["media"]);
    }

    // A QML list<string> reaches JavaScript as an array-like, not an Array.
    // Treating one as a plain object would anchor the indices "0", "1", … and
    // silently anchor nothing at all.
    function test_manual_keys_accept_a_qml_style_list() {
        const arrayLike = { length: 1, 0: "pinned" };
        const items = [item("a"), item("pinned"), item("b")];
        compare(ids(DockReorder.applySmartGrouping(items, [30, 50, 10], arrayLike)),
                ["b", "pinned", "a"]);
        compare(DockReorder.withManualKey(arrayLike, "media"), ["pinned", "media"]);
        compare(DockReorder.pruneManualKeys(arrayLike, { length: 1, 0: "pinned" }), ["pinned"]);
    }

    // ── Enter / exit retention ────────────────────────────────────────────

    function test_removed_items_are_collected_with_the_slot_they_held() {
        const before = [item("a"), item("b"), item("c")];
        const after = [item("a"), item("c")];
        const removed = DockReorder.collectRemovedItems(before, after, 500);
        compare(removed.length, 1);
        compare(removed[0].key, "b");
        compare(removed[0].index, 1);
        compare(removed[0].at, 500);
    }

    function test_exiting_items_are_handed_back_at_their_old_index() {
        const after = [item("a"), item("c")];
        const retained = [{ key: "b", item: item("b"), index: 1, at: 500 }];
        const merged = DockReorder.mergeExitingItems(after, retained, 560, 300);
        compare(ids(merged), ["a", "b", "c"]);
        verify(merged[1].__exiting);
        // The live entries are untouched.
        verify(!merged[0].__exiting);
    }

    function test_an_item_that_comes_back_or_times_out_is_dropped() {
        const retained = [{ key: "b", item: item("b"), index: 1, at: 500 }];
        // Relaunched before the exit finished.
        compare(ids(DockReorder.mergeExitingItems([item("a"), item("b")], retained, 560, 300)),
                ["a", "b"]);
        // Past the animation window.
        compare(ids(DockReorder.mergeExitingItems([item("a")], retained, 900, 300)), ["a"]);
    }

    function test_only_items_new_to_the_dock_are_marked_as_entering() {
        const before = [item("a"), item("b")];
        const after = [item("a"), item("b"), item("c")];
        const added = DockReorder.collectAddedKeys(before, after, 42);
        compare(Object.keys(added), ["c"]);
        compare(added["c"], 42);

        // The same list rebuilt (what a Repeater does on any model change)
        // introduces nothing.
        compare(Object.keys(DockReorder.collectAddedKeys(after, after.slice(), 42)).length, 0);

        // An entry handed back only to animate out is not an arrival.
        var exiting = item("d");
        exiting.__exiting = true;
        compare(Object.keys(DockReorder.collectAddedKeys(after, after.concat([exiting]), 42)).length, 0);
    }

    function test_an_item_already_exiting_is_not_collected_twice() {
        var exiting = item("b");
        exiting.__exiting = true;
        const removed = DockReorder.collectRemovedItems([item("a"), exiting], [item("a")], 10);
        compare(removed.length, 0);
    }
}
