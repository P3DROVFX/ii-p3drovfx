import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

RippleButton {
    id: root
    property string iconName: ""
    property string symbolName: ""
    property string shapeString: ""  
    property string labelText: ""
    property bool isDestructive: false
    signal triggered()

    // The Loader supplies the controller across Component creation contexts.
    readonly property var popup: {
        let item = parent;
        while (item) {
            if (item._dockPopup !== undefined)
                return item._dockPopup;
            item = item.parent;
        }
        return null;
    }
    readonly property real reveal: popup ? popup.contentProgress(Math.floor(y / Math.max(1, height))) : 1
    opacity: reveal
    transform: Translate {
        x: (root.popup?.motionX ?? 0) * Appearance.sizes.elevationMargin * (1 - root.reveal)
        y: (root.popup?.motionY ?? 1) * Appearance.sizes.elevationMargin * (1 - root.reveal)
    }

    implicitHeight: 35
    buttonRadius: Appearance.rounding.normal
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    releaseAction: () => root.triggered()

    readonly property color contentColor: isDestructive ? Appearance.colors.colError : Appearance.colors.colOnLayer0

    contentItem: RowLayout {
        spacing: 6
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: 2
            rightMargin: 2
            verticalCenter: parent.verticalCenter
        }

        Loader {
            active: root.shapeString !== ""
            visible: active
            sourceComponent: MaterialShape {
                shapeString: root.shapeString
                implicitSize: 18
                color: root.contentColor
            }
        }

        MaterialSymbol {
            visible: root.symbolName !== "" && root.shapeString === ""
            text: root.symbolName
            iconSize: 18
            color: root.contentColor
        }

        IconImage {
            visible: root.iconName !== "" && root.symbolName === "" && root.shapeString === ""
            implicitSize: 18
            source: root.iconName !== "" ? Quickshell.iconPath(root.iconName, "") : ""
            layer.enabled: true
            layer.effect: ColorOverlay {
                color: root.contentColor
            }
        }

        StyledText {
            text: root.labelText
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignLeft
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.contentColor
        }
    }
}