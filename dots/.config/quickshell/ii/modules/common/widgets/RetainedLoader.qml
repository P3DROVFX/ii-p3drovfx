pragma ComponentBehavior: Bound
import QtQuick

// Reuse a recently opened surface without retaining an unbounded set of pages.
// Visibility/focus belong to the caller; keeping the object does not show it.
Loader {
    id: root
    property bool requested: false
    property int retainFor: 120000 // Two minutes for repeated shortcut lookups.
    property bool retained: false
    active: root.requested || root.retained
    asynchronous: true

    onRequestedChanged: {
        if (root.requested) {
            expiry.stop();
            if (root.retainFor > 0)
                root.retained = true;
            else
                root.retained = false;
        } else if (root.retained) {
            if (root.retainFor > 0)
                expiry.restart();
            else
                root.retained = false;
        }
    }
    // A released surface leaves its JS objects for a GC that may not come
    // for a long time, and the engine's heap only shrinks after one. Collect
    // once the deferred deletion has run, while nothing is animating on it.
    // A Connections, not onActiveChanged: instances (Usage) declare their own.
    Connections {
        target: root
        function onActiveChanged() {
            if (!root.active)
                releaseCollect.restart();
        }
    }
    Timer {
        id: releaseCollect
        interval: 1000
        onTriggered: if (!root.active) gc()
    }
    Timer {
        id: expiry
        interval: Math.max(0, root.retainFor)
        onTriggered: if (!root.requested) root.retained = false
    }
}
