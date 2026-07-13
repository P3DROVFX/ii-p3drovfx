import qs
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.shared

Item {
    id: visualsRoot
    anchors.fill: parent

    // GPU compositing during sidebar animation: the 8 frame Rectangles/RoundCorners
    // all have anchor margins bound to animatedLeftSidebarWidth, which changes every
    // frame. layer.enabled lets the compositor cache the texture and skip per-frame
    // CPU layout invalidation of all children. Only active during animation to
    // avoid unnecessary FBO re-renders while the sidebar is statically open.
    layer.enabled: GlobalStates.leftSidebarAnimating || GlobalStates.rightSidebarAnimating

    property var screen: null
    property int frameThickness: Config.options.appearance.wrappedFrameThickness
    property bool barVertical: Config.options.bar.vertical
    property bool barBottom: Config.options.bar.bottom
    property bool showBarBackground: false
    property real hBarHiddenAmount: 0
    property real vBarHiddenAmount: 0

    property real leftSidebarMaskOffset: 0
    property real rightSidebarMaskOffset: 0

    property real sidebarTopOffset: 0
    property real sidebarBottomOffset: 0

    readonly property real leftSidebarOffset: (GlobalStates.animatedLeftSidebarWidth > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeLeftSidebarMonitor) ? GlobalStates.animatedLeftSidebarWidth : 0
    readonly property real rightSidebarOffset: (GlobalStates.animatedRightSidebarWidth > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeRightSidebarMonitor) ? GlobalStates.animatedRightSidebarWidth : 0

    readonly property real staticLeftSidebarOffset: (leftSidebarMaskOffset > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeLeftSidebarMonitor) ? leftSidebarMaskOffset : 0
    readonly property real staticRightSidebarOffset: (rightSidebarMaskOffset > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeRightSidebarMonitor) ? rightSidebarMaskOffset : 0

    readonly property real staticTotalLeftPush: staticLeftSidebarOffset + (!hasLeftFrame ? Math.max(0, Appearance.sizes.verticalBarWindowWidth - visualsRoot.vBarHiddenAmount) : 0)
    readonly property real staticTotalRightPush: staticRightSidebarOffset + (!hasRightFrame ? Math.max(0, Appearance.sizes.verticalBarWindowWidth - visualsRoot.vBarHiddenAmount) : 0)

    // Consolidated pushes that account for both the sidebar AND the vertical bar (if present and visible)
    readonly property real totalLeftPush: leftSidebarOffset + (!hasLeftFrame ? Math.max(0, Appearance.sizes.verticalBarWindowWidth - visualsRoot.vBarHiddenAmount) : 0)
    readonly property real totalRightPush: rightSidebarOffset + (!hasRightFrame ? Math.max(0, Appearance.sizes.verticalBarWindowWidth - visualsRoot.vBarHiddenAmount) : 0)

    // Consolidated pushes for horizontal bars
    readonly property real totalTopPush: !hasTopFrame ? Math.max(0, Appearance.sizes.barHeight - visualsRoot.hBarHiddenAmount) : 0
    readonly property real totalBottomPush: !hasBottomFrame ? Math.max(0, Appearance.sizes.barHeight - visualsRoot.hBarHiddenAmount) : 0

    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)
    property color baseColor: showBarBackground ? (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"

    Behavior on baseColor {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(visualsRoot)
    }

    readonly property bool isFloatingOrIsland: Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 3

    property bool hasTopFrame: isFloatingOrIsland || !(!barVertical && !barBottom)
    property bool hasBottomFrame: isFloatingOrIsland || !(!barVertical && barBottom)
    property bool hasLeftFrame: isFloatingOrIsland || !(barVertical && !barBottom)
    property bool hasRightFrame: isFloatingOrIsland || !(barVertical && barBottom)

    // HORIZONTAL FRAMES
    Rectangle {
        id: topFrame
        visible: true
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: (!hasTopFrame) ? -Math.max(0, frameThickness - visualsRoot.hBarHiddenAmount) : 0
            leftMargin: visualsRoot.totalLeftPush
            rightMargin: visualsRoot.totalRightPush
        }
        height: frameThickness
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: bottomFrame
        visible: true
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            bottomMargin: (!hasBottomFrame) ? -Math.max(0, frameThickness - visualsRoot.hBarHiddenAmount) : 0
            leftMargin: visualsRoot.totalLeftPush
            rightMargin: visualsRoot.totalRightPush
        }
        height: frameThickness
        color: visualsRoot.baseColor
    }

    // VERTICAL FRAMES
    Rectangle {
        id: leftFrame
        visible: true
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            leftMargin: (!hasLeftFrame) ? -Math.max(0, frameThickness - visualsRoot.vBarHiddenAmount) : visualsRoot.leftSidebarOffset
            topMargin: (visualsRoot.leftSidebarOffset > 0 && !visualsRoot.barBottom) ? visualsRoot.sidebarTopOffset : (hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush))
            bottomMargin: (visualsRoot.leftSidebarOffset > 0 && visualsRoot.barBottom) ? visualsRoot.sidebarBottomOffset : (hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush))
        }
        width: frameThickness
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: rightFrame
        visible: true
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
            rightMargin: (!hasRightFrame) ? -Math.max(0, frameThickness - visualsRoot.vBarHiddenAmount) : visualsRoot.rightSidebarOffset
            topMargin: (visualsRoot.rightSidebarOffset > 0 && !visualsRoot.barBottom) ? visualsRoot.sidebarTopOffset : (hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush))
            bottomMargin: (visualsRoot.rightSidebarOffset > 0 && visualsRoot.barBottom) ? visualsRoot.sidebarBottomOffset : (hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush))
        }
        width: frameThickness
        color: visualsRoot.baseColor
    }

    // CORNERS (Inner radius connecting frames/bar)
    RoundCorner {
        id: bottomLeftCorner
        visible: true
        anchors {
            bottom: parent.bottom
            left: parent.left
            bottomMargin: hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush)
            leftMargin: hasLeftFrame ? frameThickness + visualsRoot.leftSidebarOffset : Math.max(frameThickness, visualsRoot.totalLeftPush)
        }
        implicitSize: Appearance.rounding.screenRounding
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.BottomLeft
    }

    RoundCorner {
        id: topLeftCorner
        visible: true
        anchors {
            top: parent.top
            left: parent.left
            topMargin: hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush)
            leftMargin: hasLeftFrame ? frameThickness + visualsRoot.leftSidebarOffset : Math.max(frameThickness, visualsRoot.totalLeftPush)
        }
        implicitSize: Appearance.rounding.screenRounding
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.TopLeft
    }

    RoundCorner {
        id: topRightCorner
        visible: true
        anchors {
            top: parent.top
            right: parent.right
            topMargin: hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush)
            rightMargin: hasRightFrame ? frameThickness + visualsRoot.rightSidebarOffset : Math.max(frameThickness, visualsRoot.totalRightPush)
        }
        implicitSize: Appearance.rounding.screenRounding
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.TopRight
    }

    RoundCorner {
        id: bottomRightCorner
        visible: true
        anchors {
            bottom: parent.bottom
            right: parent.right
            bottomMargin: hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush)
            rightMargin: hasRightFrame ? frameThickness + visualsRoot.rightSidebarOffset : Math.max(frameThickness, visualsRoot.totalRightPush)
        }
        implicitSize: Appearance.rounding.screenRounding
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.BottomRight
    }

    // Static items for frame mask to avoid per-frame Region recalculations
    Item {
        id: topFrameMask
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: (!hasTopFrame) ? -Math.max(0, frameThickness - visualsRoot.hBarHiddenAmount) : 0
            leftMargin: visualsRoot.staticTotalLeftPush
            rightMargin: visualsRoot.staticTotalRightPush
        }
        height: frameThickness
    }

    Item {
        id: bottomFrameMask
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            bottomMargin: (!hasBottomFrame) ? -Math.max(0, frameThickness - visualsRoot.hBarHiddenAmount) : 0
            leftMargin: visualsRoot.staticTotalLeftPush
            rightMargin: visualsRoot.staticTotalRightPush
        }
        height: frameThickness
    }

    Item {
        id: leftFrameMask
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            leftMargin: (!hasLeftFrame) ? -Math.max(0, frameThickness - visualsRoot.vBarHiddenAmount) : visualsRoot.staticLeftSidebarOffset
            topMargin: (visualsRoot.staticLeftSidebarOffset > 0 && !visualsRoot.barBottom) ? visualsRoot.sidebarTopOffset : (hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush))
            bottomMargin: (visualsRoot.staticLeftSidebarOffset > 0 && visualsRoot.barBottom) ? visualsRoot.sidebarBottomOffset : (hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush))
        }
        width: frameThickness
    }

    Item {
        id: rightFrameMask
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
            rightMargin: (!hasRightFrame) ? -Math.max(0, frameThickness - visualsRoot.vBarHiddenAmount) : visualsRoot.staticRightSidebarOffset
            topMargin: (visualsRoot.staticRightSidebarOffset > 0 && !visualsRoot.barBottom) ? visualsRoot.sidebarTopOffset : (hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush))
            bottomMargin: (visualsRoot.staticRightSidebarOffset > 0 && visualsRoot.barBottom) ? visualsRoot.sidebarBottomOffset : (hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush))
        }
        width: frameThickness
    }

    Item {
        id: bottomLeftCornerMask
        anchors {
            bottom: parent.bottom
            left: parent.left
            bottomMargin: hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush)
            leftMargin: hasLeftFrame ? frameThickness + visualsRoot.staticLeftSidebarOffset : Math.max(frameThickness, visualsRoot.staticTotalLeftPush)
        }
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
    }

    Item {
        id: topLeftCornerMask
        anchors {
            top: parent.top
            left: parent.left
            topMargin: hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush)
            leftMargin: hasLeftFrame ? frameThickness + visualsRoot.staticLeftSidebarOffset : Math.max(frameThickness, visualsRoot.staticTotalLeftPush)
        }
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
    }

    Item {
        id: topRightCornerMask
        anchors {
            top: parent.top
            right: parent.right
            topMargin: hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush)
            rightMargin: hasRightFrame ? frameThickness + visualsRoot.staticRightSidebarOffset : Math.max(frameThickness, visualsRoot.staticTotalRightPush)
        }
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
    }

    Item {
        id: bottomRightCornerMask
        anchors {
            bottom: parent.bottom
            right: parent.right
            bottomMargin: hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush)
            rightMargin: hasRightFrame ? frameThickness + visualsRoot.staticRightSidebarOffset : Math.max(frameThickness, visualsRoot.staticTotalRightPush)
        }
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
    }

    property Region frameMask: Region {
        Region {
            item: topFrameMask
        }
        Region {
            item: bottomFrameMask
        }
        Region {
            item: leftFrameMask
        }
        Region {
            item: rightFrameMask
        }
        Region {
            item: topLeftCornerMask
        }
        Region {
            item: topRightCornerMask
        }
        Region {
            item: bottomLeftCornerMask
        }
        Region {
            item: bottomRightCornerMask
        }
    }
}
