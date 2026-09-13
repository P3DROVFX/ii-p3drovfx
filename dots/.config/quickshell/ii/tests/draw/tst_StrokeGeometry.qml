import QtQuick
import QtTest
import "../../modules/common/draw/StrokeGeometry.js" as StrokeGeometry

TestCase {
    name: "StrokeGeometry"

    // ── Samples in ────────────────────────────────────────────────────────

    function test_a_point_carries_pressure_and_defaults_to_full() {
        // A finger and a mouse report no pressure, and an even line is the right answer
        // for both — so the absence of a reading is 1, not 0.
        compare(StrokeGeometry.point(10, 20).p, 1);
        compare(StrokeGeometry.point(10, 20, 0.4).p, 0.4);
        // Whatever a driver sends, the rest of the file can assume 0..1.
        compare(StrokeGeometry.point(0, 0, 4).p, 1);
        compare(StrokeGeometry.point(0, 0, -3).p, 0);
        compare(StrokeGeometry.point(NaN, undefined).x, 0);
    }

    function test_a_resting_finger_stops_adding_points() {
        const last = StrokeGeometry.point(100, 100);
        // Under the threshold: hundreds of coincident samples would darken the ink under
        // a stationary finger and leave the smoothing pass nothing but noise.
        verify(!StrokeGeometry.shouldAppend(last, StrokeGeometry.point(100.5, 100)));
        verify(StrokeGeometry.shouldAppend(last, StrokeGeometry.point(103, 100)));
        // The first sample of a stroke has nothing to be far from.
        verify(StrokeGeometry.shouldAppend(null, StrokeGeometry.point(0, 0)));
    }

    // ── Smoothing ─────────────────────────────────────────────────────────

    function test_smoothing_moves_towards_the_sample() {
        const previous = StrokeGeometry.point(0, 0, 1);
        const sample = StrokeGeometry.point(100, 0, 0.5);
        // Half strength lands halfway.
        compare(StrokeGeometry.smoothed(previous, sample, 0.5).x, 50);
        // Zero is the raw sample: someone who turns smoothing off gets exactly what the
        // device sent, tremble included.
        compare(StrokeGeometry.smoothed(previous, sample, 0).x, 100);
        // Pressure is never smoothed — a deliberate press should not feel like it lags.
        compare(StrokeGeometry.smoothed(previous, sample, 0.9).p, 0.5);
    }

    function test_smoothing_can_never_freeze_the_line() {
        const previous = StrokeGeometry.point(0, 0);
        const sample = StrokeGeometry.point(100, 0);
        // Clamped below 1: a filter that never moves is a pen that does not draw.
        verify(StrokeGeometry.smoothed(previous, sample, 1).x > 0);
        verify(StrokeGeometry.smoothed(previous, sample, 5).x > 0);
        // The first sample of a stroke passes straight through.
        compare(StrokeGeometry.smoothed(null, sample, 0.9).x, 100);
    }

    // ── Width ─────────────────────────────────────────────────────────────

    function test_pressure_scales_the_width_but_never_to_nothing() {
        compare(StrokeGeometry.widthFor(10, 1, true), 10);
        // The floor is the point: pressure ramps through zero at both ends of every
        // stroke, and a zero-width end is a stroke that appears to start late.
        verify(StrokeGeometry.widthFor(10, 0, true) > 3);
        verify(StrokeGeometry.widthFor(10, 0.5, true) < 10);
        verify(StrokeGeometry.widthFor(10, 0.5, true) > StrokeGeometry.widthFor(10, 0.1, true));
    }

    function test_without_pressure_every_segment_is_the_same() {
        compare(StrokeGeometry.widthFor(6, 0.1, false), 6);
        compare(StrokeGeometry.widthFor(6, 1, false), 6);
        // Never zero, whatever the caller asks for.
        verify(StrokeGeometry.widthFor(0, 1, false) > 0);
    }

    // ── Segments ──────────────────────────────────────────────────────────

    function test_a_segment_ends_halfway_to_the_next_sample() {
        const a = StrokeGeometry.point(0, 0);
        const b = StrokeGeometry.point(10, 0);
        const c = StrokeGeometry.point(20, 0);
        const segment = StrokeGeometry.quadraticSegment(a, b, c);
        // The sample is the control point and the curve ends at the midpoint, which is
        // what makes consecutive curves meet with matching tangents.
        compare(segment.controlX, 10);
        compare(segment.endX, 15);
    }

    function test_the_last_segment_ends_on_its_sample() {
        const a = StrokeGeometry.point(0, 0);
        const b = StrokeGeometry.point(10, 4);
        const segment = StrokeGeometry.quadraticSegment(a, b, null);
        compare(segment.endX, 10);
        compare(segment.endY, 4);
    }

    // ── Bounds, for the crop a save writes ────────────────────────────────

    function test_bounds_cover_the_ink_and_its_thickness() {
        const strokes = [{
            width: 10,
            points: [StrokeGeometry.point(100, 100), StrokeGeometry.point(200, 150)]
        }];
        const bounds = StrokeGeometry.boundsOf(strokes, 0);
        // Half the line width plus a pixel, either side: the path is the centre of the
        // ink, not its edge, so a tight box would shave the stroke off at the border.
        verify(bounds.x < 100);
        verify(bounds.x + bounds.width > 200);
        verify(bounds.y < 100);
    }

    function test_bounds_pad_and_span_every_stroke() {
        const strokes = [
            { width: 2, points: [StrokeGeometry.point(500, 500)] },
            { width: 2, points: [StrokeGeometry.point(100, 900)] }
        ];
        const bounds = StrokeGeometry.boundsOf(strokes, 24);
        verify(bounds.x < 100 - 24);
        verify(bounds.y + bounds.height > 900 + 24);
    }

    function test_an_empty_sheet_has_no_bounds() {
        // What a save has to refuse rather than writing a 0×0 PNG.
        compare(StrokeGeometry.boundsOf([]), null);
        compare(StrokeGeometry.boundsOf([{ width: 4, points: [] }]), null);
        compare(StrokeGeometry.boundsOf(null), null);
    }

    // ── The eraser ────────────────────────────────────────────────────────

    function test_the_eraser_takes_whole_strokes_it_touches() {
        const stroke = {
            width: 4,
            points: [StrokeGeometry.point(0, 0), StrokeGeometry.point(50, 0),
                     StrokeGeometry.point(100, 0)]
        };
        verify(StrokeGeometry.strokeHitBy(stroke, 50, 5, 18));
        // The reach counts from the edge of the ink, not its centre line.
        verify(StrokeGeometry.strokeHitBy(stroke, 100, 19, 18));
        verify(!StrokeGeometry.strokeHitBy(stroke, 50, 300, 18));
        // A wide stroke is easier to hit, because it covers more of the screen.
        verify(StrokeGeometry.strokeHitBy({ width: 60, points: stroke.points }, 50, 40, 18));
    }

    function test_an_empty_stroke_is_never_hit() {
        verify(!StrokeGeometry.strokeHitBy({ points: [] }, 0, 0, 18));
        verify(!StrokeGeometry.strokeHitBy(null, 0, 0, 18));
    }
}
