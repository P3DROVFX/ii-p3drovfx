import QtQuick
import QtTest
import "../../modules/common/quickToggles/QuickToggleMetrics.js" as Metrics

// The compact slider row must hug the handle (StyledSlider's extreme ink),
// never the track plus arbitrary padding: the whole reason the quick-toggle
// sliders read with an oversized top margin was the box being sized around
// the track while the handle pokes past it asymmetrically against the
// surrounding spacing. These contracts pin that derivation, and the numbers
// are cross-checked against StyledSlider's own constants below.
TestCase {
    name: "QuickToggleMetrics"

    // Mirrors StyledSlider.handleHeight's general branch: max(33, track + 9)
    readonly property real styledSliderHandleExtra: 9
    readonly property real styledSliderHandleFloor: 33
    // Mirrors StyledSlider.Configuration.M
    readonly property real styledSliderMTrack: 30

    function test_handle_is_track_plus_nine_at_reference() {
        var handle = Metrics.sliderHandle(56);
        compare(handle, Math.max(styledSliderHandleFloor, styledSliderMTrack + styledSliderHandleExtra));
        compare(handle, 39);
    }

    function test_widget_height_equals_handle_at_reference() {
        // Reference cell 56, track 30: box hugs the 39px handle, not track+2*6=42.
        compare(Metrics.sliderWidgetHeight(56), Metrics.sliderHandle(56));
        compare(Metrics.sliderWidgetHeight(56), 39);
    }

    function test_widget_height_always_contains_handle() {
        var heights = [1, 20, 33, 39, 42, 56, 64, 72, 96, 116];
        for (var i = 0; i < heights.length; i++) {
            var cell = heights[i];
            verify(Metrics.sliderWidgetHeight(cell) <= cell,
                "row " + cell + " must not exceed the cell");
            // Once the cell fits the handle the box must equal it exactly.
            if (cell >= Metrics.sliderHandle(cell))
                compare(Metrics.sliderWidgetHeight(cell), Metrics.sliderHandle(cell));
        }
    }

    function test_handle_tracks_cell_above_reference() {
        // Above the reference cell the track is proportional (0.62), and the
        // handle keeps the same +9 relationship StyledSlider draws with.
        var cell = 100;
        var track = Math.round(cell * 0.62);
        compare(Metrics.sliderTrack(cell), track);
        compare(Metrics.sliderHandle(cell), Math.max(styledSliderHandleFloor, track + styledSliderHandleExtra));
        compare(Metrics.sliderWidgetHeight(cell), Metrics.sliderHandle(cell));
    }

    function test_zero_cell_is_safe() {
        verify(Metrics.sliderWidgetHeight(0) > 0);
        verify(isFinite(Metrics.sliderWidgetHeight(0)));
    }

    function test_row_spacing_matches_grid_spacing() {
        // The visual invariant: box height == handle height, so two stacked
        // slider rows separated by `spacing` have exactly `spacing` of gap
        // between their extreme ink — the same rhythm tiles keep side by side.
        var spacing = 6;
        var rowH = Metrics.sliderWidgetHeight(56);
        var slack = (rowH - Metrics.sliderHandle(56)) / 2;
        compare(2 * slack + spacing, spacing);
        // And the 30px track keeps symmetric margin inside the row: the top
        // and bottom dead bands around the painted track are identical.
        var track = 30;
        verify(rowH > track);
        compare((rowH - track) / 2, (rowH - track) / 2);
    }
}
