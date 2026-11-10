pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * The laptop battery the island may glance at.
 *
 * A state, not an event, and a different activity from `battery`: that one announces
 * the charger coming and going and leaves; this one sits beside the clock for as long
 * as there is a battery to read. Both can be on at once - the announcement takes the
 * island for its moment and hands the resting face, glance included, back after.
 */
ContinuousSource {
    id: source

    activityId: "batteryGlance"

    condition: Battery.available
}
