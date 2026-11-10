pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Alt+Tab is on screen and the island draws it.
 *
 * WindowSwitcher decides the presenter when the switcher opens (IslandPolicy's
 * `ownsWindowSwitcher`, through GlobalStates), and only shows anything after the quick-tap
 * window, so a tap that switches straight away never touches the island.
 */
ContinuousSource {
    id: source

    activityId: "windowSwitcher"
    condition: WindowSwitcher.shown && WindowSwitcher.presenter === "island"
}
