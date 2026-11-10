pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Sculpt utility buttons — three Material 3 Expressive button arrangements,
 * chosen in the widget's page (`bar.utilButtons.sculptVariant`):
 *
 *   toolbar   a floating toolbar of bare icons with the first button pulled out
 *             as its FAB; a latched toggle gets a filled disc inside the bar
 *   media     a player-controls group: the middle button is a wide hero
 *             squircle, its neighbours smaller circles — size carries rank
 *   shapes    every button has its own expressive shape, which morphs into its
 *             "on" shape under the pointer and fills when the toggle latches
 *
 * Which buttons exist and what they do lives in `UtilButtonActions`.
 */
Item {
    id: root

    property bool vertical: BarPlacement.vertical

    readonly property string variant: Config.options.bar.utilButtons.sculptVariant ?? "toolbar"
    readonly property real thickness: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8

    UtilButtonActions {
        id: utilActions
    }

    BarWidgetPalette {
        id: utilTones
        colorMode: Config.options.bar.utilButtons.colorMode
    }

    readonly property var actions: utilActions.actions

    visible: root.actions.length > 0
    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : (variantLoader.item?.implicitWidth ?? 0)
    implicitHeight: root.vertical ? (variantLoader.item?.implicitHeight ?? 0) : Appearance.sizes.baseBarHeight

    Loader {
        id: variantLoader
        anchors.centerIn: parent
        sourceComponent: root.variant === "media"
            ? mediaVariant
            : root.variant === "shapes" ? shapesVariant : toolbarVariant
    }

    Component {
        id: toolbarVariant
        SculptUtilToolbar {
            vertical: root.vertical
            thickness: root.thickness
            tones: utilTones
            actionSet: utilActions
            actions: root.actions
        }
    }

    Component {
        id: mediaVariant
        SculptUtilMedia {
            vertical: root.vertical
            thickness: root.thickness
            tones: utilTones
            actionSet: utilActions
            actions: root.actions
        }
    }

    Component {
        id: shapesVariant
        SculptUtilShapes {
            vertical: root.vertical
            thickness: root.thickness
            tones: utilTones
            actionSet: utilActions
            actions: root.actions
        }
    }
}
