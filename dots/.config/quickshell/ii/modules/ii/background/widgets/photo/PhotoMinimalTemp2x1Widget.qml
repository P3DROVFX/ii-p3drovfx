import QtQuick
import QtQuick.Layouts
import Quickshell
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "photo_minimal_temp_2x1"

    implicitWidth: 492
    implicitHeight: 240

    readonly property var currentData: Weather.data

    StyledDropShadow {
        id: shadowEffect
        target: mainCard
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    readonly property string cleanSource: {
        let entry = Config.options.background.widgets[root.configEntryName];
        let path = (entry && entry.imagePath && entry.imagePath !== "") ? entry.imagePath : Config.options.background.widgets.photo.imagePath;
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

    Rectangle {
        id: mainCard
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)

        Item {
            id: innerContent
            anchors.fill: parent
            anchors.margins: 4

            Rectangle {
                id: fallbackBg
                anchors.fill: parent
                radius: Appearance.rounding.windowRounding - 4
                color: WidgetColorScheme.tintBackground(WidgetColorScheme.innerShapeColor)
            }

            // Static Image loader (hardware-accelerated, zero QMovie overhead)
            Image {
                id: staticImg
                anchors.fill: parent
                source: (root.decodeWidth <= 0 || root.isAnimated) ? "" : root.cleanSource
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
                    maskSource: Rectangle {
                        width: staticImg.width
                        height: staticImg.height
                        radius: Appearance.rounding.windowRounding - 4
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
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: photoImage.width
                        height: photoImage.height
                        radius: Appearance.rounding.windowRounding - 4
                    }
                }
            }

            // Bottom-right temp badge
            Item {
                id: tempBadgeContainer
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                height: 48
                width: tempRow.implicitWidth + 32
                visible: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.showOverlay !== undefined ? entry.showOverlay : true;
                }

                // Semi-transparent color overlay
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: ColorUtils.applyAlpha(WidgetColorScheme.cardBgColor, 0.75)
                }

                RowLayout {
                    id: tempRow
                    anchors.centerIn: parent
                    spacing: 4

                    StyledText {
                        text: (root.currentData && root.currentData.temp) ? root.currentData.temp : "--°C"
                        color: WidgetColorScheme.textColorOnBg
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                    }
                }
            }
        }
    }
}
