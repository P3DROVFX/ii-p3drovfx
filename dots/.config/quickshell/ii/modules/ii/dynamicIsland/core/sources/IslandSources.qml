pragma ComponentBehavior: Bound

import QtQuick

/**
 * Every source the island has, in one place.
 *
 * The controller stays generic: it asks this object for the source of an activity id and
 * never knows what a clipboard or a workspace is. Adding an activity is a descriptor in
 * IslandRegistry, a source here, and a presentation - no edits to the arbitration.
 */
Item {
    id: sources

    visible: false

    readonly property list<QtObject> all: [clipboard, workspaces, media, ai]

    readonly property ClipboardSource clipboard: ClipboardSource {}
    readonly property WorkspaceSource workspaces: WorkspaceSource {}
    readonly property MediaSource media: MediaSource {}
    readonly property AiSource ai: AiSource {}

    function sourceFor(activityId) {
        for (let i = 0; i < sources.all.length; i++) {
            if (sources.all[i].activityId === activityId)
                return sources.all[i];
        }
        return null;
    }
}
