pragma ComponentBehavior: Bound

import QtQuick

/**
 * A state: on the island for exactly as long as the underlying condition holds.
 *
 * Subclasses bind `condition` to a service and nothing else. No TTL and no quiet window:
 * media really is playing, a transfer really is running, and suppressing that after a
 * reload would just hide the truth.
 */
IslandSource {
    id: source

    property bool condition: false

    // No argument: the payload stays whatever the subclass bound it to.
    onConditionChanged: {
        if (source.condition)
            source.begin();
        else
            source.end();
    }

    Component.onCompleted: {
        if (source.condition)
            source.begin();
    }
}
