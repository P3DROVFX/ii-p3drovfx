import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar

Item {
    id: visualsRoot
    anchors.fill: parent

    property int frameThickness: Config.options.appearance.wrappedFrameThickness
    property bool barVertical: Config.options.bar.vertical
    property bool barBottom: Config.options.bar.bottom
    property bool showBarBackground: false

    Bar.BarThemes { id: barThemes }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)
    property color baseColor: showBarBackground ? (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"

    Behavior on baseColor {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(visualsRoot)
    }

    // HORIZONTAL FRAMES
    Rectangle {
        id: topFrame
        visible: !(!barVertical && !barBottom)
        anchors { 
            top: parent.top; 
            left: parent.left; 
            right: parent.right 
            leftMargin: !leftFrame.visible ? Appearance.sizes.verticalBarWidth : 0
            rightMargin: !rightFrame.visible ? Appearance.sizes.verticalBarWidth : 0
        }
        height: frameThickness
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: bottomFrame
        visible: !(!barVertical && barBottom)
        anchors { 
            bottom: parent.bottom; 
            left: parent.left; 
            right: parent.right 
            leftMargin: !leftFrame.visible ? Appearance.sizes.verticalBarWidth : 0
            rightMargin: !rightFrame.visible ? Appearance.sizes.verticalBarWidth : 0
        }
        height: frameThickness
        color: visualsRoot.baseColor
    }

    // VERTICAL FRAMES
    Rectangle {
        id: leftFrame
        visible: !(barVertical && !barBottom)
        anchors {
            top: topFrame.visible ? topFrame.bottom : parent.top
            bottom: bottomFrame.visible ? bottomFrame.top : parent.bottom
            left: parent.left
            topMargin: !topFrame.visible ? Appearance.sizes.barHeight : 0
            bottomMargin: !bottomFrame.visible ? Appearance.sizes.barHeight : 0
        }
        width: frameThickness
        color: visualsRoot.baseColor
    }

    Rectangle {
        id: rightFrame
        visible: !(barVertical && barBottom)
        anchors {
            top: topFrame.visible ? topFrame.bottom : parent.top
            bottom: bottomFrame.visible ? bottomFrame.top : parent.bottom
            right: parent.right
            topMargin: !topFrame.visible ? Appearance.sizes.barHeight : 0
            bottomMargin: !bottomFrame.visible ? Appearance.sizes.barHeight : 0
        }
        width: frameThickness
        color: visualsRoot.baseColor
    }

    // CORNERS (Inner radius connecting frames/bar)
    RoundCorner {
        id: bottomLeftCorner
        anchors {
            bottom: bottomFrame.visible ? bottomFrame.top : parent.bottom
            left: leftFrame.visible ? leftFrame.right : parent.left
            bottomMargin: !bottomFrame.visible ? Appearance.sizes.barHeight : 0
            leftMargin: !leftFrame.visible ? Appearance.sizes.verticalBarWidth : 0
        }
        implicitSize: Appearance.rounding.screenRounding
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.BottomLeft
    }

    RoundCorner {
        id: topLeftCorner
        anchors {
            top: topFrame.visible ? topFrame.bottom : parent.top
            left: leftFrame.visible ? leftFrame.right : parent.left
            topMargin: !topFrame.visible ? Appearance.sizes.barHeight : 0
            leftMargin: !leftFrame.visible ? Appearance.sizes.verticalBarWidth : 0
        }
        implicitSize: Appearance.rounding.screenRounding
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.TopLeft
    }

    RoundCorner {
        id: topRightCorner
        anchors {
            top: topFrame.visible ? topFrame.bottom : parent.top
            right: rightFrame.visible ? rightFrame.left : parent.right
            topMargin: !topFrame.visible ? Appearance.sizes.barHeight : 0
            rightMargin: !rightFrame.visible ? Appearance.sizes.verticalBarWidth : 0
        }
        implicitSize: Appearance.rounding.screenRounding
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.TopRight
    }

    RoundCorner {
        id: bottomRightCorner
        anchors {
            bottom: bottomFrame.visible ? bottomFrame.top : parent.bottom
            right: rightFrame.visible ? rightFrame.left : parent.right
            bottomMargin: !bottomFrame.visible ? Appearance.sizes.barHeight : 0
            rightMargin: !rightFrame.visible ? Appearance.sizes.verticalBarWidth : 0
        }
        implicitSize: Appearance.rounding.screenRounding
        color: visualsRoot.baseColor
        corner: RoundCorner.CornerEnum.BottomRight
    }
}
