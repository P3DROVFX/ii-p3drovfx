pragma ComponentBehavior: Bound

import QtQuick
import QtQml
import qs.modules.ii.dynamicIsland.core
import qs.services

/**
 * The teleprompter on the island: a state, exactly as long as a session runs.
 *
 * The feature's own switch gates the `condition` rather than an `allowed`
 * override: the legacy schema has no `disableTeleprompter` key, so
 * `widgetEnabled` alone would answer "on" to an activity it has never heard
 * of. Turning the feature off mid-session ends it through the same binding.
 *
 * The `sizeOverride` is what makes the island's height follow the user's line
 * count and font size live: the service derives the contracted box from the
 * configuration, and the surface reads it through `pagedSizeOverride`. Only the
 * contracted box — the card the hover grows into measures itself
 * (`implicitHeight`), the registry's expanded box stays its cap.
 */
ContinuousSource {
    id: source

    activityId: "teleprompter"
    condition: Teleprompter.running && Teleprompter.featureEnabled

    readonly property var sizeOverride: ({
        width: Teleprompter.boxWidth,
        height: Teleprompter.compactBoxHeight,
        // The card the hover grows into is always wider than the strip.
        expandedWidth: Teleprompter.expandedBoxWidth
    })

    /**
     * The session holds the surface on screen: a prompter being read is the
     * point of the display, so it overrides auto-hide and the fullscreen hide
     * (each still the user's switch — `holdVisible`). A text drag hovering the
     * island holds it too: a drop target that slides away as the pointer
     * arrives is worse than none, and no hover signal fires during a drag.
     */
    readonly property bool holdsSurface: (Teleprompter.running && Teleprompter.holdVisible)
        || Teleprompter.dragHovering

    // The service must not import the island's core module (see its header):
    // the surface answers here instead, so `Teleprompter.available` knows an
    // island exists to draw the session. A property, not a child: the source
    // base is a QtObject with no default property (the TransientSource `_ttl`
    // pattern).
    property Binding _islandEnabled: Binding {
        target: Teleprompter
        property: "islandEnabled"
        value: IslandPolicy.enabled
    }
}
