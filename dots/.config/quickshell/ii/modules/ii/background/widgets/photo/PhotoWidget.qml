import QtQuick
import QtQuick.Layouts
import qs
import qs.services
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

    readonly property color expressiveInnerShape: WidgetColorScheme.innerShapeColor

    StyledDropShadow {
        target: outerCircle
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: outerCircle
        anchors.fill: parent
        color: WidgetColorScheme.cardBgColor
        radius: width / 2
    }

    readonly property string cleanSource: {
        let path = Config.options.background.widgets.photo.imagePath;
        if (!path || path === "") return "";
        const qIdx = path.indexOf("?");
        if (qIdx !== -1) path = path.substring(0, qIdx);
        return path.startsWith("file://") ? path : ("file://" + path);
    }

    readonly property bool isAnimated: {
        const lower = root.cleanSource.toLowerCase();
        return lower.includes(".gif") || lower.includes(".webp");
    }

    readonly property bool shouldPlay: {
        return root.visible && root.opacity > 0 && root.isAnimated
            && !GlobalStates.screenLocked
            && !GlobalStates.activeWorkspaceHasWindows;
    }

    Item {
        anchors.fill: outerCircle
        anchors.margins: 8

        MaterialShape {
            id: photoShape
            anchors.fill: parent
            shape: MaterialShape.Shape.Cookie12Sided
            color: WidgetColorScheme.innerShapeColor
        }

        // Static Image loader (hardware-accelerated, zero QMovie overhead)
        Image {
            id: staticImg
            anchors.fill: parent
            source: !root.isAnimated ? root.cleanSource : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: !root.isAnimated && status === Image.Ready

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: MaterialShape {
                    width: staticImg.width
                    height: staticImg.height
                    shape: MaterialShape.Shape.Cookie12Sided
                }
            }
        }

        // Animated GIF loader (only active when isAnimated is true)
        AnimatedImage {
            id: photoImage
            anchors.fill: parent
            source: root.isAnimated ? root.cleanSource : ""
            fillMode: Image.PreserveAspectCrop
            playing: root.shouldPlay
            paused: !root.shouldPlay
            asynchronous: true
            cache: false
            visible: root.isAnimated && status === Image.Ready

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: MaterialShape {
                    width: photoImage.width
                    height: photoImage.height
                    shape: MaterialShape.Shape.Cookie12Sided
                }
            }
        }
    }
}
