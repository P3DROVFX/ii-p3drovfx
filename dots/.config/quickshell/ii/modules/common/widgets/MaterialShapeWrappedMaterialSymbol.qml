import QtQuick
import qs.modules.common
import qs.modules.common.widgets

MaterialShape {
    id: root
    property alias text: symbol.text
    property alias iconSize: symbol.iconSize
    property alias font: symbol.font
    property alias colSymbol: symbol.color
    property alias fill: symbol.fill
    property alias animateChange: symbol.animateChange
    property real padding: 8

    color: Appearance.colors.colSecondaryContainer
    colSymbol: Appearance.colors.colOnSecondaryContainer
    shape: MaterialShape.Shape.Clover4Leaf
    implicitSize: iconSize + padding * 2

    /**
     * Rotation here is a target that callers move repeatedly — a slider value, a
     * spin per keystroke — not a one-shot A→B.
     *
     * A fixed-duration NumberAnimation restarts from scratch on every retarget,
     * so a stream of small changes reads as a stutter rather than a spin.
     * SmoothedAnimation carries its velocity across retargets, which is exactly
     * the "keeps up while you type" behaviour. 720°/s puts a full turn at the
     * same half second the elementMove token would have given it.
     */
    Behavior on rotation {
        SmoothedAnimation {
            velocity: 720
        }
    }

    // The glyph must cancel the spin about the *same* point the shape spins
    // around, which is the polygon's centre, not the item's. Counter-rotating
    // about the item's centre would leave the glyph drifting by exactly the
    // offset the shape no longer has.
    //
    // The counter-rotation lives on this holder rather than on the symbol,
    // because StyledText already owns its `transform` list for the text-change
    // animation and assigning another would drop it.
    Item {
        id: glyphHolder
        anchors.fill: parent

        transform: Rotation {
            origin.x: root.pivotX
            origin.y: root.pivotY
            angle: -root.rotation
        }

        MaterialSymbol {
            id: symbol
            anchors.centerIn: parent
            color: root.colSymbol
            iconSize: root.iconSize

            // Text.NativeRendering rasterises the glyph to device pixels *before*
            // the transform is applied, so a glyph that merely cancels a rotating
            // parent still gets re-snapped to the pixel grid at every new angle:
            // the icon visibly walks around inside the shape. Qt rules
            // NativeRendering out for rotated text, and this wrapper is the one
            // place a MaterialSymbol is guaranteed to sit under a rotation.
            // Unrotated callers — nearly all of them — keep the crisp native raster.
            renderType: root.rotation === 0 ? Text.NativeRendering : Text.QtRendering
        }
    }
}
