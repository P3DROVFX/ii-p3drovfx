import qs.modules.common
import QtQuick
import QtQuick.Controls

/**
 * Does not include visual layout, but includes the easily neglected colors.
 */
TextArea {
    id: root

    renderType: Text.NativeRendering
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: Appearance.m3colors.m3outline
    color: Appearance.colors.colOnLayer0
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }

    StyledTextContextMenu {
        id: contextMenu
        targetField: root
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.forceActiveFocus();
                contextMenu.popup(mouse.x, mouse.y);
            }
        }
    }
}
