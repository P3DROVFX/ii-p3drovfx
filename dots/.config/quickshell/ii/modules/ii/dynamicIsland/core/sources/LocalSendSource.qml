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
    /** The dropped files' paths, for KDE Connect's queue. */
    property var queueFiles: []
    /** The drag is over the right-hand (KDE Connect) half of the drop target. */
    property bool dragOnRight: false

    // A LocalSend choice ends once its files are gone (sent, or cleared by the user).
    // KDE Connect's is ended by the widget when its send completes.
    property Connections _files: Connections {
        target: LocalSend
        function onDroppedFilesChanged() {
            if (LocalSend.droppedFiles.length === 0 && source.serviceChoice === 1 && !LocalSend.sending)
                source.serviceChoice = 0;
        }
    }

    condition: LocalSend.currentTransfer !== null
        || LocalSend.droppedFiles.length > 0
        || LocalSend.sending
        || source.dragHovering
        || source.serviceChoice !== 0
}
