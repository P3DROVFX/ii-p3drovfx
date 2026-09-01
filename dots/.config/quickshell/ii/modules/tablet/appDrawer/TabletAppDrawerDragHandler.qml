import QtQuick
import Quickshell

import qs
import qs.modules.common

/**
 * Claims the bottom edge for the app drawer.
 *
 * The drawer follows the finger, like the shade: travel maps onto the controller's progress
 * frame by frame rather than the sheet snapping open on release. A sheet that ignores the
 * finger until you let go does not feel attached to it.
 *
 * It has to *claim* the edge — a drag the registry does not own would instead fire whatever
 * discrete action the user bound to `bottomEdge`, and the gesture would do two things.
 */
QtObject {
    id: handler

    property string _screenName: ""
    /// Where the drag started, so the controller can apply the cheaper close threshold to a
    /// drag that began with the drawer already open.
    property real _startProgress: 0

    function claims(origin) {
        return origin === "bottomEdge";
    }

    function actionId(origin) {
        return handler.claims(origin) ? "overview" : "";
    }

    function begin(origin, screenName) {
        handler._screenName = screenName ?? "";
        handler._startProgress = TabletAppDrawerGestureController.progress;
        TabletAppDrawerGestureController.startTracking(handler._screenName);
    }

    function update(origin, screenName, travel, velocity) {
        handler._screenName = screenName ?? handler._screenName;
        const screen = Quickshell.screens.find(s => s.name === handler._screenName)
            ?? Quickshell.primaryScreen;
        const distance = TabletAppDrawerGestureController.dragDistance(screen ? screen.height : 1000);
        TabletAppDrawerGestureController.updateProgress(
            handler._startProgress + travel / distance, velocity);
    }

    function release(origin, velocity) {
        TabletAppDrawerGestureController.endTracking(velocity, handler._startProgress);
    }

    function cancel(origin) {
        TabletAppDrawerGestureController.cancelTracking();
    }

    Component.onCompleted: TouchGestureDragRegistry.register(handler)
    Component.onDestruction: TouchGestureDragRegistry.unregister(handler)
}
