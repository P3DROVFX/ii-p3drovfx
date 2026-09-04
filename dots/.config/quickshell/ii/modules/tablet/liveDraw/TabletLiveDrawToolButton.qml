import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/// One round control in the pen tray, at a size a pen tip can hit without aiming.
RippleButton {
    id: root

    property string symbol: ""
    property bool active: false
    property bool emphasised: false
    property string tooltipText: ""

    signal triggered

    implicitWidth: Appearance.sizes.minimumTouchTarget
    implicitHeight: Appearance.sizes.minimumTouchTarget
    buttonRadius: Appearance.rounding.full
    colBackground: root.active
        ? Appearance.colors.colPrimary
        : (root.emphasised ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1)
    colBackgroundHover: root.active
        ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    releaseAction: () => root.triggered()

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: Appearance.font.pixelSize.larger
        fill: root.active ? 1 : 0
        color: root.active
            ? Appearance.m3colors.m3onPrimary
            : (root.emphasised ? Appearance.colors.colOnSecondaryContainer
                               : Appearance.colors.colOnLayer1)
        opacity: root.enabled ? 1 : 0.4
    }

    StyledToolTip {
        text: root.tooltipText
    }
}
