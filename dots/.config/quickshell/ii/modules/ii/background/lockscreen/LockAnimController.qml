import QtQuick
import qs
import qs.services
import qs.modules.common

Item {
    id: controller
    visible: false

    // Inputs
    required property real baseScale

    // Outputs
    property bool lockAnimationActive: false
    property bool parallaxFrozen: false
    property bool rippleActive: false
    property real effectiveWallpaperScale: baseScale
    property bool wallpaperCentered: false
    property bool hasWindowsInActiveWorkspace: false

    onWallpaperCenteredChanged: {
        GlobalStates.lockScreenCentered = wallpaperCentered;
    }

    onLockAnimationActiveChanged: {
        GlobalStates.lockAnimationActive = lockAnimationActive;
    }

    // Signals
    signal requestRipple(real x, real y)

    // The lock state below is only ever picked up from a transition, so a controller that
    // comes into existence while the screen is *already* locked would leave every background
    // widget in its desktop state for the whole lock. That is not hypothetical: with
    // `lock.launchOnStartup` the shell locks itself about 130 ms before the background windows
    // are built, so at boot the edge is gone before anything can hear it. Adopt the current
    // state on creation, without animating into it - the lock is already up.
    property bool adoptingLockedState: false
    Component.onCompleted: {
        if (!GlobalStates.screenLocked)
            return;
        controller.adoptingLockedState = true;
        controller.parallaxFrozen = false;
        controller.lockAnimationActive = true;
        controller.wallpaperCentered = true;
        controller.effectiveWallpaperScale = 1.0;
        Qt.callLater(() => controller.adoptingLockedState = false);
    }

    Behavior on effectiveWallpaperScale {
        enabled: !controller.adoptingLockedState
        NumberAnimation {
            duration: Math.round(860 * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }

    onBaseScaleChanged: {
        if (!GlobalStates.screenLocked) {
            effectiveWallpaperScale = baseScale;
        }
    }

    Timer {
        id: delayLockAnimationTimer
        interval: 250 // Dynamic: updated before start
        repeat: false
        onTriggered: {
            if (Math.abs(effectiveWallpaperScale - 1.0) < 0.001) {
                effectiveWallpaperScale = baseScale;
                Qt.callLater(function() {
                    effectiveWallpaperScale = 1.0;
                });
            } else {
                effectiveWallpaperScale = 1.0;
            }
            controller.lockAnimationActive = true;
            controller.parallaxFrozen = false;
            controller.wallpaperCentered = true;
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                delayLockAnimationTimer.interval = controller.hasWindowsInActiveWorkspace ? 250 : 0;
                delayLockAnimationTimer.start();
            } else {
                delayLockAnimationTimer.stop();
                controller.wallpaperCentered = false;
                effectiveWallpaperScale = baseScale;
                controller.parallaxFrozen = false;
                if (!GlobalStates.workspaceRestoreInProgress) {
                    lockAnimResetTimer.restart();
                }
                // Ripple on unlock — brief delay so the layer is already visible
                if (Config.options.lock.rippleEffect ?? true) {
                    rippleOnUnlockTimer.restart();
                }
            }
        }
        function onWorkspaceRestoreInProgressChanged() {
            if (!GlobalStates.workspaceRestoreInProgress && !GlobalStates.screenLocked) {
                lockAnimResetTimer.restart();
            }
        }
    }

    // Delayed ripple trigger on unlock to prevent collision with layer switches
    Timer {
        id: rippleOnUnlockTimer
        interval: Math.round(80 * Appearance.animMultiplier)
        repeat: false
        onTriggered: {
            controller.rippleActive = true;
            controller.requestRipple(0, 0);
            rippleLayerResetTimer.restart();
        }
    }

    Timer {
        id: rippleLayerResetTimer
        interval: Math.round(1800 * Appearance.animMultiplier)
        repeat: false
        onTriggered: controller.rippleActive = false
    }

    Timer {
        id: lockAnimResetTimer
        interval: Math.round(650 * Appearance.animMultiplier)
        repeat: false
        onTriggered: controller.lockAnimationActive = false
    }
}
