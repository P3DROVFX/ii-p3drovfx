import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A small action a card reveals on hover — the world clock's move / rename / remove
 * buttons, shared so alarms, cities and timers all answer the pointer the same way.
 * A tinted square on the card's own content colour; `danger` takes the error container.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string tip: ""
    property bool danger: false
    property color colContent: ClockStyle.colOnSurface

    implicitWidth: 34
    implicitHeight: 34
    buttonRadius: Appearance.rounding.small
    buttonRadiusPressed: Appearance.rounding.full
    colBackground: root.danger
        ? (root.activeFocus ? ClockStyle.colErrorContainerHover : ClockStyle.colErrorContainer)
        : ColorUtils.applyAlpha(root.colContent, root.activeFocus ? 0.16 : 0.08)
    colBackgroundHover: root.danger ? ClockStyle.colErrorContainerHover : ColorUtils.applyAlpha(root.colContent, 0.16)
    colBackgroundActive: root.danger ? Appearance.colors.colErrorContainerActive : ColorUtils.applyAlpha(root.colContent, 0.24)
    colRipple: colBackgroundActive
    opacity: root.enabled ? 1 : 0.35

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.symbol
        iconSize: Appearance.font.pixelSize.large
        color: root.danger ? ClockStyle.colOnErrorContainer : root.colContent
    }

    StyledToolTip {
        text: root.tip
        extraVisibleCondition: root.tip.length > 0
    }
}
