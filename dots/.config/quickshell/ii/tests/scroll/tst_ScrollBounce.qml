import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: scene
    width: 400
    height: 400

    StyledFlickable {
        id: flick
        width: 400
        height: 400
        contentWidth: 400
        contentHeight: 1200
        Item {
            width: 400
            height: 1200
        }
    }

    StyledListView {
        id: list
        width: 400
        height: 400
        visible: false
        model: 30
        delegate: Item {
            width: 400
            height: 40
        }
    }

    TestCase {
        name: "ScrollBounce"
        when: windowShown

        function test_01_bounce_on_by_default() {
            compare(Config.options.appearance.settingsPerformanceMode, false);
            verify(flick.bounceEffectsEnabled);
            verify(list.bounceEffectsEnabled);
            compare(flick.boundsBehavior, Flickable.DragOverBounds);
            compare(list.boundsBehavior, Flickable.DragOverBounds);
        }

        function test_02_perf_mode_disables_bounce() {
            Config.options.appearance.settingsPerformanceMode = true;
            verify(!flick.bounceEffectsEnabled);
            verify(!list.bounceEffectsEnabled);
            compare(flick.boundsBehavior, Flickable.StopAtBounds);
            compare(list.boundsBehavior, Flickable.StopAtBounds);
        }

        function test_03_wheel_overshoot_clamps_without_bounce() {
            Config.options.appearance.settingsPerformanceMode = true;
            flick.contentY = 0;
            // Scroll up past the top edge: +120 is one wheel notch up.
            mouseWheel(flick, 200, 200, 0, 120);
            wait(200);
            compare(flick.contentY, 0);
        }

        function test_04_wheel_overshoot_rubberbands_with_bounce() {
            Config.options.appearance.settingsPerformanceMode = false;
            compare(flick.boundsBehavior, Flickable.DragOverBounds);
            flick.contentY = 0;
            mouseWheel(flick, 200, 200, 0, 120);
            // The 10ms wheel smooth is done; the 90ms rebound has not fired yet.
            wait(30);
            verify(flick.contentY < -1);
        }
    }
}
