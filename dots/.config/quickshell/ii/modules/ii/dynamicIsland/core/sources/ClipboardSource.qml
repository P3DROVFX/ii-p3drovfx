pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * A new clipboard entry.
 *
 * `Cliphist.entryAdded` already means "an entry with a new id and different content was
 * stored", which is the only signal that corresponds to the user copying something. The
 * island used to listen to `clipboardUpdated` - "the list was re-read" - which the three
 * external `wl-paste --watch` processes trigger through IPC on every selection offer,
 * including the re-advertisement that happens on unlock.
 */
TransientSource {
    id: source

    activityId: "clipboard"
    ttlMs: 2500
    cooldownMs: 400   // one copy can reach cliphist through several MIME watchers

    readonly property string entry: source.payload ? String(source.payload) : ""

    property Connections _cliphist: Connections {
        target: Cliphist
        function onEntryAdded(entry) {
            source.trigger(entry);
        }
    }
}
