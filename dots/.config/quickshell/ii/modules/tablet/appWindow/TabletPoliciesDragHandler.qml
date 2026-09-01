import QtQuick
import Quickshell

import qs
import qs.modules.common

/**
 * Claims the left edge for the policies app.
 *
 * In the desktop shell that edge opens a sidebar. Here policies is an app window, so the
 * edge has to open the app instead — and it has to *claim* the drag, because otherwise the
 * same swipe would also fire whatever the user has bound to leftEdge and the gesture would
 * do two things at once.
 *
 * Like the app drawer's handler and unlike the shade's, the window does not follow the
 * finger: it is either open or closed, so this watches for a committed swipe.
 */
QtObject {
    id: handler

    readonly property real commitFraction: 0.12
    readonly property real flingVelocity: 320

    property real _travel: 0

    function claims(origin) {
        return origin === "leftEdge";
    }

    function actionId(origin) {
        return handler.claims(origin) ? "sidebarLeft" : "";
    }

    function begin(origin, screenName) {
        handler._travel = 0;
    }

    function update(origin, screenName, travel, velocity) {
        handler._travel = travel;
    }

    function release(origin, velocity) {
        const screen = Quickshell.primaryScreen;
        const needed = Math.max(1, (screen ? screen.width : 1000) * handler.commitFraction);
        if (handler._travel >= needed || velocity >= handler.flingVelocity)
            GlobalStates.openTabletApp("policies");
        handler._travel = 0;
    }

    function cancel(origin) {
        handler._travel = 0;
    }

    Component.onCompleted: TouchGestureDragRegistry.register(handler)
    Component.onDestruction: TouchGestureDragRegistry.unregister(handler)
}
