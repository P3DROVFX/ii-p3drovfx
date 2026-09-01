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
 * dependency is inverted here. The service only ever talks to this registry; the family
 * registers a handler from its own composition root and takes it away when it unloads.
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
 */
Singleton {
    id: root

    property var handler: null

    function register(candidate) {
        root.handler = candidate ?? null;
    }

    function unregister(candidate) {
        if (root.handler === candidate)
            root.handler = null;
    }

    /// True when a family wants the whole drag for this edge. The service keeps its
    /// own commit/threshold logic for every origin this returns false for.
    function claims(origin) {
        if (!root.handler || !origin)
            return false;
        try {
            return root.handler.claims(origin) === true;
        } catch (e) {
            console.log("[TouchGestureDragRegistry] claims() failed:", e);
            return false;
        }
    }

    /// What the feedback overlay should call this drag. The user's binding for the edge
    /// is not it — a claimed edge never reaches TouchGestureActionRegistry at all.
    function actionId(origin) {
        if (!root.claims(origin) || !root.handler.actionId)
            return "";
        return root.handler.actionId(origin) ?? "";
    }

    function begin(origin, screenName) {
        if (root.claims(origin))
            root.handler.begin(origin, screenName);
    }

    function update(origin, screenName, travel, velocity) {
        if (root.claims(origin))
            root.handler.update(origin, screenName, travel, velocity);
    }

    function release(origin, velocity) {
        if (!root.claims(origin))
            return false;
        root.handler.release(origin, velocity);
        return true;
    }

    function cancel(origin) {
        if (root.claims(origin))
            root.handler.cancel(origin);
    }
}
