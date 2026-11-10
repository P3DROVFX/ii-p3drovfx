import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * One indicator of the Sculpt dashboard button. What it draws depends on the
 * button's variant:
 *
 *   tile, chip   nothing — the glyph sits on the button's own surface
 *   cluster      a bubble whose size, height and tone vary with `seed`, so a
 *                row of them reads as a loose cluster; once the panel opens
 *                they all settle to one size, one line and the vivid tone
 *
 * The slot's footprint never changes (the revealer measures it); only the
 * bubble inside it moves. `ink` is the colour the glyph on it should use.
 */
Item {
    id: root

    property string treatment: "tile"
    property bool vertical: false
    property int seed: 0
    property bool open: false
    property real thickness: 32
    property BarWidgetPalette tones

    readonly property bool bubble: root.treatment === "cluster"
    readonly property var sizes: [0.9, 0.7, 0.82, 0.64, 0.86]
    readonly property var lifts: [2, -3, 3, -2, -1]
    readonly property bool vivid: root.open || root.seed % 2 === 0

    readonly property color ink: !root.tones ? Appearance.colors.colOnLayer1
        : root.bubble
            ? (root.vivid ? root.tones.colOnBackground : root.tones.colOnBackgroundVariant)
            : root.treatment === "chip"
                ? (root.open ? root.tones.colOnBackground : root.tones.colOnBackgroundVariant)
                : root.tones.colOnBackground

    implicitWidth: root.bubble ? (root.vertical ? root.thickness : root.thickness - 2) : root.thickness - 10
    implicitHeight: root.bubble ? (root.vertical ? root.thickness - 2 : root.thickness) : root.thickness - 10

    Rectangle {
        id: disc
        visible: root.bubble
        readonly property real factor: root.open ? 0.82 : root.sizes[root.seed % root.sizes.length]
        property real diameter: Math.round(root.thickness * disc.factor)
        Behavior on diameter {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(disc)
        }
        // Never so far that the bubble leaves the slot (the revealer clips it).
        readonly property real room: Math.max(0, (root.thickness - disc.diameter) / 2)
        property real lift: root.open ? 0 : Math.max(-disc.room, Math.min(disc.room, root.lifts[root.seed % root.lifts.length]))
        Behavior on lift {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(disc)
        }

        width: disc.diameter
        height: disc.diameter
        radius: Appearance.rounding.scale === 0 ? 0 : disc.diameter / 2
        x: Math.round((root.width - width) / 2 + (root.vertical ? disc.lift : 0))
        y: Math.round((root.height - height) / 2 + (root.vertical ? 0 : disc.lift))
        color: !root.tones ? "transparent" : root.vivid ? root.tones.colBackground : root.tones.colBackgroundVariant
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(disc)
        }
    }

    // Keeps the glyph centred on the bubble as it moves; one size for every
    // bubble so the animated glyphs never resize.
    readonly property real glyphLift: root.bubble && !root.vertical ? disc.lift : 0
    readonly property real glyphShift: root.bubble && root.vertical ? disc.lift : 0
    readonly property real glyphSize: Math.round(root.thickness * (root.bubble ? 0.44 : 0.54))
}
