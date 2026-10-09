import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A small action on a coloured card, tinted with the card's content colour so it stays in
 * the card's family (the clock's card actions): 8 % idle, 16 % hover, 24 % pressed.
 */
RippleButton {
    id: root

    readonly property real pillHeight: 36
    readonly property real sidePadding: 14
    readonly property real iconGap: 6

    property string symbol: ""
    property string label: ""
    property color colContent: Appearance.colors.colOnLayer1

    implicitHeight: root.pillHeight
    implicitWidth: row.implicitWidth + root.sidePadding * 2
    buttonRadius: height / 2
    buttonRadiusPressed: Appearance.rounding.small
    colBackground: ColorUtils.applyAlpha(root.colContent, 0.1)
    colBackgroundHover: ColorUtils.applyAlpha(root.colContent, 0.18)
    colBackgroundActive: ColorUtils.applyAlpha(root.colContent, 0.26)
    colRipple: ColorUtils.applyAlpha(root.colContent, 0.26)

    contentItem: Item {
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: root.iconGap

            MaterialSymbol {
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: root.colContent
            }
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.colContent
            }
        }
    }
}
