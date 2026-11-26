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

    width: implicitWidth
    height: implicitHeight

    default property alias items: gridLayout.children
    property var startRadius // left - top
    property var endRadius // right - bottom

    property color colBackground: Appearance.colors.colLayer1

    // Lazy background: expressive and material widgets use transparent
    // backgrounds, so they never allocate this Rectangle or its 4 Behaviors.
    Loader {
        id: backgroundLoader
        anchors.fill: parent
        active: root.colBackground.a > 0.001
        sourceComponent: Rectangle {
            id: background
            visible: opacity > 0.001
            opacity: (root.vertical ? (gridLayout.implicitHeight > 0) : (gridLayout.implicitWidth > 0)) ? 1 : 0
            Behavior on opacity {
                enabled: background.radiiArmed
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            anchors {
                fill: parent
                topMargin: root.vertical ? 0 : 4
                bottomMargin: root.vertical ? 0 : 4
                leftMargin: root.vertical ? 4 : 0
                rightMargin: root.vertical ? 4 : 0
            }
            color: root.colBackground

            property bool radiiArmed: false
            Component.onCompleted: Qt.callLater(() => background.radiiArmed = true)

            property real animatedStartRadius: root.startRadius ?? 0
            property real animatedEndRadius: root.endRadius ?? 0
            Behavior on animatedStartRadius {
                enabled: background.radiiArmed
                NumberAnimation {
                    duration: Appearance.animation.barResize.duration
                    easing.type: Appearance.animation.barResize.type
                    easing.bezierCurve: Appearance.animation.barResize.bezierCurve
                }
            }
            Behavior on animatedEndRadius {
                enabled: background.radiiArmed
                NumberAnimation {
                    duration: Appearance.animation.barResize.duration
                    easing.type: Appearance.animation.barResize.type
                    easing.bezierCurve: Appearance.animation.barResize.bezierCurve
                }
            }

            topLeftRadius: animatedStartRadius
            bottomLeftRadius: root.vertical ? animatedEndRadius : animatedStartRadius
            topRightRadius: root.vertical ? animatedStartRadius : animatedEndRadius
            bottomRightRadius: animatedEndRadius

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
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
