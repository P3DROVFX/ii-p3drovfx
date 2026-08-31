import QtQuick
import QtTest
import "../../modules/ii/sidebarDashboard"

TestCase {
    id: testCase
    name: "DashboardEntranceProgress"
    when: windowShown

    width: 100
    height: 100

    QtObject {
        id: canonicalSpec
        property int duration: 40
        property int type: Easing.BezierSpline
        property var bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }

    Component {
        id: progressComponent
        DashboardEntranceProgress { animationSpec: canonicalSpec }
    }

    function test_disabled_path_does_not_construct_controller() {
        const progress = createTemporaryObject(progressComponent, testCase, {
            "animationsEnabled": false,
            "trigger": -1
        });
        verify(progress !== null);
        compare(progress.progress, 1);
        compare(progress.controllerLoaded, false);

        progress.trigger = 0;
        compare(progress.progress, 1);
        compare(progress.controllerLoaded, false);
    }

    function test_enabled_trigger_runs_and_finishes() {
        const progress = createTemporaryObject(progressComponent, testCase, {
            "animationsEnabled": true,
            "trigger": -1,
            "baseDelayRatio": 0,
            "staggerRatio": 0
        });
        verify(progress !== null);
        tryCompare(progress, "controllerLoaded", true);

        progress.trigger = 0;
        compare(progress.progress, 0);
        tryCompare(progress, "progress", 1, canonicalSpec.duration * 3 + 100);
        compare(progress.running, false);
    }

    function test_inactive_page_finishes_immediately() {
        const progress = createTemporaryObject(progressComponent, testCase, {
            "animationsEnabled": true,
            "trigger": -1,
            "pageActive": false
        });
        verify(progress !== null);
        progress.trigger = 0;
        compare(progress.progress, 1);
        compare(progress.running, false);
    }
}
