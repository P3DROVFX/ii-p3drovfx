pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id: root

    property var device: null

    readonly property list<var> optionBoxes: EarbudsControlService.dynamicControls(root.device)
    readonly property list<var> indicatorsList: EarbudsControlService.indicators(root.device)
    readonly property bool hasControls: root.optionBoxes.length > 0 || root.indicatorsList.length > 0

    visible: root.hasControls
    Layout.fillWidth: true
    spacing: 12

    // Indicators section if available
    RowLayout {
        visible: root.indicatorsList.length > 0
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: root.indicatorsList
            delegate: Rectangle {
                id: indicatorChip
                required property var modelData
                required property int index

                readonly property var indObj: modelData

                implicitHeight: 28
                implicitWidth: indRow.implicitWidth + 16
                radius: Appearance.rounding.full
                color: Appearance.colors.colSurfaceContainerHighest

                RowLayout {
                    id: indRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        visible: Boolean(indicatorChip.indObj.icon)
                        text: indicatorChip.indObj.icon || "info"
                        iconSize: 14
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        text: indicatorChip.indObj.text || ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }
    }

    // Dynamic option boxes
    Repeater {
        model: root.optionBoxes
        delegate: BudsLinkOptionBox {
            required property var modelData
            required property int index

            boxData: modelData
            device: root.device

            onSliderChanged: (val, isDrag) => {
                EarbudsControlService.sendSliderAction(root.device, modelData.index, val, isDrag);
            }

            onCheckChanged: (checkIdx, st) => {
                EarbudsControlService.sendCheckAction(root.device, modelData.index, checkIdx, st);
            }

            onRadioChanged: st => {
                EarbudsControlService.sendRadioAction(root.device, modelData.index, st);
            }
        }
    }
}
