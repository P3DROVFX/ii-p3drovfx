import QtQuick
import QtQuick.Layouts
import qs.modules.common

ToolbarButton {
    id: iconBtn
    required property string iconText

    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    property color colText: toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
    property real iconSize: 22
    property bool iconFill: false
    property int labelWeight: Font.Normal

    contentItem: Row {
        anchors.centerIn: parent
        spacing: 4

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: iconBtn.iconSize
            fill: iconBtn.iconFill ? 1 : 0
            text: iconBtn.iconText
            color: iconBtn.colText
        }
        StyledText {
            visible: iconBtn.iconText.length > 0 && iconBtn.text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            color: iconBtn.colText
            text: iconBtn.text
            font.weight: iconBtn.labelWeight
        }
    }
}
