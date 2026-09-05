pragma Singleton
import Quickshell

/**
 * Where the bar actually is, as opposed to where the user's persisted config says it is.
 *
 * A panel family may pin the bar: the tablet family always runs a single horizontal bar at
 * the top, while `Config.options.bar.vertical` / `.bottom` keep holding the desktop
 * preference the user set for the ii family. Anything that positions itself against the bar
 * — popup anchors, shadows, the gradient overlay, screen corners, sidebar offsets — has to
 * read these instead, or it lays itself out for a bar that isn't on screen.
 *
 * The Settings UI keeps reading and writing Config directly: that is the stored preference,
 * and switching family must not rewrite it.
 */
Singleton {
    id: root

    readonly property bool familyPinsBarToTop: PanelFamily.pinsBarToTop

    readonly property bool vertical: !root.familyPinsBarToTop && (Config.options?.bar?.vertical ?? false)
    readonly property bool bottom: !root.familyPinsBarToTop && (Config.options?.bar?.bottom ?? false)
}
