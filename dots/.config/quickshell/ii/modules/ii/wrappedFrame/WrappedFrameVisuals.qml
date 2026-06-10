import qs
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar

Item {
    id: visualsRoot
    anchors.fill: parent

    property var screen: null
    property int frameThickness: Config.options.appearance.wrappedFrameThickness
    property bool barVertical: Config.options.bar.vertical
    property bool barBottom: Config.options.bar.bottom
    property bool showBarBackground: false
    property real hBarHiddenAmount: 0
    property real vBarHiddenAmount: 0

    readonly property real leftSidebarOffset: (GlobalStates.animatedLeftSidebarWidth > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeLeftSidebarMonitor) ? GlobalStates.animatedLeftSidebarWidth : 0
    readonly property real rightSidebarOffset: (GlobalStates.animatedRightSidebarWidth > 0 && visualsRoot.screen && visualsRoot.screen.name === GlobalStates.activeRightSidebarMonitor) ? GlobalStates.animatedRightSidebarWidth : 0

    // Consolidated pushes that account for both the sidebar AND the vertical bar (if present and visible)
    readonly property real totalLeftPush: leftSidebarOffset + (!hasLeftFrame ? Math.max(0, Appearance.sizes.verticalBarWidth - visualsRoot.vBarHiddenAmount) : 0)
    readonly property real totalRightPush: rightSidebarOffset + (!hasRightFrame ? Math.max(0, Appearance.sizes.verticalBarWidth - visualsRoot.vBarHiddenAmount) : 0)

    // Consolidated pushes for horizontal bars
    readonly property real totalTopPush: !hasTopFrame ? Math.max(0, Appearance.sizes.barHeight - visualsRoot.hBarHiddenAmount) : 0
    readonly property real totalBottomPush: !hasBottomFrame ? Math.max(0, Appearance.sizes.barHeight - visualsRoot.hBarHiddenAmount) : 0

    Bar.BarThemes { id: barThemes }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)
    property color baseColor: showBarBackground ? (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"

    Behavior on baseColor {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(visualsRoot)
    }

    property bool hasTopFrame: !(!barVertical && !barBottom)
    property bool hasBottomFrame: !(!barVertical && barBottom)
    property bool hasLeftFrame: !(barVertical && !barBottom)
    property bool hasRightFrame: !(barVertical && barBottom)

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
        visible: !leftSidebarOffset
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            leftMargin: (!hasLeftFrame) ? -Math.max(0, frameThickness - visualsRoot.vBarHiddenAmount) + visualsRoot.leftSidebarOffset : visualsRoot.leftSidebarOffset
            topMargin: hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush)
            bottomMargin: hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush)
        }
        width: frameThickness
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: rightFrame
        visible: !rightSidebarOffset
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
            rightMargin: (!hasRightFrame) ? -Math.max(0, frameThickness - visualsRoot.vBarHiddenAmount) + visualsRoot.rightSidebarOffset : visualsRoot.rightSidebarOffset
            topMargin: hasTopFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalTopPush)
            bottomMargin: hasBottomFrame ? frameThickness : Math.max(frameThickness, visualsRoot.totalBottomPush)
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

    property Region frameMask: Region {
        Region { item: topFrame }
        Region { item: bottomFrame }
        Region { item: leftFrame }
        Region { item: rightFrame }
        Region { item: topLeftCorner }
        Region { item: topRightCorner }
        Region { item: bottomLeftCorner }
        Region { item: bottomRightCorner }
    }
}
