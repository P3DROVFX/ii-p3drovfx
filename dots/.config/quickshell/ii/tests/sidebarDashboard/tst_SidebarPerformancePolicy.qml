import QtQuick
import QtTest
import "../../modules/ii/sidebarDashboard/SidebarPerformancePolicy.js" as PerformancePolicy

TestCase {
    name: "SidebarPerformancePolicy"

    function test_cold_closed_content_stays_inactive() {
        compare(PerformancePolicy.canActivateDeferredContent(false, false), false);
    }

    function test_keep_alive_content_is_preheated_before_open() {
        compare(PerformancePolicy.canActivateDeferredContent(false, true), true);

        let ready = false;
        ready = PerformancePolicy.nextDeferredContentReady(ready, false, true);
        compare(ready, true);
    }

    function test_disabled_entrance_does_not_delay_cold_open() {
        compare(PerformancePolicy.canActivateDeferredContent(true, false), true);
    }

    function test_open_request_activates_content_during_outer_motion() {
        compare(PerformancePolicy.canActivateDeferredContent(true, false), true);

        let ready = false;
        ready = PerformancePolicy.nextDeferredContentReady(ready, true, false);
        compare(ready, true);
    }

    function test_ready_state_is_monotonic_across_close_and_reopen() {
        let ready = false;
        ready = PerformancePolicy.nextDeferredContentReady(ready, true, false);
        compare(ready, true);

        ready = PerformancePolicy.nextDeferredContentReady(ready, true, false);
        compare(ready, true);

        ready = PerformancePolicy.nextDeferredContentReady(ready, false, false);
        compare(ready, true);

        ready = PerformancePolicy.nextDeferredContentReady(ready, true, false);
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
