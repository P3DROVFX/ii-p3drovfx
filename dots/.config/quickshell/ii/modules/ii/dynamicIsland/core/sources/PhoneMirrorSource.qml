pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.dynamicIsland.core
import "../PhoneMirror.js" as PhoneMirror

/**
 * The phone is mirrored into a scrcpy window: the full screen, or one app.
 *
 * The window sits on whatever workspace it opened on, and nothing says the phone is
 * still streaming once you have moved off it. Read from Hyprland's client list (see
 * PhoneMirror.js), so a mirror that outlived a shell reload is still reported.
 * A session opening is news once; one already open when the shell came up is not.
 */
ContinuousSource {
    id: source

    activityId: "phoneMirror"

    readonly property bool phoneEnabled: Config.ready && Config.options.policies.phone !== 0
    property var _memo: ({})
    /** The open sessions, the mirror first; see PhoneMirror.sessionsFrom. */
    readonly property var sessions: source.phoneEnabled
        ? ObjectUtils.keep(source._memo, "sessions", PhoneMirror.sessionsFrom(HyprlandData.windowList))
        : []

    condition: source.sessions.length > 0
    payload: source.sessions

    // ── A session opening is news once ──────────────────────────────────────
    readonly property int announceMs: 3000
    property bool announcing: false
    readonly property string tierOverride: source.announcing ? "transient" : ""
    /** The session the announcement is about. */
    property var announced: null

    property var _open: []

    Component.onCompleted: source._open = source.sessions.map(session => session.address)

    onSessionsChanged: {
        const fresh = source.sessions.filter(session => source._open.indexOf(session.address) === -1);
        source._open = source.sessions.map(session => session.address);
        // The first client list after start-up (assigned before it is marked loaded)
        // only reports what was already open.
        if (fresh.length === 0 || !HyprlandData.windowListLoaded || !source.allowed
            || IslandPolicy.quietWindowActive)
            return;
        source.announced = fresh[0];
        source.revision += 1;
        source.announcing = true;
        source._announceTimer.restart();
    }

    onActiveChanged: {
        if (source.active)
            return;
        source._announceTimer.stop();
        source.announcing = false;
    }

    property Timer _announceTimer: Timer {
        interval: source.announceMs
        onTriggered: {
            if (source.hovered)
                source._announceTimer.restart();
            else
                source.announcing = false;
        }
    }
}
