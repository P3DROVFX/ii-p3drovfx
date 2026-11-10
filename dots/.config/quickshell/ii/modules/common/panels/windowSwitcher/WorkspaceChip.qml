import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/windowSwitcher/WindowSwitcherLogic.js" as Logic

/**
 * Where a window lives, on its cover or card - only when that is not the workspace you are on
 * (WindowSwitcher.workspaceAtOpen). A special workspace is marked as one. Shared by the
 * island and the panel.
 */
Rectangle {
    id: chip

    required property var entry

    readonly property var label: Logic.workspaceLabel(chip.entry, WindowSwitcher.workspaceAtOpen)

    visible: chip.label.text !== ""
    width: row.implicitWidth + 12
    height: 20
    radius: height / 2
    color: chip.label.special ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSecondaryContainer

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 3

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label.special ? "layers" : "workspaces"
            iconSize: Appearance.font.pixelSize.smaller
            color: chip.label.special ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label.text
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: chip.label.special ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSecondaryContainer
        }
    }
}
