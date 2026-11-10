pragma ComponentBehavior: Bound

import QtQuick
import qs

/**
 * The launcher/search surface is open and the island owns it.
 *
 * `GlobalStates.floatingNotchOwnsSearch` is already the shell-wide answer to "who draws
 * search?", and it has to stay the answer: a standalone SearchDrop and an island both
 * drawing it is the duplicate-surface bug this whole consolidation exists to prevent.
 */
ContinuousSource {
    id: source

    activityId: "search"
    condition: GlobalStates.floatingNotchOwnsSearch
}
