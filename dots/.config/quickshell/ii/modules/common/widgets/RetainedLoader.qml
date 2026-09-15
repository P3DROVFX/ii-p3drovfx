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
            root.retained = true;
        } else if (root.retained) {
            expiry.restart();
        }
    }
    Timer {
        id: expiry
        interval: Math.max(0, root.retainFor)
        onTriggered: if (!root.requested) root.retained = false
    }
}
