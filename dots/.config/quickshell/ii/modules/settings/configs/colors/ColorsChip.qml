import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Filter / toggle chip of the timetable vocabulary: a dashed outline while off, the
 * secondary container once chosen, a check sliding in front of the label. `count`
 * adds a small badge after the label.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property bool chosen: false
    property int count: -1
    /// Chips on a coloured card take its content colour for the outline and text.
    property color colContent: Appearance.colors.colOnSurfaceVariant
    property color colChosen: Appearance.colors.colSecondaryContainer
    property color colOnChosen: Appearance.colors.colOnSecondaryContainer

    implicitHeight: 36
    implicitWidth: chipRow.implicitWidth + 28
    buttonRadius: height / 2
    buttonRadiusPressed: Appearance.rounding.small
    toggled: root.chosen
    colBackground: "transparent"
    colBackgroundHover: ColorUtils.applyAlpha(root.colContent, 0.08)
    colBackgroundActive: ColorUtils.applyAlpha(root.colContent, 0.16)
    colRipple: ColorUtils.applyAlpha(root.colContent, 0.16)
    colBackgroundToggled: root.colChosen
    colBackgroundToggledHover: ColorUtils.mix(root.colChosen, root.colOnChosen, 0.9)
    colBackgroundToggledActive: ColorUtils.mix(root.colChosen, root.colOnChosen, 0.8)
    colRippleToggled: ColorUtils.mix(root.colChosen, root.colOnChosen, 0.8)
    opacity: root.enabled ? 1 : 0.4

    DashedBorder {
        anchors.fill: parent
        visible: !root.chosen
        color: ColorUtils.applyAlpha(root.colContent, 0.55)
        borderWidth: 1
        dashLength: 4
        gapLength: 3
        radius: height / 2
    }

    contentItem: Item {
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                visible: root.chosen || root.symbol.length > 0
                text: root.chosen ? "check" : root.symbol
                iconSize: Appearance.font.pixelSize.normal
                fill: root.chosen ? 1 : 0
                color: root.chosen ? root.colOnChosen : root.colContent
            }

            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: root.chosen ? root.colOnChosen : root.colContent
            }

            Rectangle {
                visible: root.count >= 0
                implicitWidth: Math.max(implicitHeight, countText.implicitWidth + 10)
                implicitHeight: 20
                radius: height / 2
                color: root.chosen ? ColorUtils.applyAlpha(root.colOnChosen, 0.14) : ColorUtils.applyAlpha(root.colContent, 0.12)

                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    text: String(root.count)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: root.chosen ? root.colOnChosen : root.colContent
                }
            }
        }
    }
}
