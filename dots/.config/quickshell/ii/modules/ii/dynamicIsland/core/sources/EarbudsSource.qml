pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Connected earbuds with a readable battery.
 *
 * A state, not an event: the glance is true for exactly as long as such a device is
 * connected. The device choice and percent live in EarbudsControlService.glanceDevice
 * so the resting-face glance reads the same values this condition reads.
 */
ContinuousSource {
    id: source

    activityId: "earbuds"

    condition: EarbudsControlService.glancePercent >= 0
}
