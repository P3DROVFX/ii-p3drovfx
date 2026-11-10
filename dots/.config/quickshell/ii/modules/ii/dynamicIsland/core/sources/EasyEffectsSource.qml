pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * EasyEffects as an island activity: present for exactly as long as it runs.
 *
 * Presence is all this says; the glance and the card read EasyEffects themselves, and
 * the per-activity toggle is resolved by IslandSource.allowed.
 */
ContinuousSource {
    id: source

    activityId: "easyEffects"

    condition: EasyEffects.running
}
