pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * The shell has an update waiting.
 *
 * Present for as long as the checkout is behind its remote branch, which can be days:
 * so it lives in an auxiliary bubble (or beside the clock), and only takes the island's
 * centre once, to say that an update turned up.
 *
 * "Once" is per remote commit. A live reload re-creates this object and the update is
 * still the same one, so what was already announced is kept across reloads; a new
 * commit landing on the branch is news again.
 */
ContinuousSource {
    id: source

    activityId: "update"

    // Not while the check is still counting commits: the announcement would go out
    // without its number, and the glance would appear a second before it.
    condition: ShellUpdates.hasUpdate && !ShellUpdates.checking
    payload: ShellUpdates.remoteCommit

    /** How long the announcement holds the centre before folding into its bubble. */
    readonly property int announceMs: 5000
    property bool announcing: false
    readonly property string tierOverride: source.announcing ? "transient" : ""

    // A QtObject has no default property, so helpers hang off properties.
    property PersistentProperties _session: PersistentProperties {
        reloadableId: "islandUpdateAnnouncement"
        property string announcedCommit: ""
    }

    property Timer _announceTimer: Timer {
        interval: source.announceMs
        onTriggered: source.announcing = false
    }

    onActiveChanged: {
        if (!source.active) {
            source._announceTimer.stop();
            source.announcing = false;
            return;
        }
        const commit = ShellUpdates.remoteCommit;
        if (commit === "" || commit === source._session.announcedCommit)
            return;
        source._session.announcedCommit = commit;
        source.announcing = true;
        source._announceTimer.restart();
    }

    // A second commit landing while the first is still waiting: the condition never
    // drops, so the payload changing is the only edge there is.
    onPayloadChanged: {
        if (!source.active || source.payload === "" || source.payload === source._session.announcedCommit)
            return;
        source._session.announcedCommit = source.payload;
        source.revision += 1;
        source.announcing = true;
        source._announceTimer.restart();
    }
}
