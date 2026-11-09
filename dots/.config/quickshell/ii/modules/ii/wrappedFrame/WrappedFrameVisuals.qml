import qs
import QtQuick
import QtQuick.Effects
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
    //
    // The layer is also what carries the shell shadow (see shellShadowEnabled): the
    // frame, the welded bar and the Connect sidebars are one continuous surface, so
    // the shadow they cast into the window area has to be generated from a single
    // silhouette rendered *below* all of them. Drawing it per module put the bar's
    // shadow on top of the frame strips, of the concave corners and of an open
    // sidebar, because those are later siblings inside the very same PanelWindow.
    layer.enabled: visualsRoot.shellShadowEnabled || GlobalStates.leftSidebarAnimating || GlobalStates.rightSidebarAnimating
    layer.effect: MultiEffect {
        shadowEnabled: visualsRoot.shellShadowEnabled
        shadowColor: Qt.rgba(0, 0, 0, 0.28)
        shadowBlur: 1.0
        shadowHorizontalOffset: 0
        shadowVerticalOffset: BarPlacement.bottom ? -4 : 4
        // The silhouette already reaches every screen edge; padding would only grow
        // the effect item past the window for a shadow nobody can see.
        autoPaddingEnabled: false
    }

    property var screen: null

    // ── Retract ──────────────────────────────────────────────────────────
    // 0 = seated, 1 = fully gone. Driven by the host for the cases where the
    // shell has to leave the screen: a fullscreen window taking over, media
    // mode, and the placement swap.
    //
    // The ring collapses rather than sliding as a block. A 6px frame
    // translated 6px out reads as a blink, and translating the concave corners
    // far enough to actually clear a screen edge sends them flying across it.
    // Shrinking the thickness folds the whole ring — strips, corners and the
    // bar plate, since every margin here is derived from it — into the screen
    // edges, and the silhouette shadow follows for free.
    property real hideProgress: 0
    readonly property real retract: 1 - Math.max(0, Math.min(1, hideProgress))

    property int baseFrameThickness: Config.options.appearance.wrappedFrameThickness
    property real frameThickness: baseFrameThickness * visualsRoot.retract
    property bool barVertical: BarPlacement.vertical
    property bool barBottom: BarPlacement.bottom
    property bool showBarBackground: false
    property real hBarHiddenAmount: 0
    property real vBarHiddenAmount: 0

    property real leftSidebarMaskOffset: 0
    property real rightSidebarMaskOffset: 0

    property real sidebarTopOffset: 0
    property real sidebarBottomOffset: 0

    // A pinned dock's exclusive zone on the top or bottom edge (connect mode). The ring's
    // band on that edge widens to it, under the dock, so the hole - and its rounded
    // corners - ends where the windows do instead of running on beneath the dock.
    property real dockTopInset: 0
    property real dockBottomInset: 0
    readonly property real dockTopBand: dockTopInset * retract
    readonly property real dockBottomBand: dockBottomInset * retract
    // The same on the left and right edges, for a vertical dock. These strips already
    // ride on the sidebars, so the band moves with a sidebar pushing the dock.
    property real dockLeftInset: 0
    property real dockRightInset: 0
    readonly property real dockLeftBand: dockLeftInset * retract
    readonly property real dockRightBand: dockRightInset * retract
    // Search lifts this layer over the dock: the band keeps its place (the hole and its
    // rounded corners still end where the windows do) but is not painted, so the dock,
    // which paints its own tray in baseColor meanwhile, shows through. The side strips
    // run on across the band's ends instead.
    property bool dockBandHollow: false
    readonly property real dockTopPaint: dockBandHollow ? 0 : dockTopBand
    readonly property real dockBottomPaint: dockBandHollow ? 0 : dockBottomBand
    readonly property real dockLeftPaint: dockBandHollow ? 0 : dockLeftBand
    readonly property real dockRightPaint: dockBandHollow ? 0 : dockRightBand
    readonly property real stripTopEdge: topEdge - (dockTopBand - dockTopPaint)
    readonly property real stripBottomEdge: bottomEdge - (dockBottomBand - dockBottomPaint)
    readonly property real topEdge: (hasTopFrame ? frameThickness : Math.max(frameThickness, totalTopPush)) + dockTopBand
    readonly property real bottomEdge: (hasBottomFrame ? frameThickness : Math.max(frameThickness, totalBottomPush)) + dockBottomBand

    readonly property real leftSidebarOffset: (GlobalStates.animatedLeftSidebarWidth > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeLeftSidebarMonitor) ? GlobalStates.animatedLeftSidebarWidth : 0
    readonly property real rightSidebarOffset: (GlobalStates.animatedRightSidebarWidth > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeRightSidebarMonitor) ? GlobalStates.animatedRightSidebarWidth : 0

    readonly property real staticLeftSidebarOffset: (leftSidebarMaskOffset > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeLeftSidebarMonitor) ? leftSidebarMaskOffset : 0
    readonly property real staticRightSidebarOffset: (rightSidebarMaskOffset > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeRightSidebarMonitor) ? rightSidebarMaskOffset : 0

    readonly property real staticTotalLeftPush: staticLeftSidebarOffset + (!hasLeftFrame ? Math.max(0, Appearance.sizes.verticalBarWindowWidth - visualsRoot.vBarHiddenAmount) * visualsRoot.retract : 0)
    readonly property real staticTotalRightPush: staticRightSidebarOffset + (!hasRightFrame ? Math.max(0, Appearance.sizes.verticalBarWindowWidth - visualsRoot.vBarHiddenAmount) * visualsRoot.retract : 0)

    // Consolidated pushes that account for both the sidebar AND the vertical bar (if present and visible).
    // `retract` applies to the bar half only — the sidebar is not leaving with us.
    readonly property real totalLeftPush: leftSidebarOffset + (!hasLeftFrame ? Math.max(0, Appearance.sizes.verticalBarWindowWidth - visualsRoot.vBarHiddenAmount) * visualsRoot.retract : 0)
    readonly property real totalRightPush: rightSidebarOffset + (!hasRightFrame ? Math.max(0, Appearance.sizes.verticalBarWindowWidth - visualsRoot.vBarHiddenAmount) * visualsRoot.retract : 0)

    // Consolidated pushes for horizontal bars
    readonly property real totalTopPush: !hasTopFrame ? Math.max(0, Appearance.sizes.barHeight - visualsRoot.hBarHiddenAmount) * visualsRoot.retract : 0
    readonly property real totalBottomPush: !hasBottomFrame ? Math.max(0, Appearance.sizes.barHeight - visualsRoot.hBarHiddenAmount) * visualsRoot.retract : 0

    BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)
    property color baseColor: showBarBackground ? (Config.options.bar.amoledBackground ? "#000000" : Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"

    Behavior on baseColor {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(visualsRoot)
    }

    readonly property bool isFloatingOrIsland: BarInteraction.cornerStyle === 1 || BarInteraction.cornerStyle === 3

    property bool hasTopFrame: isFloatingOrIsland || !(!barVertical && !barBottom)
    property bool hasBottomFrame: isFloatingOrIsland || !(!barVertical && barBottom)
    property bool hasLeftFrame: isFloatingOrIsland || !(barVertical && !barBottom)
    property bool hasRightFrame: isFloatingOrIsland || !(barVertical && barBottom)

    // A Hug/Rect bar is welded to the frame: it *is* the missing side of the ring.
    // Float and Dynamic Island bars float above the frame instead, so they keep
    // their own drop shadow and are deliberately not part of this silhouette.
    // Island backgrounds (barBackgroundStyle 3) are separate pills with gaps
    // between them, so a solid plate would fill those gaps with the bar color.
    readonly property bool barWeldedToFrame: !isFloatingOrIsland && Config.options.bar.barBackgroundStyle !== 3
    readonly property bool leftPlateShown: barWeldedToFrame && !hasLeftFrame
    readonly property bool rightPlateShown: barWeldedToFrame && !hasRightFrame
    // A side strip riding on an open sidebar runs on to the screen edge (to meet the
    // sidebar); the top or bottom strip then starts past it instead of under it, or the
    // overlap paints the translucent colour twice - a dark block once a dock band widens it.
    readonly property real leftStripAtTop: (leftSidebarOffset > 0 && !barBottom && (hasLeftFrame || dockLeftBand > 0)) ? leftFrame.width : 0
    readonly property real rightStripAtTop: (rightSidebarOffset > 0 && !barBottom && (hasRightFrame || dockRightBand > 0)) ? rightFrame.width : 0
    readonly property real leftStripAtBottom: (leftSidebarOffset > 0 && barBottom && (hasLeftFrame || dockLeftBand > 0)) ? leftFrame.width : 0
    readonly property real rightStripAtBottom: (rightSidebarOffset > 0 && barBottom && (hasRightFrame || dockRightBand > 0)) ? rightFrame.width : 0

    // Inner corner radius of wrapped frame always respects windowRounding
    readonly property real frameInnerCornerRadius: Appearance.rounding.windowRounding

    readonly property bool shellShadowEnabled: Config.ready
        && Config.options.bar.dropShadow
        && !ShellModePolicy.barDropShadowBlocked
        && !Config.options.appearance.transparency.enable

    // BAR PLATES (silhouette only)
    // The frame rectangles stop at the bar's inner edge, so without these the
    // shadow would break exactly where the bar meets the frame. They are painted
    // in baseColor underneath the real bar, which uses the same expression, so
    // they are invisible on their own and only exist to close the silhouette.
    Rectangle {
        id: topBarPlate
        visible: visualsRoot.barWeldedToFrame && !visualsRoot.hasTopFrame
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: visualsRoot.totalTopPush
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: bottomBarPlate
        visible: visualsRoot.barWeldedToFrame && !visualsRoot.hasBottomFrame
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        height: visualsRoot.totalBottomPush
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: leftBarPlate
        visible: visualsRoot.barWeldedToFrame && !visualsRoot.hasLeftFrame
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: visualsRoot.totalLeftPush
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: rightBarPlate
        visible: visualsRoot.barWeldedToFrame && !visualsRoot.hasRightFrame
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: visualsRoot.totalRightPush
        color: visualsRoot.baseColor
    }

    // HORIZONTAL FRAMES
    Rectangle {
        id: topFrame
        visible: true
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            // With a dock band it sits past a top bar and spans the whole edge, except where
            // a bar plate already runs to the screen edge: with transparency every overlap
            // paints the translucent colour twice and reads as a second shade.
            topMargin: (!hasTopFrame) ? (visualsRoot.dockTopBand > 0 ? visualsRoot.totalTopPush : -Math.max(0, frameThickness - visualsRoot.hBarHiddenAmount)) : 0
            leftMargin: ((visualsRoot.dockTopBand > 0 && !visualsRoot.leftPlateShown) ? 0 : visualsRoot.totalLeftPush) + visualsRoot.leftStripAtTop
            rightMargin: ((visualsRoot.dockTopBand > 0 && !visualsRoot.rightPlateShown) ? 0 : visualsRoot.totalRightPush) + visualsRoot.rightStripAtTop
        }
        height: hasTopFrame ? frameThickness + visualsRoot.dockTopPaint : (visualsRoot.dockTopBand > 0 ? visualsRoot.dockTopPaint : frameThickness)
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: bottomFrame
        visible: true
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            bottomMargin: (!hasBottomFrame) ? (visualsRoot.dockBottomBand > 0 ? visualsRoot.totalBottomPush : -Math.max(0, frameThickness - visualsRoot.hBarHiddenAmount)) : 0
            leftMargin: ((visualsRoot.dockBottomBand > 0 && !visualsRoot.leftPlateShown) ? 0 : visualsRoot.totalLeftPush) + visualsRoot.leftStripAtBottom
            rightMargin: ((visualsRoot.dockBottomBand > 0 && !visualsRoot.rightPlateShown) ? 0 : visualsRoot.totalRightPush) + visualsRoot.rightStripAtBottom
        }
        height: hasBottomFrame ? frameThickness + visualsRoot.dockBottomPaint : (visualsRoot.dockBottomBand > 0 ? visualsRoot.dockBottomPaint : frameThickness)
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
            leftMargin: (!hasLeftFrame) ? (visualsRoot.dockLeftBand > 0 ? visualsRoot.totalLeftPush : -Math.max(0, frameThickness - visualsRoot.vBarHiddenAmount)) : visualsRoot.leftSidebarOffset
            topMargin: (visualsRoot.leftSidebarOffset > 0 && !visualsRoot.barBottom) ? visualsRoot.sidebarTopOffset : visualsRoot.stripTopEdge
            bottomMargin: (visualsRoot.leftSidebarOffset > 0 && visualsRoot.barBottom) ? visualsRoot.sidebarBottomOffset : visualsRoot.stripBottomEdge
        }
        width: hasLeftFrame ? frameThickness + visualsRoot.dockLeftPaint : (visualsRoot.dockLeftBand > 0 ? visualsRoot.dockLeftPaint : frameThickness)
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: rightFrame
        visible: true
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
            rightMargin: (!hasRightFrame) ? (visualsRoot.dockRightBand > 0 ? visualsRoot.totalRightPush : -Math.max(0, frameThickness - visualsRoot.vBarHiddenAmount)) : visualsRoot.rightSidebarOffset
            topMargin: (visualsRoot.rightSidebarOffset > 0 && !visualsRoot.barBottom) ? visualsRoot.sidebarTopOffset : visualsRoot.stripTopEdge
            bottomMargin: (visualsRoot.rightSidebarOffset > 0 && visualsRoot.barBottom) ? visualsRoot.sidebarBottomOffset : visualsRoot.stripBottomEdge
        }
        width: hasRightFrame ? frameThickness + visualsRoot.dockRightPaint : (visualsRoot.dockRightBand > 0 ? visualsRoot.dockRightPaint : frameThickness)
        color: visualsRoot.baseColor
    }

    // CORNERS (Inner radius connecting frames/bar)
    RoundCorner {
        id: bottomLeftCorner
        visible: true
        anchors {
            bottom: parent.bottom
            left: parent.left
            bottomMargin: visualsRoot.bottomEdge
            leftMargin: (hasLeftFrame ? frameThickness + visualsRoot.leftSidebarOffset : Math.max(frameThickness, visualsRoot.totalLeftPush)) + visualsRoot.dockLeftBand
        }
        implicitSize: frameInnerCornerRadius * visualsRoot.retract
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.BottomLeft
    }

    RoundCorner {
        id: topLeftCorner
        visible: true
        anchors {
            top: parent.top
            left: parent.left
            topMargin: visualsRoot.topEdge
            leftMargin: (hasLeftFrame ? frameThickness + visualsRoot.leftSidebarOffset : Math.max(frameThickness, visualsRoot.totalLeftPush)) + visualsRoot.dockLeftBand
        }
        implicitSize: frameInnerCornerRadius * visualsRoot.retract
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.TopLeft
    }

    RoundCorner {
        id: topRightCorner
        visible: true
        anchors {
            top: parent.top
            right: parent.right
            topMargin: visualsRoot.topEdge
            rightMargin: (hasRightFrame ? frameThickness + visualsRoot.rightSidebarOffset : Math.max(frameThickness, visualsRoot.totalRightPush)) + visualsRoot.dockRightBand
        }
        implicitSize: frameInnerCornerRadius * visualsRoot.retract
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.TopRight
    }

    RoundCorner {
        id: bottomRightCorner
        visible: true
        anchors {
            bottom: parent.bottom
            right: parent.right
            bottomMargin: visualsRoot.bottomEdge
            rightMargin: (hasRightFrame ? frameThickness + visualsRoot.rightSidebarOffset : Math.max(frameThickness, visualsRoot.totalRightPush)) + visualsRoot.dockRightBand
        }
        implicitSize: frameInnerCornerRadius * visualsRoot.retract
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
            topMargin: (visualsRoot.staticLeftSidebarOffset > 0 && !visualsRoot.barBottom) ? visualsRoot.sidebarTopOffset : visualsRoot.topEdge
            bottomMargin: (visualsRoot.staticLeftSidebarOffset > 0 && visualsRoot.barBottom) ? visualsRoot.sidebarBottomOffset : visualsRoot.bottomEdge
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
            topMargin: (visualsRoot.staticRightSidebarOffset > 0 && !visualsRoot.barBottom) ? visualsRoot.sidebarTopOffset : visualsRoot.topEdge
            bottomMargin: (visualsRoot.staticRightSidebarOffset > 0 && visualsRoot.barBottom) ? visualsRoot.sidebarBottomOffset : visualsRoot.bottomEdge
        }
        width: frameThickness
    }

    Item {
        id: bottomLeftCornerMask
        anchors {
            bottom: parent.bottom
            left: parent.left
            bottomMargin: visualsRoot.bottomEdge
            leftMargin: hasLeftFrame ? frameThickness + visualsRoot.staticLeftSidebarOffset : Math.max(frameThickness, visualsRoot.staticTotalLeftPush)
        }
        width: frameInnerCornerRadius
        height: frameInnerCornerRadius
    }

    Item {
        id: topLeftCornerMask
        anchors {
            top: parent.top
            left: parent.left
            topMargin: visualsRoot.topEdge
            leftMargin: hasLeftFrame ? frameThickness + visualsRoot.staticLeftSidebarOffset : Math.max(frameThickness, visualsRoot.staticTotalLeftPush)
        }
        width: frameInnerCornerRadius
        height: frameInnerCornerRadius
    }

    Item {
        id: topRightCornerMask
        anchors {
            top: parent.top
            right: parent.right
            topMargin: visualsRoot.topEdge
            rightMargin: hasRightFrame ? frameThickness + visualsRoot.staticRightSidebarOffset : Math.max(frameThickness, visualsRoot.staticTotalRightPush)
        }
        width: frameInnerCornerRadius
        height: frameInnerCornerRadius
    }

    Item {
        id: bottomRightCornerMask
        anchors {
            bottom: parent.bottom
            right: parent.right
            bottomMargin: visualsRoot.bottomEdge
            rightMargin: hasRightFrame ? frameThickness + visualsRoot.staticRightSidebarOffset : Math.max(frameThickness, visualsRoot.staticTotalRightPush)
        }
        width: frameInnerCornerRadius
        height: frameInnerCornerRadius
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
