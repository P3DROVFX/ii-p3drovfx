import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Choice row: dashed chips, the chosen one filled (ClockFormChip). Options are
 * `{ label, value, icon?, fontFamily? }`.
 */
CheatsheetSettingRow {
    id: choiceRow

    property var options: []
    property var currentValue: null

    signal selected(var value)

    below: Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: choiceRow.options

            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool chosen: choiceRow.currentValue === modelData.value

                implicitWidth: Math.max(implicitHeight, chipRow.implicitWidth + 22)
                implicitHeight: 32
                radius: Appearance.rounding.full
                color: chip.chosen ? Appearance.colors.colSecondaryContainer
                    : chipHover.hovered ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08) : "transparent"

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                DashedBorder {
                    anchors.fill: parent
                    visible: !chip.chosen
                    color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
                    borderWidth: 1
                    dashLength: 4
                    gapLength: 3
                    radius: Appearance.rounding.full
                }

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        visible: (chip.modelData.icon ?? "").length > 0
                        text: chip.modelData.icon ?? ""
                        iconSize: Appearance.font.pixelSize.normal
                        fill: chip.chosen ? 1 : 0
                        color: chip.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: chip.modelData.label
                        font.family: chip.modelData.fontFamily ?? Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: chip.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                    }
                }

                HoverHandler {
                    id: chipHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: choiceRow.selected(chip.modelData.value)
                }
            }
        }
    }
}
