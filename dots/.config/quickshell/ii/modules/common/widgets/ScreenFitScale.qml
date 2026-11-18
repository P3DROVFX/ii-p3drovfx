import QtQuick

/**
 * Lays its content out at the shell's design density and zooms it to fit a smaller screen.
 *
 * The apps are drawn in logical pixels for a 1920x1080 desktop. A 14" laptop is often a
 * much smaller desktop - 1366x768, or 1920x1080 at 1.25 (1536x864) - and there every
 * fixed size, padding and font kept its pixels while the window shrank around them:
 * the apps opened oversized and ran past the screen. Here the content is given the size
 * it would have on the design screen and scaled down to the window, so it keeps the same
 * proportions everywhere. Text renders with QtRendering (distance fields), so it stays
 * sharp under the zoom. On a design-sized or larger screen the scale is exactly 1.
 *
 * Use it as the window's only child and put the content inside, as you would in the
 * window: `anchors.fill: parent` and `focus: true` keep working.
 */
FocusScope {
    id: root

    /** The screen the window is on; its logical size picks the zoom. */
    property var screen: null
    /** Smallest zoom: past it the content would be too small to read, so it scrolls/clips. */
    property real minimumScale: 0.7
    readonly property real designWidth: 1920
    readonly property real designHeight: 1080
    readonly property real screenWidth: root.screen?.width ?? root.designWidth
    readonly property real screenHeight: root.screen?.height ?? root.designHeight
    readonly property real contentScale: Math.max(root.minimumScale,
        Math.min(1, root.screenWidth / root.designWidth, root.screenHeight / root.designHeight))

    default property alias content: inner.data

    FocusScope {
        id: inner
        focus: true
        width: root.width / root.contentScale
        height: root.height / root.contentScale
        scale: root.contentScale
        transformOrigin: Item.TopLeft
    }
}
