import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * Round icon button. Squares off slightly while pressed, the Material 3 Expressive
 * shape response to touch.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string tooltip: ""
    property real size: ClockStyle.iconButton
    property real iconSize: ClockStyle.iconNormal
    property bool filled: false
    property color colIcon: root.toggled ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant

    implicitWidth: root.size
    implicitHeight: root.size
    buttonRadius: ClockStyle.pill(root.size)
    buttonRadiusPressed: ClockStyle.radiusSmall
    colBackground: "transparent"
    colBackgroundHover: ClockStyle.colSurfaceHover
    colRipple: ClockStyle.colSurfaceActive
    colBackgroundToggled: ClockStyle.colPrimary
    colBackgroundToggledHover: ClockStyle.colPrimaryHover
    colRippleToggled: ClockStyle.colPrimaryActive

    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.symbol
            iconSize: root.iconSize
            fill: root.filled || root.toggled ? 1 : 0
            color: root.colIcon

            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }
        }
    }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: root.tooltip.length > 0
    }
}
