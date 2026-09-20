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
 * The island is a layer surface and the lock takes the screen exclusively, so it cannot
 * carry on being drawn - only its outside is rebuilt here: the same body, the same
 * fillets into the bezel, the same colour and the same corner rule as NotchIsland, at
 * the same place and the same resting height, so locking does not move it. Inside, a
 * padlock, and nothing else: the lock has its own clock, and the island's activities
 * belong to an engine whose surface is gone.
 *
 * **Every size here is declared.** The first version measured its width from the
 * island's resting face, whose width the clock drives - so the seconds ticking over
 * wrote a new width onto the body Rectangle. During the lock transition, with the
 * island's layer closing and the lock surface not yet up, that write landed on an item
 * whose window had gone and took the process down inside
 * QQuickItemPrivate::addToDirtyList. A lock-screen ornament has nothing to measure and
 * no reason to resize.
 */
Item {
    id: root

    /** Fades in with the lock's other furniture. */
    property real contentOpacity: 1

    readonly property bool pillShape: IslandPolicy.shape === "island"
    /** The island's resting height, so the shape is the size it was a moment ago. */
    readonly property real restHeight: {
        const configured = Config.options.bar.floatingNotch.heightHome ?? 36;
        return Math.max(IslandMotion.pillHeight, configured);
    }
    /** Declared, never measured: see the note above. */
    readonly property real bodyWidth: Math.round(root.restHeight * 5.2)

    readonly property real pillInset: Appearance.sizes.hyprlandGapsOut
    readonly property real bodyTop: root.pillShape ? root.pillInset : 0
    readonly property real filletSize: Appearance.rounding.verysmall

    // The island's own body colour, expressive bar theme included, so the shape does
    // not change colour the moment the screen locks.
    readonly property color surfaceColor: Config.options.bar.expressiveColors
        ? barThemes.getTheme(Config.options.bar.expressiveColorTheme).barBackground
        : Appearance.colors.colLayer0

    BarThemes {
        id: barThemes
    }

    implicitWidth: root.bodyWidth + 2 * root.filletSize
    implicitHeight: root.bodyTop + root.restHeight

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bodyTop
        width: root.bodyWidth + 2 * root.filletSize
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
            width: root.bodyWidth
            height: parent.height
            color: root.surfaceColor
            antialiasing: true

            // Square against the bezel, round everywhere else - the island's own rule.
            topLeftRadius: root.pillShape ? body.bottomLeftRadius : 0
            topRightRadius: root.pillShape ? body.bottomRightRadius : 0
            bottomLeftRadius: Math.min(body.height / 2, Appearance.rounding.large)
            bottomRightRadius: body.bottomLeftRadius

            MaterialSymbol {
                anchors.left: parent.left
                anchors.leftMargin: Math.round(root.restHeight * 0.34)
                anchors.verticalCenter: parent.verticalCenter
                text: "lock"
                fill: 1
                iconSize: Math.round(root.restHeight * 0.44)
                color: Appearance.colors.colOnLayer0
            }
        }
    }
}
