pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.common

/**
 * How far open the app drawer is, as one number the whole family reads.
 *
 * The drawer used to animate itself from a boolean while the dock animated separately from
 * the same boolean, so the two drifted: the dock had finished sliding away before the
 * drawer was anywhere near the top. Both now read this, so they move as one sheet.
 *
 * It also makes the drag continuous. A swipe up from the bottom edge maps travel onto
 * progress frame by frame, the way the shade's pull-down does, instead of the drawer
 * snapping open on release — a sheet that ignores the finger until you let go does not feel
 * attached to it.
 *
 * Modelled on TabletDashboardGestureController. They are deliberately separate objects:
 * both surfaces can be mid-gesture in principle, and sharing one progress would couple two
 * unrelated sheets.
 */
Singleton {
    id: controller

    property real progress: 0.0
    property bool tracking: false
    property real velocity: 0.0
    property string activeScreenName: ""

    /// Travel that maps to a full open. Less than the shade's, because the drawer is
    /// reached from the bottom edge where there is less room to pull through.
    function dragDistance(screenHeight) {
        return Math.max(1, screenHeight * 0.45);
    }

    readonly property real flingVelocityThreshold: 420.0
    readonly property real positionThreshold: 0.35
    /// Dismissing is the cheaper intent, so a drag that started from an open drawer only
    /// has to fall a little before it closes.
    readonly property real closeThreshold: 0.80

    readonly property bool isSettledOpen: progress >= 0.999 && !tracking
    readonly property bool isSettledClosed: progress <= 0.001 && !tracking

    NumberAnimation {
        id: settleAnimation
        target: controller
        property: "progress"
        easing.type: Easing.OutCubic
        duration: Math.round(280 * Appearance.animMultiplier)

        onFinished: {
            if (controller.progress >= 0.999) {
                controller.progress = 1.0;
                if (!GlobalStates.appDrawerOpen)
                    GlobalStates.appDrawerOpen = true;
            } else if (controller.progress <= 0.001) {
                controller.progress = 0.0;
                if (GlobalStates.appDrawerOpen)
                    GlobalStates.appDrawerOpen = false;
                controller.activeScreenName = "";
            }
        }
    }

    function startTracking(screenName) {
        settleAnimation.stop();
        controller.tracking = true;
        controller.activeScreenName = screenName || Hyprland.focusedMonitor?.name || "";
        // The surface has to be mapped and told which screen before the first frame of the
        // drag, or the first thing the user sees is the sheet appearing already part-way up.
        if (!GlobalStates.appDrawerOpen)
            GlobalStates.activeAppDrawerMonitor = controller.activeScreenName;
    }

    function updateProgress(newProgress, currentVelocity) {
        if (!controller.tracking)
            return;
        controller.progress = Math.max(0.0, Math.min(1.0, newProgress));
        if (currentVelocity !== undefined)
            controller.velocity = currentVelocity;
    }

    function endTracking(releaseVelocity, startProgress) {
        if (!controller.tracking)
            return;
        controller.tracking = false;

        const v = (releaseVelocity !== undefined) ? releaseVelocity : controller.velocity;
        let shouldOpen = false;

        if (Math.abs(v) > controller.flingVelocityThreshold)
            shouldOpen = (v > 0);
        else if (startProgress !== undefined && startProgress >= 0.5)
            shouldOpen = (controller.progress > controller.closeThreshold);
        else
            shouldOpen = (controller.progress > controller.positionThreshold);

        controller.animateTo(shouldOpen ? 1.0 : 0.0);
    }

    function cancelTracking() {
        if (!controller.tracking)
            return;
        controller.tracking = false;
        controller.animateTo(GlobalStates.appDrawerOpen ? 1.0 : 0.0);
    }

    function animateTo(targetProgress) {
        settleAnimation.stop();
        const distance = Math.abs(controller.progress - targetProgress);
        if (distance < 0.001) {
            controller.progress = targetProgress;
            GlobalStates.appDrawerOpen = targetProgress >= 0.999;
            if (targetProgress < 0.999)
                controller.activeScreenName = "";
            return;
        }
        settleAnimation.to = targetProgress;
        settleAnimation.duration = Math.max(140, Math.round(300 * distance * Appearance.animMultiplier));
        settleAnimation.start();
    }

    function open(screenName) {
        controller.activeScreenName = screenName || Hyprland.focusedMonitor?.name || "";
        GlobalStates.activeAppDrawerMonitor = controller.activeScreenName;
        controller.animateTo(1.0);
    }

    function close() {
        controller.animateTo(0.0);
    }

    // Anything that opens the drawer without a gesture — the dock button, the search pill,
    // IPC, a keybind — goes through GlobalStates, so the controller follows it.
    Connections {
        target: GlobalStates
        function onAppDrawerOpenChanged() {
            if (controller.tracking)
                return;
            if (GlobalStates.appDrawerOpen && controller.progress < 0.99)
                controller.open(GlobalStates.activeAppDrawerMonitor);
            else if (!GlobalStates.appDrawerOpen && controller.progress > 0.01)
                controller.close();
        }
    }
}
