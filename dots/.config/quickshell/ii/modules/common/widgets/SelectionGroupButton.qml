import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

GroupButton {
    id: root
    horizontalPadding: 12
    verticalPadding: 8
    bounce: true
    clickedWidth: baseWidth + (isAtSide ? 8 : 12)
    buttonRadiusPressed: Appearance.rounding.small
    Layout.fillWidth: false
    Layout.fillHeight: false
    scale: 1.0
    property string buttonIcon
    property string buttonShape
    property string buttonSymbol
    property string buttonColor
    property bool leftmost: false
    property bool rightmost: false
    
    readonly property bool sharpModeEnabled: Config.options.appearance.sharpMode
    readonly property int fullRadius: sharpModeEnabled ? Appearance.rounding.full : height / 2
    leftRadius: root.isPressed ? root.buttonRadiusPressed : ((toggled || leftmost) ? fullRadius : Appearance.rounding.unsharpenmore)
    rightRadius: root.isPressed ? root.buttonRadiusPressed : ((toggled || rightmost) ? fullRadius : Appearance.rounding.unsharpenmore)
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundActive: Appearance.colors.colSecondaryContainerActive

    contentItem: RowLayout {
        spacing: 4 * (root.buttonText?.length > 0)

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonIcon && root.buttonIcon.length > 0
            visible: active
            sourceComponent: Item {
                implicitWidth: materialSymbol.implicitWidth
                MaterialSymbol {
                    id: materialSymbol
                    anchors.centerIn: parent
                    text: root.buttonIcon
                    iconSize: Appearance.font.pixelSize.larger
                    fill: root.toggled ? 1 : 0
                    color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonShape && root.buttonShape.length > 0
            visible: active
            sourceComponent: MaterialShape {
                id: materialSymbol2
                implicitWidth: Appearance.font.pixelSize.larger
                implicitHeight: Appearance.font.pixelSize.larger
                shapeString: root.buttonShape
                color: root.buttonColor !== "" ? root.buttonColor : root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonSymbol && root.buttonSymbol.length > 0
            visible: active
            sourceComponent: CustomIcon {
                id: materialSymbol3
                width: Appearance.font.pixelSize.larger
                height: Appearance.font.pixelSize.larger
                source: root.buttonSymbol
                colorize: true
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
        }

        Item {
            implicitWidth: root.buttonText?.length > 0 ? textItem.implicitWidth : 0
            implicitHeight: textMetrics.height // Force height to that of regular text

            TextMetrics {
                id: textMetrics
                font.family: Appearance.font.family.main
                text: "Abc"
            }

            StyledText {
                id: textItem
                anchors.centerIn: parent
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                text: root.buttonText
            }
        }
    }
}