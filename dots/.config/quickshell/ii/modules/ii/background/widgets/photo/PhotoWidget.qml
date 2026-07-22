import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import Qt5Compat.GraphicalEffects

AbstractBackgroundWidget {
    id: root

    configEntryName: "photo"

    implicitWidth: 260
    implicitHeight: 260

    readonly property bool expressive: Config.options.background.widgets.photo.expressiveColors ?? false
    readonly property color expressiveInnerShape: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.25)

    StyledDropShadow {
        target: outerCircle
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: outerCircle
        anchors.fill: parent
        anchors.margins: 10
        color: root.expressive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
        radius: width / 2
    }

    Item {
        anchors.fill: outerCircle
        anchors.margins: 8

        MaterialShape {
            id: photoShape
            anchors.fill: parent
            shape: MaterialShape.Shape.Cookie12Sided
            color: root.expressive ? root.expressiveInnerShape : Appearance.colors.colSurfaceContainerLow

            Image {
                id: photoImage
                anchors.fill: parent
                source: {
                    let path = Config.options.background.widgets.photo.imagePath;
                    if (!path || path === "") return "";
                    return "file://" + path;
                }
                fillMode: Image.PreserveAspectCrop
                visible: false
            }

            OpacityMask {
                anchors.fill: parent
                source: photoImage
                maskSource: photoShape
                visible: photoImage.status === Image.Ready
            }
        }
    }
}
