import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: root
    property string buttonIcon
    property color labelColor: Appearance.colors.colOnLayer3
    property alias iconSize: iconWidget.iconSize

    Layout.fillWidth: true
    implicitHeight: contentItem.implicitHeight + 8 * 2
    font.pixelSize: Appearance.font.pixelSize.small
    
    onClicked: checked = !checked

    contentItem: RowLayout {
        spacing: 10
        MaterialSymbol {
            id: iconWidget
            text: root.buttonIcon
            opacity: root.enabled ? 1 : 0.4
            iconSize: Appearance.font.pixelSize.larger
            color: root.labelColor
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: root.labelColor
            opacity: root.enabled ? 1 : 0.4
        }
        StyledSwitch {
            id: switchWidget
            down: root.down
            Layout.fillWidth: false
            checked: root.checked
            onClicked: root.clicked()
        }
    }
}
