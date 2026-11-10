import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A round icon button sized for an entry row (the keyboard layout list's), dimmed rather
 * than hidden when it does not apply, so the buttons beside it never move. `active` fills
 * it for a state that is on (an entry in the icon bar).
 */
RippleButton {
    id: action

    property string symbol: ""
    property color tint: Appearance.colors.colOnLayer2
    // What it turns under the pointer: removing says so in red before the click.
    property color hoverTint: action.tint
    property string tooltip: ""
    property bool active: false

    readonly property color liveTint: action.active ? Appearance.colors.colOnSecondaryContainer
        : action.hovered ? action.hoverTint : action.tint

    implicitWidth: 34
    implicitHeight: 34
    buttonRadius: Appearance.rounding.full
    opacity: action.enabled ? 1 : 0.35
    colBackground: action.active ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(action.tint, 1)
    colBackgroundHover: action.active ? Appearance.colors.colSecondaryContainerHover : ColorUtils.transparentize(action.hoverTint, 0.88)
    colRipple: ColorUtils.transparentize(action.hoverTint, 0.75)

    MaterialSymbol {
        anchors.centerIn: parent
        text: action.symbol
        iconSize: Appearance.font.pixelSize.large
        fill: action.active ? 1 : 0
        color: action.liveTint

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    StyledToolTip {
        text: action.tooltip
    }
}
