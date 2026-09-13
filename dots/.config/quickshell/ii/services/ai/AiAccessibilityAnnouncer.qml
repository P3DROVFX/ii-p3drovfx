pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Shared status text for assistive technology hosts.
 *
 * The runtime's Accessible attached API is intentionally kept out of this
 * singleton: different Qt builds expose different static announcement APIs.
 * Consumers bind liveText to an accessible status item, which is portable and
 * still gives AT clients a stable live status surface.
 */
Singleton {
    id: root

    property string liveText: ""
    property string lastAnnouncement: ""
    property int revision: 0

    function announce(message, urgent = false) {
        const text = String(message ?? "").trim();
        if (text.length === 0 || text === root.lastAnnouncement)
            return;
        root.lastAnnouncement = text;
        root.liveText = text;
        root.revision += 1;
    }
}
