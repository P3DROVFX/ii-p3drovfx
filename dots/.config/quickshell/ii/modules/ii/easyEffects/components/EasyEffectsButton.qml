import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The app's labelled pill button, in five emphases:
 *   filled  — primary, the one thing a screen is for (Save, Done)
 *   tonal   — secondary container (Revert, Import)
 *   danger  — error container (Quit EasyEffects)
 *   onHero  — on a primary-container hero: the content colour as the fill (Edit effects)
 *   ghost   — a faint tint of the hero's content colour (Bypass on the hero)
 * With `iconOnly` it is a round icon button of the same family.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property string variant: "tonal"
    property bool iconOnly: false
    property string tooltip: root.iconOnly ? root.label : ""
    property real buttonHeight: EasyEffectsStyle.buttonHeight
    property real iconSize: root.iconOnly ? EasyEffectsStyle.iconNormal : EasyEffectsStyle.iconSmall + 2
    property bool filledSymbol: false

    readonly property color colContainer: root.variant === "filled" ? EasyEffectsStyle.colPrimary
        : root.variant === "onHero" ? EasyEffectsStyle.colOnPrimaryContainer
        : root.variant === "ghost" ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintPill)
        : root.variant === "danger" ? EasyEffectsStyle.colErrorContainer
        : EasyEffectsStyle.colSecondaryContainer
    readonly property color colContainerHover: root.variant === "filled" ? EasyEffectsStyle.colPrimaryHover
        : root.variant === "onHero" ? ColorUtils.mix(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.colPrimaryContainer, 0.88)
        : root.variant === "ghost" ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintPressed)
        : root.variant === "danger" ? ColorUtils.mix(EasyEffectsStyle.colErrorContainer, EasyEffectsStyle.colOnErrorContainer, 0.88)
        : EasyEffectsStyle.colSecondaryContainerHover
    readonly property color colContent: root.variant === "filled" ? EasyEffectsStyle.colOnPrimary
        : root.variant === "onHero" ? EasyEffectsStyle.colPrimaryContainer
        : root.variant === "ghost" ? EasyEffectsStyle.colOnPrimaryContainer
        : root.variant === "danger" ? EasyEffectsStyle.colOnErrorContainer
        : EasyEffectsStyle.colOnSecondaryContainer

    implicitHeight: root.buttonHeight
    implicitWidth: root.iconOnly ? root.buttonHeight : buttonRow.implicitWidth + EasyEffectsStyle.gapHuge * 2 - EasyEffectsStyle.gapSmall / 2
    buttonRadius: EasyEffectsStyle.pill(root.buttonHeight)
    buttonRadiusPressed: EasyEffectsStyle.radiusField
    colBackground: root.colContainer
    colBackgroundHover: root.colContainerHover
    colBackgroundActive: root.colContainerHover
    colRipple: root.colContainerHover

    contentItem: Item {
        RowLayout {
            id: buttonRow
            anchors.centerIn: parent
            spacing: EasyEffectsStyle.gapSmall

            MaterialSymbol {
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: root.iconSize
                fill: root.filledSymbol ? 1 : 0
                color: root.colContent
            }

            StyledText {
                visible: !root.iconOnly
                text: root.label
                font.pixelSize: root.buttonHeight > EasyEffectsStyle.buttonHeight ? EasyEffectsStyle.textBody : EasyEffectsStyle.textNormal
                font.weight: Font.DemiBold
                color: root.colContent
            }
        }
    }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: root.tooltip.length > 0
    }
}
