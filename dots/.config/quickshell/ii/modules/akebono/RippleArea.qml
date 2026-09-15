pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects as GE

MouseArea {
    id: root

    property color rippleColor: Appearance.colors.colOnLayer2
    property real hoverOpacity: 0.08
    property real pressOpacity: 0.12
    property real shapeRadius: root.parent?.radius ?? 0
    property bool squircleMask: false

    layer.enabled: squircleMask
    layer.effect: GE.OpacityMask {
        maskSource: Squircle {
            width: root.width
            height: root.height
            radius: root.shapeRadius
            smoothing: AkebonoAppearance.squircleSmoothing
            color: "white"
        }
    }

    property real stateOpacity: pressed ? pressOpacity : containsMouse ? hoverOpacity : 0
    property real pressX: width / 2
    property real pressY: height / 2
    property real circleRadius: 0
    property real endRadiusAtPress: 0

    function distSq(x: real, y: real): real {
        return (pressX - x) ** 2 + (pressY - y) ** 2;
    }
    readonly property real endRadius: Math.sqrt(Math.max(distSq(0, 0), distSq(width, 0), distSq(0, height), distSq(width, height)))
    function clampR(r: real): real {
        return Math.max(0, Math.min(r, width / 2, height / 2));
    }

    function doPress(x: real, y: real): void {
        pressX = x;
        pressY = y;
        fadeAnim.complete();
        circleRadius = 0;
        circle.opacity = root.pressOpacity;
        rippleAnim.restart();
        endRadiusAtPress = endRadius;
    }

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: e => doPress(e.x, e.y)
    onPressedChanged: {
        if (!pressed && !rippleAnim.running && circle.opacity > 0)
            fadeAnim.start();
    }
    onCircleRadiusChanged: {
        if (!pressed && circleRadius > endRadiusAtPress * 0.99 && !fadeAnim.running)
            fadeAnim.start();
    }

    NumberAnimation {
        id: rippleAnim
        target: root
        property: "circleRadius"
        to: root.endRadius
        easing.type: Easing.OutCubic
        duration: 700
    }
    NumberAnimation {
        id: fadeAnim
        target: circle
        property: "opacity"
        to: 0
        easing.type: Easing.OutCubic
        duration: 320
    }

    Rectangle {
        anchors.fill: parent
        radius: root.shapeRadius
        color: root.rippleColor
        opacity: root.stateOpacity
        Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    }

    Shape {
        id: circle
        anchors.fill: parent
        opacity: 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.pressX
                centerY: root.pressY
                centerRadius: root.circleRadius
                focalX: centerX
                focalY: centerY
                GradientStop { position: 0; color: Qt.alpha(root.rippleColor, 1) }
                GradientStop { position: 0.99; color: Qt.alpha(root.rippleColor, 1) }
                GradientStop { position: 1; color: Qt.alpha(root.rippleColor, 0) }
            }

            startX: root.clampR(root.shapeRadius)
            startY: 0
            PathLine { x: root.width - root.clampR(root.shapeRadius); y: 0 }
            PathArc { relativeX: root.clampR(root.shapeRadius); relativeY: root.clampR(root.shapeRadius); radiusX: root.clampR(root.shapeRadius); radiusY: root.clampR(root.shapeRadius) }
            PathLine { x: root.width; y: root.height - root.clampR(root.shapeRadius) }
            PathArc { relativeX: -root.clampR(root.shapeRadius); relativeY: root.clampR(root.shapeRadius); radiusX: root.clampR(root.shapeRadius); radiusY: root.clampR(root.shapeRadius) }
            PathLine { x: root.clampR(root.shapeRadius); y: root.height }
            PathArc { relativeX: -root.clampR(root.shapeRadius); relativeY: -root.clampR(root.shapeRadius); radiusX: root.clampR(root.shapeRadius); radiusY: root.clampR(root.shapeRadius) }
            PathLine { x: 0; y: root.clampR(root.shapeRadius) }
            PathArc { x: root.clampR(root.shapeRadius); y: 0; radiusX: root.clampR(root.shapeRadius); radiusY: root.clampR(root.shapeRadius) }
        }
    }
}
