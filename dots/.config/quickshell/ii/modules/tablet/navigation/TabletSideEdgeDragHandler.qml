import QtQuick
import Quickshell

import qs
import qs.modules.common
import qs.modules.tablet.appWindow

/**
 * The two side edges.
 *
 * On Android, swiping in from either side is Back, and after Home it is the gesture people
 * use most. Here the left edge opened an AI chat and the right edge opened the shade — which
 * the top edge already does — so the most-used gesture on a touch device had no edge at all
 * and Back existed only as a button on the dock.
 *
 * Both edges are Back by default. The old left-edge behaviour is still available: "policies"
 * keeps it there and leaves Back on the right, which is the trade for anyone who reached for
 * Intelligence more often than for Back. "none" claims neither edge, handing both back to
 * whatever the user bound in Settings — the drag registry only owns an edge while a handler
 * says it does.
 *
 * Back is discrete, not a drag: unlike the shade there is nothing to follow the finger with,
 * so this watches for a committed swipe the way the app drawer's handler used to.
 */
QtObject {
    id: handler

    readonly property real commitFraction: 0.12
    readonly property real flingVelocity: 320

    /// "back" | "policies" | "none"
    readonly property string mode: Config.options?.tablet?.gestures?.sideEdges ?? "back"

    property real _travel: 0

    function claims(origin) {
        if (handler.mode === "none")
            return false;
        return origin === "leftEdge" || origin === "rightEdge";
    }

    /// What the feedback overlay calls the drag while it is in flight.
    function actionId(origin) {
        if (!handler.claims(origin))
            return "";
        return handler._opensPolicies(origin) ? "sidebarLeft" : "back";
    }

    function _opensPolicies(origin) {
        return handler.mode === "policies" && origin === "leftEdge";
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
        const committed = handler._travel >= needed || velocity >= handler.flingVelocity;
        handler._travel = 0;
        if (!committed)
            return;

        if (handler._opensPolicies(origin)) {
            // Policies is six separate apps now, so the edge opens the first one still
            // switched on — "the panel that used to be here" — rather than a hub that would
            // only put the tab bar back.
            const first = TabletSystemApps.available.find(app => app.id.startsWith("policies."));
            if (first)
                GlobalStates.openTabletApp(first.id);
            return;
        }

        TabletNavigation.back();
    }

    function cancel(origin) {
        handler._travel = 0;
    }

    Component.onCompleted: TouchGestureDragRegistry.register(handler)
    Component.onDestruction: TouchGestureDragRegistry.unregister(handler)
}
