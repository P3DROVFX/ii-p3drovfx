pragma Singleton

import QtQuick
import Quickshell

/**
 * Where a panel family claims an edge gesture as a *continuous drag* instead of a
 * discrete action.
 *
 * TouchGestureActionRegistry handles the normal case: the finger travels far enough,
 * the gesture commits, one action fires. Some surfaces instead need the whole drag —
 * the tablet shade follows the finger down the screen and settles from the release
 * velocity, so it has to see every move event, not just the commit.
 *
 * The service used to import the tablet module directly and test
 * `Config.options.panelFamily === "tablet"` inline, which made a shared service depend
 * on one family's implementation: adding a second dragging family meant editing the
 * service, and the tablet module could never be deleted without breaking it. The
 * dependency is inverted here. The service only ever talks to this registry; a family
 * registers its handlers from its own composition root and takes them away when it
 * unloads.
 *
 * A handler is any object providing:
 *
 *     function claims(origin): bool          // "topEdge", "leftEdge", "rightEdge", "bottomEdge"
 *     function actionId(origin): string      // optional; names the drag for the feedback overlay
 *     function begin(origin, screenName)
 *     function update(origin, screenName, travel, velocity)
 *     function release(origin, velocity)     // the drag is over; settle it
 *     function cancel(origin)
 *
 * `travel` is the raw primary-axis distance in pixels. Mapping it to a 0..1 progress is
 * the handler's business — only it knows what a full open means for its own surface.
 *
 * Several handlers may be registered at once, each claiming different edges: a home
 * screen wants the bottom edge for its app drawer while the shade holds the top. Two
 * handlers claiming the SAME edge is a bug in the family, not a supported layering —
 * the first one registered wins and the collision is logged, because silently picking
 * one would make the loser's surface simply never respond.
 */
Singleton {
    id: root

    property var handlers: []

    function register(candidate) {
        if (!candidate || root.handlers.indexOf(candidate) !== -1)
            return;
        root.handlers = root.handlers.concat([candidate]);
    }

    function unregister(candidate) {
        root.handlers = root.handlers.filter(h => h !== candidate);
    }

    /// The handler that owns this edge, or null. Never throws: a handler whose family is
    /// mid-teardown can raise, and one broken handler must not take the gesture service
    /// with it.
    function handlerFor(origin) {
        if (!origin)
            return null;
        let found = null;
        for (const handler of root.handlers) {
            let claimed = false;
            try {
                claimed = handler.claims(origin) === true;
            } catch (e) {
                console.log("[TouchGestureDragRegistry] claims() failed:", e);
                continue;
            }
            if (!claimed)
                continue;
            if (found) {
                console.log("[TouchGestureDragRegistry] two handlers claim", origin,
                            "- keeping the first registered");
                break;
            }
            found = handler;
        }
        return found;
    }

    /// True when a family wants the whole drag for this edge. The service keeps its
    /// own commit/threshold logic for every origin this returns false for.
    function claims(origin) {
        return root.handlerFor(origin) !== null;
    }

    /// What the feedback overlay should call this drag. The user's binding for the edge
    /// is not it — a claimed edge never reaches TouchGestureActionRegistry at all.
    function actionId(origin) {
        const handler = root.handlerFor(origin);
        if (!handler || !handler.actionId)
            return "";
        return handler.actionId(origin) ?? "";
    }

    function begin(origin, screenName) {
        const handler = root.handlerFor(origin);
        if (handler)
            handler.begin(origin, screenName);
    }

    function update(origin, screenName, travel, velocity) {
        const handler = root.handlerFor(origin);
        if (handler)
            handler.update(origin, screenName, travel, velocity);
    }

    function release(origin, velocity) {
        const handler = root.handlerFor(origin);
        if (!handler)
            return false;
        handler.release(origin, velocity);
        return true;
    }

    function cancel(origin) {
        const handler = root.handlerFor(origin);
        if (handler)
            handler.cancel(origin);
    }
}
