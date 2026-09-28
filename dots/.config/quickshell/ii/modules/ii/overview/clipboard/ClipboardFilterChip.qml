import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One type filter over the clipboard list: dashed and empty while idle, filled with
 * the secondary container once chosen — the timetable rail's chip vocabulary — with
 * the live match count riding inside and the symbol turning to acknowledge the pick.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property int count: 0
    property bool selected: false

    implicitWidth: chipRow.implicitWidth + 24
    implicitHeight: 32
    buttonRadius: Appearance.rounding.full
    colBackground: root.selected ? Appearance.colors.colSecondaryContainer : "transparent"
    colBackgroundHover: root.selected ? Appearance.colors.colSecondaryContainerHover : ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08)
    colBackgroundActive: root.selected ? Appearance.colors.colSecondaryContainerActive : ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16)
    colRipple: root.colBackgroundActive

    readonly property color colContent: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant

    DashedBorder {
        anchors.fill: parent
        visible: !root.selected
        color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
        borderWidth: 1
        dashLength: 4
        gapLength: 3
        radius: Appearance.rounding.full
    }

    contentItem: Item {
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: Appearance.font.pixelSize.normal
                fill: root.selected ? 1 : 0
                color: root.colContent
            }

            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.Bold
                color: root.colContent
            }

            Rectangle {
                visible: root.count > 0
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: countText.implicitWidth + 10
                implicitHeight: 18
                radius: Appearance.rounding.full
                color: ColorUtils.applyAlpha(root.colContent, root.selected ? 0.16 : 0.10)

                Behavior on color {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    text: root.count > 99 ? "99+" : root.count
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: root.colContent
                }
            }
        }
    }
}
