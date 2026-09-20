pragma ComponentBehavior: Bound

import QtQuick
import qs

/**
 * A colour has been picked and the island shows it.
 *
 * `GlobalStates.colorPickerPopupOpen` is what the picker sets when it has a result;
 * this only decides which surface answers. See SearchSource for the same shape.
 */
ContinuousSource {
    id: source

    activityId: "colorPicker"
    condition: GlobalStates.islandOwnsColorPicker && GlobalStates.colorPickerPopupOpen
}
