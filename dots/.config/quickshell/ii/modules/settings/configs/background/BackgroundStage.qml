pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The desktop wallpaper playing one of its effects: a parallax pan at the configured zoom,
 * the window blur behind stand-in windows, or a wallpaper change through the real
 * transition shader. `play()` runs the effect once, from nothing to the settled state;
 * nothing loops. The picture keeps clear of the overlays' bands.
 */
Item {
    id: root

    readonly property real parallaxTravel: 0.5
    readonly property real blurMax: 48
    readonly property int decodeWidth: 960
    readonly property int decodeHeight: 540
    readonly property int transitionDuration: 900
    readonly property int flipDelay: 120
    readonly property real windowsAreaWidth: 0.72
    readonly property real windowsMinFreeHeight: 70
    readonly property real windowEnterScale: 0.92
    readonly property string shadersPath: Qt.resolvedUrl("../../../ii/background/shaders")
    // Stand-in windows of the blur demo, as fractions of the free area: x, y, width, height.
    readonly property var windowShapes: [
        { "x": 0.14, "y": 0.1, "w": 0.4, "h": 0.62 },
        { "x": 0.46, "y": 0.28, "w": 0.4, "h": 0.62 }
    ]

    /// "parallax", "blur" or "transition".
    property string mode: "parallax"
    property string source: ""
    property string alternate: ""
    property real zoom: 1.07
    property real blurAmount: 0.8
    property string transitionShader: ""
    property bool transitionAnimated: true
    // What the overlays on top take.
    property real topBand: 0
    property real bottomBand: 0

    // 0 → 1 while an effect plays; the settled state is 1.
    property real progress: 1
    property int direction: 1
    property bool flipped: false

    readonly property real freeHeight: Math.max(1, root.height - root.topBand - root.bottomBand)
    // Going to the next workspace moves the wallpaper the other way, as the real parallax does.
    readonly property int workspace: root.direction > 0 ? 1 : 0
    readonly property real sceneScale: root.mode === "parallax" ? Math.max(1, root.zoom) : 1
    readonly property real panX: root.mode === "parallax"
        ? -(root.progress - 0.5) * root.direction * (root.sceneScale - 1) * root.width * root.parallaxTravel * 2 : 0
    readonly property real blurValue: root.mode === "blur" ? root.blurAmount * root.progress : 0
    readonly property bool windowsShown: root.mode === "blur" && root.freeHeight >= root.windowsMinFreeHeight

    function play() {
        root.direction = -root.direction;
        if (Appearance.reducedMotion) {
            root.progress = 1;
        } else {
            root.progress = 0;
            playAnimation.restart();
        }
        if (root.mode !== "transition")
            return;
        // The first change waits a beat for the picture it leaves to be on screen.
        if (root.flipped)
            root.flipped = false;
        else
            flipTimer.restart();
    }

    function settle() {
        playAnimation.stop();
        root.progress = 1;
    }

    onModeChanged: {
        flipTimer.stop();
        root.flipped = false;
    }

    NumberAnimation {
        id: playAnimation
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: Appearance.animation.elementMoveEnter.duration * 2
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    Timer {
        id: flipTimer
        interval: root.flipDelay
        onTriggered: root.flipped = true
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer1
    }

    Item {
        id: scene
        anchors.fill: parent
        scale: root.sceneScale
        x: root.panX
        layer.enabled: root.mode === "blur"
        layer.effect: MultiEffect {
            blurEnabled: root.blurValue > 0
            blur: root.blurValue
            blurMax: root.blurMax
            autoPaddingEnabled: false
        }

        Image {
            anchors.fill: parent
            visible: root.mode !== "transition"
            source: root.mode !== "transition" ? root.source : ""
            sourceSize: Qt.size(root.decodeWidth, root.decodeHeight)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            mipmap: false
        }

        // Built fresh each time the mode is entered, so a change never meets a stale one.
        Loader {
            anchors.fill: parent
            active: root.mode === "transition"

            sourceComponent: TransitionImage {
                imageSource: root.flipped ? root.alternate : root.source
                animated: root.transitionAnimated
                animationDuration: root.transitionDuration
                transitionShader: root.transitionShader
                shadersPath: root.shadersPath
                sourceSize: Qt.size(root.decodeWidth, root.decodeHeight)
                fillMode: Image.PreserveAspectCrop
                mipmap: false
            }
        }
    }

    Repeater {
        model: root.windowShapes

        delegate: BackgroundWindowShape {
            required property var modelData

            visible: root.windowsShown && opacity > 0.01
            x: (root.width - root.width * root.windowsAreaWidth) / 2 + root.width * root.windowsAreaWidth * modelData.x
            y: root.topBand + root.freeHeight * modelData.y
            width: root.width * root.windowsAreaWidth * modelData.w
            height: root.freeHeight * modelData.h
            opacity: root.mode === "blur" ? root.progress : 0
            scale: root.windowEnterScale + (1 - root.windowEnterScale) * root.progress
        }
    }
}
