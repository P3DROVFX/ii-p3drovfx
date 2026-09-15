import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property real padding: 5
    property real leftPadding: padding
    property real rightPadding: padding
    property real topPadding: padding
    property real bottomPadding: padding

    implicitWidth: vertical 
        ? (gridLayout.implicitHeight > 0 ? Appearance.sizes.baseVerticalBarWidth : 0)
        : (gridLayout.implicitWidth > 0 ? (gridLayout.implicitWidth + leftPadding + rightPadding) : 0)
    implicitHeight: vertical 
        ? (gridLayout.implicitHeight > 0 ? (gridLayout.implicitHeight + topPadding + bottomPadding) : 0) 
        : (gridLayout.implicitWidth > 0 ? Appearance.sizes.baseBarHeight : 0)

    default property alias items: gridLayout.children
    property var startRadius // left - top
    property var endRadius // right - bottom

    property color colBackground: Appearance.m3colors.m3surfaceContainerLow

    Rectangle {
        id: background
        // Fade rather than blink: a group that empties or fills is the same
        // event as a widget arriving or leaving, and should read that way.
        visible: opacity > 0.001
        opacity: (root.vertical ? (gridLayout.implicitHeight > 0) : (gridLayout.implicitWidth > 0)) ? 1 : 0
        Behavior on opacity {
            enabled: background.radiiArmed
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(background)
        }
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color: root.colBackground

        // These flip whenever a neighbour appears or disappears: a widget that
        // gains a neighbour squares off the side facing it. Snapping between
        // full-round and square is the most visible part of "the bar changed",
        // so they morph on the same clock as everything else that resizes.
        // Armed one pass after creation: the radii resolve from `undefined` on
        // the first evaluation, and animating that would morph every corner on
        // the bar at startup.
        property bool radiiArmed: false
        Component.onCompleted: Qt.callLater(() => background.radiiArmed = true)

        property real animatedStartRadius: root.startRadius ?? 0
        property real animatedEndRadius: root.endRadius ?? 0
        Behavior on animatedStartRadius {
            enabled: background.radiiArmed
            animation: Appearance.animation.barResize.numberAnimation.createObject(background)
        }
        Behavior on animatedEndRadius {
            enabled: background.radiiArmed
            animation: Appearance.animation.barResize.numberAnimation.createObject(background)
        }

        topLeftRadius: animatedStartRadius
        bottomLeftRadius: root.vertical ? animatedEndRadius : animatedStartRadius
        topRightRadius: root.vertical ? animatedStartRadius : animatedEndRadius
        bottomRightRadius: animatedEndRadius

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: root.vertical ? undefined : parent.left
            right: root.vertical ? undefined : parent.right
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            topMargin: root.topPadding
            bottomMargin: root.bottomPadding
            leftMargin: root.leftPadding
            rightMargin: root.rightPadding
        }
        columnSpacing: 4
        rowSpacing: 12
    }
}