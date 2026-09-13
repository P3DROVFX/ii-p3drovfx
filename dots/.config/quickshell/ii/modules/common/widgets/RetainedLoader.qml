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
    Timer {
        id: expiry
        interval: Math.max(0, root.retainFor)
        onTriggered: if (!root.requested) root.retained = false
    }
}
