pragma ComponentBehavior: Bound

import QtQuick
import qs

/**
 * The session menu is open and the island draws it.
 *
 * `GlobalStates.sessionOpen` is already what every entry point sets - the bar's power
 * buttons, the dashboard's toolbar, the touch gesture - so the island picks all of them
 * up without any of them knowing it exists. Who *draws* the menu is IslandPolicy's
 * question; see SearchSource for the same shape.
 */
ContinuousSource {
    id: source

    activityId: "session"
    condition: GlobalStates.islandOwnsSession && GlobalStates.sessionOpen
}
