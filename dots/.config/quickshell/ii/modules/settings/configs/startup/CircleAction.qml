import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/** 36 px round icon action with a tooltip (secondary actions on cards and rows). */
RippleButton {
    id: root

    property string symbol: ""
    property string tip: ""
    property color colContent: Appearance.colors.colOnSurface
    property color colFill: Appearance.colors.colSurfaceContainerHighest
    property real size: 36

    implicitWidth: root.size
    implicitHeight: root.size
    buttonRadius: root.size / 2
    buttonRadiusPressed: Appearance.rounding.small
    colBackground: root.colFill
    colBackgroundHover: ColorUtils.mix(root.colFill, root.colContent, 0.88)
    colRipple: ColorUtils.mix(root.colFill, root.colContent, 0.76)

    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.symbol
            iconSize: Math.round(root.size * 0.5)
            color: root.colContent
        }
    }

    StyledToolTip {
        text: root.tip
        extraVisibleCondition: root.tip.length > 0
    }
}
