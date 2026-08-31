import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "photo_1x1"

    visibleWhenLocked: root.lockBehavior === "keep"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "photo_1x1")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property real contentScale: (Config.options.background.widgets.photo_1x1.widgetSize ?? 100) / 100.0
    implicitWidth:  240 * contentScale
    implicitHeight: 240 * contentScale

    readonly property var options: Config.options.background.widgets.photo_1x1
    readonly property string shapeName: options?.backgroundShape ?? "Cookie9Sided"
    readonly property bool isRectangle: root.shapeName === "Rectangle"
    readonly property var chosenShape: MaterialShape.Shape[shapeName] !== undefined
                                        ? MaterialShape.Shape[shapeName]
                                        : MaterialShape.Shape.Cookie9Sided

    readonly property string imageSource: {
        let customPath = options?.imagePath;
        if (customPath && customPath !== "") {
            const qIdx = customPath.indexOf("?");
            if (qIdx !== -1) customPath = customPath.substring(0, qIdx);
            return customPath.startsWith("file://") ? customPath : ("file://" + customPath);
        }
        // Fallback to desktop wallpaper if no custom photo set
        let wallPath = Config.options?.background?.wallpaperPath;
        if (wallPath && wallPath !== "") {
            const qIdx = wallPath.indexOf("?");
            if (qIdx !== -1) wallPath = wallPath.substring(0, qIdx);
            return wallPath.startsWith("file://") ? wallPath : ("file://" + wallPath);
        }
        return "";
    }

    readonly property bool isAnimated: {
        const lower = root.imageSource.toLowerCase();
        return lower.includes(".gif") || lower.includes(".webp");
    }

    readonly property bool shouldPlay: {
        return root.visible && root.opacity > 0 && root.isAnimated
            && !GlobalStates.screenLocked
            && !GlobalStates.activeWorkspaceHasWindows;
    }

    StyledDropShadow {
        target: root.isRectangle ? shapeBgRect : shapeBg
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Item {
        anchors.fill: parent

        // 1. Background shape fill
        Rectangle {
            id: shapeBgRect
            anchors.fill: parent
            radius: Appearance.rounding.windowRounding
            color: WidgetColorScheme.cardBgColor
            visible: root.isRectangle
        }

        MaterialShape {
            id: shapeBg
            anchors.fill: parent
            shape: root.chosenShape
            color: WidgetColorScheme.cardBgColor
            visible: !root.isRectangle
        }

        // Static Image loader (hardware-accelerated, zero QMovie overhead)
        Image {
            id: staticImg
            anchors.fill: parent
            source: !root.isAnimated ? root.imageSource : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: !root.isAnimated && status === Image.Ready

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Item {
                    width: staticImg.width
                    height: staticImg.height

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.windowRounding
                        visible: root.isRectangle
                    }

                    MaterialShape {
                        anchors.fill: parent
                        shape: root.chosenShape
                        visible: !root.isRectangle
                    }
                }
            }
        }

        // Animated GIF loader (only active when isAnimated is true)
        AnimatedImage {
            id: photoImg
            anchors.fill: parent
            source: root.isAnimated ? root.imageSource : ""
            fillMode: Image.PreserveAspectCrop
            playing: root.shouldPlay
            paused: !root.shouldPlay
            asynchronous: true
            cache: false
            visible: root.isAnimated && status === Image.Ready

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Item {
                    width: photoImg.width
                    height: photoImg.height

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.windowRounding
                        visible: root.isRectangle
                    }

                    MaterialShape {
                        anchors.fill: parent
                        shape: root.chosenShape
                        visible: !root.isRectangle
                    }
                }
            }
        }

        // Placeholder icon if no photo is available
        MaterialSymbol {
            anchors.centerIn: parent
            visible: (!root.isAnimated && !staticImg.visible) || (root.isAnimated && !photoImg.visible)
            text: "image"
            iconSize: Math.round(48 * root.contentScale)
            color: Appearance.colors.colOnLayer0
            opacity: 0.50
        }
    }
}
