import QtQuick
import QtTest
import "../../modules/ii/sidebarDashboard/quickToggles/androidStyle/QuickToggleLayout.js" as Layout

TestCase {
    name: "QuickToggleLayout"

    function item(id, width, height) {
        return { id: id, type: id, sizeW: width, sizeH: height };
    }

    function packedById(packed, id) {
        for (var i = 0; i < packed.items.length; i++) {
            if (packed.items[i].id === id)
                return packed.items[i];
        }
        return null;
    }

    function test_bug_empty_cell_before_slider_is_filled() {
        var packed = Layout.pack([
            item("a", 1, 1), item("b", 1, 1), item("c", 1, 1),
            item("slider", 4, 1), item("d", 1, 1)
        ], 4);
        compare(packed.rowsUsed, 2);
        compare(packedById(packed, "d").row, 0);
        compare(packedById(packed, "d").column, 3);
        compare(packedById(packed, "slider").row, 1);
        compare(packedById(packed, "slider").column, 0);
        verify(Layout.validateNoOverlap(packed, 4));
    }

    function test_only_1x1_items_fill_rows() {
        var packed = Layout.pack([
            item("a", 1, 1), item("b", 1, 1), item("c", 1, 1),
            item("d", 1, 1), item("e", 1, 1), item("f", 1, 1)
        ], 4);
        compare(packed.rowsUsed, 2);
        compare(packedById(packed, "e").row, 1);
        compare(packedById(packed, "e").column, 0);
        compare(packedById(packed, "f").column, 1);
    }

    function test_vertical_span_blocks_all_rows() {
        var packed = Layout.pack([
            item("tall", 1, 2), item("a", 1, 1), item("b", 1, 1),
            item("c", 1, 1), item("d", 1, 1)
        ], 3);
        compare(packed.rowsUsed, 2);
        compare(packedById(packed, "c").row, 1);
        compare(packedById(packed, "c").column, 1);
        compare(packedById(packed, "d").row, 1);
        compare(packedById(packed, "d").column, 2);
        verify(Layout.validateNoOverlap(packed, 3));
    }

    function test_complex_spans_have_no_overlap_or_overflow() {
        var packed = Layout.pack([
            item("one", 1, 1), item("wide", 2, 1), item("tall", 1, 2),
            item("large", 2, 2), item("slider", 4, 1)
        ], 4);
        verify(Layout.validateNoOverlap(packed, 4));
        for (var i = 0; i < packed.items.length; i++)
            verify(packed.items[i].column + packed.items[i].columnSpan <= 4);
    }

    function test_resize_repack_is_deterministic() {
        var source = [item("a", 1, 1), item("b", 2, 1), item("c", 1, 1)];
        var resized = [item("a", 2, 2), item("b", 2, 1), item("c", 1, 1)];
        var first = Layout.pack(resized, 4);
        compare(JSON.stringify(first), JSON.stringify(Layout.pack(resized, 4)));
        compare(JSON.stringify(source), JSON.stringify([
            item("a", 1, 1), item("b", 2, 1), item("c", 1, 1)
        ]));
        verify(Layout.validateNoOverlap(first, 4));
    }

    function test_column_changes_keep_items_inside_grid() {
        var source = [item("a", 4, 1), item("b", 2, 2), item("c", 1, 1), item("d", 1, 1)];
        var columns = [4, 5, 3];
        for (var c = 0; c < columns.length; c++) {
            var packed = Layout.pack(source, columns[c]);
            verify(Layout.validateNoOverlap(packed, columns[c]));
            for (var i = 0; i < packed.items.length; i++)
                verify(packed.items[i].column + packed.items[i].columnSpan <= columns[c]);
        }
    }

    function test_move_is_move_not_swap_and_does_not_mutate_input() {
        var source = [item("a", 1, 1), item("b", 1, 1), item("c", 1, 1), item("d", 1, 1)];
        var moved = Layout.moveItem(source, 1, 3);
        compare(moved.map(function(value) { return value.id; }), ["a", "c", "d", "b"]);
        compare(source.map(function(value) { return value.id; }), ["a", "b", "c", "d"]);
    }

    function test_positioned_model_keeps_delegate_identity_during_reorder() {
        var persisted = [
            item("network", 1, 1),
            item("audio", 1, 1),
            item("bluetooth", 1, 1),
            item("brightnessSlider", 4, 1)
        ];
        var preview = [persisted[1], persisted[2], persisted[0], persisted[3]];
        var positioned = Layout.positionedItems(persisted, Layout.pack(preview, 4), 80, 56, 6);

        compare(positioned.map(function(value) { return value.id; }),
                ["network", "audio", "bluetooth", "brightnessSlider"]);
        compare(positioned.map(function(value) { return value.type; }),
                ["network", "audio", "bluetooth", "brightnessSlider"]);
        compare(positioned[0].layoutX, 2 * 86);
        compare(positioned[1].layoutX, 0);
        compare(positioned[3].layoutY, 62);
    }

    function test_positioned_model_backfills_hole_before_full_width_slider() {
        var persisted = [
            item("a", 1, 1), item("b", 1, 1), item("c", 1, 1),
            item("slider", 4, 1), item("d", 1, 1)
        ];
        var positioned = Layout.positionedItems(persisted, Layout.pack(persisted, 4), 80, 56, 6);

        compare(positioned[3].layoutY, 62);
        compare(positioned[4].layoutX, 3 * 86);
        compare(positioned[4].layoutY, 0);
    }

    function test_positioned_drawer_items_do_not_share_the_origin() {
        var drawer = [item("a", 1, 1), item("b", 1, 1), item("c", 1, 1), item("d", 1, 1), item("e", 1, 1)];
        var positioned = Layout.positionedItems(drawer, Layout.pack(drawer, 4), 80, 56, 6);
        var positions = positioned.map(function(value) { return value.layoutX + ":" + value.layoutY; });

        compare(new Set(positions).size, drawer.length);
        compare(positioned[4].layoutX, 0);
        compare(positioned[4].layoutY, 62);
    }

    function test_hovered_item_swaps_in_both_directions() {
        var source = [item("tailscale", 1, 1), item("darkMode", 1, 1)];
        var packed = Layout.pack(source, 4);

        compare(Layout.findInsertionIndex(packed.items, 0, 0, "darkMode"), 0);
        compare(Layout.findInsertionIndex(packed.items, 0, 1, "tailscale"), 2);
    }

    function test_full_width_item_targets_the_whole_hovered_row() {
        var movingUp = [
            item("a", 1, 1), item("b", 1, 1), item("c", 1, 1), item("d", 1, 1),
            item("slider", 4, 1)
        ];
        var packedUp = Layout.pack(movingUp, 4);
        compare(Layout.findInsertionIndex(packedUp.items, 0, 0, "slider", 4), 0);

        var movingDown = [
            item("slider", 4, 1),
            item("a", 1, 1), item("b", 1, 1), item("c", 1, 1), item("d", 1, 1)
        ];
        var packedDown = Layout.pack(movingDown, 4);
        compare(Layout.findInsertionIndex(packedDown.items, 1, 0, "slider", 4), 5);
    }

    function test_resize_span_uses_absolute_gesture_delta() {
        compare(Layout.resizeSpanFromDelta(1, 27, 50, 6, 4), 1);
        compare(Layout.resizeSpanFromDelta(1, 29, 50, 6, 4), 2);
        compare(Layout.resizeSpanFromDelta(1, 40, 50, 6, 4), 2);
        compare(Layout.resizeSpanFromDelta(1, 83, 50, 6, 4), 2);
        compare(Layout.resizeSpanFromDelta(1, 85, 50, 6, 4), 3);
    }

    // --- Drag stability ---------------------------------------------------

    function test_hysteresis_keeps_the_cell_it_owns_until_the_pointer_commits() {
        // No anchor yet: plain rounding.
        compare(Layout.quantizeWithHysteresis(0.6, null, 0.3), 1);
        // Owning cell 0, the pointer must reach 0.8 of a cell to concede it.
        compare(Layout.quantizeWithHysteresis(0.6, 0, 0.3), 0);
        compare(Layout.quantizeWithHysteresis(0.79, 0, 0.3), 0);
        compare(Layout.quantizeWithHysteresis(0.81, 0, 0.3), 1);
        // Symmetric on the way back.
        compare(Layout.quantizeWithHysteresis(0.4, 1, 0.3), 1);
        compare(Layout.quantizeWithHysteresis(0.21, 1, 0.3), 1);
        compare(Layout.quantizeWithHysteresis(0.19, 1, 0.3), 0);
        // A flick past several cells is never damped.
        compare(Layout.quantizeWithHysteresis(3.1, 0, 0.3), 3);
    }

    function dragGeometry(centerX, centerY) {
        return {
            pointerX: centerX, pointerY: centerY,
            cellWidth: 50, cellHeight: 56, spacing: 6,
            columns: 4, columnSpan: 1, rowSpan: 1
        };
    }

    function test_pointer_parked_on_a_seam_never_flips_the_cell() {
        var state = Layout.createDragCellState();
        // Column 1 of a 56px grid step, i.e. the item's own home cell.
        var first = Layout.resolveDragCell(dragGeometry(81, 28), state, { hysteresis: 0.3 });
        compare(first.column, 1);
        compare(first.row, 0);
        verify(first.accepted);
        Layout.acceptDragCell(state, first, 81, 28, 0, true);

        // Sit exactly on the 0/1 seam and shiver. Rounding alone would toggle
        // the column on every sample; the dead band swallows all of it.
        var seam = 53;
        for (var i = 0; i < 40; i++) {
            var jitter = seam + ((i % 2 === 0) ? -2 : 2);
            var sample = Layout.resolveDragCell(dragGeometry(jitter, 28 + (i % 3) - 1), state, { hysteresis: 0.3 });
            verify(!sample.accepted);
            compare(sample.column, 1);
            compare(sample.row, 0);
        }

        // A deliberate move still lands.
        var committed = Layout.resolveDragCell(dragGeometry(25, 28), state, { hysteresis: 0.3 });
        verify(committed.accepted);
        compare(committed.column, 0);
    }

    function test_settle_lock_holds_a_fresh_swap_until_the_reflow_ends() {
        var state = Layout.createDragCellState();
        var options = { hysteresis: 0.3, settleMs: 200, settleTravel: 1, now: 1000 };
        var first = Layout.resolveDragCell(dragGeometry(25, 28), state, options);
        verify(first.accepted);
        Layout.acceptDragCell(state, first, 25, 28, 1000, true);

        // Barely past the dead band, 45px of travel, 40ms after the swap: the
        // grid is still animating, so the placement is held.
        var early = Layout.resolveDragCell(dragGeometry(70, 28), state,
            { hysteresis: 0.3, settleMs: 200, settleTravel: 1, now: 1040 });
        verify(!early.accepted);
        verify(early.locked);
        compare(early.column, 0);

        // The same sample once the window has passed.
        var late = Layout.resolveDragCell(dragGeometry(70, 28), state,
            { hysteresis: 0.3, settleMs: 200, settleTravel: 1, now: 1240 });
        verify(late.accepted);
        compare(late.column, 1);

        // A decisive drag is never held: a full cell of travel overrides it.
        var decisive = Layout.resolveDragCell(dragGeometry(137, 28), state,
            { hysteresis: 0.3, settleMs: 200, settleTravel: 1, now: 1040 });
        verify(decisive.accepted);
        compare(decisive.column, 2);
    }

    function test_a_resolution_that_moves_nothing_does_not_arm_the_settle_lock() {
        var state = Layout.createDragCellState();
        var first = Layout.resolveDragCell(dragGeometry(25, 28), state,
            { hysteresis: 0.3, settleMs: 200, settleTravel: 1, now: 1000 });
        Layout.acceptDragCell(state, first, 25, 28, 1000, false);
        var next = Layout.resolveDragCell(dragGeometry(70, 28), state,
            { hysteresis: 0.3, settleMs: 200, settleTravel: 1, now: 1010 });
        verify(next.accepted);
        compare(next.column, 1);
    }

    function test_drag_cell_state_resets_between_gestures() {
        var state = Layout.createDragCellState();
        var first = Layout.resolveDragCell(dragGeometry(81, 28), state, { hysteresis: 0.3 });
        Layout.acceptDragCell(state, first, 81, 28, 0, true);
        Layout.resetDragCellState(state);
        verify(!state.valid);
        verify(!state.changed);
        // With no anchor the seam rounds freely again instead of inheriting
        // the previous gesture's column.
        var fresh = Layout.resolveDragCell(dragGeometry(52, 28), state, { hysteresis: 0.3 });
        verify(fresh.accepted);
        compare(fresh.column, 0);
    }

    function test_wide_items_resolve_from_their_own_footprint() {
        var state = Layout.createDragCellState();
        var geometry = {
            pointerX: 2 * 56, pointerY: 28,
            cellWidth: 50, cellHeight: 56, spacing: 6,
            columns: 4, columnSpan: 4, rowSpan: 1
        };
        // A 4-wide slider can only ever start at column 0, whatever the pointer
        // says, and the clamp must not leak into the hysteresis anchor.
        var resolved = Layout.resolveDragCell(geometry, state, { hysteresis: 0.3 });
        compare(resolved.column, 0);
        Layout.acceptDragCell(state, resolved, geometry.pointerX, geometry.pointerY, 0, true);
        geometry.pointerY = 28 + 62;
        var down = Layout.resolveDragCell(geometry, state, { hysteresis: 0.3 });
        verify(down.accepted);
        compare(down.row, 1);
        compare(down.column, 0);
    }

    function test_deterministic_stress_never_overlaps() {
        var source = [];
        for (var i = 0; i < 120; i++) {
            source.push(item("stress-" + i, 1 + (i % 4), 1 + (i % 3)));
        }
        for (var run = 0; run < 20; run++) {
            var packed = Layout.pack(source, 4 + (run % 2));
            verify(Layout.validateNoOverlap(packed, 4 + (run % 2)));
            compare(JSON.stringify(packed), JSON.stringify(Layout.pack(source, 4 + (run % 2))));
        }
    }
}
