import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: profileCard
    
    property string profileName: ""
    property bool isActive: false
    
    signal applyClicked()
    signal deleteClicked()
    
    Layout.fillWidth: true
    Layout.preferredHeight: 65
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    border.width: isActive ? 2 : 1
    border.color: isActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

    RowLayout {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 12

        MaterialSymbol {
            text: "display_settings"
            iconSize: 22
            color: isActive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            
            RowLayout {
                spacing: 8
                
                StyledText {
                    text: profileName
                    color: isActive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: isActive ? Font.Bold : Font.Normal
                }
                
                Rectangle {
                    visible: isActive
                    color: Appearance.colors.colPrimaryContainer
                    radius: 4
                    Layout.preferredWidth: activeText.contentWidth + 12
                    Layout.preferredHeight: activeText.contentHeight + 4
                    
                    StyledText {
                        id: activeText
                        anchors.centerIn: parent
                        text: "ACTIVE"
                        color: Appearance.colors.colOnPrimaryContainer
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                    }
                }
            }
        }

        RippleButtonWithIcon {
            buttonRadius: Appearance.rounding.small
            materialIcon: "done"
            mainText: Translation.tr("Apply")
            enabled: !isActive
            onClicked: profileCard.applyClicked()
        }
        
        Rectangle {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: Appearance.rounding.small
            color: "transparent"
            
            MaterialSymbol {
                anchors.centerIn: parent
                text: "delete"
                iconSize: 20
                color: Appearance.colors.colError
            }
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: profileCard.deleteClicked()
            }
        }
    }
}
