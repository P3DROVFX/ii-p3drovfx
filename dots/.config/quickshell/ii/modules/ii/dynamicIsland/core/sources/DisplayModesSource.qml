pragma ComponentBehavior: Bound

import QtQuick
import qs

/**
 * The display modes card is open and the island draws it.
 *
 * `GlobalStates.displayModesPopupOpen` is the request; this only decides which surface
 * answers. See ColorPickerSource for the same shape.
 */
ContinuousSource {
    id: source

    activityId: "displayModes"
    condition: GlobalStates.islandOwnsDisplayModes && GlobalStates.displayModesPopupOpen
}
