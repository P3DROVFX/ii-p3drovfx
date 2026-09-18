pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * The keyboard layout changed.
 *
 * Pointless with a single layout configured, and the first reading after startup is the
 * layout the session already had.
 */
TransientSource {
    id: source

    activityId: "keyboard"
    ttlMs: 1500
    cooldownMs: 300

    readonly property string currentLayout: HyprlandXkb.currentLayoutName
    property string previousLayout: ""

    onCurrentLayoutChanged: {
        const from = source.previousLayout;
        source.previousLayout = source.currentLayout;
        if (from === "" || from === source.currentLayout)
            return;
        if (HyprlandXkb.layoutCodes.length <= 1)
            return;
        source.trigger({ from: from, to: source.currentLayout });
    }

    Component.onCompleted: source.previousLayout = source.currentLayout
}
