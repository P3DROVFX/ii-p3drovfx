pragma ComponentBehavior: Bound

import QtQuick
import qs

/**
 * A mode or routine started or ended.
 *
 * The modes engine already owns the flash window, so this follows its flag: the island
 * draws the banner that `ModeFlashPopup` would otherwise draw on its own.
 */
ContinuousSource {
    id: source

    activityId: "mode"
    condition: GlobalStates.modeFlashActive && GlobalStates.modeFlashPayload !== null
    payload: GlobalStates.modeFlashPayload
}
