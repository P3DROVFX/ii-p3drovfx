import QtQuick
import Quickshell

import qs.modules.common

/**
 * Claims the top edge for the shade, on behalf of the tablet family.
 *
 * This is the tablet's half of the TouchGestureDragRegistry contract. It exists so the
 * shared gesture service never has to know that a tablet family exists: the family's
 * composition root instantiates this, it registers itself, and everything specific to
 * the shade — that it is the top edge, that a full pull is 60% of the screen, that the
 * gesture is called "the notification shade" — lives on this side of the boundary.
 */
QtObject {
    id: handler

    // A full pull covers most of the screen, matching Android's shade. Sixty percent
    // rather than the whole height so a determined swipe reaches 1.0 without the finger
    // running off the bottom bezel.
    readonly property real fullPullFraction: 0.60

    function claims(origin) {
        return origin === "topEdge";
    }

    function actionId(origin) {
        return handler.claims(origin) ? "sidebarRight" : "";
    }

    function begin(origin, screenName) {
        TabletDashboardGestureController.startTracking(screenName);
    }

    function update(origin, screenName, travel, velocity) {
        const screen = Quickshell.screens.find(s => s.name === screenName) ?? Quickshell.primaryScreen;
        const targetDistance = Math.max(1, (screen ? screen.height : 1000) * handler.fullPullFraction);
        TabletDashboardGestureController.updateProgress(
            Math.max(0, Math.min(1, travel / targetDistance)), velocity);
    }

    function release(origin, velocity) {
        TabletDashboardGestureController.endTracking(velocity);
    }

    function cancel(origin) {
        TabletDashboardGestureController.cancelTracking();
    }

    Component.onCompleted: TouchGestureDragRegistry.register(handler)
    Component.onDestruction: TouchGestureDragRegistry.unregister(handler)
}
