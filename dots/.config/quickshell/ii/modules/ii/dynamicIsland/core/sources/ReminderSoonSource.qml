pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * A reminder is due within the hour: a glance beside the clock until it alerts.
 *
 * RemindersService refreshes `upcoming` from its own alert timer, so this costs nothing
 * while no reminder is near.
 */
ContinuousSource {
    id: source

    activityId: "reminderSoon"

    condition: RemindersService.upcoming !== null && RemindersService.ringing === null
    payload: RemindersService.upcoming
}
