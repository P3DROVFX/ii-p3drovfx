import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The hinge of the language bar: a scalloped tertiary shape carrying the swap arrows.
 *
 * Hover morphs it into a busier scallop; every swap turns it half a turn, counted
 * across swaps so it never unwinds — the turn acknowledges the change.
 */
RippleButton {
    id: root

    property int turns: 0
    property string tooltip: ""
    property real size: 52
    /// Reached with the arrow keys (the overview panel): morphs like a hover.
    property bool keyboardFocused: false
    readonly property bool engaged: root.hovered || root.keyboardFocused

    implicitWidth: root.size
    implicitHeight: root.size
    rippleEnabled: false
    colBackground: "transparent"
    colBackgroundHover: "transparent"
    colBackgroundActive: "transparent"
    colRipple: "transparent"

    property real angle: root.turns * 180
    Behavior on angle {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
    }

    opacity: root.enabled ? 1 : 0.45
    Behavior on opacity {
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    contentItem: Item {
        MaterialShape {
            anchors.centerIn: parent
            width: root.size
            height: root.size
            shape: root.engaged ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
            rotation: root.angle
            color: root.down ? ClockStyle.colTertiaryContainerActive
                : root.engaged ? ClockStyle.colTertiaryContainerHover
                : ClockStyle.colTertiaryContainer
            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "swap_horiz"
            iconSize: ClockStyle.iconNormal
            color: ClockStyle.colOnTertiaryContainer
            rotation: root.angle
        }
    }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: root.tooltip.length > 0
    }
}
