pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * A file transfer, or files waiting to be sent.
 *
 * The drop target is part of this too: while a drag hovers the island the activity must
 * stay up regardless of whether a transfer has started, or the drop target would vanish
 * from under the pointer.
 */
ContinuousSource {
    id: source

    activityId: "localSend"

    /** Set by the surface while a file drag is over the island. */
    property bool dragHovering: false
    /** 0 none, 1 LocalSend, 2 KDE Connect - the pending choice from a drop. */
    property int serviceChoice: 0

    condition: LocalSend.currentTransfer !== null
        || LocalSend.droppedFiles.length > 0
        || LocalSend.sending
        || source.dragHovering
        || source.serviceChoice !== 0
}
