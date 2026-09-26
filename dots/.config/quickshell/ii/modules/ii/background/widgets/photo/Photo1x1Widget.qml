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

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
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

    // The photo is minified straight down to the widget box by the GPU's 2x2 tap,
    // which aliases badly past ~2x. Cap the decode so the JPEG decoder does that
    // downscale properly instead, and the texture arrives at the size it is shown.
    // The window's DPR churns while the window is set up (2 -> 1.5 -> 1) and every
    // change re-decodes the file, so keep its high-water mark. The box itself still
    // follows the widget: latching that too would leave an oversized texture to
    // undersample again after scaling down.
    readonly property real windowDpr: Math.max(1, (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
    property real dprLatched: 1
    function updateDpr() {
        if (root.windowDpr > root.dprLatched) root.dprLatched = root.windowDpr;
    }

    // Quantised so small box changes don't re-decode, and frozen outright while
    // the resize grip runs: this widget resizes through the widgetSize path,
    // which rewrites its layout box on every 5% step, and a decode per step
    // drops the picture back to its placeholder mid-drag. It rides the gesture
    // at the resolution it already had and is re-decoded once, on release.
    readonly property real decodeScale: root.dprLatched * root.renderScale
    property int decodeWidth: 0
    property int decodeHeight: 0
    function updateDecodeBox() {
        if (root._resizeActive || root.width <= 0 || root.height <= 0) return;
        root.decodeWidth = Math.ceil(root.width * root.decodeScale / 64) * 64;
        root.decodeHeight = Math.ceil(root.height * root.decodeScale / 64) * 64;
    }

    // The window is not attached yet at completion, so latch the DPR on both.
    onWindowDprChanged: root.updateDpr()
    onDecodeScaleChanged: root.updateDecodeBox()
    onWidthChanged: root.updateDecodeBox()
    onHeightChanged: root.updateDecodeBox()
    on_ResizeActiveChanged: root.updateDecodeBox()
    Component.onCompleted: {
        root.updateDpr();
        root.updateDecodeBox();
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
            color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
            visible: root.isRectangle
        }

        MaterialShape {
            id: shapeBg
            anchors.fill: parent
            shape: root.chosenShape
            color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
            visible: !root.isRectangle
        }

        // Static Image loader (hardware-accelerated, zero QMovie overhead)
        Image {
            id: staticImg
            anchors.fill: parent
            source: (root.decodeWidth <= 0 || root.isAnimated) ? "" : root.imageSource
            sourceSize: Qt.size(root.decodeWidth, root.decodeHeight)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Hold the frame already on screen across a re-decode instead of
            // falling back to the placeholder for the frames it takes.
            retainWhileLoading: true
            property bool everLoaded: false
            onStatusChanged: if (status === Image.Ready) staticImg.everLoaded = true
            visible: !root.isAnimated && (status === Image.Ready || staticImg.everLoaded)

            layer.enabled: true
            layer.smooth: true
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
            layer.smooth: true
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
