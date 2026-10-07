import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * A photo and nothing else: the picture cropped to fill a rounded rectangle,
 * no border, no text. The base of the Plain Photo 1x1, 2x1 and 1x2 widgets,
 * which only set their entry and their size in design units.
 *
 * The picture is this instance's own (picked from its Edit Mode page), else
 * the type's, else the wallpaper. It is decoded at the size it is shown at,
 * like Photo1x1Widget, and an animated one only plays while it can be seen.
 */
AbstractBackgroundWidget {
    id: root

    property real designWidth: 240
    property real designHeight: 240

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === root.configEntryName)

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.[root.configEntryName] ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    // Sized in real pixels, not by `scale`: the picture is decoded for the box it fills.
    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    function fileUrl(path) {
        if (!path)
            return "";
        const q = path.indexOf("?");
        const clean = q !== -1 ? path.substring(0, q) : path;
        return clean.startsWith("file://") ? clean : "file://" + clean;
    }

    readonly property string imageSource: {
        const own = root.instanceImagePath !== undefined ? root.instanceImagePath : root.options?.imagePath;
        if (own && own !== "")
            return root.fileUrl(own);
        return root.fileUrl(Config.options?.background?.wallpaperPath ?? "");
    }

    readonly property bool isAnimated: {
        const lower = root.imageSource.toLowerCase();
        return lower.includes(".gif") || lower.includes(".webp");
    }
    readonly property bool shouldPlay: root.visible && root.opacity > 0 && root.isAnimated
                                     && !GlobalStates.screenLocked
                                     && !GlobalStates.activeWorkspaceHasWindows

    // Decode box: the shown size times the window's DPR (high-water mark - it
    // churns while the window is set up) and the render scale, quantised so
    // small changes do not re-decode, and held while the resize grip runs.
    readonly property real windowDpr: Math.max(1, (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
    property real dprLatched: 1
    readonly property real decodeScale: root.dprLatched * root.renderScale
    property int decodeWidth: 0
    property int decodeHeight: 0

    function updateDpr() {
        if (root.windowDpr > root.dprLatched)
            root.dprLatched = root.windowDpr;
    }
    function updateDecodeBox() {
        if (root._resizeActive || root.width <= 0 || root.height <= 0)
            return;
        root.decodeWidth = Math.ceil(root.width * root.decodeScale / 64) * 64;
        root.decodeHeight = Math.ceil(root.height * root.decodeScale / 64) * 64;
    }

    onWindowDprChanged: root.updateDpr()
    onDecodeScaleChanged: root.updateDecodeBox()
    onWidthChanged: root.updateDecodeBox()
    onHeightChanged: root.updateDecodeBox()
    on_ResizeActiveChanged: root.updateDecodeBox()
    Component.onCompleted: {
        root.updateDpr();
        root.updateDecodeBox();
    }

    StyledRectangularShadow {
        target: frame
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    ClippingRectangle {
        id: frame
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)

        Image {
            id: still
            anchors.fill: parent
            source: (root.decodeWidth <= 0 || root.isAnimated) ? "" : root.imageSource
            sourceSize: Qt.size(root.decodeWidth, root.decodeHeight)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Keep the frame on screen across a re-decode.
            retainWhileLoading: true
            visible: !root.isAnimated
        }

        AnimatedImage {
            anchors.fill: parent
            source: root.isAnimated ? root.imageSource : ""
            fillMode: Image.PreserveAspectCrop
            playing: root.shouldPlay
            paused: !root.shouldPlay
            asynchronous: true
            cache: false
            visible: root.isAnimated
        }
    }
}
