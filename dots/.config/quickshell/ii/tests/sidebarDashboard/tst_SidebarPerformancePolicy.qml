import QtQuick
import QtTest
import "../../modules/ii/sidebarDashboard/SidebarPerformancePolicy.js" as PerformancePolicy

TestCase {
    name: "SidebarPerformancePolicy"

    function test_defers_heavy_content_during_outer_motion() {
        compare(PerformancePolicy.canActivateDeferredContent(false, false), false);
        compare(PerformancePolicy.canActivateDeferredContent(false, true), false);
        compare(PerformancePolicy.canActivateDeferredContent(true, true), false);
        compare(PerformancePolicy.canActivateDeferredContent(true, false), true);
    }

    function test_opt_in_entrance_loads_content_during_outer_motion() {
        compare(PerformancePolicy.canActivateDeferredContent(true, true, false), false);
        compare(PerformancePolicy.canActivateDeferredContent(true, true, true), true);

        let ready = false;
        ready = PerformancePolicy.nextDeferredContentReady(ready, true, true, true);
        compare(ready, true);
    }

    function test_ready_state_is_monotonic_across_close_and_reopen() {
        let ready = false;
        ready = PerformancePolicy.nextDeferredContentReady(ready, true, true);
        compare(ready, false);

        ready = PerformancePolicy.nextDeferredContentReady(ready, true, false);
        compare(ready, true);

        ready = PerformancePolicy.nextDeferredContentReady(ready, false, false);
        compare(ready, true);

        ready = PerformancePolicy.nextDeferredContentReady(ready, true, true);
        compare(ready, true);
    }

    function test_optional_entrance_starts_with_open_request() {
        compare(PerformancePolicy.shouldQueueEntranceAnimations(false, true), false);
        compare(PerformancePolicy.shouldQueueEntranceAnimations(true, false), false);
        compare(PerformancePolicy.shouldQueueEntranceAnimations(true, true), true);

        compare(PerformancePolicy.canTriggerEntranceAnimations(true, false, true, false), false);
        compare(PerformancePolicy.canTriggerEntranceAnimations(true, true, false, false), false);
        compare(PerformancePolicy.canTriggerEntranceAnimations(true, true, true, true), true);
        compare(PerformancePolicy.canTriggerEntranceAnimations(false, true, true, false), false);
        compare(PerformancePolicy.canTriggerEntranceAnimations(true, true, true, false), true);
    }
}
