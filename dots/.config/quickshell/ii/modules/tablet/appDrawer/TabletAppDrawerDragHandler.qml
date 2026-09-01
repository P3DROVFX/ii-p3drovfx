import QtQuick
import Quickshell

import qs
import qs.modules.common

/**
 * Claims the bottom edge for the app drawer.
 *
 * Unlike the shade, the drawer does not follow the finger: it is either open or closed, so
 * this watches the drag for a committed upward swipe and then opens, rather than mapping
 * travel onto a progress. It still has to claim the edge — a drag the registry does not own
 * would instead fire whatever discrete action the user bound to `bottomEdge`, and the
 * gesture would do two things at once.
 */
QtObject {
    id: handler

    // Far enough that a short flick while scrolling something at the bottom of the screen
    // does not open the drawer, short enough to feel like Android's.
    readonly property real commitFraction: 0.18
    // Below this the release is treated as a tap or an aborted drag, whatever the distance.
    readonly property real flingVelocity: 320

    property real _travel: 0
    property string _screenName: ""

    function claims(origin) {
        return origin === "bottomEdge";
    }

    function actionId(origin) {
        return handler.claims(origin) ? "overview" : "";
    }

    function begin(origin, screenName) {
        handler._travel = 0;
        handler._screenName = screenName ?? "";
    }

    function update(origin, screenName, travel, velocity) {
        handler._travel = travel;
        handler._screenName = screenName ?? handler._screenName;
    }

    function release(origin, velocity) {
        const screen = Quickshell.screens.find(s => s.name === handler._screenName) ?? Quickshell.primaryScreen;
        const needed = Math.max(1, (screen ? screen.height : 1000) * handler.commitFraction);
        if (handler._travel >= needed || velocity >= handler.flingVelocity)
            GlobalStates.openAppDrawer(handler._screenName);
        handler._travel = 0;
    }

    function cancel(origin) {
        handler._travel = 0;
    }

    Component.onCompleted: TouchGestureDragRegistry.register(handler)
    Component.onDestruction: TouchGestureDragRegistry.unregister(handler)
}
