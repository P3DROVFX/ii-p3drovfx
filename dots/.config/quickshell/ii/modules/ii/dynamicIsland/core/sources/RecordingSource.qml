pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/** A screen recording is in progress. */
ContinuousSource {
    id: source

    activityId: "recording"
    condition: (Persistent.states.screenRecord && Persistent.states.screenRecord.active) || false
}
