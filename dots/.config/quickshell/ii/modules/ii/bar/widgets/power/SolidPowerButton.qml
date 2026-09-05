pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets

/**
 * Solid power button.
 *
 * This started out as a die-cut: the plate was solid and the power symbol was a
 * hole punched through it. It looked good and it was wrong — a hole shows
 * whatever is *behind* the bar, so a dark plate over a dark wallpaper made the
 * glyph disappear. Contrast that depends on the wallpaper is not contrast.
 *
 * So the glyph is painted, and every state is a real Material pair. The palette
 * guarantees the contrast; nothing behind the bar can take it away.
 *
 *   rest   neutral container, quiet in the bar
 *   hover  the same pair, one step up
 *   open   the accent pair, and the glyph fills, while the session screen is up
 */
Item {
    id: root

    property bool vertical: false

    readonly property real side: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8

    // The glyph follows the bar; without this a taller bar just puts more empty
    // circle around the same small symbol.
    readonly property real contentScale: root.vertical
        ? Appearance.sizes.verticalBarContentScale
        : Appearance.sizes.barContentScale

    implicitWidth: root.side
    implicitHeight: root.side

    readonly property bool open: GlobalStates.sessionOpen

    RippleButton {
        id: button
        anchors.fill: parent
        buttonRadius: Appearance.rounding.full

        toggled: root.open

        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colBackgroundActive: Appearance.colors.colSecondaryContainerActive
        colRipple: Appearance.colors.colSecondaryContainerActive

        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
        colRippleToggled: Appearance.colors.colPrimaryActive

        onPressed: GlobalStates.sessionOpen = !GlobalStates.sessionOpen

        MaterialSymbol {
            id: glyph
            anchors.centerIn: parent
            text: "power_settings_new"
            iconSize: Math.round(root.side * 0.52 * root.contentScale)
            fill: root.open ? 1 : 0
            // The other half of whichever pair the plate is currently painted
            // in — never mixed across families.
            color: root.open
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnSecondaryContainer

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(glyph)
            }
        }
    }
}
