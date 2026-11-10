pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * An alarm is ringing.
 *
 * An interrupt that only a ringing call outranks: it holds the centre until it is stopped,
 * snoozed, or AlarmService gives up on it after five minutes. While the island owns it
 * (IslandPolicy.ownsAlarm) the fullscreen popup and the notification stand aside.
 */
ContinuousSource {
    id: source

    activityId: "alarm"

    condition: AlarmService.ringingAlarm !== null
    payload: AlarmService.ringingAlarm
}
