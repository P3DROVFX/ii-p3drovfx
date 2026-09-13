import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/**
 * One control in the floating window's title strip.
 *
 * A separate file rather than an inline component: inline components belong to the top
 * level of a document, and this one is wanted three levels down inside a Variants delegate.
 */
RippleButton {
    id: root

    property string symbol: ""
    property real controlSize: Appearance.sizes.minimumTouchTarget

    implicitWidth: root.controlSize
    implicitHeight: root.controlSize
    buttonRadius: Appearance.rounding.full
    buttonRadiusPressed: Appearance.rounding.small
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active
    colRipple: Appearance.colors.colLayer2Active

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: Math.round(root.controlSize * 0.5)
        color: Appearance.colors.colOnLayer1
    }
}
