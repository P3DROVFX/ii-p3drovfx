import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * App-bar icon action: a circle at rest that squares its corners while toggled or
 * pressed (shape = state), on the tab's surface tint.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string tooltip: ""
    property bool busy: false

    implicitWidth: 40
    implicitHeight: 40
    buttonRadius: root.toggled ? Appearance.rounding.normal : Appearance.rounding.full
    buttonRadiusPressed: Appearance.rounding.small
    colBackground: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0)
    colBackgroundHover: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.08)
    colBackgroundActive: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.14)
    colBackgroundToggled: ClockStyle.colSecondaryContainer
    colBackgroundToggledHover: ClockStyle.colSecondaryContainerHover
    colBackgroundToggledActive: ClockStyle.colSecondaryContainerActive
    colRipple: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.16)
    colRippleToggled: ClockStyle.colSecondaryContainerActive

    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            visible: !root.busy
            text: root.symbol
            iconSize: 22
            fill: root.toggled ? 1 : 0
            color: root.toggled ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
        }
        MaterialLoadingIndicator {
            anchors.centerIn: parent
            visible: root.busy
            loading: root.busy
            implicitSize: 30
            shapeColor: ClockStyle.colPrimary
        }
    }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: root.tooltip.length > 0
    }
}
