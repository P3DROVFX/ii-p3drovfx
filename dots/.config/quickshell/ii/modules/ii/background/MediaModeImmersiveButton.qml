pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Round icon action for the Immersive frontend. `quiet` buttons rest without a
// surface, like transport controls over glass; `filled` is the primary action.
RippleButton {
    id: root
    required property string symbol
    property string tooltip: ""
    property real symbolSize: Appearance.font.pixelSize.large
    property color foreground: Appearance.colors.colOnLayer0
    property bool quiet: false
    property bool filled: false
    readonly property color filledForeground: ColorUtils.getContrastingTextColor(foreground)
    implicitWidth: Appearance.sizes.minimumTouchTarget
    implicitHeight: implicitWidth
    buttonRadius: Appearance.rounding.full
    colBackground: filled ? foreground : ColorUtils.applyAlpha(foreground, highlighted ? 0.18 : (quiet ? 0 : 0.08))
    colBackgroundHover: filled ? ColorUtils.mix(foreground, filledForeground, 0.9) : ColorUtils.applyAlpha(
                                     foreground, highlighted ? 0.24 : 0.14)
    colBackgroundActive: filled ? ColorUtils.mix(foreground, filledForeground, 0.8) : ColorUtils.applyAlpha(
                                      foreground, 0.28)
    colRipple: ColorUtils.applyAlpha(filled ? filledForeground : foreground, 0.2)
    Accessible.name: tooltip
    MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: root.symbolSize
        color: root.filled ? root.filledForeground : ColorUtils.applyAlpha(root.foreground, !root.enabled ? 0.38 :
                                                                                                          (root.quiet && !root.highlighted) ? 0.82 : 1)
        fill: 1
    }
    PopupToolTip {
        text: root.tooltip
    }
}
