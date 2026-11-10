pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.core
import qs.modules.ii.bar.shared
import qs.modules.ii.bar.styles
import qs.modules.settings.configs.colors

/**
 * The bar, live, along the edge of the wallpaper.
 *
 * The bar's own style file (Hug, Float, Rect or Island) is built at the monitor's logical
 * width with the real layout lists, theme and widgets, over the real wallpaper, with what
 * the shell draws around it (the Hug corners under the bar, the screen corners, the wrapped
 * frame, the transparent bar's blur). That whole band is rendered off the page and shown
 * through windows: on a page narrower than the monitor, three — the left end, the centre
 * and the right end at a readable size, joined as a connected group (two when the middle is
 * empty, one on the pill for Island); on a wide page, one.
 * A style can be tried on (`styleOverride`) before it is chosen. Nothing here takes input.
 */
Item {
    id: root

    readonly property real splitScale: 0.8
    readonly property real narrowSplitScale: 0.68
    readonly property real singleMinScale: 0.6
    readonly property real cropGap: 4
    readonly property real roomBelow: 40

    /// -1 shows the saved value; anything else is tried on the preview only.
    property int styleOverride: -1
    property int groupOverride: -1
    property int backgroundOverride: -1
    property int roundingOverride: -1

    readonly property var bar: Config.options.bar
    readonly property int cornerStyle: root.styleOverride >= 0 ? root.styleOverride : root.bar.cornerStyle
    readonly property int backgroundStyle: root.backgroundOverride >= 0 ? root.backgroundOverride : root.bar.barBackgroundStyle
    readonly property int screenRounding: root.roundingOverride >= 0 ? root.roundingOverride : Config.options.appearance.fakeScreenRounding
    readonly property bool atBottom: root.bar.bottom && !root.bar.vertical
    readonly property var monitor: root.QsWindow.window?.screen ?? null
    readonly property real virtualWidth: Math.max(1024, root.monitor?.width ?? 1920)
    readonly property real virtualHeight: Math.max(600, root.monitor?.height ?? 1080)

    readonly property real barHeight: Appearance.sizes.baseBarHeight
        + (root.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut * 2 : 0)
    // Sized for the tallest style (Float adds the gaps), so trying one on never moves the page.
    readonly property real bandHeight: Appearance.sizes.baseBarHeight + Appearance.sizes.hyprlandGapsOut * 2 + root.roomBelow
    // Adaptive draws its plate while windows are open: that is the look worth showing.
    readonly property bool showBarBackground: root.backgroundStyle !== 0
    readonly property color barColor: root.showBarBackground
        ? (root.bar.amoledBackground ? "#000000" : root.bar.expressiveColors ? themes.getTheme(root.bar.expressiveColorTheme).barBackground : Appearance.colors.colLayer0)
        : "transparent"
    readonly property bool wrapped: root.screenRounding === 3
    readonly property bool weldedToFrame: root.wrapped && root.cornerStyle !== 1 && root.cornerStyle !== 3 && root.backgroundStyle !== 3

    readonly property real fitScale: root.width / root.virtualWidth
    readonly property bool split: root.fitScale < root.singleMinScale
    readonly property real scale_: root.split ? (root.width < 600 ? root.narrowSplitScale : root.splitScale) : root.fitScale
    // Nothing in the middle of the bar (or only the island, which is not the bar's): the two
    // ends get the room.
    readonly property bool middleEmpty: (layout.leftList?.length ?? 0) + (layout.centerList?.length ?? 0) + (layout.rightList?.length ?? 0) === 0
        && root.cornerStyle !== 3
    // Island gathers everything into its centred pill: one window on the middle.
    readonly property bool centreOnly: root.split && root.cornerStyle === 3
    readonly property int cropCount: !root.split || root.centreOnly ? 1 : root.middleEmpty ? 2 : 3
    readonly property real cropWidth: (root.width - root.cropGap * (root.cropCount - 1)) / root.cropCount
    readonly property real cropSpan: root.cropWidth / root.scale_

    readonly property real preferredHeight: Math.round(root.bandHeight * root.scale_)

    // Built a frame after the page: the page shows at once, the bar arrives right after.
    property bool ready: false
    Component.onCompleted: Qt.callLater(() => root.ready = true)

    BarThemes {
        id: themes
    }
    BarLayout {
        id: layout
        backgroundStyle: root.backgroundStyle
    }

    // ── The band, drawn at the monitor's size, off the page ───────────────
    Item {
        id: band
        x: -root.virtualWidth - 400
        width: root.virtualWidth
        height: root.bandHeight
        // Read by every BarComponent inside (walking up): the group style to wear.
        readonly property var barPreviewOverrides: ({ "groupStyle": root.groupOverride })

        ColorsWallpaperImage {
            id: wallpaper
            width: band.width
            height: root.virtualHeight
            y: root.atBottom ? band.height - height : 0
            targetMode: "desktop"
        }

        // Transparent bar with blur: the wallpaper under the bar softened and dimmed.
        Item {
            visible: root.backgroundStyle === 0 && root.bar.transparentGlow
            width: band.width
            height: root.barHeight + 24
            y: root.atBottom ? band.height - height : 0
            clip: true

            MultiEffect {
                source: wallpaper
                x: 0
                y: root.atBottom ? -(wallpaper.height - parent.height) : 0
                width: wallpaper.width
                height: wallpaper.height
                blurEnabled: true
                blur: 1
                blurMax: 48
                autoPaddingEnabled: false
            }
        }
        Rectangle {
            visible: root.backgroundStyle === 0 && root.bar.transparentGlow
            width: band.width
            height: root.barHeight + 60
            y: root.atBottom ? band.height - height : 0
            gradient: Gradient {
                GradientStop { position: root.atBottom ? 1 : 0; color: Qt.rgba(0, 0, 0, 0.32) }
                GradientStop { position: root.atBottom ? 0 : 1; color: "transparent" }
            }
        }

        // Wrapped frame: the plate behind a welded bar and the strips down the sides.
        Item {
            visible: root.wrapped
            anchors.fill: parent
            readonly property real thickness: Config.options.appearance.wrappedFrameThickness
            readonly property color frameColor: root.barColor

            Rectangle {
                visible: root.weldedToFrame
                width: parent.width
                height: root.barHeight
                y: root.atBottom ? band.height - height : 0
                color: parent.frameColor
            }
            Rectangle {
                width: parent.thickness
                height: parent.height
                color: parent.frameColor
            }
            Rectangle {
                x: parent.width - width
                width: parent.thickness
                height: parent.height
                color: parent.frameColor
            }
            Rectangle {
                visible: !root.weldedToFrame
                width: parent.width
                height: parent.thickness
                y: root.atBottom ? band.height - height : 0
                color: parent.frameColor
            }
            RoundCorner {
                x: parent.thickness
                y: root.atBottom ? band.height - (root.weldedToFrame ? root.barHeight : parent.thickness) - implicitSize
                                 : (root.weldedToFrame ? root.barHeight : parent.thickness)
                implicitSize: Appearance.rounding.windowRounding
                color: parent.frameColor
                corner: root.atBottom ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.TopLeft
            }
            RoundCorner {
                x: parent.width - parent.thickness - implicitSize
                y: root.atBottom ? band.height - (root.weldedToFrame ? root.barHeight : parent.thickness) - implicitSize
                                 : (root.weldedToFrame ? root.barHeight : parent.thickness)
                implicitSize: Appearance.rounding.windowRounding
                color: parent.frameColor
                corner: root.atBottom ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.TopRight
            }
        }

        // Hug: the screen curves into the bar's plate below it (BarWindow's decorators).
        Item {
            visible: root.cornerStyle === 0 && root.showBarBackground && root.backgroundStyle !== 3 && !root.wrapped
            width: band.width
            height: Appearance.rounding.screenRounding
            y: root.atBottom ? band.height - root.barHeight - height : root.barHeight
            RoundCorner {
                implicitSize: Appearance.rounding.screenRounding
                color: root.barColor
                corner: root.atBottom ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.TopLeft
            }
            RoundCorner {
                x: parent.width - implicitSize
                implicitSize: Appearance.rounding.screenRounding
                color: root.barColor
                corner: root.atBottom ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.TopRight
            }
        }

        // The bar itself: its own style file with the real lists and theme.
        Loader {
            id: styleLoader
            width: band.width
            height: root.barHeight
            y: root.atBottom ? band.height - height : 0
            // The widgets carry Qt5Compat effects, which pin a window that is already gone.
            active: root.ready && root.Window.window !== null
            sourceComponent: root.cornerStyle === 1 ? floatStyle
                : root.cornerStyle === 2 ? rectStyle
                : root.cornerStyle === 3 ? islandStyle
                : hugStyle
        }

        // Fake screen corners (Yes / When not fullscreen), on the screen's edge.
        Repeater {
            model: root.screenRounding === 1 || root.screenRounding === 2 ? 2 : 0
            delegate: RoundCorner {
                required property int index
                x: index === 0 ? 0 : band.width - implicitSize
                y: root.atBottom ? band.height - implicitSize : 0
                implicitSize: Appearance.rounding.screenRounding
                color: "#000000"
                corner: root.atBottom
                    ? (index === 0 ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.BottomRight)
                    : (index === 0 ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.TopRight)
            }
        }
    }

    Component {
        id: hugStyle
        HugStyle {
            backgroundStyle: root.backgroundStyle
            screenRounding: root.screenRounding
            showBarBackground: root.showBarBackground
            activeTheme: themes.getTheme(root.bar.expressiveColorTheme)
            leftList: layout.leftList
            centerList: layout.centerList
            rightList: layout.rightList
        }
    }
    Component {
        id: floatStyle
        FloatStyle {
            backgroundStyle: root.backgroundStyle
            screenRounding: root.screenRounding
            showBarBackground: root.showBarBackground
            activeTheme: themes.getTheme(root.bar.expressiveColorTheme)
            leftList: layout.leftList
            centerList: layout.centerList
            rightList: layout.rightList
        }
    }
    Component {
        id: rectStyle
        RectStyle {
            backgroundStyle: root.backgroundStyle
            screenRounding: root.screenRounding
            showBarBackground: root.showBarBackground
            activeTheme: themes.getTheme(root.bar.expressiveColorTheme)
            leftList: layout.leftList
            centerList: layout.centerList
            rightList: layout.rightList
        }
    }
    Component {
        id: islandStyle
        DynamicIslandStyle {
            screen: null
            showBarBackground: root.showBarBackground
            isSearchActiveHere: false
            expectedSearchWidth: 0
            frameThickness: root.wrapped ? Config.options.appearance.wrappedFrameThickness : 0
            activeTheme: themes.getTheme(root.bar.expressiveColorTheme)
            leftList: layout.leftList
            centerList: layout.centerList
            rightList: layout.rightList
        }
    }

    // ── The windows onto it ───────────────────────────────────────────────
    Repeater {
        model: root.cropCount

        delegate: ClippingRectangle {
            id: crop
            required property int index
            readonly property bool first: crop.index === 0
            readonly property bool last: crop.index === root.cropCount - 1
            readonly property real outer: Appearance.rounding.windowRounding
            readonly property real inner: Appearance.rounding.verysmall
            // Left end, centre, right end of the monitor.
            readonly property real sourceX: root.centreOnly ? (root.virtualWidth - root.cropSpan) / 2
                : root.cropCount === 1 ? 0
                : crop.first ? 0
                : crop.last ? root.virtualWidth - root.cropSpan
                : (root.virtualWidth - root.cropSpan) / 2

            x: crop.index * (root.cropWidth + root.cropGap)
            width: root.cropWidth
            height: root.height
            topLeftRadius: crop.first ? crop.outer : crop.inner
            bottomLeftRadius: crop.first ? crop.outer : crop.inner
            topRightRadius: crop.last ? crop.outer : crop.inner
            bottomRightRadius: crop.last ? crop.outer : crop.inner
            color: Appearance.colors.colLayer2

            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: band
                sourceRect: Qt.rect(crop.sourceX, 0, root.split ? root.cropSpan : root.virtualWidth, root.bandHeight)
                hideSource: true
                smooth: true
                live: root.visible
            }
        }
    }
}
