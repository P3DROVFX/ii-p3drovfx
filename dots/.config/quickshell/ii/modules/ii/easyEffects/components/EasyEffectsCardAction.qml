import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * A round action on a card or a row (edit, make default, move, remove), tinted with the
 * card's own content colour so it reads on a primary-container card and an idle one alike.
 * `danger` takes the error container.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string tip: ""
    property bool danger: false
    property bool filledSymbol: false
    property color colContent: EasyEffectsStyle.colOnSurface
    property real size: EasyEffectsStyle.fieldBadge

    implicitWidth: root.size
    implicitHeight: root.size
    buttonRadius: EasyEffectsStyle.pill(root.size)
    buttonRadiusPressed: EasyEffectsStyle.radiusField
    colBackground: root.danger ? EasyEffectsStyle.colErrorContainer
        : EasyEffectsStyle.tint(root.colContent, root.activeFocus ? EasyEffectsStyle.tintHover : EasyEffectsStyle.tintIdle)
    colBackgroundHover: root.danger ? EasyEffectsStyle.colErrorContainer : EasyEffectsStyle.tint(root.colContent, EasyEffectsStyle.tintHover)
    colBackgroundActive: root.danger ? EasyEffectsStyle.colErrorContainer : EasyEffectsStyle.tint(root.colContent, EasyEffectsStyle.tintPressed)
    colRipple: root.colBackgroundActive
    opacity: root.enabled ? 1 : EasyEffectsStyle.opacityDisabled

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.symbol
        iconSize: EasyEffectsStyle.iconSmall + 2
        fill: root.filledSymbol ? 1 : 0
        color: root.danger ? EasyEffectsStyle.colOnErrorContainer : root.colContent
    }

    StyledToolTip {
        text: root.tip
        extraVisibleCondition: root.tip.length > 0
    }
}
