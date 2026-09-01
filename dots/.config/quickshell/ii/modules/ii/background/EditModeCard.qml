import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

/**
 * Edit Mode's desktop, drawn as a card lifted off its own wallpaper.
 *
 * Ported from XephyLon/immaterial-impulse (GPL-3.0), v0.32.0,
 * modules/imi/background/EditModeCard.qml, with the backdrop swapped for a
 * MultiEffect blur of the live wallpaper plane.
 *
 * The mode shrinks the desktop with a transform and nothing else, which leaves
 * a hard rectangular edge: a cropped screenshot rather than a surface being
 * edited. This is the chrome around it - the blurred backdrop, the corner, the
 * drop shadow and the edge - as one component so the four cannot end up a
 * pixel apart from each other or from the desktop. Everything geometric comes
 * from `card`, which is edit_mode.js's cardRect: the same arithmetic the
 * transform is built out of.
 *
 * ---- why the backdrop is drawn ON TOP of the desktop -----------------------
 *
 * QML has no rounded clip, and wrapping the whole wallpaper plane in a masked
 * layer means re-rendering it through an effect for every frame of the shrink.
 * So the corner is made by covering it with what is behind it: the backdrop
 * draws above the desktop and is cut out to the card's rounded rect, which is
 * visually identical to drawing it behind everywhere except the four corners.
 * It also puts the shadow where a shadow belongs - inside the same cut-out, so
 * only the half outside the card survives and its interior never darkens the
 * desktop it is supposed to lift. It hides the wallpaper's overscan too: the
 * plane is larger than the screen for the parallax, and shrunk about the
 * screen's origin its margins would otherwise show around the card.
 *
 * What it costs is one full-screen layer and one mask, re-rendered while the
 * card's geometry moves - the entry and the exit - and never at rest.
 */
Item {
    id: root

    // The wallpaper plane to blur - an item, never a path, so it is sampled in
    // its OWN coordinates and the backdrop stays full-screen while the plane
    // it samples is transformed into the card.
    property Item wallpaperLayer: null
    // The desktop's rectangle on screen, and the corner it is drawn with. Both
    // interpolate from "the whole screen, square" so that at rest there is
    // nothing inset, nothing rounded and nothing to stand down.
    property rect card: Qt.rect(0, 0, root.width, root.height)
    property real cardRadius: 0

    // How far the card's MASK is grown past the card itself: half a pixel
    // inward, the standard cure for a compositing seam. The card is a screen
    // scaled to fit a room measured in whole pixels, so its edge lands between
    // two pixels as the normal case; the boundary pixel would otherwise be
    // partly backdrop, which is brighter than the desktop, and the seam
    // renders as a bright rim down the flank. Shrunk, the backdrop laps half a
    // pixel over the desktop and one layer owns the boundary pixel.
    readonly property real maskBleed: -0.5

    // The glass edge: ONE tone, one pixel wide, and mostly not there. A bright
    // catch along the top and the corner arcs, almost nothing along the rest;
    // what carries the card's presence is the shadow around it, not a drawn
    // perimeter. A rim at one strength all the way round is a border however
    // faint it is.
    readonly property real edgeSpecularWidth: 1
    readonly property color specularColor: "#ffffff"
    // Where the light rolls off, as a fraction of the card's height: the
    // corner arc is the piece of the outline whose normal turns from facing up
    // to facing sideways, so it is exactly the run over which a lamp overhead
    // stops reaching the edge.
    readonly property real edgeRollOff: root.card.height > 0
        ? Math.min(0.5, root.cardRadius / root.card.height) : 0

    // Everything that lives OUTSIDE the card, composited once and then cut to
    // shape. The mask is inverted, so what survives is the complement of the
    // card: the backdrop, the outer half of the shadow, and the specular.
    Item {
        id: surround
        anchors.fill: parent

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: cardShapeMask
            invert: true
        }

        Loader {
            anchors.fill: parent
            active: root.wallpaperLayer !== null
            sourceComponent: MultiEffect {
                source: root.wallpaperLayer
                blurEnabled: true
                blurMax: 64
                blur: 0.9
            }
        }

        // The dim, so the card reads as the lit object: the lock blur's own
        // recipe over its blurred wallpaper.
        Rectangle {
            anchors.fill: parent
            color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
        }

        // Not drawn - it is the shape the shadow is taken from. A Rectangle
        // rather than an Item because StyledRectangularShadow reads its
        // target's radius, which is how the shadow's corner follows the card's.
        Rectangle {
            id: cardShape
            x: root.card.x
            y: root.card.y
            width: root.card.width
            height: root.card.height
            radius: root.cardRadius
            color: "transparent"
            visible: false
        }

        // The shell's one shadow for a floating surface, at the magnitude the
        // component defines. Most of a RectangularShadow sits UNDER its target,
        // which the cut removes.
        StyledRectangularShadow {
            target: cardShape
        }

        // Drawn AFTER the shadow, because the shadow is at its darkest exactly
        // where this is: a bright catch on the near edge of a pool of shade is
        // the whole of what reads as glass. Grown from the card and cut back
        // to it by the mask above, so its inner boundary IS the card's edge -
        // to the same antialiased pixel as the corner. The bleed too, or the
        // mask's edge moving out by it would take half of a one-pixel ring.
        Rectangle {
            id: edgeSpecular
            x: root.card.x - root.edgeSpecularWidth - root.maskBleed
            y: root.card.y - root.edgeSpecularWidth - root.maskBleed
            width: root.card.width + 2 * (root.edgeSpecularWidth + root.maskBleed)
            height: root.card.height + 2 * (root.edgeSpecularWidth + root.maskBleed)
            radius: root.cardRadius > 0 ? root.cardRadius + root.edgeSpecularWidth : 0
            antialiasing: true
            // The roll-off happens over the CORNER, not over the flank: the
            // top's value holds to the end of the arc and the flank's along the
            // whole flank. The bottom is a bounce off whatever the card lies
            // on, a hint above the flank rather than symmetric with the top.
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(root.specularColor, 0.44) }
                GradientStop { position: root.edgeRollOff; color: Qt.alpha(root.specularColor, 0.07) }
                GradientStop { position: 1 - root.edgeRollOff; color: Qt.alpha(root.specularColor, 0.07) }
                GradientStop { position: 1; color: Qt.alpha(root.specularColor, 0.13) }
            }
        }
    }

    // The cut. OpacityMask reads nothing but alpha, so any opaque colour does;
    // `antialiasing` is what makes the corner smooth - the mask's own edge is
    // the card's edge. Nothing is drawn INSIDE the card on purpose: an outline
    // there is a border however it is coloured, and the job of defining the
    // edge belongs to the shadow and the specular's catch, both of which vary
    // round the perimeter the way a real edge does.
    Item {
        id: cardShapeMask
        anchors.fill: parent
        visible: false

        Rectangle {
            x: root.card.x - root.maskBleed
            y: root.card.y - root.maskBleed
            width: root.card.width + root.maskBleed * 2
            height: root.card.height + root.maskBleed * 2
            radius: root.cardRadius
            color: "white"
            antialiasing: true
        }
    }
}
