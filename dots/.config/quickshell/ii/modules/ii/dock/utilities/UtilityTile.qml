import QtQuick
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * Base of every utility tile: the surface, the size tokens and the contract
 * the dock host (DockUtilityWidget) reads. A tile sets its colours and puts
 * its content in the body; clicks it does not take fall through to the host,
 * which opens the panel or calls `activate()`.
 *
 * Two faces, one rule each:
 * - square (an icon's size): ONE thing — a glyph on a shape, or one number.
 *   A ring or a single pip may frame it; no captions, no second line.
 * - wide (three slots, an icon's height): a badge or control on the left, a
 *   value over a caption, and at most one action on the right.
 *
 * Everything is sized from `height`/`width` (a 56 px dock gives 48 px tiles,
 * the default 96 px dock 82 px), rounded. Text, glyphs and shapes use the
 * Tile* components, which stay sharp under the lens.
 */
Item {
    id: tile

    property var host: null
    readonly property bool wide: tile.host?.wide ?? false
    readonly property bool vertical: tile.host?.isVertical ?? false
    readonly property bool live: tile.host?.live ?? true
    readonly property bool hovered: tile.host?.hovered ?? false
    readonly property bool dropHovering: tile.host?.dropHovering ?? false
    readonly property real radius: tile.host?.bodyRadius ?? Appearance.rounding.normal
    // How far the lens may enlarge the tile: shapes and pictures are drawn
    // this much larger so it never stretches a bitmap.
    readonly property real renderScale: tile.host?.renderScale ?? 1

    // Host contract.
    property string tooltipText: ""
    property string panelSubtitle: ""
    property real panelWidth: 340
    property var menuActions: []
    function activate() { return false; }
    function menuAction(actionId) {}

    // Surface.
    property color surfaceColor: ClockStyle.colSurfaceHigh
    property color contentColor: ClockStyle.colOnSurface
    readonly property color captionColor: Qt.rgba(tile.contentColor.r, tile.contentColor.g, tile.contentColor.b, 0.72)

    // ── Size tokens ─────────────────────────────────────────────────────
    readonly property real side: Math.min(tile.width, tile.height)
    // Inner padding; the wide face keeps its content concentric with the corner.
    readonly property real pad: Math.max(3, Math.round(tile.height * (tile.wide ? 0.125 : 0.1)))
    // The square element on the left of the wide face.
    readonly property real badgeSize: Math.round(tile.height - tile.pad * 2)
    // The one number of a square face, and the value / caption of a wide one.
    readonly property int heroSize: Math.round(tile.side * 0.42)
    readonly property int valueSize: Math.round(tile.height * 0.4)
    readonly property int captionSize: Math.max(8, Math.round(tile.height * 0.2))
    readonly property var digitAxes: ClockStyle.axesDigitsBold
    readonly property var captionAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })

    default property alias content: body.data

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: tile.radius
        color: tile.surfaceColor
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
    }

    Item {
        id: body
        anchors.fill: parent
    }
}
