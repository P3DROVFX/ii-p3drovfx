import QtQuick
import QtTest
import qs.modules.common.functions

TestCase {
    name: "WidgetPlacement"

    function entry() {
        return {
            id: "cookie", x: 1210, y: 690, scale: 1.25,
            refWidth: 1920, refHeight: 1080,
            positions: { "eDP-1": { x: 1210, y: 690, scale: 1.25 } }
        };
    }

    function test_lockInheritsLocalDesktop_data() {
        return [
            { tag: "reference", width: 1920, height: 1080 },
            { tag: "larger", width: 2560, height: 1600 },
            { tag: "fractional-scale", width: 1707, height: 1067 }
        ];
    }

    function test_lockInheritsLocalDesktop(data) {
        const widget = entry();
        const before = JSON.stringify(widget);
        const desktop = WidgetPlacement.resolveIn([widget], "cookie", "eDP-1", false, data.width, data.height);
        const locked = WidgetPlacement.resolveIn([widget], "cookie", "eDP-1", true, data.width, data.height);
        compare(locked.x, desktop.x);
        compare(locked.y, desktop.y);
        compare(locked.scale, desktop.scale);
        // Inheriting the desktop must not create an independent lock placement.
        compare(locked.forked, false);
        compare(JSON.stringify(widget), before);
    }

    function test_explicitLockRemainsIndependent() {
        const widget = entry();
        widget.lockPositions = { "eDP-1": { x: 500, y: 300, scale: 0.75 } };
        const locked = WidgetPlacement.resolve(widget, "eDP-1", true, 2560, 1600);
        compare(locked.x, 500);
        compare(locked.y, 300);
        compare(locked.scale, 0.75);
        WidgetPlacement.clearFork(widget, "eDP-1", true);
        const inherited = WidgetPlacement.resolve(widget, "eDP-1", true, 2560, 1600);
        compare(inherited.x, 1210);
        compare(inherited.y, 690);
    }

    function test_foreignDesktopStillAdapts() {
        const widget = entry();
        const desktop = WidgetPlacement.resolve(widget, "DP-2", false, 2560, 1600);
        const locked = WidgetPlacement.resolve(widget, "DP-2", true, 2560, 1600);
        compare(desktop.x, 1613);
        compare(desktop.y, 1022);
        compare(locked.x, desktop.x);
        compare(locked.y, desktop.y);
    }

    function test_foreignLockStillAdaptsOverLocalDesktop() {
        const widget = entry();
        widget.lockPositions = { "DP-2": { x: 600, y: 540 } };
        const locked = WidgetPlacement.resolve(widget, "eDP-1", true, 2560, 1600);
        compare(locked.x, 800);
        compare(locked.y, 800);
    }
}
