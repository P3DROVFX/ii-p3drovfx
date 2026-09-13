import QtQuick
import QtTest
import "../../modules/common/animations"

TestCase {
    id: testCase
    name: "DeferredAnimationStarter"
    when: windowShown

    Component {
        id: harnessComponent
        Item {
            id: harness
            property bool starterEnabled: true
            property bool controllerActive: false
            property int restartCount: 0
            property int stopCount: 0
            readonly property bool controllerLoaded: controller.item !== null
            property var starterObject: null

            Loader {
                id: controller
                active: harness.controllerActive
                asynchronous: true
                sourceComponent: Item {
                    function restart() { harness.restartCount++; }
                    function stop() { harness.stopCount++; }
                }
            }

            Item {
                id: starterHost

                DeferredAnimationStarter {
                    id: starter
                    controller: controller
                    enabled: harness.starterEnabled
                }

                Component.onCompleted: harness.starterObject = starter
            }
        }
    }

    function test_starts_after_controller_is_already_loaded() {
        const harness = createTemporaryObject(harnessComponent, testCase, {
            "controllerActive": true
        });
        verify(harness !== null);
        tryCompare(harness, "controllerLoaded", true);

        harness.starterObject.requestStart();
        tryCompare(harness, "restartCount", 1);
    }

    function test_keeps_request_until_async_controller_loads() {
        const harness = createTemporaryObject(harnessComponent, testCase);
        verify(harness !== null);
        const starter = harness.starterObject;
        starter.requestStart();
        compare(starter.pending, true);

        harness.controllerActive = true;
        tryCompare(harness, "controllerLoaded", true);
        tryCompare(harness, "restartCount", 1);
        compare(starter.pending, false);
    }

    function test_stop_cancels_pending_request() {
        const harness = createTemporaryObject(harnessComponent, testCase);
        verify(harness !== null);
        const starter = harness.starterObject;
        starter.requestStart();
        starter.stop();
        compare(starter.pending, false);

        harness.controllerActive = true;
        tryCompare(harness, "controllerLoaded", true);
        wait(50);
        compare(harness.restartCount, 0);
    }
}
