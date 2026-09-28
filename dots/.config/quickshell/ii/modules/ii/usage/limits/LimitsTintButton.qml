import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A labelled pill tinted with the colour of the card it sits on — the labelled sibling
 * of ClockCardAction, for the actions a hero or a block screen carries on a coloured
 * surface where a secondary-container button would be a sticker of another hue.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property color colContent: ClockStyle.colOnSurface
    /// Filled with the content colour instead of tinted by it.
    property bool solid: false
    property color colSolidContent: ClockStyle.colPrimary
    property real height_: ClockStyle.buttonHeight

    implicitHeight: root.height_
    implicitWidth: root.label.length > 0 ? row.implicitWidth + ClockStyle.gapHuge * 2 - 4 : root.height_
    buttonRadius: ClockStyle.pill(root.height_)
    buttonRadiusPressed: ClockStyle.radiusSmall
    colBackground: root.solid ? root.colContent : ColorUtils.applyAlpha(root.colContent, root.activeFocus ? 0.2 : 0.12)
    colBackgroundHover: root.solid ? ColorUtils.mix(root.colContent, root.colSolidContent, 0.88) : ColorUtils.applyAlpha(root.colContent, 0.2)
    colBackgroundActive: root.solid ? ColorUtils.mix(root.colContent, root.colSolidContent, 0.76) : ColorUtils.applyAlpha(root.colContent, 0.28)
    colRipple: colBackgroundActive
    opacity: root.enabled ? 1 : 0.4

    contentItem: Item {
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: ClockStyle.gapSmall

            MaterialSymbol {
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: ClockStyle.iconSmall + 2
                color: root.solid ? root.colSolidContent : root.colContent
            }

            StyledText {
                visible: root.label.length > 0
                text: root.label
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
                color: root.solid ? root.colSolidContent : root.colContent
            }
        }
    }
}
