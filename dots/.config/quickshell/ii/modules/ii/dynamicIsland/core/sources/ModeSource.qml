pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services

/**
 * A mode or routine is active, or a mode start/end announcement is flashing.
 *
 * When a mode is toggled, it flashes as a transient banner in the island center.
 * While active, it stays present on the island (resting face beside clock or auxiliary bubble).
 */
ContinuousSource {
    id: source

    activityId: "mode"

    readonly property bool isFlashing: GlobalStates.modeFlashActive && GlobalStates.modeFlashPayload !== null
    readonly property bool isModeActive: Modes.active && Modes.activeMode !== null

    condition: source.isFlashing || source.isModeActive
    payload: source.isFlashing ? GlobalStates.modeFlashPayload : Modes.activeMode

    // Announcements take the center briefly; active mode stays ambient.
    readonly property string tierOverride: source.isFlashing ? "transient" : ""

    onIsFlashingChanged: {
        if (source.active)
            source.revision += 1;
    }

    // A QtObject has no default property: a bare `Connections` fails to compile and
    // takes the whole island's type chain down with it. Hang it off a property.
    property Connections _modes: Connections {
        target: Modes
        function onModeStarted() {
            if (source.active)
                source.revision += 1;
        }
        function onModeEnded() {
            if (source.active)
                source.revision += 1;
        }
    }
}
