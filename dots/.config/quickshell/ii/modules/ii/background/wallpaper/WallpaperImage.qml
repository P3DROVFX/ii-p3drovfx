import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.ii.background.blur

Item {
    id: wallpaperImageRoot
    anchors.fill: parent

    // Required inputs
    required property var screen
    required property string wallpaperPath
    property string lockscreenWallpaperPath: ""
    property bool useSeparateLockscreenWallpaper: false
    required property bool wallpaperIsVideo
    required property bool wallpaperSafetyTriggered
    required property real preferredWallpaperScale
    required property real effectiveWallpaperScale
    required property real baseWallpaperScale
    required property int wallpaperWidth
    required property int wallpaperHeight
    required property real wallpaperToScreenRatio
    required property real movableXSpace
    required property real movableYSpace
    required property real minSafeScale

    required property real parallaxX
    required property real parallaxY
    required property real scaleValue
    required property real scaleOriginX
    required property real scaleOriginY
    required property real scaleProgress

    required property bool anyWidgetIsDragging
    required property bool mediaModeOpen
    property bool lockAnimationActive: false
    required property bool hasWindowsInActiveWorkspace

    // Output aliases
    property alias wallpaperItem: wallpaper
    property alias clipRectItem: centralWallpaperClipRect

    // Calculations
    readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    readonly property bool zoomInStyle: Config.options.overview.scrollingStyle.zoomStyle === "in"
    readonly property bool showOpeningAnimation: Config.options.overview.showOpeningAnimation
    readonly property bool overviewOpen: GlobalStates.overviewOpen

    readonly property var zoomLevels: ({
        "in": {
            default: 1.04,
            zoomed: 1
        },
        "out": {
            default: 1,
            zoomed: 1.01
        }
    })

    readonly property real defaultRatio: zoomInStyle ? zoomLevels.in.default : zoomLevels.out.default
    readonly property real zoomedRatio: zoomInStyle ? zoomLevels.in.zoomed : zoomLevels.out.zoomed

    property real scaleAnimated: overviewOpen && showOpeningAnimation ? zoomedRatio : defaultRatio
    Behavior on scaleAnimated {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(wallpaperImageRoot)
    }

    scale: showOpeningAnimation && overviewOpen && isScrollingLayout ? zoomedRatio : defaultRatio
    opacity: mediaModeOpen ? 0 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: 300
            easing.type: Easing.InOutQuad
        }
    }

    Behavior on scale {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(wallpaperImageRoot)
    }

    // --- STYLE 0/1: Blurred backing ---
    TransitionImage {
        id: bgWallpaperBlurred
        anchors.fill: parent
        imageSource: !wallpaperSafetyTriggered ? wallpaperPath : ""
        animated: Config.options.background.animateWallpaperChanges
        fillMode: Image.PreserveAspectCrop
        visible: Config.options.background.zoomOutStyle !== 2 && !wallpaperSafetyTriggered
        opacity: 1.0
        mipmap: false
        antialiasing: false
        sourceSize: Qt.size(screen.width > 0 ? Math.round(screen.width / 4) : 480, screen.height > 0 ? Math.round(screen.height / 4) : 270)
        lockAnimationActive: wallpaperImageRoot.lockAnimationActive
    }

    Loader {
        id: bgWallpaperBlurLoader
        anchors.fill: bgWallpaperBlurred
        active: true
        opacity: wallpaperImageRoot.wallpaperZoomedOut ? 1.0 : 0.0
        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(wallpaperImageRoot)
        }
        sourceComponent: MultiEffect {
            anchors.fill: parent
            source: bgWallpaperBlurred
            blurEnabled: true
            blurMax: 75
            blur: 0.7

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0.24
            }
        }
    }

    readonly property bool scratchpadOpen: {
        if (!HyprlandData.monitors)
            return false;
        return HyprlandData.monitors.some(function(mon) { return mon.specialWorkspace && mon.specialWorkspace.name !== ""; });
    }
    readonly property bool wallpaperZoomedOut: Config.options.background.zoomOutEnabled && (GlobalStates.cheatsheetOpen || GlobalStates.overviewOpen || scratchpadOpen) && (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name == screen.name : false)

    property real wallpaperClipRadius: wallpaperZoomedOut ? Appearance.rounding.windowRounding : 0
    Behavior on wallpaperClipRadius {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(wallpaperImageRoot)
    }

    // Wallpaper planes: scale zoom-out.
    Item {
        id: wallpaperPlanes
        anchors.fill: parent

        readonly property real wallpaperW: wallpaperWidth / wallpaperToScreenRatio * baseWallpaperScale
        readonly property real wallpaperH: wallpaperHeight / wallpaperToScreenRatio * baseWallpaperScale
        readonly property real centeredX: -movableXSpace
        readonly property real centeredY: -movableYSpace

        transform: Scale {
            origin.x: scaleOriginX
            origin.y: scaleOriginY
            xScale: scaleValue
            yScale: scaleValue
        }

        Rectangle {
            id: centralClipMask
            x: 0
            y: 0
            width: centralWallpaperClipRect.width
            height: centralWallpaperClipRect.height
            radius: centralWallpaperClipRect.radius
            visible: false
            layer.enabled: centralWallpaperClipRect.layer.enabled
        }

        StyledRectangularShadow {
            id: centralWallpaperShadow
            target: centralWallpaperClipRect
            blur: 32 * scaleProgress
            offset: Qt.vector2d(0, 4 * scaleProgress)
            visible: Config.options.background.zoomOutStyle === 0 && scaleProgress > 0.01
            opacity: scaleProgress
        }

        Rectangle {
            id: centralWallpaperClipRect
            x: Config.options.background.zoomOutStyle !== 1 ? 0 : parallaxX
            y: Config.options.background.zoomOutStyle !== 1 ? 0 : parallaxY
            width: Config.options.background.zoomOutStyle !== 1 ? screen.width : wallpaperPlanes.wallpaperW
            height: Config.options.background.zoomOutStyle !== 1 ? screen.height : wallpaperPlanes.wallpaperH
            color: "transparent"
            radius: Config.options.background.zoomOutStyle === 0 ? wallpaperImageRoot.wallpaperClipRadius : 0
            clip: Config.options.background.zoomOutStyle !== 1
            border.color: CF.ColorUtils.transparentize(Appearance.colors.colPrimary, 0.35)
            border.width: 1.5 * scaleProgress

            layer.enabled: radius > 0
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: centralClipMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Behavior on x {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(wallpaperImageRoot)
            }
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(wallpaperImageRoot)
            }
            Behavior on width {
                enabled: !wallpaperImageRoot.lockAnimationActive
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on height {
                enabled: !wallpaperImageRoot.lockAnimationActive
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }

            Item {
                id: wallpaperContent
                layer.enabled: true
                width: Config.options.background.zoomOutStyle !== 1 ? wallpaperPlanes.wallpaperW : parent.width
                height: Config.options.background.zoomOutStyle !== 1 ? wallpaperPlanes.wallpaperH : parent.height

                transform: [
                    Scale {
                        origin.x: wallpaperContent.width / 2
                        origin.y: wallpaperContent.height / 2
                        xScale: baseWallpaperScale > 0 ? (effectiveWallpaperScale / baseWallpaperScale) : 1.0
                        yScale: baseWallpaperScale > 0 ? (effectiveWallpaperScale / baseWallpaperScale) : 1.0
                    },
                    Translate {
                        id: parallaxTranslate
                        x: {
                            if (Config.options.background.zoomOutStyle === 1) {
                                return 0;
                            }
                            return wallpaperImageRoot.wallpaperZoomedOut ? wallpaperPlanes.centeredX : parallaxX;
                        }
                        y: {
                            if (Config.options.background.zoomOutStyle === 1) {
                                return 0;
                            }
                            return wallpaperImageRoot.wallpaperZoomedOut ? wallpaperPlanes.centeredY : parallaxY;
                        }
                        Behavior on x {
                            NumberAnimation {
                                duration: Math.round(450 * Appearance.animMultiplier)
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on y {
                            NumberAnimation {
                                duration: Math.round(450 * Appearance.animMultiplier)
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                ]

                Item {
                    id: wallpaperVisualContainer
                    anchors.fill: parent

                    TransitionImage {
                        id: wallpaper
                        anchors.fill: parent

                        visible: opacity > 0 && !wallpaperIsVideo
                        opacity: (wallpaper.status === Image.Ready && !wallpaperIsVideo) ? 1 : 0
                        sourceSize: Config.options.background.scaleLargeWallpapers ? Qt.size(screen.width > 0 ? Math.round(screen.width * preferredWallpaperScale) : 1920, screen.height > 0 ? Math.round(screen.height * preferredWallpaperScale) : 1080) : Qt.size(-1, -1)

                        imageSource: wallpaperSafetyTriggered ? "" : wallpaperPath
                        animated: Config.options.background.animateWallpaperChanges
                        transitionShader: Config.options.background.wallpaperAnimation
                        shadersPath: Qt.resolvedUrl("../shaders")
                        fillMode: Image.PreserveAspectCrop
                        mipmap: true
                        antialiasing: false
                        lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                    }

                    TransitionImage {
                        id: lockscreenWallpaper
                        anchors.fill: parent

                        readonly property bool isActive: wallpaperImageRoot.useSeparateLockscreenWallpaper && wallpaperImageRoot.lockscreenWallpaperPath !== "" && wallpaperImageRoot.lockscreenWallpaperPath !== wallpaperImageRoot.wallpaperPath
                        visible: isActive && opacity > 0
                        opacity: (isActive && GlobalStates.screenLocked) ? 1.0 : 0.0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Math.round(750 * Appearance.animMultiplier)
                                easing.type: Easing.InOutCubic
                            }
                        }

                        sourceSize: Config.options.background.scaleLargeWallpapers ? Qt.size(screen.width > 0 ? Math.round(screen.width * preferredWallpaperScale) : 1920, screen.height > 0 ? Math.round(screen.height * preferredWallpaperScale) : 1080) : Qt.size(-1, -1)
                        imageSource: (isActive && !wallpaperSafetyTriggered) ? wallpaperImageRoot.lockscreenWallpaperPath : ""
                        animated: Config.options.background.animateWallpaperChanges
                        transitionShader: Config.options.background.wallpaperAnimation
                        shadersPath: Qt.resolvedUrl("../shaders")
                        fillMode: Image.PreserveAspectCrop
                        mipmap: true
                        antialiasing: false
                        lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                    }
                }

                Rectangle {
                    id: wallpaperDimLayer
                    anchors.fill: parent
                    color: "black"
                    opacity: anyWidgetIsDragging ? 0.45 : 0.0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                LockBlur {
                    id: lockBlur
                    anchors.fill: parent
                    sourceItem: wallpaperVisualContainer
                    baseScale: wallpaperImageRoot.baseWallpaperScale
                    lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                }

                LockDesaturate {
                    anchors.fill: parent
                    sourceItem: Config.options.lock.blur.enable ? lockBlur : wallpaperVisualContainer
                    baseScale: wallpaperImageRoot.baseWallpaperScale
                    lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                }

                LockColorWash {
                    anchors.fill: parent
                    sourceItem: wallpaperVisualContainer
                    baseScale: wallpaperImageRoot.baseWallpaperScale
                    lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                }

                LockVignette {
                    anchors.fill: parent
                    sourceItem: wallpaperVisualContainer
                    baseScale: wallpaperImageRoot.baseWallpaperScale
                    lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                }

                GradientBlur {
                    anchors.fill: parent
                    wallpaperPath: GlobalStates.screenLocked && wallpaperImageRoot.useSeparateLockscreenWallpaper && wallpaperImageRoot.lockscreenWallpaperPath !== "" ? wallpaperImageRoot.lockscreenWallpaperPath : wallpaperImageRoot.wallpaperPath
                }

                WindowBlur {
                    anchors.fill: parent
                    sourceItem: wallpaperVisualContainer
                    hasWindowsInActiveWorkspace: wallpaperImageRoot.hasWindowsInActiveWorkspace
                    overviewOpen: wallpaperImageRoot.overviewOpen
                }

            }
        }
    }
}
