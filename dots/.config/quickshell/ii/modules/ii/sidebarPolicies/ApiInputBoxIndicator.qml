import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item { // Model indicator
    id: root
    property string icon: ""
    property string symbol: ""
    property string text: ""
    property string tooltipText: ""
    implicitHeight: rowLayout.implicitHeight + 4 * 2
    implicitWidth: rowLayout.implicitWidth + 4 * 2

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent

        Loader {
            active: root.icon.length > 0
            sourceComponent: MaterialSymbol {
                text: root.icon
                iconSize: Appearance.font.pixelSize.normal
            }
        }
        Loader {
            active: root.symbol.length > 0
            sourceComponent: CustomIcon {
                source: root.symbol
                width: Appearance.font.pixelSize.normal
                height: Appearance.font.pixelSize.normal
                colorize: true
                color: Appearance.colors.colPrimary
            }
        }
        
        AnimatedStyledText {
            id: providerName
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.m3colors.m3onSurface
            elide: Text.ElideRight
            text: root.text
            animateChange: true
        }
    }

    Loader {
        active: root.tooltipText?.length > 0
        anchors.fill: parent
        sourceComponent: MouseArea {
            id: mouseArea
            hoverEnabled: true

            StyledToolTip {
                id: toolTip
                extraVisibleCondition: false
                alternativeVisibleCondition: mouseArea.containsMouse // Show tooltip when hovered
                text: root.tooltipText
            }
        }
    }
}
