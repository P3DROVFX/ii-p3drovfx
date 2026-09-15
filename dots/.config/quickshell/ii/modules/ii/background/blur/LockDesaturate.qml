import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common

Item {
    id: lockDesatRoot

    required property var sourceItem
    // Same capture-once caveat as LockBlur, and its source is often LockBlur itself, so it must
    // not capture an effect that has not produced its own texture yet.
    required property bool sourceReady
    required property real baseScale
    required property bool lockAnimationActive

    readonly property real targetSaturation: -Config.options.lock.desaturate.amount
    // Keep the effect mounted while the lock look is on, and just long enough after it goes
    // off for the unlock desaturation animation to finish. Only the handlers below write this:
    // reading Loader.status/item from Loader.active is a self-dependency in Qt's Loader (a
    // binding loop on every lock/unlock), and a binding on lockLookActive would race the
    // Connections handler for the same signal and unload the effect before the hold is set.
    property bool holdLoaded: false

    Component.onCompleted: holdLoaded = GlobalStates.lockLookActive

    Connections {
        target: GlobalStates
        function onLockLookActiveChanged() {
            if (GlobalStates.lockLookActive) {
                unlockReleaseTimer.stop();
                lockDesatRoot.holdLoaded = true;
                return;
            }
            unlockReleaseTimer.restart();
        }
    }

    Timer {
        id: unlockReleaseTimer
        interval: Math.round(600 * Appearance.animMultiplier)
        repeat: false
        onTriggered: lockDesatRoot.holdLoaded = false
    }

    Loader {
        id: desatLoader
        active: Config.options.lock.desaturate.enable && lockDesatRoot.sourceReady && lockDesatRoot.holdLoaded
        anchors.fill: parent
        sourceComponent: MultiEffect {
            source: lockDesatRoot.sourceItem
            saturation: GlobalStates.lockLookActive ? lockDesatRoot.targetSaturation : 0.0
            Behavior on saturation {
                NumberAnimation {
                    id: desaturationAnim
                    duration: Math.round(600 * Appearance.animMultiplier)
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
