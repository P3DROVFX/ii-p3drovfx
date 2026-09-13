pragma ComponentBehavior: Bound

import QtQuick

// Lazily owns the decorative entrance controller used by dashboard children.
// With animationsEnabled=false only this lightweight progress item exists; the animation
// object graph is not constructed.
Item {
    id: root

    property bool animationsEnabled: false
    required property var animationSpec
    property int trigger: -1
    property bool pageActive: true
    property int delayIndex: 0
    property real baseDelayRatio: 0
    property real staggerRatio: 0
    property real progress: 1
    property bool pending: false
    property bool _controllerRunning: false
    readonly property bool running: _controllerRunning
    readonly property bool controllerLoaded: controller.item !== null
    signal restartController
    signal stopController

    function finish() {
        pending = false;
        stopController();
        _controllerRunning = false;
        progress = 1;
    }

    function restart() {
        if (!animationsEnabled || trigger < 0 || !pageActive) {
            finish();
            return;
        }
        progress = 0;
        pending = true;
        Qt.callLater(function() {
            if (controller.item && root.pending) {
                root.pending = false;
                root.restartController();
            }
        });
    }

    onTriggerChanged: restart()
    onAnimationsEnabledChanged: animationsEnabled ? restart() : finish()
    onPageActiveChanged: {
        if (!pageActive)
            finish();
    }
    Component.onCompleted: trigger >= 0 ? restart() : finish()

    Loader {
        id: controller
        active: root.animationsEnabled
        onLoaded: {
            if (root.pending) {
                root.pending = false;
                root.restartController();
            }
        }
        sourceComponent: Item {
            Connections {
                target: root
                function onRestartController() { animation.restart(); }
                function onStopController() { animation.stop(); }
            }

            SequentialAnimation {
                id: animation
                onRunningChanged: root._controllerRunning = running
                PauseAnimation {
                    duration: Math.round(root.animationSpec.duration
                        * (root.baseDelayRatio + Math.max(0, root.delayIndex) * root.staggerRatio))
                }
                SidebarGroupAnimation {
                    target: root
                    property: "progress"
                    from: 0
                    to: 1
                    animationSpec: root.animationSpec
                }
            }
        }
    }
}
