import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls.FluentWinUI3
import QtQuick.Controls

TextField {
    id: root
    
    clip: true
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    color: Looks.colors.fg

    palette {
        active: Looks.colors.accent
    }

    font {
        hintingPreference: Font.PreferDefaultHinting
        family: Looks.font.family.ui
        pixelSize: Looks.font.pixelSize.normal
        weight: Looks.font.weight.regular
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
