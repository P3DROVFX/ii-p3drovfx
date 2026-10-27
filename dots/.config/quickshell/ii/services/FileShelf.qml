pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "../modules/ii/dock/utilities/UtilityFiles.js" as UtilityFiles

/**
 * The drop shelf: files left halfway through a drag, to be picked up later.
 *
 * One store for every surface that shows it - the dock's Shelf tile, the
 * desktop Drop Shelf widgets, the island's shelf activity - so a file dropped
 * on one is waiting on all of them. Kept in Persistent (paths only, newest
 * last), so the shelf survives a restart.
 */
Singleton {
    id: root

    readonly property var items: Persistent.ready ? Array.from(Persistent.states.dockUtilities.shelf ?? []) : []
    readonly property int count: root.items.length
    readonly property string newest: root.count > 0 ? root.items[root.count - 1] : ""
    // Whether a file dragged off the shelf leaves it (Settings → Dock → Shelf).
    readonly property bool removeAfterDrag: Config.options?.dock?.utilities?.shelf?.removeAfterDrag ?? false

    // Urls or paths, as a drop hands them over; already-shelved ones move to the top.
    function add(urls) {
        if (!Persistent.ready)
            return;
        const incoming = UtilityFiles.dedupe(Array.from(urls ?? []).map(url => String(url)));
        if (incoming.length === 0)
            return;
        Persistent.states.dockUtilities.shelf = UtilityFiles.dedupe(root.items.filter(path => incoming.indexOf(path) < 0).concat(incoming));
    }

    function remove(path) {
        if (Persistent.ready)
            Persistent.states.dockUtilities.shelf = root.items.filter(item => item !== path);
    }

    function clear() {
        if (Persistent.ready)
            Persistent.states.dockUtilities.shelf = [];
    }

    // After a drag out: honours removeAfterDrag for the paths that left.
    function dragged(paths) {
        if (!root.removeAfterDrag)
            return;
        const gone = Array.from(paths ?? []);
        if (Persistent.ready)
            Persistent.states.dockUtilities.shelf = root.items.filter(item => gone.indexOf(item) < 0);
    }
}
