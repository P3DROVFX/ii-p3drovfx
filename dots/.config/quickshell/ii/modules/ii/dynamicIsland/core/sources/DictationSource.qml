pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.services

/** Speech is being transcribed. */
ContinuousSource {
    id: source

    activityId: "dictation"
    condition: DictationService.busy && (Config.options?.dictation?.showInIsland ?? true)
}
