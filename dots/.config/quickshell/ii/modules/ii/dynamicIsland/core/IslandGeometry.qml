pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * The island's live size, published for the bar to lay itself out around.
 *
 * While the island is drawn in the bar centre the two surfaces are separate windows, so
 * the bar cannot measure the island the way a layout measures a child. It reads this
 * instead: the island writes its *current* (already animating) size here, and the bar
 * reserves exactly that much room in its centre. Widget groups are pushed outward as the
 * island grows and close back in as it shrinks.
 *
 * The value is deliberately the live one and not the target. The bar must not animate
 * toward a target that is itself animating - two animations chasing each other is what
 * made the old bar pill lag behind its own contents. Following the live value keeps the
 * bar locked to the island for the whole travel.
 *
 * No cycle: the island sizes itself from its own content and from `barHeight`, never from
 * the bar's width, so the bar reading this cannot feed back into it.
 */
Singleton {
    id: root

    /** Outer width of the island surface, shoulders included. 0 when it is not in the bar. */
    property real centerWidth: 0
    property real centerHeight: 0

    /** True while an island is actually publishing a size. */
    readonly property bool inBarCenter: root.centerWidth > 0
}
