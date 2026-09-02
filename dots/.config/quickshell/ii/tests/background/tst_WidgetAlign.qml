import QtQuick
import QtTest
import "../../modules/common/functions/widget_align.js" as WidgetAlign

TestCase {
    name: "WidgetAlign"

    // A member with no clamp: what a widget on an open desktop looks like.
    function member(id, x, y, width, height) {
        return {
            "id": id,
            "x": x,
            "y": y,
            "box": { "x": x, "y": y, "width": width, "height": height }
        };
    }

    // The same widget drawn somewhere its stored coordinate is not: a scaled
    // widget's box is offset from x/y, which is the case the deltas exist for.
    function offsetMember(id, x, y, boxX, boxY, width, height) {
        return {
            "id": id,
            "x": x,
            "y": y,
            "box": { "x": boxX, "y": boxY, "width": width, "height": height }
        };
    }

    function dx(result, id) {
        return (id in result) ? result[id].dx : 0;
    }

    function dy(result, id) {
        return (id in result) ? result[id].dy : 0;
    }

    // ── Bounds ────────────────────────────────────────────────────────────

    function test_bounds_wrap_every_box() {
        const frame = WidgetAlign.bounds([
            member("a", 10, 20, 100, 50),
            member("b", 200, 5, 40, 200)
        ]);
        compare(frame.x, 10);
        compare(frame.y, 5);
        compare(frame.width, 230);
        compare(frame.height, 200);
    }

    function test_bounds_of_nothing_is_null() {
        compare(WidgetAlign.bounds([]), null);
        compare(WidgetAlign.bounds(null), null);
    }

    // ── Aligning ──────────────────────────────────────────────────────────

    function test_left_moves_everything_onto_the_leftmost_edge() {
        const result = WidgetAlign.deltas([
            member("a", 10, 0, 100, 50),
            member("b", 60, 0, 100, 50),
            member("c", 200, 0, 100, 50)
        ], "left");
        compare(dx(result, "a"), 0);
        compare(dx(result, "b"), -50);
        compare(dx(result, "c"), -190);
    }

    function test_right_aligns_the_far_edges_not_the_near_ones() {
        // Widths differ, so a right alignment is not one shared delta.
        const result = WidgetAlign.deltas([
            member("wide", 0, 0, 200, 50),
            member("narrow", 100, 0, 50, 50)
        ], "right");
        compare(dx(result, "wide"), 0);
        compare(dx(result, "narrow"), 50);
    }

    function test_centre_is_the_bounding_box_not_the_average_of_centres() {
        // Two boxes on the left, one far right: an average of centres would
        // land left of the middle, and centring twice would move twice.
        const members = [
            member("a", 0, 0, 100, 50),
            member("b", 20, 0, 100, 50),
            member("c", 400, 0, 100, 50)
        ];
        const once = WidgetAlign.deltas(members, "hcenter");
        // Frame is [0, 500]; every box is 100 wide, so all three want x = 200.
        compare(dx(once, "a"), 200);
        compare(dx(once, "b"), 180);
        compare(dx(once, "c"), -200);

        // Applied, the selection is already centred: nothing moves again.
        const settled = [
            member("a", 200, 0, 100, 50),
            member("b", 200, 0, 100, 50),
            member("c", 200, 0, 100, 50)
        ];
        compare(Object.keys(WidgetAlign.deltas(settled, "hcenter")).length, 0);
    }

    function test_vertical_modes_only_touch_y() {
        const result = WidgetAlign.deltas([
            member("a", 10, 10, 100, 50),
            member("b", 90, 300, 100, 50)
        ], "top");
        compare(dx(result, "b"), 0);
        compare(dy(result, "b"), -290);
    }

    function test_a_delta_is_measured_off_the_box_and_applied_to_the_stored_x() {
        // Stored x is 500 while the widget is DRAWN at 480: a scaled widget.
        // The move must be the box's, not the difference between coordinates.
        const result = WidgetAlign.deltas([
            member("anchor", 0, 0, 100, 50),
            offsetMember("scaled", 500, 0, 480, 0, 140, 70)
        ], "left");
        compare(dx(result, "scaled"), -480);
    }

    // ── Refusals ──────────────────────────────────────────────────────────

    function test_one_widget_is_not_a_selection() {
        compare(Object.keys(WidgetAlign.deltas([member("a", 10, 0, 100, 50)], "left")).length, 0);
    }

    function test_distributing_needs_something_between_the_ends() {
        compare(WidgetAlign.minimumMembers("left"), 2);
        compare(WidgetAlign.minimumMembers("hdistribute"), 3);
        const two = [member("a", 0, 0, 100, 50), member("b", 400, 0, 100, 50)];
        compare(Object.keys(WidgetAlign.deltas(two, "hdistribute")).length, 0);
    }

    function test_an_unknown_mode_does_nothing() {
        const members = [member("a", 0, 0, 100, 50), member("b", 400, 0, 100, 50)];
        compare(Object.keys(WidgetAlign.deltas(members, "diagonal")).length, 0);
    }

    // ── Distributing ──────────────────────────────────────────────────────

    function test_distribute_holds_the_ends_and_evens_the_gaps() {
        // Boxes 100 wide inside a 500 frame: 3 boxes occupy 300, so the two
        // gaps are 100 each and the middle one lands at 200.
        const result = WidgetAlign.deltas([
            member("a", 0, 0, 100, 50),
            member("b", 120, 0, 100, 50),
            member("c", 400, 0, 100, 50)
        ], "hdistribute");
        compare(dx(result, "a"), 0);
        compare(dx(result, "b"), 80);
        compare(dx(result, "c"), 0);
    }

    function test_distribute_reads_the_order_off_the_boxes_not_the_list() {
        // Same three widgets handed over out of order: the answer is the same.
        const result = WidgetAlign.deltas([
            member("c", 400, 0, 100, 50),
            member("a", 0, 0, 100, 50),
            member("b", 120, 0, 100, 50)
        ], "hdistribute");
        compare(dx(result, "b"), 80);
        compare(Object.keys(result).length, 1);
    }

    function test_distribute_accounts_for_differing_sizes() {
        // 100 + 200 + 100 = 400 inside a 600 frame: two gaps of 100.
        const result = WidgetAlign.deltas([
            member("a", 0, 0, 100, 50),
            member("mid", 150, 0, 200, 50),
            member("b", 500, 0, 100, 50)
        ], "hdistribute");
        compare(dx(result, "mid"), 50);
    }

    function test_distribute_spreads_overlapping_boxes_rather_than_refusing() {
        // Three 100-wide boxes inside a 150 frame: the gap is negative and the
        // middle one still lands halfway between the two ends.
        const result = WidgetAlign.deltas([
            member("a", 0, 0, 100, 50),
            member("b", 0, 0, 100, 50),
            member("c", 50, 0, 100, 50)
        ], "hdistribute");
        compare(dx(result, "b"), 25);
    }

    function test_vertical_distribute_uses_heights() {
        const result = WidgetAlign.deltas([
            member("a", 0, 0, 50, 100),
            member("b", 0, 120, 50, 100),
            member("c", 0, 400, 50, 100)
        ], "vdistribute");
        compare(dy(result, "b"), 80);
        compare(dx(result, "b"), 0);
    }

    // ── Clamps ────────────────────────────────────────────────────────────

    function test_one_member_against_a_wall_does_not_drag_the_rest_back() {
        // `b` may not go left of 40, so it stops there - and `c` still lands
        // on the line. A nudge shrinks the whole group to the smallest
        // headroom; an alignment is a statement about each member's own edge.
        const members = [
            member("a", 10, 0, 100, 50),
            member("b", 60, 0, 100, 50),
            member("c", 200, 0, 100, 50)
        ];
        members[1].minX = 40;
        const result = WidgetAlign.deltas(members, "left");
        compare(dx(result, "b"), -20);
        compare(dx(result, "c"), -190);
    }

    function test_a_member_already_at_its_wall_is_left_out_entirely() {
        const members = [
            member("a", 10, 0, 100, 50),
            member("stuck", 300, 0, 100, 50)
        ];
        members[1].minX = 300;
        const result = WidgetAlign.deltas(members, "left");
        verify(!("stuck" in result));
    }

    // ── Idempotence ───────────────────────────────────────────────────────

    function test_aligning_an_aligned_selection_commits_nothing() {
        const members = [
            member("a", 40, 0, 100, 50),
            member("b", 40, 0, 100, 50),
            member("c", 40, 0, 100, 50)
        ];
        compare(Object.keys(WidgetAlign.deltas(members, "left")).length, 0);
    }

    function test_a_sub_pixel_move_is_not_a_move() {
        const members = [
            member("a", 0, 0, 100, 50),
            member("b", 0.2, 0, 100, 50)
        ];
        compare(Object.keys(WidgetAlign.deltas(members, "left")).length, 0);
    }
}
