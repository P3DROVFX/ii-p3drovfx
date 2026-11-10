pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * A Medium or Strong reminder is alerting.
 *
 * Holds the centre until it is completed, snoozed or dismissed (or RemindersService
 * silences it). While the island owns reminders (IslandPolicy.ownsReminder) the
 * full-screen alert stands aside.
 */
ContinuousSource {
    id: source

    activityId: "reminder"

    condition: RemindersService.ringing !== null
    payload: RemindersService.ringing
}
