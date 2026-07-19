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

    Behavior on effectiveWallpaperScale {
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
