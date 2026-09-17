pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ii.dynamicIsland.core

/**
 * Base for everything that can put an activity on the island.
 *
 * Two shapes inherit this. A *transient* source is an announcement: something happened,
 * show it for a while, then let it go (`trigger()` plus a TTL). A *continuous* source is
 * a state: it is true for as long as the thing is happening, and `active` is bound
 * straight to the service.
 *
 * The distinction matters because the island's worst bugs came from treating a state as
 * an event. "The clipboard list was re-read" is a state change with many innocent
 * causes; "a new entry was stored" is an event. Sources that can only observe state must
 * derive an edge, filter it, and stay quiet inside the quiet window - and doing that once
 * here is why no future activity has to remember to.
 */
QtObject {
    id: source

    required property string activityId

    /** Whether the activity should currently be on the island. */
    readonly property bool active: source._active && source.allowed
    property bool _active: false

    /** Per-activity user toggle, resolved in one place. */
    readonly property bool allowed: IslandPolicy.widgetEnabled(source.activityId)

    /** Whatever the presentation needs to draw: a device, an entry, a payload. */
    property var payload: null

    /**
     * Bumped on every fresh trigger of an already-visible activity.
     *
     * Presentations watch this to replay an accent - the album art crossfading, a count
     * ticking - without being destroyed and rebuilt, which is what the old island did
     * for every change.
     */
    property int revision: 0

    /** When the activity arrived, which is what drives its settle-then-detach beat. */
    property double arrivedAt: 0

    /** Set by the surface while the pointer is on this activity, to hold its TTL open. */
    property bool hovered: false

    signal triggered(var payload)
    signal dismissed()

    /**
     * `data` is optional on purpose: a source whose payload is a *binding* to a service
     * (the agent list, the active track) must not have it overwritten here, because an
     * imperative assignment destroys the binding and freezes the value at whatever it
     * held when the activity appeared.
     */
    function begin(data) {
        if (data !== undefined)
            source.payload = data;
        source.revision += 1;
        if (!source._active) {
            source.arrivedAt = Date.now();
            source._active = true;
        }
        source.triggered(source.payload);
    }

    function end() {
        if (!source._active)
            return;
        source._active = false;
        source.dismissed();
    }
}
