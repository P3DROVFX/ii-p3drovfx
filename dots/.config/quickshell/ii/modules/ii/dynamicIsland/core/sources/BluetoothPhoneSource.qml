pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.ii.dynamicIsland.core

/**
 * A phone connected over Bluetooth, as a bubble beside the island.
 *
 * A state, not an event: the connection strip (BluetoothSource) announces the phone
 * arriving, and this keeps it at hand afterwards - battery, disconnect, settings - for as
 * long as it stays connected. Only while bubbles are on: this activity has no place in
 * the resting face, and without a bubble to take it, a live activity would claim the
 * island's centre for the whole connection. It follows the Bluetooth toggle, since it is
 * the rest of that announcement.
 */
ContinuousSource {
    id: source

    activityId: "btPhone"

    condition: BluetoothStatus.phoneDevice !== null
        && IslandPolicy.auxiliaryBubble
        && IslandPolicy.widgetEnabled("bluetooth")
}
