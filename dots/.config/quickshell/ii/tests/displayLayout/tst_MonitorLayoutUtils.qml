import QtQuick
import QtTest
import "../../modules/common/models/hyprland/MonitorLayoutUtils.js" as LayoutUtils

TestCase {
    name: "MonitorLayoutUtils"

    function makeMonitor(name, x, y, w, h, scale, transform, disabled) {
        return {
            name: name,
            x: x,
            y: y,
            width: w || 1920,
            height: h || 1080,
            scale: scale || 1,
            transform: transform || 0,
            disabled: !!disabled
        };
    }

    function test_logical_dimensions_with_scale_and_rotation() {
        const normal = makeMonitor("eDP-1", 0, 0, 1920, 1080, 1, 0, false);
        compare(LayoutUtils.logicalWidth(normal), 1920);
        compare(LayoutUtils.logicalHeight(normal), 1080);

        const scaled = makeMonitor("DP-1", 0, 0, 3840, 2160, 1.5, 0, false);
        compare(LayoutUtils.logicalWidth(scaled), 2560);
        compare(LayoutUtils.logicalHeight(scaled), 1440);

        const portrait = makeMonitor("HDMI-A-1", 0, 0, 1920, 1080, 1, 1, false);
        compare(LayoutUtils.logicalWidth(portrait), 1080);
        compare(LayoutUtils.logicalHeight(portrait), 1920);
    }

    function test_drag_bounds_zooms_out_to_fit_above_and_below() {
        const monitors = [
            makeMonitor("eDP-1", 0, 0, 1920, 1080),
            makeMonitor("HDMI-A-1", 1920, 0, 1920, 1080)
        ];

        const idleBounds = LayoutUtils.computeBounds(monitors, null);
        compare(idleBounds.width, 3840);
        compare(idleBounds.height, 1080);

        const dragBounds = LayoutUtils.computeDragBounds(monitors, 1, 1.15);
        verify(dragBounds.minY <= -1080);
        verify(dragBounds.maxY >= 2160);
        verify(dragBounds.minX <= -1920);
        verify(dragBounds.maxX >= 3840);

        const canvasW = 560;
        const canvasH = 260;
        const pad = 24;
        const idleCam = LayoutUtils.computeFitCamera(idleBounds, canvasW, canvasH, pad, 1.0);
        const dragCam = LayoutUtils.computeFitCamera(dragBounds, canvasW, canvasH, pad, 1.0);

        // Drag camera zooms out relative to idle side-by-side camera
        verify(dragCam.scale < idleCam.scale);

        // A monitor placed directly above (-1080) or below (+1080) fits completely inside canvas padding
        const topMonitorScreenY = -1080 * dragCam.scale + dragCam.offsetY;
        const bottomMonitorScreenBottom = (1080 + 1080) * dragCam.scale + dragCam.offsetY;
        verify(topMonitorScreenY >= pad - 0.5);
        verify(bottomMonitorScreenBottom <= canvasH - pad + 0.5);
    }

    function test_snap_above_and_below_from_side_by_side() {
        const monitors = [
            makeMonitor("eDP-1", 0, 0, 1920, 1080),
            makeMonitor("HDMI-A-1", 1920, 0, 1920, 1080)
        ];

        // Dragged above monitor 0 (slightly offset horizontally)
        const above = LayoutUtils.snapForDrag(monitors, 1, 50, -950, 0.07);
        verify(above.valid);
        compare(above.x, 0);
        compare(above.y, -1080);

        // Dragged below monitor 0 (even slightly overlapping bottom edge of monitor 0)
        const below = LayoutUtils.snapForDrag(monitors, 1, 40, 980, 0.07);
        verify(below.valid);
        compare(below.x, 0);
        compare(below.y, 1080);

        // Normalizing "above" shifts both so minY = 0
        const normalized = LayoutUtils.computeNormalized(monitors, 1, above.x, above.y);
        compare(normalized[1].x, 0);
        compare(normalized[1].y, 0);
        compare(normalized[0].x, 0);
        compare(normalized[0].y, 1080);
        verify(!LayoutUtils.checkOverlap(normalized, 1));
    }

    function test_swap_vertically_stacked_monitors_preserving_x_offset() {
        const monitors = [
            makeMonitor("HDMI-A-1", 3840, 1080, 1920, 1080),
            makeMonitor("eDP-1", 3840, 0, 1920, 1080)
        ];

        // Drag HDMI-A-1 above eDP-1
        const snap = LayoutUtils.snapForDrag(monitors, 0, 3860, -920, 0.07);
        verify(snap.valid);
        compare(snap.x, 3840);
        compare(snap.y, -1080);

        const normalized = LayoutUtils.computeNormalized(monitors, 0, snap.x, snap.y);
        compare(normalized[0].x, 3840);
        compare(normalized[0].y, 0);
        compare(normalized[1].x, 3840);
        compare(normalized[1].y, 1080);
        verify(!LayoutUtils.checkOverlap(normalized, 0));

        const links = LayoutUtils.computeSnapPoints(normalized, null);
        compare(links.length, 1);
        compare(links[0].x, 3840 + 960);
        compare(links[0].y, 1080);
    }

    function test_center_aligns_smaller_monitor_above_larger_monitor() {
        const monitors = [
            makeMonitor("DP-1", 0, 0, 2560, 1440),
            makeMonitor("eDP-1", 2560, 0, 1920, 1080)
        ];

        // Center X for 1920 above 2560 is (2560 - 1920) / 2 = 320
        const snap = LayoutUtils.snapForDrag(monitors, 1, 340, -1020, 0.08);
        verify(snap.valid);
        compare(snap.x, 320);
        compare(snap.y, -1080);
    }

    function test_three_monitors_stack_without_overlap() {
        const monitors = [
            makeMonitor("DP-1", 0, 0, 1920, 1080),
            makeMonitor("DP-2", 1920, 0, 1920, 1080),
            makeMonitor("HDMI-A-1", 3840, 0, 1920, 1080)
        ];

        const snap = LayoutUtils.snapForDrag(monitors, 1, 20, -1000, 0.06);
        verify(snap.valid);
        compare(snap.x, 0);
        compare(snap.y, -1080);

        const normalized = LayoutUtils.computeNormalized(monitors, 1, snap.x, snap.y);
        verify(!LayoutUtils.checkOverlap(normalized, 1));
    }
}
