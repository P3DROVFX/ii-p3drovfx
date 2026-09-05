import QtQuick
import QtTest
import "../../modules/tablet/windows/TabletWindowGeometry.js" as WindowGeometry

TestCase {
    name: "TabletWindowGeometry"

    // ── Which of the three sources wins ───────────────────────────────────

    function test_the_finger_leads_everything() {
        // Mid-drag: the request is one frame behind and the report is a whole
        // client-list refresh behind. Neither may be drawn.
        compare(WindowGeometry.effective(420, 380, 100), 420);
    }

    function test_a_request_outranks_a_stale_report() {
        // The release case, and the bug: Hyprland emits no event for a pixel move, so
        // 100 here is where the window was *before* the drag started and can stay that
        // way indefinitely. Dropping to it is the jump the user sees.
        compare(WindowGeometry.effective(-1, 380, 100), 380);
    }

    function test_the_report_is_what_is_left() {
        compare(WindowGeometry.effective(-1, -1, 100), 100);
        // Nothing pending, nothing dragged, window against the left edge.
        compare(WindowGeometry.effective(-1, -1, 0), 0);
    }

    function test_zero_is_a_position_not_an_absence() {
        // The sentinel is negative precisely so that a window at the monitor's origin
        // is not mistaken for "no drag in progress".
        compare(WindowGeometry.effective(0, 380, 100), 0);
        compare(WindowGeometry.effective(-1, 0, 100), 0);
    }

    // ── When the request may be released ──────────────────────────────────

    function test_a_matching_report_settles() {
        verify(WindowGeometry.settled(380, 380));
        // Integer dispatch against a fractional surface coordinate.
        verify(WindowGeometry.settled(380, 379.4));
        verify(WindowGeometry.settled(378, 380));
    }

    function test_a_report_that_has_not_caught_up_does_not() {
        verify(!WindowGeometry.settled(100, 380));
        verify(!WindowGeometry.settled(380, 100));
        // A compositor that clamped the request is never going to agree; that case is
        // the settle *timeout*'s to end, not this function's to pretend about.
        verify(!WindowGeometry.settled(376, 380, 2));
        verify(WindowGeometry.settled(376, 380, 4));
    }

    function test_nothing_requested_is_already_settled() {
        verify(WindowGeometry.settled(100, -1));
        verify(WindowGeometry.settled(100, undefined));
        verify(WindowGeometry.settled(100, null));
    }

    // ── A whole geometry ──────────────────────────────────────────────────

    function test_a_move_settles_without_waiting_on_a_size_nobody_asked_for() {
        // Dragging the strip requests a position only; width and height stay -1, and
        // holding the override open for them would never end.
        const pending = { x: 380, y: 220, width: -1, height: -1 };
        const reported = { x: 380, y: 220, width: 900, height: 500 };
        verify(WindowGeometry.geometrySettled(reported, pending));
    }

    function test_a_resize_waits_for_every_side() {
        const pending = { x: 380, y: 220, width: 900, height: 500 };
        verify(WindowGeometry.geometrySettled(
            { x: 380, y: 220, width: 900, height: 500 }, pending));
        // The move landed and the resize has not.
        verify(!WindowGeometry.geometrySettled(
            { x: 380, y: 220, width: 640, height: 480 }, pending));
        // The resize landed and the move has not — which is the order the two
        // dispatches actually go out in.
        verify(!WindowGeometry.geometrySettled(
            { x: 100, y: 100, width: 900, height: 500 }, pending));
    }

    function test_nothing_pending_at_all_is_settled() {
        verify(WindowGeometry.geometrySettled({ x: 1, y: 2, width: 3, height: 4 }, {}));
        verify(WindowGeometry.geometrySettled(null, null));
    }
}
