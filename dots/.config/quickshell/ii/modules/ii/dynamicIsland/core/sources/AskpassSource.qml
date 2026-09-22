pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * A password prompt is waiting: sudo, polkit or ssh/git, whichever the user opted into.
 *
 * AskpassService owns the requests; this only says one exists. It holds the island until
 * the prompt is answered, cancelled, or its asker is gone - never a TTL, never a quiet
 * window, since a prompt nobody sees just leaves sudo hanging. A finger winning
 * pam_fprintd_grosshack's race is one way of the asker being gone: the client notices
 * sudo moving on and closes its prompt itself.
 */
ContinuousSource {
    id: source

    activityId: "askpass"

    condition: AskpassService.current !== null
    payload: AskpassService.current
    readonly property int _revision: AskpassService.revision
    on_RevisionChanged: if (source.active) source.revision += 1
}
