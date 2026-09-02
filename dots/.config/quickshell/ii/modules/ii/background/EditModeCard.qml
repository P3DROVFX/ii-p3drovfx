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

    // The card's only edge treatment is the shadow below. There was a specular
    // catch along the top and the corner arcs here - a one-pixel bright rim
    // meant to read as glass - and however faint it was it read as a BORDER on
    // the top edge, which is not what a wallpaper being edited should have. It
    // is gone; what carries the card now is the pool of shade around it.

    // Everything that lives OUTSIDE the card, composited once and then cut to
    // shape. The mask is inverted, so what survives is the complement of the
    // card: the backdrop and the outer half of the shadow.
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

        // The card's shadow. NOT StyledRectangularShadow: that one stands down
        // entirely when either transparency toggle is on, and on a machine with
        // transparency the card was then left with no edge treatment at all -
        // which is how the specular rim ended up being the only thing defining
        // it. This one is unconditional, and it is a different shape besides:
        // no offset (the card is lifted straight off the wallpaper, not lit
        // from above), a blur several times the shell's own, and an alpha low
        // enough that what the eye reads is a soft pool spreading out from
        // under the middle rather than a drawn outline. Most of it sits UNDER
        // the card, which the cut removes.
        RectangularShadow {
            anchors.fill: cardShape
            radius: cardShape.radius
            blur: Appearance.sizes.elevationMargin * 3.5
            spread: Appearance.sizes.elevationMargin * 0.5
            offset: Qt.vector2d(0, 0)
            color: Qt.alpha(Appearance.m3colors.m3shadow, 0.5)
            cached: true
        }
    }

    // The cut. OpacityMask reads nothing but alpha, so any opaque colour does;
    // `antialiasing` is what makes the corner smooth - the mask's own edge is
    // the card's edge. Nothing is drawn INSIDE the card on purpose: an outline
    // there is a border however it is coloured, and the job of defining the
    // edge belongs to the shadow alone.
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
