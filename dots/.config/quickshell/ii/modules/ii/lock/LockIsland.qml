pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.dynamicIsland.styles.notch

/**
 * The Dynamic Island, on the lock screen.
 *
 * The island itself is a layer surface, and the lock takes the screen exclusively, so
 * it cannot simply carry on being drawn - it has to be rebuilt inside the lock. What is
 * rebuilt is only the outside: the same body, the same fillets into the bezel, the same
 * colour and the same corner rule as NotchIsland, at the same place and the same resting
 * size, so locking does not move it.
 *
 * Inside, a padlock sits at the left and the island's own resting face - the clock and
 * whatever side widgets it carries - fills the rest. The lock's sources keep running, so
 * the clock is live; nothing here drives activities, because the engine's surface is
 * gone and an island that changed shape while locked would be a second thing to trust.
 */
Item {
    id: root

    /** Fades in with the lock's other furniture. */
    property real contentOpacity: 1

    readonly property bool pillShape: IslandPolicy.shape === "island"
    readonly property real restHeight: {
        const configured = Config.options.bar.floatingNotch.heightHome ?? 36;
        return Math.max(IslandMotion.pillHeight, configured);
    }
    /** Where the body's top edge sits: against the bezel, or inset if it is a pill. */
    readonly property real pillInset: Appearance.sizes.hyprlandGapsOut
    readonly property real bodyTop: root.pillShape ? root.pillInset : 0

    readonly property real filletSize: Appearance.rounding.verysmall
    // The island's own body colour, including the expressive bar theme when one is on,
    // so the shape does not change colour the moment the screen locks.
    readonly property color surfaceColor: Config.options.bar.expressiveColors
        ? barThemes.getTheme(Config.options.bar.expressiveColorTheme).barBackground
        : Appearance.colors.colLayer0

    BarThemes {
        id: barThemes
    }

    /** The padlock's own column, so the resting face is not pushed off centre by it. */
    readonly property real lockSize: Math.round(root.restHeight * 0.44)
    readonly property real lockInset: Math.round(root.restHeight * 0.32)

    implicitWidth: body.width + 2 * root.filletSize
    implicitHeight: root.bodyTop + root.restHeight

    Item {
        id: bodyRow
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bodyTop
        width: body.width + 2 * root.filletSize
        height: root.restHeight
        opacity: root.contentOpacity

        // The flare into the bezel, exactly as the island does it - and only when the
        // body actually meets the edge, which a floating pill does not.
        NotchFillet {
            anchors.right: body.left
            anchors.top: parent.top
            visible: !root.pillShape
            color: root.surfaceColor
            mirrored: true
            implicitWidth: root.filletSize
            implicitHeight: root.filletSize
        }

        NotchFillet {
            anchors.left: body.right
            anchors.top: parent.top
            visible: !root.pillShape
            color: root.surfaceColor
            implicitWidth: root.filletSize
            implicitHeight: root.filletSize
        }

        Rectangle {
            id: body
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            width: Math.max(220, restingFace.targetWidth + 2 * (root.lockInset + root.lockSize))
            color: root.surfaceColor
            antialiasing: true

            // Square against the bezel, round everywhere else - the island's own rule.
            topLeftRadius: root.pillShape ? body.bottomLeftRadius : 0
            topRightRadius: root.pillShape ? body.bottomRightRadius : 0
            bottomLeftRadius: Math.min(body.height / 2, Appearance.rounding.large)
            bottomRightRadius: body.bottomLeftRadius

            MaterialSymbol {
                id: padlock
                anchors.left: parent.left
                anchors.leftMargin: root.lockInset
                anchors.verticalCenter: parent.verticalCenter
                text: "lock"
                fill: 1
                iconSize: root.lockSize
                color: Appearance.colors.colOnLayer0
            }

            // The island's resting face, unchanged: the clock, and the side widgets it
            // carries. Centred in the body rather than in the space left of the
            // padlock, so the clock stays where it is when the screen locks.
            NotchRestingFace {
                id: restingFace
                anchors.fill: parent
                anchors.leftMargin: root.lockInset + root.lockSize
                anchors.rightMargin: root.lockInset + root.lockSize
                restHeight: root.restHeight
            }
        }
    }
}
