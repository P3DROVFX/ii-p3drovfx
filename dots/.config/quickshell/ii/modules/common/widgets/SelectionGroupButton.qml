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

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            visible: root.buttonIcon !== undefined && root.buttonIcon !== ""
            text: root.buttonIcon || ""
            iconSize: Appearance.font.pixelSize.larger
            fill: root.toggled ? 1 : 0
            color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonShape !== undefined && root.buttonShape !== ""
            visible: active
            sourceComponent: root.buttonShape === "Rectangle" ? rectangleShapeComp : materialShapeComp
        }

        Component {
            id: rectangleShapeComp
            Rectangle {
                implicitWidth: Appearance.font.pixelSize.larger
                implicitHeight: Appearance.font.pixelSize.larger
                radius: Math.min(implicitWidth / 2, Appearance.rounding.windowRounding > 0 ? 4 : 0)
                color: root.buttonColor !== "" ? root.buttonColor : root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
        }

        Component {
            id: materialShapeComp
            MaterialShape {
                id: materialSymbol2
                implicitWidth: Appearance.font.pixelSize.larger
                implicitHeight: Appearance.font.pixelSize.larger
                shapeString: root.buttonShape
                color: root.buttonColor !== "" ? root.buttonColor : root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonSymbol !== undefined && root.buttonSymbol !== ""
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

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: root.buttonText !== undefined && root.buttonText.length > 0
            color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            text: root.buttonText || ""
        }
    }
}
