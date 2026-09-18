pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common

/**
 * Volume, brightness and the other hardware sliders.
 *
 * The shell has standalone OSD styles of its own; when the user picked one of those, the
 * island stays out of the way rather than drawing a second indicator.
 */
ContinuousSource {
    id: source

    activityId: "osd"
    condition: GlobalStates.osdVolumeOpen
        && !(Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material"))
    payload: GlobalStates.osdCurrentIndicator

    // Nudging the volume again while the slider is up re-accents it; the indicator
    // itself animates, the island does not move.
    onPayloadChanged: if (source.active) source.revision += 1
}
