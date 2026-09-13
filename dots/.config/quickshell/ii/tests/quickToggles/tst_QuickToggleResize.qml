import QtQuick
import QtTest
import "../../modules/common/quickToggles/androidStyle/QuickToggleResize.js" as Resize

TestCase {
    name: "QuickToggleResize"

    function test_pointer_is_continuous_before_snap() {
        var bounds = Resize.bounds("bluetooth", 4);
        var a = Resize.pixels(106, 56, 1.25, 2.5, 50, 56, 6, bounds, 56);
        var b = Resize.pixels(106, 56, 1.75, 2.75, 50, 56, 6, bounds, 56);
        compare(a.width, 107.25);
        compare(a.height, 58.5);
        compare(b.width - a.width, 0.5);
        compare(b.height - a.height, 0.25);
        compare(Resize.candidate("bluetooth", 2.02, 1.04, 4, [2, 1]), [2, 1]);
    }

    function test_snap_hysteresis_and_reversal() {
        compare(Resize.candidate("bluetooth", 2, 1.51, 4, [2, 1]), [2, 1]);
        compare(Resize.candidate("bluetooth", 2, 1.7, 4, [2, 1]), [2, 2]);
        compare(Resize.candidate("bluetooth", 2, 1.49, 4, [2, 2]), [2, 2]);
        compare(Resize.candidate("bluetooth", 2, 1.3, 4, [2, 2]), [2, 1]);
    }

    function test_media_diagonal_respects_allowed_sizes() {
        compare(Resize.candidate("mediaWidget", 3.9, 1.1, 4, [2, 1]), [4, 2]);
        compare(Resize.candidate("mediaWidget", 2, 1, 4, [4, 2]), [2, 1]);
        compare(Resize.bounds("mediaWidget", 4), { minW: 2, maxW: 4, minH: 1, maxH: 2 });
    }

    function test_limits_and_compact_slider() {
        var bounds = Resize.bounds("volumeSlider", 4);
        var small = Resize.pixels(218, 30, -1000, -1000, 50, 56, 6, bounds, 30);
        compare(small.width, 50);
        compare(small.height, 30);
        var large = Resize.pixels(218, 30, 1000, 1000, 50, 56, 6, bounds, 30);
        compare(large.width, 218);
        compare(large.height, 490);
        compare(Resize.candidate("bluetooth", 100, 100, 4, [1, 1]), [4, 8]);
    }
}
